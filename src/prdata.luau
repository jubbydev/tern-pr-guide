--!strict
-- Reading a PR and posting a review through `gh` and `git` in a checkout (the reader's own, or PR
-- Guide's saved light copy of a repo): the PR's metadata, changes and files for the review page, what
-- the fixes page reads for conflicts, and submitting the review. Its public functions are what the
-- web port replaces with GitHub API calls; a PR loads as `Pr.PR` and a review lands as
-- `Review.Delivery`. Each step starts the next from its callback; the first failure ends the chain
-- with a message naming the step.
local Fetch = require("./fetch")
local Fixes = require("./hub/fixes")
local Github = require("./github")
local GitOutput = require("./git-output")
local Host = require("./host")
local Links = require("./links")
local Model = require("./hub/model")
local Pr = require("./pr")
local Review = require("./review")
local Text = require("./text")

-- A PR as the reader named it (number, URL or branch), the root of its repository's checkout, and
-- the repo's "owner/repo" when that checkout is PR Guide's own saved copy. A caller that already
-- knows the PR (the PR hub) gives its head commit, so a PR kept from an earlier load at another head
-- is loaded again, and its base branch, so its commits are fetched while GitHub is read.
export type Target = { pr: string, repo: string, cache: string?, head: string?, base: string? }

-- Where a submitted review goes: in a dry run, the file at `dryRunPath`; otherwise GitHub. Without
-- a `repo` (the bundled sample) there is no PR to check or post to.
export type Destination = { repo: string?, dryRunPath: string? }

type Job = Fetch.Job
type Meta = { number: number, title: string, body: string?, url: string, author: { login: string }?, createdAt: string?, baseRefName: string, headRefOid: string, mergeCommit: { oid: string }? }

local GH_MS = 30_000

local run, named, git = Fetch.run, Fetch.named, Fetch.git

local function readMeta(job: Job, pr: string, ok: (meta: Meta) -> ())
 local argv = { "gh", "pr", "view", pr, "--json", "number,title,body,url,author,createdAt,baseRefName,headRefOid,mergeCommit" }
 run(argv, { cwd = job.repo, timeout_ms = GH_MS }, named("gh pr view", job.fail), function(stdout)
  ok(Host.json.decode(stdout))
 end)
end

-- Where the PR's head and base are fetched to.
local function refPrefix(number: number): string
 return "refs/prguide/" .. number
end

-- Fetches PR `number`'s head and base branch `base` into refs/prguide/<n>/*, leaving branches and
-- the working tree alone.
local function fetchRefs(job: Job, number: number, base: string, ok: () -> ())
 local prefix = refPrefix(number)
 local fetch = {
  "fetch", "--no-tags", "--no-write-fetch-head", "--recurse-submodules=no", "origin",
  "+refs/pull/" .. number .. "/head:" .. prefix .. "/head",
  "+refs/heads/" .. base .. ":" .. prefix .. "/base",
 }
 -- Commits only: a saved copy reads the trees and files a PR changes in one batch, later.
 if job.partial then table.insert(fetch, 2, "--filter=tree:0") end
 git(job, "git fetch", fetch, nil, function() ok() end)
end

-- The fetched head commit and where it branched from the base. Once a PR is merged with a merge
-- commit, its head is part of the base and the two meet at the head itself, which would show no
-- changes; it branched from where the merge commit's first parent meets the head instead.
local function branchPoint(job: Job, meta: Meta, ok: (head: string, mergeBase: string) -> ())
 local prefix = refPrefix(meta.number)
 git(job, "git rev-parse", { "rev-parse", prefix .. "/head" }, nil, function(head)
  git(job, "git merge-base", { "merge-base", prefix .. "/head", prefix .. "/base" }, nil, function(mergeBase)
   head, mergeBase = Text.trimEnd(head), Text.trimEnd(mergeBase)
   local merge = if type(meta.mergeCommit) == "table" then meta.mergeCommit.oid else nil
   if mergeBase ~= head or not merge or merge == head then return ok(head, mergeBase) end
   git(job, "git merge-base", { "merge-base", head, merge .. "^1" }, nil, function(before)
    ok(head, Text.trimEnd(before))
   end)
  end)
 end)
end

-- What a saved copy fetches by object id, in one request: no negotiation, since it names exact objects.
local FETCH_IDS = { "-c", "fetch.negotiationAlgorithm=noop", "fetch", "--no-tags", "--no-write-fetch-head", "--recurse-submodules=no", "--filter=blob:none", "--stdin", "origin" }

-- Fetches the whole trees of `head` and `mergeBase` (no file contents) that a saved copy lacks, in one request.
-- Its commits came without trees, and `git diff` would fetch them a directory at a time, each a round trip.
local function prefetchTrees(job: Job, head: string, mergeBase: string, ok: () -> ())
 if not job.partial then return ok() end
 -- `log` reads the tree ids from the commits; `rev-parse <commit>^{tree}` would fetch each tree on its own.
 git(job, "git log", { "log", "--no-walk", "--format=%T", head, mergeBase }, nil, function(trees)
  git(job, "git fetch", FETCH_IDS, trees, function() ok() end)
 end)
end

-- The changes worth reviewing: every changed file but lockfiles. Ones marked linguist-generated stay,
-- marked `generated`: the page sets them apart and the guide agent never reads them.
local function listChanges(job: Job, mergeBase: string, head: string, ok: (changes: { GitOutput.Change }) -> ())
 git(job, "git diff --name-status", { "diff", "--name-status", "-z", "--find-renames", mergeBase, head }, nil, function(stdout)
  local changes = {}
  for _, change in GitOutput.changes(stdout) do
   if not GitOutput.isLockfile(change.path) then table.insert(changes, change) end
  end
  if #changes == 0 then return ok(changes) end
  local paths = {}
  for _, change in changes do table.insert(paths, change.path) end
  local stdin = table.concat(paths, "\0") .. "\0"
  git(job, "git check-attr", { "check-attr", "--source=" .. head, "-z", "--stdin", "linguist-generated" }, stdin, function(attrs)
   local generated = GitOutput.generated(attrs)
   for _, change in changes do
    if generated[change.path] then change.generated = true end
   end
   ok(changes)
  end)
 end)
end

-- One `git diff` of just the kept files, computed locally: GitHub refuses diffs of big PRs.
local function readPatches(job: Job, mergeBase: string, head: string, changes: { GitOutput.Change }, ok: (patches: { [string]: GitOutput.Patch }) -> ())
 if #changes == 0 then return ok({}) end
 local args = {
  "-c", "core.quotePath=false", "diff", "--no-ext-diff", "--no-color", "--find-renames",
  "--src-prefix=a/", "--dst-prefix=b/", mergeBase, head, "--",
 }
 local paths = {}
 for _, change in changes do
  table.insert(paths, change.path)
  if change.oldPath then table.insert(args, change.oldPath) end
  table.insert(args, change.path)
 end
 git(job, "git diff", args, nil, function(stdout)
  ok(GitOutput.patches(stdout, paths))
 end)
end

-- Fetches the files `paths` have at `head` that a saved copy lacks, in one request: its `git diff`
-- fetches the changed files it shows in one batch, but a rename or a mode change shows none, and
-- `git cat-file` would fetch each of those on its own.
local function prefetchSources(job: Job, head: string, paths: { string }, ok: () -> ())
 if not job.partial or #paths == 0 then return ok() end
 local listing = { "ls-tree", "-z", head, "--" }
 table.move(paths, 1, #paths, #listing + 1, listing)
 git(job, "git ls-tree", listing, nil, function(tree)
  local oids = {}
  for oid in string.gmatch(tree, "%d+ blob (%x+)\t") do table.insert(oids, oid) end
  if #oids == 0 then return ok() end
  local wanted = table.concat(oids, "\n") .. "\n"
  git(job, "git cat-file", { "--no-lazy-fetch", "cat-file", "--batch-check" }, wanted, function(checked)
   local missing = {}
   for oid in string.gmatch(checked, "(%x+) missing") do table.insert(missing, oid) end
   if #missing == 0 then return ok() end
   git(job, "git fetch", FETCH_IDS, table.concat(missing, "\n") .. "\n", function() ok() end)
  end)
 end)
end

-- The whole new side of `paths` at `head`, all through one `git cat-file --batch`.
local function readSources(job: Job, head: string, paths: { string }, ok: (blobs: { [string]: string }) -> ())
 if #paths == 0 then return ok({}) end
 local requests = {}
 for _, path in paths do table.insert(requests, head .. ":" .. path) end
 git(job, "git cat-file", { "cat-file", "--batch" }, table.concat(requests, "\n") .. "\n", function(stdout)
  ok(GitOutput.blobs(stdout, paths))
 end)
end

local function prOf(meta: Meta, head: string, files: { Pr.File }): Pr.PR
 return {
  repo = string.match(meta.url, "^https?://[^/]+/([^/]+/[^/]+)/pull/") or "",
  number = meta.number,
  title = meta.title,
  body = meta.body or "",
  url = meta.url,
  author = if meta.author then meta.author.login else "",
  createdAt = meta.createdAt or "",
  baseRef = meta.baseRefName,
  head = head,
  files = files,
 }
end

-- The review as GitHub's create-review request body; `comments` stays an array when empty.
local function requestJson(payload: Review.Payload): string
 local body = table.clone(payload)
 body.comments = Host.json.array(table.clone(payload.comments))
 return Host.json.encode(body, true)
end

local function saveDryRun(path: string, payload: Review.Payload, done: (Review.Delivery?, string?) -> ())
 local written, err = pcall(Host.fs.write, path, requestJson(payload))
 if written then done({ kind = "saved", path = path }, nil) else done(nil, "saving " .. path .. ": " .. tostring(err)) end
end

local function post(repo: string, pr: Pr.PR, payload: Review.Payload, done: (Review.Delivery?, string?) -> ())
 local fail = function(message: string) done(nil, message) end
 local argv = { "gh", "api", "--method", "POST", "repos/" .. pr.repo .. "/pulls/" .. pr.number .. "/reviews", "--input", "-" }
 run(argv, { cwd = repo, stdin = requestJson(payload), timeout_ms = GH_MS }, named("gh api", fail), function(stdout)
  local review = Host.json.decode(stdout)
  done({ kind = "posted", url = review.html_url }, nil)
 end)
end

-- Work on one saved copy at a time: `go` gets a `release` to call when it is done with the copy
-- (calling it again does nothing); a `go` that arrives while another holds the copy waits its
-- turn. Two PR links into one repo then never fetch into it together.
local holders: { [string]: { (release: () -> ()) -> () } } = {}

local function acquire(key: string, go: (release: () -> ()) -> ())
 local waiting = holders[key]
 if waiting then
  table.insert(waiting, go)
  return
 end
 local queue: { (release: () -> ()) -> () } = {}
 holders[key] = queue
 local function hand(next: (release: () -> ()) -> ())
  local released = false
  next(function()
   if released then return end
   released = true
   local following = table.remove(queue, 1)
   if following then hand(following) else holders[key] = nil end
  end)
 end
 hand(go)
end

-- The file that says a saved copy's first download finished.
local DOWNLOADED = "/prguide-downloaded"

-- What the fetch stage says: for a saved copy, whether it is the first download.
local function fetchStage(target: Target): string
 local slug = target.cache
 if not slug then return "Fetching its commits into " .. target.repo end
 if Host.fs.exists(target.repo .. DOWNLOADED) then return "Checking " .. slug .. " for new commits" end
 return "Downloading " .. slug .. " (first time only)"
end

-- Reads the PR from GitHub and fetches its commits: at once when the caller knows its number and base
-- branch, else the one after the other. A base changed since the caller read it is fetched again.
local function readAndFetch(job: Job, target: Target, progress: (stage: string) -> (), ok: (meta: Meta) -> ())
 local number, base = Links.named(target.pr), target.base
 if not number or not base then
  progress("Reading the PR from GitHub")
  return readMeta(job, target.pr, function(meta)
   progress(fetchStage(target))
   fetchRefs(job, meta.number, meta.baseRefName, function() ok(meta) end)
  end)
 end
 progress(fetchStage(target))
 local read: Meta?, fetched = nil, false
 local function both()
  local meta = read
  if not meta or not fetched then return end
  if meta.baseRefName == base then return ok(meta) end
  fetchRefs(job, meta.number, meta.baseRefName, function() ok(meta) end)
 end
 readMeta(job, target.pr, function(meta)
  read = meta
  both()
 end)
 fetchRefs(job, number, base, function()
  fetched = true
  both()
 end)
end

local M = {}

function M.dryRunPath(number: number): string
 return "/tmp/prguide-review-" .. number .. ".json"
end

M.refPrefix = refPrefix

-- Loads `target` from GitHub and its checkout, reporting each stage as it starts. Calls `done`
-- once, with the PR or with what failed. A saved copy is set up first if need be, and held while
-- its commits are fetched, so that PRs of one repo opening together take turns.
local function load(target: Target, progress: (stage: string) -> (), done: (pr: Pr.PR?, err: string?) -> ())
 local function open(release: () -> ())
  local failed = false
  local job: Job = {
   repo = target.repo,
   -- Reading GitHub and fetching run at once, and both may fail.
   fail = function(message: string)
    if failed then return end
    failed = true
    release()
    done(nil, message)
   end,
   partial = target.cache ~= nil,
  }
  readAndFetch(job, target, progress, function(meta)
   branchPoint(job, meta, function(head, mergeBase)
    if target.cache then pcall(Host.fs.write, target.repo .. DOWNLOADED, "") end
    release()
    progress("Reading the changes")
    prefetchTrees(job, head, mergeBase, function()
     listChanges(job, mergeBase, head, function(changes)
      readPatches(job, mergeBase, head, changes, function(patches)
       progress("Reading the changed files")
       local paths = GitOutput.textPaths(changes, patches)
       prefetchSources(job, head, paths, function()
        readSources(job, head, paths, function(blobs)
         done(prOf(meta, head, GitOutput.files(changes, patches, blobs)), nil)
        end)
       end)
      end)
     end)
    end)
   end)
  end)
 end
 local slug = target.cache
 if not slug then return open(function() end) end
 progress("Preparing a saved copy of " .. slug)
 acquire(target.repo, function(release)
  Fetch.prepareCache(target.repo, slug, function(err)
   if err then
    release()
    done(nil, err)
   else
    open(release)
   end
  end)
 end)
end

-- PRs loaded lately, by checkout and number, so a PR the hub loaded in the background opens at once;
-- the most kept and for how long, since a kept PR's title and description may since have changed.
type Kept = { pr: Pr.PR, at: number }
local kept: { [string]: Kept } = {}
local KEEP_PRS, KEEP_MS = 12, 10 * 60_000

-- Loads under way, by the same key: an open of a PR already loading waits for that load.
type Waiter = { progress: (stage: string) -> (), done: (pr: Pr.PR?, err: string?) -> () }
type Loading = { stage: string?, waiters: { Waiter } }
local loading: { [string]: Loading } = {}

local function keep(key: string, pr: Pr.PR)
 kept[key] = { pr = pr, at = Host.now() }
 local count, oldest = 0, nil :: string?
 for k, entry in kept do
  count += 1
  if not oldest or entry.at < kept[oldest].at then oldest = k end
 end
 if count > KEEP_PRS and oldest then kept[oldest] = nil end
end

-- Opens `target` as `load` does, from a PR kept from a recent load when there is one at the head the
-- caller knows, or by waiting for a load of it already under way.
function M.openPr(target: Target, progress: (stage: string) -> (), done: (pr: Pr.PR?, err: string?) -> ())
 local number = Links.named(target.pr)
 if not number then return load(target, progress, done) end
 local key = target.repo .. "#" .. number
 local entry = kept[key]
 if entry and Host.now() - entry.at < KEEP_MS and (target.head == nil or target.head == entry.pr.head) then
  return done(entry.pr, nil)
 end
 local waiter: Waiter = { progress = progress, done = done }
 local under = loading[key]
 if under then
  if under.stage then progress(under.stage) end
  table.insert(under.waiters, waiter)
  return
 end
 local this: Loading = { stage = nil, waiters = { waiter } }
 loading[key] = this
 load(target, function(stage)
  this.stage = stage
  for _, w in this.waiters do w.progress(stage) end
 end, function(pr, err)
  loading[key] = nil
  if pr then keep(key, pr) end
  for _, w in this.waiters do w.done(pr, err) end
 end)
end

-- What the fixes page reads from local git, as text: `mergeTree` is `git merge-tree --write-tree --name-only`
-- of the PR's head into its base (nil when the page did not ask), `shown` each conflicted file as the merged
-- tree holds it (with markers), `logs` the last commit on the base touching it since the merge base, and
-- `files` the annotated files as the head commit has them.
export type FixRead = { mergeTree: string?, shown: { [string]: string }, logs: { [string]: string }, files: { [string]: string } }

-- Files read for conflicts and for annotations, at most.
local CONFLICT_FILES, ANNOTATED_FILES = 8, 6

-- `git` in `job`'s repo whose exit status the caller reads: `merge-tree` exits 1 for a merge with conflicts.
local function gitStatus(job: Job, args: { string }, done: (out: Github.Out) -> ())
 local argv = { "git", "--literal-pathspecs", "-C", job.repo }
 table.move(args, 1, #args, #argv + 1, argv)
 Fetch.runner(argv, { timeout_ms = Fetch.GIT_MS }, done)
end

-- Runs `step` on each of `items` in turn, then `done`.
local function eachInTurn(items: { string }, step: (item: string, next: () -> ()) -> (), done: () -> ())
 local at = 0
 local function advance()
  at += 1
  if at > #items then return done() end
  step(items[at], advance)
 end
 advance()
end

local function firstLines(paths: { string }, cap: number): { string }
 local out = {}
 for _, path in paths do
  if #out < cap then table.insert(out, path) end
 end
 return out
end

-- Reads what the fixes page needs from the checkout `repo` (its own, or PR Guide's saved copy): fetches the
-- PR's head and base into refs/prguide/<n>/*, merges them with `git merge-tree` when the PR conflicts, and
-- reads each conflicted file and its cause with `git show` and `git log`. `paths` are annotated files to
-- read at the head with `git show`; a missing one is left out. Calls `done` once.
function M.readFixes(repo: Fetch.Repo, pr: Model.HubPR, paths: { string }, done: (read: FixRead?, err: string?) -> ())
 local function open(release: () -> ())
  local job: Job = {
   repo = repo.root,
   fail = function(message: string)
    release()
    done(nil, message)
   end,
   partial = repo.cache ~= nil,
  }
  local meta: Meta = {
   number = pr.number, title = pr.title, body = nil, url = pr.url, author = nil, createdAt = nil,
   baseRefName = pr.baseBranch, headRefOid = pr.headOid, mergeCommit = nil,
  }
  local read: FixRead = { mergeTree = nil, shown = {}, logs = {}, files = {} }
  fetchRefs(job, meta, function(head, mergeBase)
   release()
   local base = refPrefix(pr.number) .. "/base"
   local function annotated()
    eachInTurn(firstLines(paths, ANNOTATED_FILES), function(path, next)
     gitStatus(job, { "show", head .. ":" .. path }, function(out)
      if out.status == 0 then read.files[path] = out.stdout end
      next()
     end)
    end, function() done(read, nil) end)
   end
   if not pr.conflicts then return annotated() end
   gitStatus(job, { "merge-tree", "--write-tree", "--name-only", head, base }, function(out)
    -- 0 is a clean merge and 1 a merge with conflicts; anything else is git failing.
    if out.timed_out or (out.status ~= 0 and out.status ~= 1) then
     return job.fail("git merge-tree: " .. (if out.timed_out then "timed out" else (string.match(out.stderr, "%S[^\r\n]*") or ("exit status " .. out.status))))
    end
    read.mergeTree = out.stdout
    local tree = Fixes.parseMergeTree(out.stdout)
    if tree == nil then return annotated() end
    eachInTurn(firstLines(tree.files, CONFLICT_FILES), function(path, next)
     gitStatus(job, { "show", tree.tree .. ":" .. path }, function(shown)
      if shown.status == 0 then read.shown[path] = shown.stdout end
      local log = { "log", "-1", "--format=%H%x09%an%x09%s", mergeBase .. ".." .. base, "--", path }
      gitStatus(job, log, function(logged)
       if logged.status == 0 then read.logs[path] = logged.stdout end
       next()
      end)
     end)
    end, annotated)
   end)
  end)
 end
 local slug = repo.cache
 if not slug then return open(function() end) end
 acquire(repo.root, open)
end

-- Sends `payload` to `to` in one go, first checking the PR still has the head the page shows.
-- Calls `done` once, with where the review went or why it didn't.
function M.submitReview(pr: Pr.PR, payload: Review.Payload, to: Destination, done: (Review.Delivery?, string?) -> ())
 local repo = to.repo
 local function deliver()
  if to.dryRunPath then saveDryRun(to.dryRunPath, payload, done) else post(repo :: string, pr, payload, done) end
 end
 if not repo then return deliver() end
 local fail = function(message: string) done(nil, message) end
 run({ "gh", "pr", "view", pr.url, "--json", "headRefOid" }, { cwd = repo, timeout_ms = GH_MS }, named("gh pr view", fail), function(stdout)
  local head = Host.json.decode(stdout).headRefOid
  if head ~= pr.head then
   fail("The PR moved on to " .. string.sub(head, 1, 7) .. " since this page loaded, so nothing was sent. Reopen it to review the new commits.")
   return
  end
  deliver()
 end)
end

return M
