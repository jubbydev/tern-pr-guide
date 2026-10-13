--!strict
-- The plugin's host side: running commands on the reader's shell PATH (`run`, `git`, `runner`, which
-- prdata, agent-host and tandem run through), finding checkouts and setting up PR Guide's saved light
-- copies of repos, the guide and review lens files, and what the plugin remembers between runs
-- (recent PRs, run durations, where links open, background guides), and opening a link in the system browser.
local Agent = require("./agent")
local Github = require("./github")
local Host = require("./host")
local Lens = require("./lens")
local Links = require("./links")
local Pr = require("./pr")
local Platform = require("./platform")
local Sync = require("./hub/sync")
local Text = require("./text")

-- A checkout: its root, and the directory holding guides for its PRs, shared by its worktrees.
-- `cache` is the repo's "owner/repo" when the checkout is PR Guide's saved copy: a bare clone
-- that has no files, only history, with file contents fetched as they are read.
export type Repo = { root: string, guides: string, cache: string? }

export type Fail = (message: string) -> ()
-- A command chain in the checkout `repo`; `partial` is set for a saved copy, whose fetches leave out
-- trees and file contents.
export type Job = { repo: string, fail: Fail, partial: boolean? }

local GIT_MS = 60_000
-- The first fetch of a big repo's history takes a while.
local GIT_FETCH_MS = 20 * 60_000

-- The plugin's own lenses, and the most a lens file may be.
local LENSES = "lenses"
local LENS_BYTES = 64 * 1024

-- What went wrong: stderr's first line, plus GitHub's own explanation, which `gh api` prints to stdout.
local function reason(result: ProcessResult): string
 if result.timed_out then return "timed out" end
 local line = string.match(result.stderr, "%S[^\r\n]*") or ("exit status " .. result.status)
 local decoded, body = pcall(Host.json.decode, result.stdout)
 if decoded and type(body) == "table" and type(body.errors) == "table" then
  local details = {}
  for _, err in body.errors do
   table.insert(details, if type(err) == "string" then err else tostring(err.message or err.code))
  end
  if #details > 0 then line ..= " — " .. table.concat(details, "; ") end
 end
 return line
end

-- Tern started from the Dock has a bare PATH, without Homebrew's `gh` or tools like `omp` that a
-- shell rc file adds. Every command runs with the PATH of the reader's interactive login shell,
-- read once and shared by the window's blocks; Homebrew's directories are added in case the shell
-- gives nothing. Windows has no login shell to ask: Tern's own PATH there is the reader's, from the registry.
local FALLBACK_DIRS = "/opt/homebrew/bin:/usr/local/bin"
local shellPath: string? = nil
local waitingForPath: { (path: string) -> () }? = nil

local function withShellPath(go: (path: string) -> ())
 if shellPath then return go(shellPath) end
 if waitingForPath then
  table.insert(waitingForPath, go)
  return
 end
 waitingForPath = { go }
 local function settle(path: string?)
  if Platform.windows() then
   shellPath = Host.getenv("PATH") or ""
  else
   local base = if path and path ~= "" then path else (Host.getenv("PATH") or "/usr/bin:/bin")
   shellPath = base .. ":" .. FALLBACK_DIRS
  end
  local waiting = waitingForPath :: { (path: string) -> () }
  waitingForPath = nil
  for _, resume in waiting do resume(shellPath :: string) end
 end
 if Platform.windows() then return settle(nil) end
 local shell = Host.getenv("SHELL") or "/bin/zsh"
 local spawned = pcall(Host.process.run, { shell, "-lic", "printf '\\n%s%s' PRGUIDE_PATH= \"$PATH\"" }, { timeout_ms = 15_000 }, function(result: ProcessResult)
  settle(string.match(result.stdout, "PRGUIDE_PATH=([^\n]*)%s*$"))
 end)
 if not spawned then settle(nil) end
end

-- The first file for `program` in the folders of `path`; `program` itself when it already names a
-- path or nothing matches.
local function located(program: string, path: string): string
 if Platform.isPath(program) then return program end
 return Platform.which(program, path, Host.fs.exists) or program
end

-- Runs `argv` and hands its stdout to `ok`; a failed run, or an error from `ok` reading unexpected
-- output, goes to `fail`.
local function run(argv: { string }, opts: ProcessOptions, fail: Fail, ok: (stdout: string) -> ())
 withShellPath(function(path)
  local resolved = table.clone(argv)
  resolved[1] = located(argv[1], path)
  local withPath = table.clone(opts)
  local env = if opts.env then table.clone(opts.env) else {}
  env.PATH = env.PATH or path
  withPath.env = env
  local spawned, err = pcall(Host.process.run, resolved, withPath, function(result: ProcessResult)
   if result.status ~= 0 then
    fail(reason(result))
    return
   end
   local handled, problem = pcall(ok, result.stdout)
   if not handled then fail(Text.errorLine(problem)) end
  end)
  if not spawned then fail(Text.errorLine(err)) end
 end)
end

-- `fail` with each message prefixed by the step that failed.
local function named(what: string, fail: Fail): Fail
 return function(message: string) fail(what .. ": " .. message) end
end

local function git(job: Job, what: string, args: { string }, stdin: string?, ok: (stdout: string) -> ())
 local argv = { "git", "--literal-pathspecs", "-C", job.repo }
 table.move(args, 1, #args, #argv + 1, argv)
 -- A git that needs a password must fail, not wait for one nobody can type.
 local opts = { stdin = stdin, timeout_ms = if args[1] == "fetch" then GIT_FETCH_MS else GIT_MS, env = { GIT_TERMINAL_PROMPT = "0" } }
 run(argv, opts, named(what, job.fail), ok)
end

-- The file that says a saved copy is set up.
local READY = "/prguide-ready"

-- Makes the bare repo at `root` for the GitHub repo `slug` if it isn't set up: an empty repo that
-- fetches from GitHub and asks `gh` for a login, so a private repo works as `gh` does. Setting up
-- again after an interrupted attempt does the same steps over. Calls `done` once, with why it
-- failed or nil.
local function prepareCache(root: string, slug: string, done: (err: string?) -> ())
 if Host.fs.exists(root .. READY) then return done(nil) end
 local made, err = pcall(Host.fs.mkdir, root)
 if not made then return done("making " .. root .. ": " .. Text.errorLine(err)) end
 local job: Job = { repo = root, fail = done }
 withShellPath(function(path)
  local helper = "!\"" .. located("gh", path) .. "\" auth git-credential"
  run({ "git", "init", "--bare", "-q", root }, { timeout_ms = GIT_MS }, named("git init", done), function()
   git(job, "git config", { "config", "remote.origin.url", "https://github.com/" .. slug .. ".git" }, nil, function()
    -- The empty value drops the reader's own credential helpers, which would ask for a password.
    git(job, "git config", { "config", "--replace-all", "credential.helper", "" }, nil, function()
     git(job, "git config", { "config", "--add", "credential.helper", helper }, nil, function()
      local marked, problem = pcall(Host.fs.write, root .. READY, "")
      done(if marked then nil else "writing " .. root .. READY .. ": " .. Text.errorLine(problem))
     end)
    end)
   end)
  end)
 end)
end

local M = {}

M.GIT_MS = GIT_MS
M.run, M.named, M.git, M.withShellPath = run, named, git, withShellPath
M.prepareCache = prepareCache

function M.guidePath(repo: Repo, number: number): string
 return repo.guides .. "/" .. number .. ".json"
end

-- Where the review pass's comments and summary for PR `number` are kept, beside its guide.
function M.reviewPath(repo: Repo, number: number): string
 return repo.guides .. "/" .. number .. ".review.json"
end

-- Finds the checkout `dir` is in. Calls `done` once, with it or with what failed.
function M.findRepo(dir: string, done: (repo: Repo?, err: string?) -> ())
 local job: Job = { repo = dir, fail = function(message: string) done(nil, message) end }
 if not Host.fs.exists(dir) then return job.fail("No checkout at " .. dir) end
 git(job, "git rev-parse", { "rev-parse", "--path-format=absolute", "--show-toplevel", "--git-common-dir" }, nil, function(stdout)
  local root, common = string.match(stdout, "^([^\n]+)\n([^\n]+)")
  done({ root = root :: string, guides = (common :: string) .. "/prguide" }, nil)
 end)
end

local function parentOf(path: string): string?
 return string.match(path, "^(.+)/[^/]+$")
end

-- The "owner/repo" the `origin` remote of the checkout at `root` points at, or nil.
local function originOf(root: string, done: (slug: string?) -> ())
 run({ "git", "-C", root, "remote", "get-url", "origin" }, { timeout_ms = GIT_MS }, function() done(nil) end, function(stdout)
  done(Links.remoteRepo(stdout))
 end)
end

M.originOf = originOf

-- The most folders-worth of candidates whose origin is looked up.
local CANDIDATE_CAP = 40

-- A checkout of the GitHub repo `slug` ("owner/repo"), for a PR link: `near` when its origin is that
-- repo, else a checkout in the folder holding `near` or holding its main checkout, or, with no
-- `near`, in `dir` or the folder holding it; preferring one named like the repo. Calls `done`
-- once, with it, or with nil when there is none.
function M.checkoutFor(near: Repo?, dir: string, slug: string, done: (repo: Repo?) -> ())
 local function search()
  local candidates, seen = {}, {}
  local folders: { string? } = {}
  if near then
   seen[near.root] = true
   -- `guides` is <common git dir>/prguide; the main checkout holds the common git dir.
   local mainCheckout = parentOf(parentOf(near.guides) or "")
   folders = { parentOf(near.root), if mainCheckout then parentOf(mainCheckout) else nil }
  elseif dir ~= "" then
   folders = { dir, parentOf(dir) }
  end
  for _, folder in folders do
   if folder and not seen[folder] and Host.fs.exists(folder) then
    seen[folder] = true
    local listed, found = pcall(Host.fs.list, folder)
    local names: { string } = if listed then found else {}
    for _, name in names do
     local path = folder .. "/" .. name
     if not seen[path] and Host.fs.exists(path .. "/.git") then
      seen[path] = true
      table.insert(candidates, { path = path, name = name })
     end
    end
   end
  end
  local repoName = string.lower(string.match(slug, "/(.+)$") :: string)
  local function ranks(a: { name: string }, b: { name: string }): boolean
   local aNamed, bNamed = string.lower(a.name) == repoName, string.lower(b.name) == repoName
   if aNamed ~= bNamed then return aNamed end
   return a.name < b.name
  end
  table.sort(candidates, ranks)
  while #candidates > CANDIDATE_CAP do table.remove(candidates) end
  local matches, waiting = {}, #candidates
  local function finish()
   if #matches == 0 then return done(nil) end
   table.sort(matches, ranks)
   M.findRepo(matches[1].path, function(repo) done(repo) end)
  end
  if waiting == 0 then return finish() end
  for _, candidate in candidates do
   originOf(candidate.path, function(origin)
    if Links.sameRepo(origin, slug) then table.insert(matches, candidate) end
    waiting -= 1
    if waiting == 0 then finish() end
   end)
  end
 end
 if not near then return search() end
 originOf(near.root, function(own)
  if Links.sameRepo(own, slug) then done(near) else search() end
 end)
end

-- PR Guide's own saved copy of the GitHub repo `slug`, which a PR link on `host` names; nothing is
-- downloaded until a PR of it opens. Gives why when the link can't have one.
function M.savedCopy(host: string?, slug: string): (Repo?, string?)
 local owner, name = string.match(slug, "^(%w[%w._-]*)/(%w[%w._-]*)$")
 if not owner or not name or string.lower(host or "") ~= "github.com" then
  return nil, "No checkout of " .. slug .. " was found next to this one, and PR Guide only downloads its own copy of repos on github.com."
 end
 local root = Host.plugin.data .. "/repos/" .. string.lower(owner) .. "/" .. string.lower(name) .. ".git"
 return { root = root, guides = root .. "/prguide", cache = slug }, nil
end

-- PR Guide's saved copy of the GitHub repo `slug` when it is already set up (the fixes page never sets one up), else nil.
function M.readySavedCopy(slug: string): Repo?
 local copy = M.savedCopy("github.com", slug)
 if copy and Host.fs.exists(copy.root .. READY) then return copy end
 return nil
end

-- The folder the reader's own lenses live in.
function M.lensFolder(): string
 return Host.plugin.data .. "/lenses"
end

-- The text of every lens file in `dir`: the `.md` files but the README, none when it can't be read.
local function lensTexts(dir: string): { string }
 local texts = {}
 if not Host.fs.exists(dir) then return texts end
 local listed, names = pcall(Host.fs.list, dir)
 if not listed then return texts end
 for _, name in names do
  if string.lower(string.sub(name, -3)) == ".md" and string.lower(name) ~= "readme.md" and string.sub(name, 1, 1) ~= "." then
   local read, text = pcall(Host.fs.read, dir .. "/" .. name, LENS_BYTES)
   if read then table.insert(texts, text) end
  end
 end
 return texts
end

-- Lists the lenses `agent` can review through again: the plugin's own and the reader's, which
-- may have changed since the last look.
function M.refreshLenses(agent: Agent.Agent)
 agent.lenses = Lens.assemble(lensTexts(LENSES), lensTexts(M.lensFolder()))
end

-- Makes sure the reader's lens folder exists, with the README explaining lenses in it, and gives
-- its path; or says why it can't.
function M.prepareLensFolder(): (string?, string?)
 local dir = M.lensFolder()
 local ok, err = pcall(function()
  Host.fs.mkdir(dir)
  local readme = dir .. "/README.md"
  if not Host.fs.exists(readme) then Host.fs.write(readme, Host.fs.read(LENSES .. "/README.md")) end
 end)
 if ok then return dir, nil end
 return nil, Text.errorLine(err)
end

-- Where GitHub links open: "tern", Tern's own browser, or "browser", the system's default browser.
local LINKS_KEY = "links"

function M.linkTarget(): "tern" | "browser"
 local ok, saved = pcall(function() return Host.kv.get(LINKS_KEY) end)
 return if ok and saved == "browser" then "browser" else "tern"
end

function M.saveLinkTarget(target: "tern" | "browser")
 pcall(Host.kv.set, LINKS_KEY, target)
end

-- Whether the hub prepares AI guides for review requests in the background (Settings); off unless turned on.
local PREPARE_KEY = "hub.prepare"

function M.prepareGuides(): boolean
 local ok, saved = pcall(function() return Host.kv.get(PREPARE_KEY) end)
 return ok and saved == true
end

function M.savePrepareGuides(on: boolean)
 pcall(Host.kv.set, PREPARE_KEY, on)
end

-- The PR head the saved guide for PR `number` was written against: nil when there is no guide, "" when it can't be
-- read or names none.
function M.guideHead(repo: Repo, number: number): string?
 local path = M.guidePath(repo, number)
 if not Host.fs.exists(path) then return nil end
 local ok, raw = pcall(function() return Host.json.decode(Host.fs.read(path)) end)
 return if ok and type(raw) == "table" and type(raw.head) == "string" then raw.head else ""
end

-- Opens `url` in the system's default browser; `done` gets why it couldn't, else nil.
function M.openInBrowser(url: string, done: (err: string?) -> ())
 M.runner(Platform.openCommand(url), { timeout_ms = 15_000 }, function(out)
  if out.status == 0 and not out.timed_out then return done(nil) end
  done(if out.timed_out then "the browser didn't answer" else Text.errorLine(if out.stderr ~= "" then out.stderr else "the browser didn't open"))
 end)
end

-- How long the last finished run took, which the next run's progress is estimated from, before
-- there is one a guess. Each pass keeps its own.
local SECONDS_KEYS: { [Agent.Pass]: string } = { explain = "runSeconds", review = "reviewSeconds" }
local DEFAULT_SECONDS: { [Agent.Pass]: number } = { explain = 90, review = 180 }

function M.expectedSeconds(pass: Agent.Pass): number
 local ok, seconds = pcall(Host.kv.get, SECONDS_KEYS[pass])
 return if ok and type(seconds) == "number" and seconds > 0 then seconds else DEFAULT_SECONDS[pass]
end

function M.saveSeconds(pass: Agent.Pass, seconds: number)
 pcall(Host.kv.set, SECONDS_KEYS[pass], seconds)
end

-- The PRs the reader opened lately, newest first, which the hub lists under Review requests. They
-- live in `hub.recent`; the picker kept them in `recent`, which is read until the hub moves them.
local RECENT_KEY, LEGACY_RECENT_KEY = "hub.recent", "recent"

local function kvGet(key: string): any
 local ok, saved = pcall(Host.kv.get, key)
 return if ok then saved else nil
end

-- Personal hub rules survive closing a pane; GitHub logins have separate preferences.
function M.hubFilters(viewer: string): (any, string?)
 local ok, value = pcall(Host.kv.get, "hub.filters." .. string.lower(viewer))
 if not ok then return nil, tostring(value) end
 return value, nil
end

function M.saveHubFilters(viewer: string, value: any): string?
 local ok, why = pcall(Host.kv.set, "hub.filters." .. string.lower(viewer), value)
 return if ok then nil else tostring(why)
end

function M.recentPrs(): { Sync.Opened }
 local saved = kvGet(RECENT_KEY)
 if saved == nil then saved = kvGet(LEGACY_RECENT_KEY) end
 return Sync.openedList(saved)
end

-- Moves the picker's `recent` list to `hub.recent` (a list already there stands) and deletes it.
-- Run when the hub first loads; safe to run again.
function M.migrateRecent()
 local legacy = kvGet(LEGACY_RECENT_KEY)
 if legacy == nil then return end
 if kvGet(RECENT_KEY) == nil then pcall(Host.kv.set, RECENT_KEY, Sync.openedList(legacy)) end
 pcall(Host.kv.set, LEGACY_RECENT_KEY, nil)
end

-- Puts `pr` first in the recently opened list.
function M.rememberPr(pr: Pr.PR)
 if pr.repo == "" then return end
 local opened = { repo = pr.repo, number = pr.number, title = pr.title, author = pr.author, at = os.date("!%Y-%m-%dT%H:%M:%SZ") :: string }
 pcall(Host.kv.set, RECENT_KEY, Sync.remember(M.recentPrs(), opened))
end

-- `Github.Runner` (and `Log.Run`) over `Host.process.run`: `argv[1]` is found on the shell's PATH like `run` does,
-- and the result is always handed back, a failed spawn as status -1.
function M.runner(argv: { string }, opts: { cwd: string?, stdin: string?, timeout_ms: number?, env: { [string]: string }? }, done: (out: Github.Out) -> ())
 local called = false
 local function settle(out: Github.Out)
  if called then return end
  called = true
  done(out)
 end
 withShellPath(function(path)
  local resolved = table.clone(argv)
  resolved[1] = located(argv[1], path)
  local env = if opts.env then table.clone(opts.env) else {}
  env.PATH = path
  local spawned, err = pcall(Host.process.run, resolved, { cwd = opts.cwd, stdin = opts.stdin, timeout_ms = opts.timeout_ms, env = env }, function(result: ProcessResult)
   settle({ status = result.status, stdout = result.stdout, stderr = result.stderr, timed_out = result.timed_out })
  end)
  if not spawned then settle({ status = -1, stdout = "", stderr = Text.errorLine(err), timed_out = false }) end
 end)
end

return M
