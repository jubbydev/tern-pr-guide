--!strict
-- The reader's AI agent (`omp`) as a process: finding it and the model they picked, listing its
-- models, explaining a PR and drafting its review, summarizing feedback, and agent fixes (where the repo's clone is, the
-- engine run in a leased worktree, reading the fix, pushing it and returning the lease).
local Agent = require("./agent")
local AgentFix = require("./hub/agent-fix")
local Fetch = require("./fetch")
local Github = require("./github")
local Guide = require("./guide")
local Host = require("./host")
local Links = require("./links")
local Platform = require("./platform")
local Pr = require("./pr")
local Prdata = require("./prdata")
local ReviewFix = require("./hub/review-fix")
local Summary = require("./hub/summary")
local Tandem = require("./tandem")
local Text = require("./text")

local MODELS_MS = 30_000
local AGENT_MS = 20 * 60_000

local PROMPTS: { [Agent.Pass]: string } = { explain = "prompts/explain.md", review = "prompts/review.md" }

-- Where the models, efforts, review switch and lens the reader last picked are kept, in the plugin's
-- key/value store (see Agent.picks).
local CHOICE_KEY = "model"

local function savedChoice(): { [string]: any }
 local ok, saved = pcall(Host.kv.get, CHOICE_KEY)
 return if ok and type(saved) == "table" then saved else {}
end

-- What OMP's config at `config` says each pass runs with; nothing when it has no config.
local function ompDefaults(config: string): Agent.Defaults
 return Agent.defaults(if Host.fs.exists(config) then Host.fs.read(config) else "")
end

local M = {}

-- The reader's agent: `omp` on their shell's PATH with what they last picked, OMP's own roles
-- standing in for a model never picked. Calls `done` once, with nil and why when `omp` or the
-- model is missing. `omp` is looked up as a file because an interactive shell may define it as an alias.
function M.findAgent(done: (agent: Agent.Agent?, why: string?) -> ())
 local home = Platform.home()
 if not home then return done(nil, "your home directory is unknown") end
 Fetch.withShellPath(function(path)
  local command = Platform.which("omp", path, Host.fs.exists)
  if not command then return done(nil, "omp isn't installed (it isn't on your shell's PATH)") end
  local saved = savedChoice()
  local picks = Agent.picks(saved, ompDefaults(home .. Agent.CONFIG))
  if not picks then return done(nil, "omp has no model set (pick one in omp first)") end
  local agent = Agent.new(command, path, picks)
  Fetch.refreshLenses(agent)
  done(agent)
 end)
end

-- Remembers everything the reader picked for `agent`, for every PR and the next start.
function M.saveChoice(agent: Agent.Agent)
 pcall(Host.kv.set, CHOICE_KEY, Agent.saved(agent))
end

-- Takes up what the reader last saved, which the review page or the hub's Settings may have changed
-- since `agent` was found, so a pick made in one doesn't save over the other's. What was never
-- picked keeps the default the agent was found with.
function M.refreshChoice(agent: Agent.Agent)
 local defaults: Agent.Defaults = { review = { model = agent.model, effort = agent.effort }, explain = if agent.explainPicked then nil else agent.explain }
 local picks = Agent.picks(savedChoice(), defaults) :: Agent.Picks
 agent.model, agent.effort, agent.explain, agent.explainPicked, agent.lens = picks.model, picks.effort, picks.explain, picks.explainPicked, picks.lens
end

-- The models `agent` can run with, from `omp models`. Calls `done` once; the list is empty when
-- listing fails, which leaves the current model as the only choice.
function M.listModels(agent: Agent.Agent, done: (models: { Agent.Model }) -> ())
 Fetch.run({ agent.command, "models", "--json" }, { env = { PATH = agent.path }, timeout_ms = MODELS_MS }, function() done({}) end, function(stdout)
  local ok, raw = pcall(Host.json.decode, stdout)
  done(if ok then Agent.parseModels(raw) else {})
 end)
end

-- Has `agent` run `pass` for `pr`: the run's directory gets the numbered diff and the pass's
-- filled-in prompt, then `omp -p` runs in the checkout with the pass's model. A file the pass
-- writes, `clear`, is removed first, so only this run's can be read. Calls `fail` with the first
-- line of what went wrong, else `ran` with what the agent replied.
local function runPass(agent: Agent.Agent, pass: Agent.Pass, repo: Fetch.Repo, pr: Pr.PR, clear: string?, values: { [string]: string }, fail: (string) -> (), ran: (reply: string) -> ())
 local dir = Agent.workDir(pr)
 local diffPath, promptPath = dir .. "/diff.txt", dir .. "/" .. pass .. ".md"
 local prepared, err = pcall(function()
  Host.fs.mkdir(dir)
  Host.fs.mkdir(repo.guides)
  if clear and Host.fs.exists(clear) then Host.fs.remove(clear) end
  Host.fs.write(diffPath, Agent.numberedDiff(pr.files))
  local filled = table.clone(values)
  filled.repo, filled.number, filled.title, filled.head = pr.repo, tostring(pr.number), pr.title, pr.head
  filled.base, filled.diffPath = Prdata.refPrefix(pr.number) .. "/base", diffPath
  filled.author = Agent.shortName(Agent.choiceFor(agent, pass).model)
  Host.fs.write(promptPath, Agent.prompt(Host.fs.read(PROMPTS[pass]), filled))
 end)
 if not prepared then return fail(Text.errorLine(err)) end
 Fetch.run(Agent.argv(agent, pass, promptPath, diffPath), { cwd = repo.root, env = { PATH = agent.path }, timeout_ms = AGENT_MS }, fail, ran)
end

-- Moves the unusable file at `path` into `pr`'s run directory as `name`, so the checkout never
-- keeps one, and says where it went.
local function setAside(pr: Pr.PR, path: string, name: string): string
 local kept = Agent.workDir(pr) .. "/" .. name
 Host.fs.write(kept, Host.fs.read(path))
 Host.fs.remove(path)
 return kept
end

-- Has `agent` explain `pr` in one request and saves its reply as the PR's guide: the overview,
-- flow and changes. Calls `done` once, with the guide or the first line of what went wrong.
function M.explain(agent: Agent.Agent, repo: Fetch.Repo, pr: Pr.PR, done: (Guide.Guide?, string?) -> ())
 local path = Fetch.guidePath(repo, pr.number)
 local fail = function(message: string) done(nil, message) end
 local body = string.match(pr.body, "^%s*(.-)%s*$") :: string
 local values = { description = if body == "" then "No description provided." else body }
 runPass(agent, "explain", repo, pr, nil, values, fail, function(reply)
  local json = Agent.replyJson(reply)
  if json == "" then return fail(Agent.shortName(agent.explain.model) .. " finished without replying") end
  Host.fs.write(path, json)
  local guide, problem = Guide.read(path, pr)
  if guide then return done(guide, nil) end
  fail("its explanation isn't usable: " .. (problem :: string) .. " (kept at " .. setAside(pr, path, "guide.json") .. ")")
 end)
end

-- Has `agent` draft review comments and a summary for `pr` through its lens. Calls `done` once,
-- with them or the first line of what went wrong.
function M.draftReview(agent: Agent.Agent, repo: Fetch.Repo, pr: Pr.PR, done: (Guide.Draft?, string?) -> ())
 local path = Fetch.reviewPath(repo, pr.number)
 Fetch.refreshLenses(agent)
 local lens = Agent.currentLens(agent)
 local fail = function(message: string) done(nil, message) end
 runPass(agent, "review", repo, pr, path, { reviewPath = path, lens = Host.json.encode(lens.name), focus = Agent.focus(lens) }, fail, function()
  if not Host.fs.exists(path) then return fail(Agent.shortName(agent.model) .. " finished without writing " .. path) end
  local draft, problem = Guide.readDraft(path, pr)
  if draft then return done(draft, nil) end
  fail("the review it wrote isn't usable: " .. (problem :: string) .. " (kept at " .. setAside(pr, path, "review.json") .. ")")
 end)
end

-- Runs the read-only summary: one ephemeral, tool-free omp call. The command is built here from the
-- validated fields by Summary.plan, never taken from the caller. No cwd, worktree, file or kv write.
function M.summarizeFeedback(agent: { command: string, model: string, effort: string? }, prompt: string, done: (string?, string?) -> ())
 local argv = Summary.plan(agent.command, agent.model, agent.effort, prompt)
 if not argv then return done(nil, "Invalid read-only summary command") end
 local called = false
 local function finish(text: string?, err: string?)
  if called then return end
  called = true
  done(text, err)
 end
 local ok, err = pcall(Fetch.runner, argv, { timeout_ms = AGENT_MS }, function(out)
  if out.status ~= 0 or out.timed_out then
   return finish(nil, if out.timed_out then "Summarizing feedback timed out" else Text.errorLine(out.stderr ~= "" and out.stderr or "The agent returned no answer"))
  end
  finish(out.stdout, nil)
 end)
 if not ok then finish(nil, Text.errorLine(err)) end
end

-- Agent fixes: only this boundary reads hub.clones, local journals and environment, and Tandem's
-- database through tandem.luau. The caller owns the folder question and card lifecycle. No UI effects here.
local CLONES_KEY = "hub.clones"

function M.agentClones(): { [string]: string }
 local read, raw = pcall(Host.kv.get, CLONES_KEY)
 local clones = {}
 if read and type(raw) == "table" then
  for slug, path in raw do
   if type(slug) == "string" and type(path) == "string" then clones[slug] = path end
  end
 end
 return clones
end

function M.rememberAgentClone(slug: string, path: string): string?
 local clones = M.agentClones()
 clones[string.lower(slug)] = path
 local ok, err = pcall(Host.kv.set, CLONES_KEY, clones)
 return if ok then nil else "Couldn't save the clone folder: " .. Text.errorLine(err)
end

function M.findAgentClone(near: Fetch.Repo?, dir: string, slug: string, ask: (string, (string?) -> ()) -> (), done: (string?, string?) -> ())
 local function validate(path: string, name: string, callback: (boolean) -> ())
  Fetch.originOf(path, function(origin) callback(Links.sameRepo(origin, name)) end)
 end
 AgentFix.locateClone(slug, {
  existing = function(name, callback)
   Fetch.checkoutFor(near, dir, name, function(repo)
    if repo then return callback(repo.root) end
    local ready = Fetch.readySavedCopy(name)
    callback(if ready then ready.root else nil)
   end)
  end,
  tandem = Tandem.clone,
  saved = function(name) return M.agentClones()[string.lower(name)] end,
  validate = validate, ask = ask, remember = M.rememberAgentClone, runner = Fetch.runner,
 }, done)
end

local activeAgentFix: AgentFix.Engine? = nil
local activeBotFix: AgentFix.Fix? = nil

export type AgentFixRequest = {
 key: string, clone: string, checkout: string, branch: string, base: string, headOid: string,
 number: number, regenerate: { [string]: { string } }?, input: AgentFix.Input?,
}

-- Start separately from clone lookup, so the glue can finish its folder question first.
-- A ready fix keeps the single-run slot until returnAgentFix succeeds after Push or Discard.
function M.startAgentFix(request: AgentFixRequest, agent: Agent.Agent, now: number, changed: (AgentFix.Outcome) -> (), done: (AgentFix.Fix?, string?) -> ()): AgentFix.Engine?
 if activeAgentFix and activeAgentFix.busy() then done(nil, "An agent fix already holds a worktree"); return nil end
 activeAgentFix = nil
 local home = Platform.home()
 if not home then done(nil, "The home directory is unknown"); return nil end
 if request.number < 1 or request.number % 1 ~= 0 or not string.match(request.headOid, "^%x+$") or string.sub(request.base, 1, 1) == "-" or request.base == "" then
  done(nil, "Invalid PR refs"); return nil
 end
 local spec: AgentFix.Spec = {
  key = request.key, clone = request.clone, checkout = request.checkout,
  pool = Host.getenv("TANDEM_POOL_ROOT") or (home .. "/.tandem/pool"),
  branch = request.branch, base = request.base, headOid = request.headOid, number = request.number,
  tool = Host.plugin.dir .. "/tools/conflicts", omp = agent.command, model = agent.model,
  effort = agent.effort, regenerate = request.regenerate, input = request.input,
  -- A bot edit runs in macOS Seatbelt; where it is missing the run fails and nothing is applied. Windows has no
  -- sandbox to apply, so there the worker runs unconfined.
  sandbox = if request.input and not Platform.windows() then { exec = "/usr/bin/sandbox-exec", home = home } else nil,
  unconfined = if request.input and Platform.windows() then true else nil,
 }
 if Platform.windows() then
  -- Windows ignores the tool's `#!` line; forward slashes keep backslash escapes out of the agent's shell.
  spec.tool, spec.interpreter = (string.gsub(spec.tool, "\\", "/")), Platform.python()
 end
 local function samePath(a: string, b: string, callback: (boolean?, string?) -> ())
  -- Physical paths protect /tmp versus /private/tmp, symlinked checkouts and, on Windows, case and slashes. Also
  -- reject the source clone itself, which can differ from the currently viewed checkout.
  Fetch.runner({ Platform.python(), "-c", "import os,sys; r=lambda p: os.path.normcase(os.path.realpath(p)); print('same' if r(sys.argv[1]) in [r(p) for p in sys.argv[2:]] else 'different')", a, b, spec.clone }, { timeout_ms = 15_000 }, function(out)
   if out.status ~= 0 then return callback(nil, "Couldn't verify the acquired worktree path") end
   local result = Text.trimEnd(out.stdout)
   callback(if result == "different" then false elseif result == "same" then true else nil, nil)
  end)
 end
 local function resolutions(path: string, callback: ({ { id: string, lines: { AgentFix.ResolvedLine } } }?, string?) -> ())
  Fetch.runner({ "git", "-C", path, "rev-parse", "--absolute-git-dir" }, { timeout_ms = Fetch.GIT_MS }, function(out)
   if out.status ~= 0 then return callback(nil, "Couldn't locate the conflict journal") end
   local ok, rows = pcall(function()
    local journal = Host.json.decode(Host.fs.read(Text.trimEnd(out.stdout) .. "/prguide-conflicts.json", 16 * 1024 * 1024))
    local resolved = {}
    for _, hunk in journal.hunks do
     if hunk.resolved then table.insert(resolved, { id = hunk.id, lines = hunk.resolved.lines }) end
    end
    return resolved
   end)
   callback(if ok then rows else nil, if ok then nil else Text.errorLine(rows))
  end)
 end
 local engine: AgentFix.Engine
 activeBotFix = nil
 engine = AgentFix.engine(spec, { runner = Fetch.runner, decode = Host.json.decode, samePath = samePath, resolutions = resolutions }, now, changed, function(fix, err)
  if fix and request.input then activeBotFix = fix end
  if not fix and not engine.busy() then activeAgentFix = nil end
  done(fix, err)
 end)
 activeAgentFix = engine
 engine.begin()
 return engine
end

-- The later lifecycle calls this only after a successful Push or confirmed Discard. It runs
-- no Git write and never pushes; both ownership guards always reach treehouse.
function M.returnAgentFix(path: string, done: (boolean?, string?) -> ())
 local engine = activeAgentFix
 if not engine then return done(nil, "No agent fix holds a worktree") end
 local lease = engine.held()
 if not lease or lease.path ~= path then return done(nil, "The worktree does not belong to this agent fix") end
 engine.release(function(ok, err)
  if ok and (engine.held() ~= nil or engine.busy()) then ok, err = nil, "The engine still holds the worktree lease" end
  if ok and activeAgentFix == engine then activeAgentFix, activeBotFix = nil, nil end
  done(ok, err)
 end)
end

export type AgentFixRead = { files: { [string]: string }, diff: string, originals: { [string]: ReviewFix.Original }? }

local function ownsAgentFix(fix: AgentFix.Fix): boolean
 local engine = activeAgentFix
 local lease = if engine then engine.held() else nil
 return lease ~= nil and lease.path == fix.worktree
end

-- Read only paths with recorded conflicts, at the exact commit the reader will push.
function M.readAgentFix(fix: AgentFix.Fix, done: (AgentFixRead?, string?) -> ())
 if not ownsAgentFix(fix) then return done(nil, "The worktree does not belong to this agent fix") end
 local commands, problem = ReviewFix.readCommands(fix)
 if not commands then return done(nil, problem) end
 local result: AgentFixRead = { files = {}, diff = "" }
 local index = 0
 local nextCommand: () -> ()
 nextCommand = function()
  index += 1
  local command = (commands :: { ReviewFix.Command })[index]
  if not command then return done(result, nil) end
  local called = false
  local function read(out: Github.Out)
   if called then return end
   called = true
   if out.status ~= 0 or out.timed_out then return done(nil, if out.timed_out then "Reading the fix timed out" else Text.errorLine(if out.stderr ~= "" then out.stderr else "Git could not read the fix")) end
   if not ownsAgentFix(fix) then return done(nil, "The worktree lease changed") end
   if command.argv[4] == "rev-parse" then
    if activeBotFix == fix then
     -- Bot edits have exact original sides in the retained engine result, with no conflict journal.
     -- Only this exact ready result may use them; commit files still pass ReviewFix.build.
     local snapshots: { [string]: ReviewFix.Original } = {}
     for _, hunk in fix.hunks do
      snapshots[hunk.id] = { path = hunk.path, start = hunk.start, base = table.clone(hunk.base), ours = table.clone(hunk.ours), theirs = table.clone(hunk.theirs) }
     end
     result.originals = snapshots
     return nextCommand()
    end
    local ok, originals = pcall(function()
     local journal = Host.json.decode(Host.fs.read(Text.trimEnd(out.stdout) .. "/prguide-conflicts.json", 16 * 1024 * 1024))
     assert(type(journal.identity) == "string" and string.sub(journal.identity, 1, #fix.headOid + 1) == fix.headOid .. ":", "The conflict journal belongs to a different pull request head")
     local snapshots: { [string]: ReviewFix.Original } = {}
     local function lines(value: any): { string }
      assert(type(value) == "table", "The original conflict sides are missing")
      local exact: { string } = {}
      for _, line in value do
       assert(type(line) == "string", "The original conflict side is invalid")
       table.insert(exact, (string.gsub(line, "[\r\n]+$", "")))
      end
      return exact
     end
     for _, hunk in journal.hunks do
      assert(type(hunk.id) == "string" and not snapshots[hunk.id], "The conflict journal has missing or duplicate ids")
      snapshots[hunk.id] = { path = hunk.path, start = hunk.start, base = lines(hunk.base), ours = lines(hunk.ours), theirs = lines(hunk.theirs) }
     end
     return snapshots
    end)
    if not ok then return done(nil, Text.errorLine(originals)) end
    result.originals = originals
   elseif command.argv[5] == "diff" then result.diff = out.stdout
   else
    local ref = command.argv[#command.argv]
    result.files[string.sub(ref, #fix.commit + 2)] = out.stdout
   end
   nextCommand()
  end
  local ok, err = pcall(Fetch.runner, command.argv, { cwd = command.cwd, timeout_ms = Fetch.GIT_MS }, read)
  if not ok then read({ status = -1, stdout = "", stderr = tostring(err), timed_out = false }) end
 end
 nextCommand()
end

-- P is the only caller. Validate the pure plan again, read the PR's actual head repo
-- (including forks), and preserve Git's ordinary non-fast-forward protection.
function M.pushAgentFix(plan: ReviewFix.Plan, canPush: () -> boolean, done: (boolean?, string?) -> ())
 local validated, problem = ReviewFix.plan("push", plan.request)
 if plan.kind ~= "push" or not validated or not validated.command then return done(nil, problem or "No push is planned") end
 local request, fix = validated.request, validated.request.fix
 if not ownsAgentFix(fix) then return done(nil, "The worktree does not belong to this agent fix") end
 local finished = false
 local function finish(ok: boolean?, err: string?)
  if finished then return end
  finished = true
  done(ok, err)
 end
 local function run(argv: { string }, callback: (Github.Out) -> ())
  if not canPush() then return finish(nil, "The selected fix changed") end
  local called = false
  local function reply(out: Github.Out)
   if called or finished then return end
   called = true
   if not ownsAgentFix(fix) then return finish(nil, "The worktree lease changed") end
   if out.status ~= 0 or out.timed_out then return finish(nil, if out.timed_out then "Pushing the fix timed out" else Text.errorLine(if out.stderr ~= "" then out.stderr else "Git could not push the fix")) end
   callback(out)
  end
  local ok, err = pcall(Fetch.runner, argv, { cwd = fix.worktree, timeout_ms = 60_000 }, reply)
  if not ok then reply({ status = -1, stdout = "", stderr = tostring(err), timed_out = false }) end
 end
 run({ "gh", "pr", "view", tostring(request.number), "--repo", request.repo, "--json", "headRefName,headRefOid,headRepository,headRepositoryOwner" }, function(out)
  local ok, meta = pcall(Host.json.decode, out.stdout)
  if not ok or type(meta) ~= "table" or meta.headRefName ~= fix.branch or type(meta.headRepository) ~= "table" then
   return finish(nil, "The pull request branch changed or is missing")
  end
  local remoteRepo = meta.headRepository.nameWithOwner
  if not remoteRepo and type(meta.headRepositoryOwner) == "table" and type(meta.headRepositoryOwner.login) == "string" and type(meta.headRepository.name) == "string" then
   remoteRepo = meta.headRepositoryOwner.login .. "/" .. meta.headRepository.name
  end
  if type(remoteRepo) ~= "string" then return finish(nil, "The pull request head repository is missing") end
  local remotePlan, err = ReviewFix.plan("push", request, nil, remoteRepo)
  if not remotePlan or not remotePlan.command then return finish(nil, err) end
  local command = remotePlan.command
  -- Reconcile an earlier push whose response was lost. Never send it twice on a cleanup retry.
  if meta.headRefOid ~= fix.headOid and meta.headRefOid ~= fix.commit then return finish(nil, "The pull request head changed; refresh the board") end
  run({ "git", "-C", fix.worktree, "ls-remote", "--heads", command.argv[5], "refs/heads/" .. fix.branch }, function(remote)
   local head = string.match(remote.stdout, "^(%x+)%s+refs/heads/")
   if head == fix.commit then return finish(true, nil) end
   if head ~= fix.headOid then return finish(nil, "The remote branch changed; refresh the board") end
   run(command.argv, function() finish(true, nil) end)
  end)
 end)
end

return M
