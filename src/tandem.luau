--!strict
-- Tandem, the reader's PR-fixing service, through its CLI and its database: which PRs it watches
-- (`tandem watch --json`), handing one over (`tandem native act`), and where it keeps a repo's clone.
-- Plugin-only: the web port has no Tandem and leaves this module out.
local Fetch = require("./fetch")
local Github = require("./github")
local Host = require("./host")
local Model = require("./hub/model")
local Platform = require("./platform")
local Text = require("./text")

-- Both CLI calls run in the project's absolute root, and every failure settles the callback once, as (nil, reason).
local TANDEM_MS = 30_000
local TANDEM_STATUS: { [string]: boolean } = { done = true, kept = true, refused = true }

export type Outcome = { status: "done" | "kept" | "refused", notice: { code: string, text: string }? }

local function onceOf<T>(done: (T?, string?) -> ()): (T?, string?) -> ()
 local called = false
 return function(value: T?, err: string?)
  if called then return end
  called = true
  done(value, err)
 end
end

-- A process output with its status, as one reason when it did not exit 0 in time.
local function failedRun(out: Github.Out): string?
 if out.timed_out then return "timed out" end
 if out.status ~= 0 then return Text.errorLine(if out.stderr ~= "" then out.stderr else "exit status " .. out.status) end
 return nil
end

local function runTandem(argv: { string }, opts: { cwd: string?, stdin: string?, timeout_ms: number? }, finish: (string?, string?) -> ())
 local ok, err = pcall(Fetch.runner, argv, opts, function(out)
  local failure = failedRun(out)
  if failure then return finish(nil, failure) end
  finish(out.stdout, nil)
 end)
 if not ok then finish(nil, Text.errorLine(err)) end
end

local M = {}

-- The PRs Tandem watches, in lowercase "owner/repo#123" keys (Model.parseTandemWatch).
function M.watch(root: string, done: ({ [string]: boolean }?, string?) -> ())
 local finish = onceOf(done)
 if string.sub(root, 1, 1) ~= "/" then return finish(nil, "The project folder is not an absolute path") end
 runTandem({ "tandem", "watch", "--json" }, { cwd = root, timeout_ms = TANDEM_MS }, function(stdout, err)
  if not stdout then return finish(nil, err) end
  local decoded, value = pcall(Host.json.decode, stdout)
  local watched = if decoded then Model.parseTandemWatch(value) else nil
  if not watched then return finish(nil, "Tandem returned output this version can't read") end
  finish(watched, nil)
 end)
end

-- Asks Tandem to watch and fix PR `number` of `repo` ("owner/repo"). The request names this plugin as its
-- origin and carries exactly the verb, repo, number and reason; a refusal is an outcome, not an error.
function M.handoff(root: string, repo: string, number: number, reason: string, done: (Outcome?, string?) -> ())
 local finish = onceOf(done)
 local why = string.match(reason, "^%s*(.-)%s*$") :: string
 if string.sub(root, 1, 1) ~= "/" then return finish(nil, "The project folder is not an absolute path") end
 if not string.match(repo, "^[%w%-_.]+/[%w%-_.]+$") or number < 1 or number % 1 ~= 0 or why == "" then
  return finish(nil, "The hand-off request is incomplete")
 end
 local request = { v = 1, origin = { plugin = "prguide", repoPath = root }, action = { verb = "pr-fix", repo = repo, number = number, reason = why } }
 local encoded, stdin = pcall(Host.json.encode, request)
 if not encoded then return finish(nil, Text.errorLine(stdin)) end
 runTandem({ "tandem", "native", "act" }, { cwd = root, stdin = stdin :: string, timeout_ms = TANDEM_MS }, function(stdout, err)
  if not stdout then return finish(nil, err) end
  local decoded, value = pcall(Host.json.decode, stdout)
  if not decoded or type(value) ~= "table" or not TANDEM_STATUS[value.status] then
   return finish(nil, "Tandem returned an answer this version can't read")
  end
  local notice = value.notice
  if notice ~= nil and not (type(notice) == "table" and type(notice.code) == "string" and type(notice.text) == "string") then
   return finish(nil, "Tandem returned an answer this version can't read")
  end
  finish({ status = value.status, notice = if notice then { code = notice.code, text = notice.text } else nil }, nil)
 end)
end

-- The folder Tandem keeps its clone of `slug` in, or nil: a read-only SELECT, with SQL quoting and no
-- migration or write to Tandem's store.
function M.clone(slug: string, done: (string?) -> ())
 local home = Host.getenv("TANDEM_HOME") or ((Platform.home() or "") .. "/.tandem")
 local database = home .. "/state.sqlite"
 if not Host.fs.exists(database) then return done(nil) end
 local quoted = string.gsub(string.lower(slug), "'", "''")
 local sql = "SELECT path FROM repo_locations WHERE repo = '" .. quoted .. "' LIMIT 1;"
 Fetch.runner({ "sqlite3", "-readonly", "-json", database, sql }, { timeout_ms = 15_000 }, function(out)
  if out.status ~= 0 then return done(nil) end
  local ok, rows = pcall(Host.json.decode, out.stdout)
  local path = if ok and type(rows) == "table" and type(rows[1]) == "table" then rows[1].path else nil
  done(if type(path) == "string" and path ~= "" then path else nil)
 end)
end

return M
