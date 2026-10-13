--!strict
-- No host, model or network. Scripted effects assert the engine's exact command sequence.
local AgentFix = require("../src/hub/agent-fix")
local Tree: any = require("../fixtures/hub/agent/treehouse")
local Tool: any = require("../fixtures/hub/agent/conflicts")
local Omp: any = require("../fixtures/hub/agent/omp")
local NOW = 1791590400
local WORKTREE = "/pool/acme/web/wt-1"
local HEAD = string.rep("a", 40)
local COMMIT = string.rep("b", 40)
local POOL_HEAD = string.rep("d", 40)

local function equal(a: { string }, b: { string })
 assert(#a == #b, "argv length: " .. table.concat(a, " "))
 for i, value in a do assert(value == b[i], "argv at " .. i .. ": " .. value .. " versus " .. tostring(b[i])) end
end

-- Set while a scenario runs as on Windows, where the conflicts tool runs through its interpreter.
local interpreter: string? = nil

local function spec(): AgentFix.Spec
 return { key = "acme/web#15", clone = "/clone", checkout = "/reader", pool = "/pool",
  branch = "topic", base = "main", headOid = HEAD, number = 15, tool = "/plugin/tools/conflicts",
  omp = "/omp", model = "provider/model", effort = "high", interpreter = interpreter }
end

type Entry = { argv: { string }, cwd: string?, status: number?, stdout: string?, decoded: any? }
local function git(args: { string }, stdout: string?, status: number?): Entry
 local argv = { "git", "--literal-pathspecs", "-C", WORKTREE }
 table.move(args, 1, #args, 5, argv)
 return { argv = argv, cwd = WORKTREE, stdout = stdout, status = status }
end
local function tool(args: { string }, decoded: any): Entry
 local argv = if interpreter then { interpreter, "/plugin/tools/conflicts" } else { "/plugin/tools/conflicts" }
 table.move(args, 1, #args, #argv + 1, argv)
 return { argv = argv, cwd = WORKTREE, decoded = decoded }
end
local function acquisition(): Entry
 return { argv = Tree.get.argv, cwd = "/clone", decoded = Tree.get.reply }
end
local function returned(status: number?): Entry
 return { argv = Tree["return"].argv, cwd = "/clone", status = status, decoded = Tree["return"].reply }
end
local function preparation(conflict: boolean): { Entry }
 local entries = {
  acquisition(), git({ "status", "--porcelain" }, ""), git({ "rev-parse", "HEAD" }, POOL_HEAD .. "\n"),
  git({ "fetch", "--no-tags", "origin", "+refs/pull/15/head:refs/prguide/agent/head", "+refs/heads/main:refs/remotes/origin/main" }),
  git({ "rev-parse", "refs/prguide/agent/head" }, HEAD .. "\n"),
  git({ "-c", "core.hooksPath=/dev/null", "switch", "--detach", HEAD }),
  git({ "-c", "core.hooksPath=/dev/null", "-c", "rerere.enabled=true", "-c", "rerere.autoupdate=true", "-c", "merge.conflictStyle=diff3", "merge", "--no-commit", "--no-ff", "origin/main" }, "", if conflict then 1 else 0),
 }
 if conflict then table.insert(entries, git({ "rev-parse", "-q", "--verify", "MERGE_HEAD" }, string.rep("c", 40))) end
 return entries
end
local function append(to: { Entry }, entries: { Entry })
 for _, entry in entries do table.insert(to, entry) end
end
local function cleanup(entries: { Entry })
 append(entries, { git({ "reset", "--hard", POOL_HEAD }), git({ "clean", "-fd" }), returned() })
end
local function committed(): { Entry }
 return {
  tool({ "check" }, { remaining = 0 }), git({ "diff", "--name-only", "--diff-filter=U" }, ""),
  git({ "add", "-u" }), git({ "rev-parse", "-q", "--verify", "MERGE_HEAD" }, string.rep("c", 40)),
  git({ "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", "commit", "--no-verify", "-m", "Merge main and resolve conflicts" }),
  git({ "rev-parse", "HEAD" }, COMMIT .. "\n"), git({ "log", "-1", "--format=%s" }, "Merge main and resolve conflicts\n"),
 }
end

local function harness(entries: { Entry }, same: boolean?, delayAt: number?, replacements: any?)
 local calls: { Entry } = {}
 local documents: { [string]: any } = {}
 local waiting: (() -> ())? = nil
 local finished = 0
 local result: AgentFix.Fix? = nil
 local failure: string? = nil
 local outcomes: { AgentFix.Outcome } = {}
 local runner: AgentFix.Runner = function(argv, opts, callback)
  local index = #calls + 1
  local entry = entries[index]
  assert(entry, "unexpected call " .. table.concat(argv, " "))
  equal(argv, entry.argv)
  assert(opts.cwd == entry.cwd, "wrong cwd")
  table.insert(calls, { argv = argv, cwd = opts.cwd, stdout = opts.stdin })
  local stdout = entry.stdout or ("document-" .. index)
  if entry.decoded then documents[stdout] = entry.decoded end
  local function resume()
   callback({ status = entry.status or 0, stdout = stdout, stderr = if entry.status == 1 then "simulated failure" else "", timed_out = false })
   -- Duplicate callbacks must never advance the machine or finish twice.
   callback({ status = 0, stdout = stdout, stderr = "", timed_out = false })
  end
  if delayAt == index then waiting = resume else resume() end
 end
 local engine = AgentFix.engine(spec(), {
  runner = runner, decode = function(value) assert(documents[value]); return documents[value] end,
  samePath = function(a, b, callback)
   assert(a == WORKTREE and b == "/reader")
   callback(same or false, nil)
  end,
  resolutions = function(path, callback) assert(path == WORKTREE); callback(replacements or Tool.resolutions, nil) end,
 }, NOW, function(outcome) table.insert(outcomes, outcome) end, function(fix, err)
  finished += 1
  result, failure = fix, err
 end)
 return {
  engine = engine, calls = calls, outcomes = outcomes,
  resume = function() local resume = waiting :: () -> (); waiting = nil; resume() end,
  finish = function(wantReady: boolean)
   assert(finished == 1, "callback must fire once")
   assert((result ~= nil) == wantReady)
   return result, failure
  end,
  only = function()
   assert(#calls == #entries, "missing calls")
   for _, call in calls do
    for _, word in call.argv do assert(word ~= "push", "engine must never push") end
   end
  end,
 }
end

return function()
 assert(Tree.asOf == NOW)
 local run = AgentFix.start("acme/web#15", NOW)
 assert(run.stage == "worktree" and run.since == NOW and run.left == 0)
 local bound = AgentFix.bind(run, spec())
 local acquired = AgentFix.step(bound, { kind = "worktree", path = WORKTREE })
 assert(acquired.kind == "running" and acquired.run.stage == "merge")
 assert(run.worktree == nil, "transition is pure")
 local hunks = AgentFix.step(acquired.run, { kind = "hunks", hunks = { Tool.transcript[2].reply } })
 assert(hunks.kind == "running" and hunks.run.left == 1)
 local resolved = AgentFix.step(hunks.run, { kind = "resolved", id = "h1", by = "agent", lines = Tool.resolutions[1].lines })
 assert(resolved.kind == "running" and resolved.run.left == 0)
 assert(hunks.run.left == 1 and hunks.run.hunks[1].resolved == nil)
 local duplicate = AgentFix.step(resolved.run, { kind = "resolved", id = "h1", by = "agent", lines = {} })
 assert(duplicate.kind == "running" and duplicate.run.left == 0)
 local invalid = AgentFix.step(run, { kind = "committed", commit = COMMIT, summary = "x" })
 assert(invalid.kind == "failed", "unbound Run cannot invent refs")

 for _, path in { "package-lock.json", "sub/yarn.lock", "bun.lockb", "Cargo.lock", "poetry.lock", "pnpm-lock.yaml", "go.sum", "Package.resolved", "packages.lock.json", "deno.lock", "mix.lock", "Gemfile.lock", "Pipfile.lock", "uv.lock", "composer.lock", "flake.lock", "pubspec.lock", "npm-shrinkwrap.json", "bun.lock" } do
  assert(AgentFix.isLockfile(path))
 end
 assert(AgentFix.regeneration("package-lock.json") ~= nil and AgentFix.regeneration("deno.lock") == nil)
 assert(not AgentFix.isLockfile("lock.txt") and not AgentFix.isLockfile("yarn.lock.ts"))

 -- Clean merge: no omp, ready retains lease until the Push/Discard lifecycle returns it.
 for _, action in { "Push", "Discard" } do
  local entries = preparation(false)
  append(entries, { tool({ "list" }, { hunks = {}, generated = {} }), tool({ "list" }, { hunks = {}, generated = {} }) })
  append(entries, committed())
  cleanup(entries)
  local fake = harness(entries)
  fake.engine.begin()
  local fix = fake.finish(true) :: AgentFix.Fix
  assert(fix.worktree ~= "/reader" and fix.headOid == HEAD and fix.branch == "topic" and fix.base == "main")
  assert(fix.commit == COMMIT and not fix.usedAgent and #fix.hunks == 0)
  assert(fake.engine.held() ~= nil, "ready lease retained before " .. action)
  for _, call in fake.calls do assert(call.argv[1] ~= "/omp") end
  fake.engine.release(function(ok, err) assert(ok and not err) end)
  assert(fake.engine.held() == nil)
  fake.only()
 end

 -- Real hunk transcript, OMP sees only show, replacements are collected from its tool journal.
 local entries = preparation(true)
 append(entries, { tool({ "list" }, Tool.transcript[1].reply), tool({ "show", "h1" }, Tool.transcript[2].reply), tool({ "show", "h2" }, Tool.transcript[3].reply),
  tool({ "list" }, Tool.transcript[1].reply), { argv = Omp.argv, cwd = WORKTREE, stdout = Omp.stdout } })
 append(entries, committed())
 cleanup(entries)
 local agent = harness(entries)
 agent.engine.begin()
 local fix = agent.finish(true) :: AgentFix.Fix
 assert(fix.usedAgent and fix.hunks[1].resolved and fix.hunks[1].resolved.lines[1].tag == "agent")
 for _, call in Omp.toolCalls do assert(call.command ~= "read" and call.command ~= "cat") end
 agent.engine.release(function(ok) assert(ok) end)
 agent.only()

 -- Windows ignores the tool's `#!` line: the engine runs it through Python, and the agent is told the same command.
 interpreter = "python"
 local windows = preparation(true)
 local windowsOmp = table.clone(Omp.argv)
 windowsOmp[#windowsOmp] = AgentFix.prompt('python "/plugin/tools/conflicts"')
 assert(windowsOmp[#windowsOmp] ~= Omp.argv[#Omp.argv])
 append(windows, { tool({ "list" }, Tool.transcript[1].reply), tool({ "show", "h1" }, Tool.transcript[2].reply), tool({ "show", "h2" }, Tool.transcript[3].reply),
  tool({ "list" }, Tool.transcript[1].reply), { argv = windowsOmp, cwd = WORKTREE, stdout = Omp.stdout } })
 append(windows, committed())
 cleanup(windows)
 local onWindows = harness(windows)
 onWindows.engine.begin()
 assert((onWindows.finish(true) :: AgentFix.Fix).usedAgent)
 onWindows.engine.release(function(ok) assert(ok) end)
 onWindows.only()
 interpreter = nil

 -- A lockfile uses the base and regenerates at zero tokens, with full rule provenance.
 local lock = table.clone(Tool.transcript[2].reply)
 lock.path = "package-lock.json"
 lock.theirs = { '{"name":"base"}' }
 local lockList = { hunks = { { id = "h1", path = "package-lock.json", start = 2, lines = 7 } }, generated = { "package-lock.json" } }
 local ruled = preparation(true)
 append(ruled, {
  tool({ "list" }, lockList), tool({ "show", "h1" }, lock),
  tool({ "take", "h1", "theirs" }, { id = "h1", taken = "theirs" }),
  git({ "-c", "core.hooksPath=/dev/null", "checkout", "--theirs", "--", "package-lock.json" }), git({ "add", "--", "package-lock.json" }),
  tool({ "list" }, { hunks = {}, generated = { "package-lock.json" } }),
  { argv = { "npm", "install", "--package-lock-only", "--ignore-scripts" }, cwd = WORKTREE },
  git({ "add", "--", "package-lock.json" }),
 })
 append(ruled, committed())
 cleanup(ruled)
 local rule = harness(ruled, nil, nil, { { id = "h1", lines = { { tag = "theirs", text = '{"name":"base"}' } } } })
 rule.engine.begin()
 local ruleFix = rule.finish(true) :: AgentFix.Fix
 assert(not ruleFix.usedAgent and ruleFix.hunks[1].resolved and ruleFix.hunks[1].resolved.by == "rule")
 assert(ruleFix.hunks[1].resolved.lines[1].text == '{"name":"base"}')
 rule.engine.release(function(ok) assert(ok) end)
 rule.only()

 -- A generic generated file cannot be regenerated without an explicit repository command.
 local generated = preparation(true)
 table.insert(generated, tool({ "list" }, { hunks = {}, generated = { "generated.txt" } }))
 cleanup(generated)
 local missingRule = harness(generated)
 missingRule.engine.begin(); missingRule.finish(false); missingRule.only()

 -- Failure, Stop during get, and Stop during merge return the captured exact lease guards.
 local failed = harness({ acquisition(), git({ "status", "--porcelain" }, " M dirty.txt\n"), returned() })
 failed.engine.begin(); failed.finish(false); failed.only()
 local acquiring = harness({ acquisition(), returned() }, nil, 1)
 acquiring.engine.begin(); acquiring.engine.stop(); acquiring.resume()
 acquiring.finish(false); acquiring.only()
 local pending = preparation(false)
 cleanup(pending)
 local merging = harness(pending, nil, 7)
 merging.engine.begin(); merging.engine.stop()
 assert(#merging.calls == 7, "do not return while git is running")
 merging.resume(); merging.finish(false); merging.only()
 -- A valid lease that aliases the reader's checkout is returned without reset or clean.
 local same = harness({ acquisition(), returned() }, true)
 same.engine.begin()
 local _, sameError = same.finish(false)
 assert(sameError == "Treehouse returned the reader's checkout")
 assert(same.engine.held() == nil and not same.engine.busy())
 same.only()

 -- Failed guarded returns retain this lease too, without ever cleaning the checkout.
 local sameRetry = harness({ acquisition(), returned(1), returned() }, true)
 sameRetry.engine.begin(); sameRetry.finish(false)
 assert(sameRetry.engine.held() ~= nil)
 sameRetry.engine.release(function(ok) assert(ok) end)
 sameRetry.only()

 -- Missing lease guards cannot be returned safely and remain a reconciliation failure.
 local invalid = harness({ { argv = Tree.get.argv, cwd = "/clone", decoded = { path = WORKTREE, lease_holder = "prguide" } } })
 invalid.engine.begin(); invalid.finish(false)
 assert(invalid.engine.held() == nil and invalid.engine.busy())
 invalid.engine.release(function(ok, err)
  assert(not ok and err == "The worktree lease needs reconciliation")
 end)
 invalid.only()

 -- A failed return retains the lease and can be retried without running the job again.
 local retry = harness({ acquisition(), git({ "status", "--porcelain" }, "dirty\n"), returned(1), returned() })
 retry.engine.begin(); retry.finish(false)
 assert(retry.engine.held() ~= nil)
 retry.engine.release(function(ok) assert(ok) end)
 retry.only()

 -- Clone precedence and one folder question, with exact partial-clone argv.
 local order, asks, cloneCalls = {}, 0, 0
 local tandemHit: string? = "/tandem/clone"
 local savedReads = 0
 local function lookup(): AgentFix.CloneLookup
  return {
   existing = function(_, callback) table.insert(order, "existing"); callback(nil) end,
   tandem = function(_, callback) table.insert(order, "tandem"); callback(tandemHit) end,
   saved = function(_) savedReads += 1; return "/kv/clone" end,
   validate = function(path, _, callback) callback(path ~= "/kv/clone") end,
   ask = function(_, callback) asks += 1; callback("/chosen/clone"); callback("/ignored") end,
   remember = function(slug, path) assert(slug == "acme/web" and path == "/chosen/clone"); return nil end,
   runner = function(argv, opts, callback)
    cloneCalls += 1
    equal(argv, { "gh", "repo", "clone", "acme/web", "/chosen/clone", "--", "--filter=blob:none", "--no-checkout" })
    assert(opts.cwd == nil)
    callback({ status = 0, stdout = "", stderr = "", timed_out = false })
   end,
  }
 end
 AgentFix.locateClone("acme/web", lookup(), function(path, err) assert(path == "/tandem/clone" and not err) end)
 assert(table.concat(order, ",") == "existing,tandem" and savedReads == 0 and asks == 0)
 tandemHit = nil
 AgentFix.locateClone("acme/web", lookup(), function(path, err) assert(path == "/chosen/clone" and not err) end)
 assert(asks == 1 and cloneCalls == 1)
end
