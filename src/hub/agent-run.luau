--!strict
-- An agent fix's flight, the part only a live block holds: finding the clone (asking for a folder when there is none),
-- reading and revalidating the PR's refs, starting the engine, settling its outcome onto the board, and stopping,
-- retrying or opening its worktree. The flight's lease return lives in hub/runtime, since closing the block uses it.
local Agent = require("../agent")
local AgentFix = require("./agent-fix")
local AgentHost = require("../agent-host")
local Details = require("./details")
local Fetch = require("../fetch")
local Github = require("../github")
local Host = require("../host")
local Model = require("./model")
local Platform = require("../platform")
local Runtime = require("./runtime")
local State = require("./state")
local Store = require("./store")

type Block = Runtime.Block
type AgentFlight = Runtime.AgentFlight

local FIXTURES, draw, reasonOf = Runtime.FIXTURES, Runtime.draw, Runtime.reasonOf
local forgetReturned, returnAgentLease, closeAgentFlight = Runtime.forgetReturned, Runtime.returnAgentLease, Runtime.closeAgentFlight
local carryOn = Store.carryOn
local readFeedback = Details.readFeedback

-- Folder selection is the smallest host bridge available. No shell interpolation, and all
-- process effects use Fetch.runner. Cancel is an ordinary nil answer.
local function agentFolder(b: Block, flight: AgentFlight, prompt: string, done: (string?, string?) -> ())
	local replied = false
	local function finish(path: string?, err: string?)
		if replied then return end
		replied = true
		flight.cancel = nil
		done(path, err)
	end
	flight.cancel = function() finish(nil, nil) end
	local ok, err = pcall(Fetch.runner, {
		"osascript", "-e", "on run argv\ntry\nreturn POSIX path of (choose folder with prompt (item 1 of argv))\non error number -128\nreturn \"\"\nend try\nend run", prompt,
	}, { timeout_ms = 5 * 60_000 }, function(out)
		if b.closed or flight.stopping then return finish(nil, nil) end
		if out.status ~= 0 or out.timed_out then
			return finish(nil, if out.timed_out then "Folder selection timed out" else reasonOf(out.stderr))
		end
		local path = string.gsub(out.stdout, "[\r\n]+$", "")
		finish(if path == "" then nil else path, nil)
	end)
	if not ok then finish(nil, tostring(err)) end
end

local function settleAgent(b: Block, cx: BlockCx, flight: AgentFlight, outcome: AgentFix.Outcome)
	if b.agentFlight ~= flight or flight.settled then return end
	if outcome.kind == "running" then
		if not b.closed and not flight.stopping then State.agentOutcome(b.s, flight.key, outcome); draw(b, cx) end
		return
	end
	flight.settled = true
	if outcome.kind == "failed" then flight.failure = outcome.reason end
	-- A ready callback is preserved even if closure was detected just before it arrived.
	if outcome.kind == "ready" then
		b.s.agents[flight.key] = { kind = "ready", fix = outcome.fix, reviewed = {} }
		State.project(b.s)
	elseif outcome.kind == "failed" and b.closed then
		State.agentFailed(b.s, flight.key, outcome.reason, outcome.worktree)
	elseif not b.closed then
		State.agentOutcome(b.s, flight.key, outcome)
	end
	forgetReturned(b, flight)
	if not b.closed then draw(b, cx) end
end

local function startAgentEngine(b: Block, cx: BlockCx, flight: AgentFlight, clone: string, checkout: string, pr: Model.HubPR)
	if not carryOn(b, cx, flight) then return end
	-- HubPR has baseBranch and headOid, but no head branch. Read and revalidate all three
	-- together; never guess a branch from a local checkout or pass a stale head to the engine.
	local replied = false
	-- A bot fix reads its feedback before the refs: what it read must still be what the board has when the refs arrive.
	local expected: { signature: string, prompt: string }? = nil
	local function metadata(out: Github.Out)
		if replied then return end
		replied = true
		if not carryOn(b, cx, flight) then return end
		local ok, meta = pcall(Host.json.decode, out.stdout)
		local latest = State.prOf(b.s, pr.key)
		if out.status ~= 0 or out.timed_out or not ok or type(meta) ~= "table" then
			settleAgent(b, cx, flight, { kind = "failed", reason = if out.timed_out then "Reading PR refs timed out" else reasonOf(out.stderr ~= "" and out.stderr or "No PR refs were returned") })
			return forgetReturned(b, flight)
		end
		if not latest or latest.headOid ~= pr.headOid or latest.baseBranch ~= pr.baseBranch or meta.headRefOid ~= pr.headOid or meta.baseRefName ~= pr.baseBranch
			or type(meta.headRefName) ~= "string" or meta.headRefName == "" then
			settleAgent(b, cx, flight, { kind = "failed", reason = "PR refs changed or are missing; refresh the board" })
			return forgetReturned(b, flight)
		end
		if flight.bot then
			local _, prompt = State.botFeedback(b.s, pr.key)
			if not expected or State.feedbackSignature(latest) ~= expected.signature or prompt ~= expected.prompt then
				settleAgent(b, cx, flight, { kind = "failed", reason = "Feedback changed; refresh the board" })
				return forgetReturned(b, flight)
			end
		end
		local doneCalled = false
		local function completed(fix: AgentFix.Fix?, err: string?)
			if doneCalled then return end
			doneCalled = true
			if err == "An agent fix already holds a worktree" and not flight.settled then
				settleAgent(b, cx, flight, { kind = "stopped" })
				if not b.closed then cx:toast("info", "One fix at a time") end
			end
			if not flight.settled then
				settleAgent(b, cx, flight, if fix then { kind = "ready", fix = fix }
					elseif err == "stopped" then { kind = "stopped" }
					else { kind = "failed", reason = err or "The agent returned no result" })
			end
			-- During a synchronous callback the handle is assigned just after this returns.
			if flight.engine then forgetReturned(b, flight) end
		end
		flight.starting = true
		local started, engine = pcall(AgentHost.startAgentFix, {
			key = pr.key, clone = clone, checkout = checkout, branch = meta.headRefName,
			base = pr.baseBranch, headOid = pr.headOid, number = pr.number, input = flight.input,
		}, b.agent :: Agent.Agent, b.s.now, function(outcome) settleAgent(b, cx, flight, outcome) end, completed)
		if started then flight.engine = engine else completed(nil, tostring(engine)) end
		flight.starting = false
		if not flight.engine then
			completed(nil, "The agent could not start")
			forgetReturned(b, flight)
		else
			-- Reconcile synchronous terminal callbacks once the handle is available.
			forgetReturned(b, flight)
			if b.closed or flight.stopping then closeAgentFlight(b, flight) end
		end
		if not b.closed then draw(b, cx) end
	end
	local function refs()
		if not carryOn(b, cx, flight) then return end
		local ok, err = pcall(Fetch.runner, Github.commands.refs(pr).argv, { timeout_ms = 30_000 }, metadata)
		if not ok then metadata({ status = -1, stdout = "", stderr = tostring(err), timed_out = false }) end
	end
	if flight.bot then
		readFeedback(b, pr, function(details, err)
			if not carryOn(b, cx, flight) then return end
			local latest = State.prOf(b.s, pr.key)
			local input, prompt = State.botFeedback(b.s, pr.key)
			if not details or not latest or not input or not prompt then
				return settleAgent(b, cx, flight, { kind = "failed", reason = err or "No bot feedback bodies are available" })
			end
			expected = { signature = State.feedbackSignature(latest), prompt = prompt }
			flight.input = input
			refs()
		end)
	else refs() end
end

local function beginAgent(b: Block, cx: BlockCx, key: string, mode: "fix" | "clone" | "folder")
	if b.closed then return end
	local pr = State.prOf(b.s, if key ~= "" then key else b.s.selected or "")
	-- One owner per branch: no fix starts, retries or looks for a clone on a PR Tandem watches.
	if not pr or pr.tandem or b.s.busy[pr.key] then return end
	if b.agentFlight then forgetReturned(b, b.agentFlight) end
	if b.agentFlight or State.agentRunning(b.s) then return cx:toast("info", "One fix at a time") end
	local existing = b.s.agents[pr.key]
	if existing and (existing.kind == "ready" or existing.kind == "pushing") then return end
	if not b.fixture and not b.agent then
		State.agentFailed(b.s, pr.key, "No agent is available", if existing and existing.kind == "failed" then existing.worktree else nil)
		return draw(b, cx)
	end
	if pr.baseBranch == "" or pr.headOid == "" or pr.number < 1 then
		State.agentFailed(b.s, pr.key, "PR refs are missing; refresh the board", if existing and existing.kind == "failed" then existing.worktree else nil)
		return draw(b, cx)
	end
	b.s.now = if b.fixture then b.s.now else Host.time()
	if not State.beginAgent(b.s, pr.key, b.s.now) then return cx:toast("info", "One fix at a time") end
	local flight: AgentFlight = { key = pr.key, settled = false, stopping = false, releasing = false, bot = b.botKeys[pr.key] == true }
	b.agentFlight = flight
	draw(b, cx)
	if not carryOn(b, cx, flight) then return end
	if b.fixture then
		-- Even ordinary sample boards stay entirely local. ⌘R advances one recorded event.
		local data: any = FIXTURES["agent-cards"]()
		if flight.bot then data = require("../../fixtures/hub/summary") end
		b.s.agents[pr.key] = { kind = "running", run = AgentFix.bind(AgentFix.start(pr.key, b.s.now), data.spec(pr.key)) }
		flight.fixtureStep = 0
		State.project(b.s)
		return draw(b, cx)
	end
	local dir = cx.cwd or Platform.home() or ""
	local near: Fetch.Repo? = nil
	local checkout: string? = nil
	local cancelled, missing, answered = false, false, false
	local function cloned(path: string?, err: string?)
		if answered then return end
		answered = true
		if not carryOn(b, cx, flight) then return end
		if path then return startAgentEngine(b, cx, flight, path, checkout or path, pr) end
		flight.settled = true
		b.agentFlight = nil
		if cancelled or missing then State.noAgentClone(b.s, pr.key, pr.repo)
		else State.agentFailed(b.s, pr.key, err or "No clone was found", nil) end
		draw(b, cx)
	end
	local function find(allowClone: boolean)
		local ok, err = pcall(AgentHost.findAgentClone, near, dir, pr.repo, function(slug, answer)
			if not carryOn(b, cx, flight) then return answer(nil) end
			if not allowClone then missing = true; return answer(nil) end
			agentFolder(b, flight, "Choose a parent folder for " .. slug, function(parent, why)
				if not carryOn(b, cx, flight) then return answer(nil) end
				if why then cloned(nil, why); return answer(nil) end
				if not parent then cancelled = true; return answer(nil) end
				local name = string.match(slug, "[^/]+$") :: string
				answer(string.gsub(parent, "/+$", "") .. "/" .. name)
			end)
		end, cloned)
		if not ok then cloned(nil, tostring(err)) end
	end
	local function choose()
		if mode ~= "folder" then return find(mode == "clone") end
		agentFolder(b, flight, "Choose the existing clone of " .. pr.repo, function(path, err)
			if not carryOn(b, cx, flight) then return end
			if err then return cloned(nil, err) end
			if not path then cancelled = true; return cloned(nil, nil) end
			local checked = false
			local function selected(repo: Fetch.Repo?, why: string?)
				if checked then return end
				checked = true
				if not carryOn(b, cx, flight) then return end
				if not repo then return cloned(nil, why or "The selected folder is not a clone") end
				local ok, problem = pcall(AgentHost.rememberAgentClone, pr.repo, repo.root)
				if not ok or problem then return cloned(nil, tostring(problem)) end
				near = repo
				find(false)
			end
			local ok, why = pcall(Fetch.findRepo, path, selected)
			if not ok then selected(nil, tostring(why)) end
		end)
	end
	-- Resolve the reader's root even when cwd is a subfolder. Both it and the source clone
	-- are protected by #15's physical-path check at worktree acquisition.
	local checked = false
	local function found(repo: Fetch.Repo?)
		if checked then return end
		checked = true
		if not carryOn(b, cx, flight) then return end
		near, checkout = repo, if repo then repo.root else nil
		choose()
	end
	local ok, err = pcall(Fetch.findRepo, dir, found)
	if not ok then cloned(nil, tostring(err)) end
end

local function advanceAgentFixture(b: Block, cx: BlockCx): boolean
	local flight = b.agentFlight
	if not flight or flight.fixtureStep == nil or flight.settled then return false end
	local data: any = if flight.bot then require("../../fixtures/hub/summary") else FIXTURES["agent-cards"]()
	flight.fixtureStep += 1
	local event = data.events()[flight.fixtureStep]
	local current = b.s.agents[flight.key]
	if event and current and current.kind == "running" then
		settleAgent(b, cx, flight, AgentFix.step(current.run, event))
	end
	if flight.settled then b.agentFlight = nil end
	return true
end

local function stopAgent(b: Block, cx: BlockCx, key: string)
	local flight = b.agentFlight
	local agent = b.s.agents[key]
	if not agent or agent.kind ~= "running" then return end
	if flight and flight.key == key then
		if flight.stopping then return end
		flight.stopping = true
		if flight.cancel then flight.cancel() end
		if flight.engine then return flight.engine.stop() end
		if flight.starting then return end
		flight.settled = true
		b.agentFlight = nil
	end
	State.agentOutcome(b.s, key, { kind = "stopped" })
	draw(b, cx)
end
local function retryAgent(b: Block, cx: BlockCx, key: string)
	local agent, flight = b.s.agents[key], b.agentFlight
	if not agent or agent.kind ~= "failed" then return end
	-- On a PR Tandem watches this is Return worktree: it retries the guarded return and never starts a fixer.
	local owner = State.prOf(b.s, key)
	local cleanup = owner ~= nil and owner.tandem
	local function afterReturn()
		if not cleanup then return beginAgent(b, cx, key, "fix") end
		State.project(b.s)
		draw(b, cx)
	end
	-- A failed lease return retains the handle. Retry first retries that exact guarded
	-- return, and starts no engine until it succeeds. Never release a ready worktree.
	if flight and flight.key == key then
		local disposition = forgetReturned(b, flight)
		if disposition == "wait" then return cx:toast("info", "One fix at a time") end
		if disposition ~= "release" then return afterReturn() end
		returnAgentLease(b, flight, function(ok, err)
			if not ok then
				local lease = (flight.engine :: AgentFix.Engine).held()
				State.agentFailed(b.s, key, err or "The worktree lease could not be returned", if lease then lease.path else nil, lease ~= nil)
				return draw(b, cx)
			end
			if b.closed then return end
			afterReturn()
		end)
		return
	end
	beginAgent(b, cx, key, "fix")
end
local function openWorktree(b: Block, cx: BlockCx, key: string)
	local agent = b.s.agents[key]
	if not agent or agent.kind ~= "failed" or not agent.worktree then return end
	if b.fixture then return cx:toast("info", "Sample worktree", agent.worktree) end
	-- The system's file manager is the available folder-opening surface; the path stays a single argv.
	local replied = false
	local function opened(out: Github.Out)
		if replied then return end
		replied = true
		if b.closed then return end
		if out.status ~= 0 or out.timed_out then cx:toast("error", "Couldn't open worktree: " .. reasonOf(out.stderr ~= "" and out.stderr or "Opening the folder failed")) end
	end
	local ok, err = pcall(Fetch.runner, Platform.openCommand(agent.worktree), { timeout_ms = 15_000 }, opened)
	if not ok then opened({ status = -1, stdout = "", stderr = tostring(err), timed_out = false }) end
end

return {
	beginAgent = beginAgent,
	advanceAgentFixture = advanceAgentFixture,
	stopAgent = stopAgent,
	retryAgent = retryAgent,
	openWorktree = openWorktree,
}
