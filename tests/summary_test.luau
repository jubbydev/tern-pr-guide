--!strict
-- Pure feedback/keys/state acceptance plus injected read-only calls and the actual bot engine.
local AgentFix = require("../src/hub/agent-fix")
local Fixes = require("../src/hub/fixes")
local Keys = require("../src/keys")
local ReviewFix = require("../src/hub/review-fix")
local State = require("../src/hub/state")
local Summary = require("../src/hub/summary")
local Fixture: any = require("../fixtures/hub/summary")

local HEAD, COMMIT, POOL_HEAD = string.rep("a", 40), string.rep("b", 40), string.rep("d", 40)
local WORKTREE = "/pool/acme/web/wt-1"

local function copy(value: any): any
	if type(value) ~= "table" then return value end
	local out = {}
	for key, item in value do out[key] = copy(item) end
	return out
end

local function fresh(): State.State
	local s = State.new(copy(Fixture.prs), Fixture.asOf, nil)
	for _, details in Fixture.details do State.setDetails(s, copy(details)) end
	return s
end

local function card(s: State.State, key: string): State.Card
	local found = State.card(s, key)
	assert(found, "missing card " .. key)
	return found
end

local function equal(actual: { string }, expected: { string })
	assert(#actual == #expected, "argv length: " .. table.concat(actual, " "))
	for i, value in expected do assert(actual[i] == value, "argv at " .. i) end
end

type Entry = { argv: { string }, stdout: string?, status: number?, cwd: string?, stderr: string? }
local function git(args: { string }, stdout: string?, status: number?): Entry
	local argv = { "git", "--literal-pathspecs", "-C", WORKTREE }
	table.move(args, 1, #args, 5, argv)
	return { argv = argv, cwd = WORKTREE, stdout = stdout or "", status = status }
end

-- These are the engine's actual injected effects. Unexpected commands fail, including any push,
-- conflicts-tool call, merge or journal read on the bot path.
local SANDBOX = "/usr/bin/sandbox-exec"
local STATE = WORKTREE .. "/.prguide-omp-state"
-- The reserved state folder is set up before the worker and removed straight after it, whatever its outcome.
-- `unconfined` is Windows: no sandbox exists, so the unchanged omp argv runs straight in the worktree.
local function botEngine(mode: "ready" | "stop" | "unsandboxed" | "unconfined" | "tracked" | "exists" | "failed" | "unclean")
	local stopDuringAgent = mode == "stop"
	local s = fresh()
	local key = Fixture.details.bot.key
	local spec = Fixture.spec(key)
	if mode == "unsandboxed" or mode == "unconfined" then spec.sandbox = nil end
	if mode == "unconfined" then spec.unconfined = true end
	local entries: { Entry } = {
		{ argv = { "treehouse", "--root", "/pool", "get", "--lease", "--lease-holder", "prguide", "--no-fetch", "--json" }, cwd = "/clone", stdout = "lease" },
		git({ "status", "--porcelain" }), git({ "rev-parse", "HEAD" }, POOL_HEAD .. "\n"),
		git({ "fetch", "--no-tags", "origin", "+refs/pull/1904/head:refs/prguide/agent/head", "+refs/heads/main:refs/remotes/origin/main" }),
		git({ "rev-parse", "refs/prguide/agent/head" }, HEAD .. "\n"),
		git({ "-c", "core.hooksPath=/dev/null", "switch", "--detach", HEAD }),
	}
	if mode == "unconfined" then
		table.insert(entries, { argv = Fixture.transcripts.bot.argv, cwd = WORKTREE, stdout = Fixture.transcripts.bot.stdout })
	elseif mode ~= "unsandboxed" then
		table.insert(entries, git({ "ls-files", "--", ".prguide-omp-state" }, if mode == "tracked" then ".prguide-omp-state/omp/logs/omp.log\n" else ""))
		if mode ~= "tracked" then
			table.insert(entries, { argv = { "/bin/mkdir", STATE }, cwd = WORKTREE, stdout = "", status = if mode == "exists" then 1 else 0, stderr = "File exists" })
			if mode ~= "exists" then
				table.insert(entries, { argv = { "/bin/mkdir", STATE .. "/omp" }, cwd = WORKTREE, stdout = "" })
				table.insert(entries, { argv = { SANDBOX }, cwd = WORKTREE, stdout = Fixture.transcripts.bot.stdout,
					status = if mode == "failed" then 1 else 0, stderr = if mode == "failed" then "boom" else "" })
				-- Removed before git sees the tree, and only by its exact path.
				table.insert(entries, { argv = { "/bin/rm", "-rf", STATE }, cwd = WORKTREE, stdout = "", status = if mode == "unclean" then 1 else 0, stderr = "busy" })
			end
		end
	end
	if mode == "ready" or mode == "unconfined" then
		for _, entry in {
			git({ "rev-parse", "HEAD" }, HEAD .. "\n"), git({ "diff", "--name-only", "--diff-filter=U" }),
			git({ "add", "--all" }),
			git({ "diff", "--cached", "--no-color", "--no-ext-diff", "--no-textconv", "--no-renames", "--unified=3", "--src-prefix=a/", "--dst-prefix=b/", HEAD, "--" }, Fixture.botDiff),
			git({ "diff", "--cached", "--check" }),
			git({ "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false", "commit", "--no-verify", "-m", "Address bot review comments" }),
			git({ "rev-parse", "HEAD" }, COMMIT .. "\n"),
		} do table.insert(entries, entry) end
	end
	for _, entry in {
		git({ "reset", "--hard", POOL_HEAD }), git({ "clean", "-fd" }),
		{ argv = { "treehouse", "--root", "/pool", "return", WORKTREE, "--if-lease-holder", "prguide", "--if-lease-id", "lease-19" }, cwd = "/clone", stdout = "" },
	} do table.insert(entries, entry) end
	local calls: { Entry } = {}
	local pending: (() -> ())? = nil
	local finished, released = 0, false
	local fix: AgentFix.Fix? = nil
	assert(State.beginAgent(s, key, Fixture.asOf))
	local engine = AgentFix.engine(spec, {
		runner = function(argv, opts, done)
			local entry = entries[#calls + 1]
			assert(entry, "unexpected call " .. table.concat(argv, " "))
			assert(opts.cwd == entry.cwd and opts.stdin == nil)
			if argv[1] == SANDBOX then
				-- The worker runs only inside the write sandbox, with the unchanged omp argv behind a state-only env.
				local profile = AgentFix.sandboxProfile(WORKTREE, "/home/prguide") :: string
				assert(argv[2] == "-p" and argv[3] == profile and opts.timeout_ms == 20 * 60_000)
				assert(argv[4] == "/usr/bin/env" and argv[5] == "XDG_STATE_HOME=" .. STATE, "only XDG_STATE_HOME moves")
				for _, word in argv do assert(not string.find(word, "XDG_DATA_HOME", 1, true)) end
				local inner = table.move(argv, 6, #argv, 1, {})
				equal(inner, Fixture.transcripts.bot.argv)
				equal(inner, { "/omp", "-p", "--no-session", "--no-extensions", "--no-skills", "--no-rules", "--no-lsp", "--no-title",
					"--tools", "read,edit,write,grep,glob", "--model", "provider/model", "--thinking", "high", AgentFix.botPrompt(Fixture.details.bot) })
			else
				assert(argv[1] ~= "/omp" or mode == "unconfined", "the bot worker must never run unwrapped")
				if argv[1] == "/omp" then assert(opts.timeout_ms == 20 * 60_000 and argv[#argv] == AgentFix.botPrompt(Fixture.details.bot)) end
				equal(argv, entry.argv)
			end
			for _, word in argv do assert(word ~= "push" and word ~= "--force" and word ~= "--force-with-lease") end
			table.insert(calls, { argv = argv, cwd = opts.cwd })
			local function resume()
				done({ status = entry.status or 0, stdout = entry.stdout or "", stderr = entry.stderr or "", timed_out = false })
				-- Duplicate responses cannot start a second commit or return.
				done({ status = 0, stdout = entry.stdout or "", stderr = "", timed_out = false })
			end
			if argv[1] == SANDBOX and stopDuringAgent then pending = resume else resume() end
		end,
		decode = function(text)
			assert(text == "lease")
			return { path = WORKTREE, lease_id = "lease-19", lease_holder = "prguide" }
		end,
		samePath = function(a, b, done) assert(a == WORKTREE and b == "/reader"); done(false, nil) end,
		resolutions = function() error("a bot edit must not read the conflict journal") end,
	}, Fixture.asOf, function(outcome)
		assert(State.agentOutcome(s, key, outcome))
		assert(card(s, key).column == "in_review", "bot lifecycle must stay In review")
	end, function(result, err)
		finished += 1
		fix = result
		local why = ({ unsandboxed = "write sandbox", tracked = "tracks .prguide-omp-state", exists = "/bin/mkdir: File exists",
			failed = "omp: boom", unclean = "state folder: busy" })[mode]
		if why then assert(result == nil and err and string.find(err, why, 1, true), tostring(err))
		else assert((err == "stopped") == stopDuringAgent) end
	end)
	assert(#calls == 0, "constructing an engine is lazy")
	engine.begin()
	if mode ~= "ready" and mode ~= "stop" and mode ~= "unconfined" then
		assert(finished == 1 and fix == nil and engine.held() == nil, "a failed bot run returns its lease")
	elseif stopDuringAgent then
		assert(#calls == 10 and pending ~= nil)
		engine.stop()
		assert(#calls == 10 and finished == 0 and engine.held() ~= nil, "Stop waits for the child before cleanup")
		local resume = pending :: () -> ()
		resume()
		assert(finished == 1 and fix == nil and engine.held() == nil)
	else
		assert(finished == 1 and fix ~= nil)
		local ready = fix :: AgentFix.Fix
		assert(ready.commit == COMMIT and ready.headOid == HEAD and ready.usedAgent and ready.branch == "topic")
		assert(card(s, key).chips[1].text == "Fix ready" and engine.held() ~= nil)
		assert(State.openReviewFix(s, key))
		local page = State.reviewPage(s); assert(page and page.bot)
		assert(not State.beginAgent(s, key, Fixture.asOf), "ready fix retains ownership")
		local review = ReviewFix.build(ready, { ["src/retry.luau"] = Fixture.botFile }, nil)
		assert(review.verified and #review.hunks == 1)
		assert(review.hunks[1].lines[2].text == "return value or 0" and review.hunks[1].lines[2].tag == "agent")
		assert(not ReviewFix.allReviewed(ready, {}) and ReviewFix.allReviewed(ready, { ["bot:1"] = true }))
		assert(not ReviewFix.build(ready, { ["src/retry.luau"] = "changed" }, nil).verified)
		engine.release(function(ok, err) assert(ok and not err); released = true end)
		assert(released and engine.held() == nil and not engine.busy())
	end
	assert(#calls == #entries, "missing bot pipeline calls")
end

-- The real src/hub/block.luau and the real AgentHost.summarizeFeedback, driven through their own callbacks. Both reach
-- the platform through src/host.luau, so the stub is written into the Host table's fields.
-- Every process, GitHub and engine effect is a recorded call that a scenario settles by hand and in the order
-- it chooses, so a guard between an effect and its result is proved by the state left when it is removed.
local REFS = "REFS_JSON"

local function blockPaths()
	local Block: any = require("../src/hub/block")
	local Fetch: any = require("../src/fetch")
	local Host: any = require("../src/host")
	local AgentHost: any = require("../src/agent-host")
	local kept: { [string]: any } = {}
	for _, name in { "runner", "findRepo" } do kept[name] = Fetch[name] end
	local keptAgent: { [string]: any } = {}
	for _, name in { "startAgentFix", "findAgentClone", "pushAgentFix", "returnAgentFix" } do keptAgent[name] = AgentHost[name] end
	local stub: { [string]: any } = {
		json = {
			decode = function(text: string): any
				if text == REFS then return { headRefName = "topic", baseRefName = "main", headRefOid = HEAD } end
				error("invalid json", 0)
			end,
		},
		timer = function(): any return { cancel = function() end } end,
		getenv = function(): string? return nil end,
		kv = { get = function(): any return nil end, set = function() end },
	}
	local hostFields: { [string]: any } = {}
	for name, value in stub do
		hostFields[name] = Host[name]
		Host[name] = value
	end
	local function restore()
		for name in stub do Host[name] = hostFields[name] end
		for name, value in kept do Fetch[name] = value end
		for name, value in keptAgent do AgentHost[name] = value end
	end

	-- A live board (fixture=summary, then made a live one) whose every effect lands in `w`.
	local function world(provide: ((details: any, n: number) -> (any?, any?))?): any
		local w: any = { calls = {}, started = {}, toasts = {}, renders = 0, reads = 0, stops = 0, pushes = 0, fail = false, throws = false }
		local cx: any = { cwd = "/reader" }
		function cx:render()
			if w.fail then error("window gone", 0) end
			w.renders += 1
		end
		function cx:toast(kind: string, title: string, detail: string?)
			table.insert(w.toasts, { kind = kind, title = title, detail = detail })
		end
		function cx:frame() end
		function cx:open() end
		Fetch.runner = function(argv: { string }, opts: any, done: (any) -> ())
			table.insert(w.calls, { argv = table.clone(argv), opts = opts, done = done })
			if w.throws then error("spawn failed", 0) end
		end
		Fetch.findRepo = function(_dir: string, done: (any, string?) -> ()) done({ root = "/reader" }, nil) end
		AgentHost.findAgentClone = function(_near: any, _dir: string, _slug: string, _ask: any, done: (string?, string?) -> ()) done("/clone", nil) end
		AgentHost.startAgentFix = function(request: any, agent: any, _now: number, changed: (any) -> (), done: (any, string?) -> ()): any
			table.insert(w.started, { request = request, agent = agent, changed = changed, done = done })
			return {
				stop = function() w.stops += 1 end,
				release = function(finished: (boolean?, string?) -> ()) finished(true, nil) end,
				begin = function() end,
				held = function(): any return { path = WORKTREE, id = "lease", holder = "prguide" } end,
				busy = function(): boolean return false end,
			}
		end
		AgentHost.pushAgentFix = function() w.pushes += 1; error("push", 0) end
		AgentHost.returnAgentFix = function() w.pushes += 1; error("return", 0) end
		local b: any = Block.init(cx, { "fixture=summary" }, nil)
		b.fixture = nil
		b.agent = { command = "/omp", path = "/omp", model = "provider/model", effort = "high", models = {}, lenses = {}, lens = "" }
		b.github = {
			details = function(pr: any, done: (any?, any?) -> ())
				w.reads += 1
				local details: any = nil
				for _, source in Fixture.details do
					if source.key == pr.key then details = copy(source) end
				end
				if provide then return done(provide(details, w.reads)) end
				done(details, nil)
			end,
		}
		-- The block's own PRs are the fixture's tables: take copies, as `fresh` does, before a scenario edits one.
		b.s.prs = copy(Fixture.prs)
		for _, source in Fixture.details do State.setDetails(b.s, copy(source)) end
		w.b, w.cx = b, cx
		return w
	end
	local function settle(call: any, out: { status: number?, stdout: string?, stderr: string?, timed_out: boolean? })
		call.done({ status = out.status or 0, stdout = out.stdout or "", stderr = out.stderr or "", timed_out = out.timed_out or false })
	end
	local function press(w: any, name: string, shift: boolean?)
		Block.key(w.b, { name = name, shift = shift } :: any, w.cx)
	end
	local function errorToast(w: any): string
		assert(#w.toasts == 1 and w.toasts[1].kind == "error", "one error toast")
		return w.toasts[1].title
	end
	local function hasText(text: string, part: string)
		assert(string.find(text, part, 1, true), text)
	end

	local d = Fixture.details
	local function scenarios()
		-- Summarize: nothing runs until a key is pressed, then one read-only omp call over the feedback.
		local comments = d.comments.key
		local w = world()
		State.select(w.b.s, comments)
		assert(#w.calls == 0 and w.reads == 0 and w.renders == 0 and #w.started == 0, "selecting a card runs nothing")
		press(w, "a")
		assert(w.b.s.busy[comments] == State.SUMMARIZING and w.renders == 1 and w.reads == 1 and #w.calls == 1)
		local call = w.calls[1]
		local live = Summary.current(copy(d.comments), State.prOf(w.b.s, comments) :: any)
		equal(call.argv, Summary.argv("/omp", "provider/model", "high", Summary.prompt(live)))
		assert(call.opts.cwd == nil and call.opts.stdin == nil, "no worktree or input file")
		for _, word in call.argv do
			assert(word ~= "git" and word ~= "treehouse" and word ~= "get" and word ~= "write" and word ~= "push", word)
		end
		assert(w.b.s.agents[comments] == nil and w.b.agentFlight == nil and #w.started == 0)
		press(w, "a")
		assert(#w.calls == 1 and w.reads == 1 and w.renders == 1, "a press while summarizing starts nothing")
		settle(call, { stdout = Fixture.transcripts.comments.stdout })
		assert(w.reads == 2, "the feedback is read again before the answer is installed")
		assert(w.b.s.busy[comments] == nil and #w.toasts == 0 and w.renders == 2)
		assert(w.b.s.summaries[comments].verdict == "Reply to @maria-k" and card(w.b.s, comments).detail == "Reply to @maria-k")
		settle(call, { stdout = Fixture.transcripts.comments.stdout })
		assert(w.reads == 2 and w.renders == 2 and #w.toasts == 0, "a duplicate callback settles nothing")
		assert(#w.started == 0 and w.pushes == 0)

		-- ⇧A on three commenters, one a bot, reads comments and no code.
		local three = world()
		State.select(three.b.s, d.three.key)
		press(three, "a", true)
		assert(#three.calls == 1)
		local sent = three.calls[1].argv[#three.calls[1].argv]
		for _, text in { "maria-k", "devon", "review-bot[bot]", "Guard the empty value." } do hasText(sent, text) end
		for _, text in { "SOURCE_PATH_SENTINEL", "DIFF_HUNK_SENTINEL", "FILE_CONTENT_SENTINEL", "CHECK_CONTENT_SENTINEL" } do
			assert(not string.find(sent, text, 1, true), text)
		end
		settle(three.calls[1], { stdout = Fixture.transcripts.three.stdout })
		assert(card(three.b.s, d.three.key).detail == "Reply to @maria-k" and #three.toasts == 0 and #three.started == 0)

		-- A comment edited while the model ran changes no metadata the board reads: only the second read sees it.
		local edited = world(function(details: any, n: number): (any?, any?)
			if n >= 2 then details.threads[1].body = "Edited after the model started." end
			return details, nil
		end)
		State.select(edited.b.s, comments)
		press(edited, "a")
		settle(edited.calls[1], { stdout = Fixture.transcripts.comments.stdout })
		assert(edited.reads == 2 and edited.b.s.busy[comments] == nil and edited.b.s.summaries[comments] == nil and edited.renders == 2)
		hasText(errorToast(edited), "Couldn't summarize feedback")
		assert(edited.b.s.details[comments].threads[1].body == "Edited after the model started.", "the fresh read is kept")
		press(edited, "a")
		assert(#edited.calls == 2)
		hasText(edited.calls[2].argv[#edited.calls[2].argv], "Edited after the model started.")

		-- The second read failing leaves no summary and no busy state.
		local unread = world(function(details: any, n: number): (any?, any?)
			if n >= 2 then return nil, { operation = "details", message = "HTTP 502" } end
			return details, nil
		end)
		State.select(unread.b.s, comments)
		press(unread, "a")
		settle(unread.calls[1], { stdout = Fixture.transcripts.comments.stdout })
		assert(unread.reads == 2 and unread.b.s.busy[comments] == nil and unread.b.s.summaries[comments] == nil and unread.renders == 2)
		hasText(errorToast(unread), "HTTP 502")

		-- The first read failing never reaches the model.
		local first = world(function(): (any?, any?) return nil, { operation = "details", message = "HTTP 404" } end)
		State.select(first.b.s, comments)
		press(first, "a")
		assert(#first.calls == 0 and first.reads == 1 and first.b.s.busy[comments] == nil and first.renders == 2)
		hasText(errorToast(first), "HTTP 404")

		-- Timeout and error exit: one toast, busy cleared, one draw, and a late duplicate callback does nothing.
		for name, reply in { timeout = { status = -1, timed_out = true }, failed = { status = 1, stderr = "omp exited" } } do
			local ended = world()
			State.select(ended.b.s, comments)
			press(ended, "a")
			settle(ended.calls[1], reply)
			assert(ended.reads == 1 and ended.b.s.busy[comments] == nil and ended.b.s.summaries[comments] == nil and ended.renders == 2, name)
			hasText(errorToast(ended), if name == "timeout" then "timed out" else "omp exited")
			settle(ended.calls[1], reply)
			settle(ended.calls[1], { stdout = Fixture.transcripts.comments.stdout })
			assert(#ended.toasts == 1 and ended.renders == 2 and ended.reads == 1 and ended.b.s.summaries[comments] == nil, name)
		end
		local thrown = world()
		State.select(thrown.b.s, comments)
		thrown.throws = true
		press(thrown, "a")
		assert(#thrown.calls == 1 and thrown.b.s.busy[comments] == nil and thrown.renders == 2)
		hasText(errorToast(thrown), "spawn failed")

		-- A closed block takes no answer: no toast, no draw, no second read, no summary.
		local closed = world()
		State.select(closed.b.s, comments)
		press(closed, "a")
		closed.b.closed = true
		settle(closed.calls[1], { stdout = Fixture.transcripts.comments.stdout })
		assert(closed.reads == 1 and #closed.toasts == 0 and closed.renders == 1 and closed.b.s.summaries[comments] == nil)

		-- Fix bot comments: the feedback is read before the refs, and must still be what the board has when
		-- the refs arrive. Nothing starts an engine before that, and nothing here can push.
		local bot = d.bot.key
		local fix: any = {
			worktree = WORKTREE, branch = "topic", base = "main", headOid = HEAD, commit = COMMIT,
			hunks = AgentFix.botHunks(Fixture.botDiff), summary = "Guard the empty value.", usedAgent = true,
		}
		local function begin(provide: any?): (any, any)
			local started = world(provide)
			State.select(started.b.s, bot)
			assert(started.b.s.agents[bot] == nil and #started.calls == 0)
			press(started, "a")
			assert(started.reads == 1 and #started.calls == 1 and #started.started == 0, "the refs are read before an engine starts")
			assert(started.b.s.agents[bot].kind == "running")
			assert(table.concat(started.calls[1].argv, " ") == "gh pr view 1904 --repo acme/web --json headRefName,baseRefName,headRefOid")
			return started, started.calls[1]
		end
		local function refused(wb: any)
			local agent = wb.b.s.agents[bot]
			assert(#wb.started == 0 and agent.kind == "failed" and agent.reason == "Feedback changed; refresh the board", agent.kind)
			assert(wb.b.agentFlight == nil and wb.pushes == 0)
		end

		local ok, refs = begin()
		settle(refs, { stdout = REFS })
		assert(#ok.started == 1)
		local request = ok.started[1].request
		assert(request.key == bot and request.branch == "topic" and request.base == "main" and request.headOid == HEAD)
		assert(request.input.kind == "bot" and string.find(AgentFix.botPrompt(request.input.details, request.input.authors), "Guard the empty value.", 1, true))
		assert(ok.b.s.agents[bot].kind == "running")
		local drawn = ok.renders
		ok.started[1].done(fix, nil)
		local ready = ok.b.s.agents[bot]
		assert(ready.kind == "ready" and ok.renders == drawn + 1)
		ok.started[1].done(fix, nil)
		ok.started[1].changed({ kind = "ready", fix = fix })
		assert(ok.b.s.agents[bot] == ready and ok.renders == drawn + 1 and #ok.toasts == 0, "one settle and one draw")
		assert(ok.pushes == 0 and #ok.calls == 1, "nothing is pushed, and nothing runs beyond the refs read")
		ok.b.s.now = Fixture.asOf
		State.project(ok.b.s)
		assert(card(ok.b.s, bot).column == "in_review", "the card stays In review")

		-- Only the board's signature moved while the refs were out: same prompt, different signature.
		local signed, signedRefs = begin()
		local signedPr = State.prOf(signed.b.s, bot) :: any
		local _, signedPrompt = State.botFeedback(signed.b.s, bot)
		local signedBefore = State.feedbackSignature(signedPr)
		signedPr.lastActivityAt = "2026-10-10T12:00:00Z"
		assert(State.feedbackSignature(signedPr) ~= signedBefore)
		local _, signedSame = State.botFeedback(signed.b.s, bot)
		assert(signedSame == signedPrompt, "only the signature moved")
		settle(signedRefs, { stdout = REFS })
		refused(signed)

		-- Only the prompt moved: a comment edit changes no metadata, so the signature is the same.
		local worded, wordedRefs = begin()
		local wordedPr = State.prOf(worded.b.s, bot) :: any
		local _, wordedBefore = State.botFeedback(worded.b.s, bot)
		local wordedSignature = State.feedbackSignature(wordedPr)
		local rewritten = copy(worded.b.s.details[bot])
		rewritten.threads[1].body = "Changed while the refs were out."
		State.setDetails(worded.b.s, rewritten)
		assert(State.feedbackSignature(wordedPr) == wordedSignature, "only the prompt moved")
		local _, wordedAfter = State.botFeedback(worded.b.s, bot)
		assert(wordedAfter ~= wordedBefore)
		settle(wordedRefs, { stdout = REFS })
		refused(worded)

		-- A timed-out refs read fails the card once; its late reply and a failed first read settle nothing more.
		local slow, slowRefs = begin()
		local slowDrawn = slow.renders
		settle(slowRefs, { status = -1, timed_out = true })
		local slowAgent = slow.b.s.agents[bot]
		assert(#slow.started == 0 and slowAgent.kind == "failed" and slowAgent.reason == "Reading PR refs timed out")
		assert(slow.renders == slowDrawn + 1 and slow.b.agentFlight == nil)
		settle(slowRefs, { stdout = REFS })
		assert(#slow.started == 0 and slow.renders == slowDrawn + 1 and slow.b.s.agents[bot] == slowAgent)
		local unread2 = world(function(): (any?, any?) return nil, { operation = "details", message = "HTTP 404" } end)
		State.select(unread2.b.s, bot)
		press(unread2, "a")
		assert(#unread2.calls == 0 and #unread2.started == 0 and unread2.b.s.agents[bot].kind == "failed")
		assert(unread2.b.s.agents[bot].reason == "HTTP 404" and unread2.b.agentFlight == nil)

		-- A render that fails closes the block: the engine is stopped once, and late callbacks do nothing.
		local gone, goneRefs = begin()
		settle(goneRefs, { stdout = REFS })
		assert(#gone.started == 1)
		gone.fail = true
		gone.started[1].changed({ kind = "running", run = AgentFix.start(bot, Fixture.asOf) })
		assert(gone.b.closed and gone.stops == 1 and gone.b.s.agents[bot] == nil, "a failed render stops the engine once")
		local goneDrawn = gone.renders
		gone.started[1].done(nil, "stopped")
		gone.started[1].done(nil, "stopped")
		gone.started[1].changed({ kind = "stopped" })
		assert(gone.stops == 1 and gone.renders == goneDrawn and #gone.toasts == 0 and gone.b.s.agents[bot] == nil)

		-- A on each card goes to the action the board shows, through the block's own key handler.
		for _, case in { { d.comments.key, "card-summarize" }, { d.three.key, "card-agent" }, { d.bot.key, "card-agent" } } do
			local routed = world()
			State.select(routed.b.s, case[1])
			local action = Keys.hubAction(routed.b.s, { name = "a" } :: any)
			assert(action and action.act == case[2] and action.value == case[1], case[1])
		end
	end
	local ran, err = pcall(scenarios)
	restore()
	if not ran then error(err, 0) end
end

return function()
	local d = Fixture.details
	local prompt = Summary.prompt(d.three)
	for _, text in { "maria-k", "devon", "review-bot[bot]", "Explain the retry limit.", "Use a clearer name.", "Guard the empty value." } do
		assert(string.find(prompt, text, 1, true), "missing feedback " .. text)
	end
	for _, text in { "SOURCE_PATH_SENTINEL", "DIFF_HUNK_SENTINEL", "URL_SENTINEL", "CHANGED_PATH_SENTINEL", "FILE_CONTENT_SENTINEL",
		"CHECK_NAME_SENTINEL", "CHECK_URL_SENTINEL", "CHECK_CONTENT_SENTINEL", "ANNOTATION_PATH_SENTINEL", "ANNOTATION_CONTENT_SENTINEL",
		"CONFLICT_PATH_SENTINEL", "CONFLICT_OURS_SENTINEL", "CONFLICT_THEIRS_SENTINEL", "CONFLICT_NOTE_SENTINEL", HEAD, d.three.key } do
		assert(not string.find(prompt, text, 1, true), "code/metadata leaked into feedback prompt: " .. text)
	end
	assert(string.find(Summary.prompt(d.requested), "Add the guard before retrying.", 1, true))
	assert(not Summary.onlyComments(d.three) and Summary.onlyComments(d.comments) and not Summary.onlyComments(d.requested))
	assert(not Summary.onlyComments(d.bot))
	local empty = copy(d.comments); empty.threads = {}; assert(not Summary.onlyComments(empty))
	local check = copy(d.comments); check.checks = copy(d.three.checks); assert(not Summary.onlyComments(check))
	local conflict = copy(d.comments); conflict.conflictNote = "Reading conflicts"; assert(not Summary.onlyComments(conflict))
	local requestedThread = copy(d.comments); requestedThread.threads[1].group = "requested"; assert(not Summary.onlyComments(requestedThread))

	local three = Summary.parse(Fixture.transcripts.three.stdout)
	assert(three and three.verdict == "Reply to @maria-k" and #three.comments == 3)
	assert(three.comments[1].author == "maria-k" and three.comments[1].text == "Needs an explanation of the retry limit.")
	assert(three.comments[2].author == "devon" and three.comments[2].text == "Suggests a clearer name.")
	assert(three.comments[3].author == "review-bot[bot]" and three.comments[3].text == "Requests a guard for an empty value.")
	local commentsAnswer = Summary.parse(Fixture.transcripts.comments.stdout)
	assert(commentsAnswer and commentsAnswer.verdict == "Reply to @maria-k" and #commentsAnswer.comments == 1)
	assert(commentsAnswer.comments[1].author == "maria-k" and commentsAnswer.comments[1].text == "Asks why retries stop at three.")
	local requestedAnswer = Summary.parse(Fixture.transcripts.requested.stdout)
	assert(requestedAnswer and requestedAnswer.verdict == "Address requested changes" and #requestedAnswer.comments == 1)
	assert(requestedAnswer.comments[1].author == "devon" and requestedAnswer.comments[1].text == "Requests a guard before retrying.")
	for _, name in { "three", "comments", "requested" } do
		local parsed = Summary.parse(Fixture.transcripts[name].stdout)
		assert(parsed and Summary.matches(d[name], parsed))
		equal(Summary.argv("/omp", "provider/model", "high", Summary.prompt(d[name])), Fixture.transcripts[name].argv)
	end
	for _, text in { "", "Reply to @maria-k", "PRGUIDE_SUMMARY_V1\nVerdict: Review feedback\nEnd", "PRGUIDE_SUMMARY_V1\nVerdict: \nComment: @devon\tHi\nEnd",
		"PRGUIDE_SUMMARY_V1\nVerdict: Review feedback\nComment: @devon\tHi\nComment: @devon\tAgain\nEnd",
		"PRGUIDE_SUMMARY_V1\nVerdict: Review feedback\nComment: @devon\t\nEnd", Fixture.transcripts.three.stdout .. "\nExtra text",
		string.gsub(Fixture.transcripts.three.stdout, "\nEnd$", ""), "```\n" .. Fixture.transcripts.three.stdout .. "\n```" } do assert(Summary.parse(text) == nil) end
	local incomplete = Summary.parse("PRGUIDE_SUMMARY_V1\nVerdict: Reply to @maria-k\nComment: @maria-k\tReply to the question.\nEnd")
	assert(incomplete and not Summary.matches(d.three, incomplete))
	local unknown = Summary.parse("PRGUIDE_SUMMARY_V1\nVerdict: Reply to @unknown\nComment: @maria-k\tReply to the question.\nEnd")
	assert(unknown and not Summary.matches(d.comments, unknown))

	local s = fresh()
	for _, name in { "comments", "requested", "three", "bot" } do
		local key = d[name].key
		State.select(s, key)
		local main = card(s, key).main
		assert(main and main.act == (if name == "comments" then "card-summarize" else "card-agent") and main.key == "A")
		local a = Keys.hubAction(s, { name = "a" } :: any)
		assert(a and a.act == main.act and a.value == key)
		local shift = Keys.hubAction(s, { name = "a", shift = true } :: any)
		assert(shift and shift.act == "card-summarize" and shift.value == key)
		assert(State.openFixes(s, key))
		local pageShift = Keys.hubAction(s, { name = "a", shift = true } :: any)
		assert(pageShift and pageShift.act == "card-summarize" and pageShift.value == key)
		State.closeFixes(s)
	end
	assert(State.installSummary(s, d.three, Fixture.transcripts.three.stdout))
	assert(card(s, d.three.key).detail == "Reply to @maria-k" and #card(s, d.three.key).chips == 1 and #card(s, d.three.key).reasons == 3)
	State.select(s, d.comments.key)
	s.search.text = "filter"; assert(Keys.hubAction(s, { name = "a" } :: any) == nil)
	s.search.text = ""; s.link.text = "link"; assert(Keys.hubAction(s, { name = "a", shift = true } :: any) == nil)
	s.link.text = ""

	-- A bot's body-only comment review at the current head is actionable (its body is in the details as a
	-- review-level thread); one on an older head is not. Bot threads and bot requested changes stay actionable.
	local quiet = fresh()
	local botPr = State.prOf(quiet, d.bot.key) :: any
	local function botCard(): State.Card
		State.project(quiet)
		return card(quiet, d.bot.key)
	end
	local live = botCard()
	assert(State.botActionable(botPr) and live.main and live.main.act == "card-agent")
	botPr.reviews.threads, botPr.reviews.unresolved = {}, 0
	local bodyOnly = botCard()
	assert(State.botActionable(botPr) and bodyOnly.column == "in_review" and bodyOnly.agentSlot)
	assert(bodyOnly.main and bodyOnly.main.act == "card-agent" and bodyOnly.main.label == "Fix bot comments")
	botPr.reviews.latest[1].oid = COMMIT
	assert(not State.botActionable(botPr) and botCard().main.act == "card-copy", "a bot review on an older head offers nothing")
	botPr.reviews.latest[1].oid = HEAD
	botPr.reviews.latest[1].verdict = "changes_requested"
	local requestedBot = botCard()
	assert(State.botActionable(botPr) and requestedBot.main and requestedBot.main.act == "card-agent")

	-- The review-level bot comment reaches both consumers once, as a bot comment.
	local review = copy(Fixture.reviewBot)
	assert(Summary.authors(review)[1] == "review-bot[bot]" and string.find(Summary.prompt(review), "Comment by @review-bot[bot] (bot) (22 bytes):\nGuard the empty value.", 1, true))
	assert(AgentFix.hasBotFeedback(review, nil))
	local reviewPrompt = AgentFix.botPrompt(review)
	assert(string.find(reviewPrompt, "Bot @review-bot[bot] review comment (22 bytes):\nGuard the empty value.", 1, true))
	assert(not string.find(reviewPrompt, " on  ", 1, true))

	-- Only feedback still live on the PR is read: a requested change the reviewer has since approved is a
	-- plain comment, not a request, and an active request is kept.
	local function livePr(verdict: string, oid: string?): any
		local pr = copy(State.prOf(fresh(), d.requested.key))
		pr.reviews.latest = { { author = "devon", bot = false, verdict = verdict, at = Fixture.asOfIso, oid = oid or HEAD } }
		return pr
	end
	local withComment = copy(d.requested)
	table.insert(withComment.threads, { id = "c2", author = "maria-k", body = "Why three retries?", bot = false, group = "comment",
		path = "src/retry.luau", line = 5, outdated = false, replies = 0, url = "", hunk = nil })
	local active = Summary.current(withComment, livePr("changes_requested"))
	assert(#active.reviews == 1 and active.threads[1].group == "requested" and not Summary.onlyComments(active))
	assert(string.find(Summary.prompt(active), "Requested changes by @devon", 1, true))
	local superseded = Summary.current(withComment, livePr("approved"))
	assert(#superseded.reviews == 0 and superseded.threads[1].group == "comment" and Summary.onlyComments(superseded))
	local supersededPrompt = Summary.prompt(superseded)
	assert(not string.find(supersededPrompt, "Requested change", 1, true) and not string.find(supersededPrompt, "Add the guard before retrying.", 1, true))
	assert(string.find(supersededPrompt, "Comment by @devon", 1, true) and string.find(supersededPrompt, "Why three retries?", 1, true))
	assert(#Summary.current(withComment, livePr("changes_requested", COMMIT)).reviews == 0, "a request on an older head is superseded")
	assert(#Summary.current(withComment, livePr("dismissed")).reviews == 0)
	local approvedState = fresh()
	local approvedPr = State.prOf(approvedState, d.requested.key) :: any
	approvedPr.reviews.latest[1].verdict = "approved"
	State.project(approvedState)
	-- The cached details still hold the review, but it is not current: A summarizes the comment instead.
	local comment = copy(d.requested)
	comment.threads = { { id = "c", author = "maria-k", body = "Why three retries?", bot = false, group = "comment",
		path = "src/retry.luau", line = 5, outdated = false, replies = 0, url = "", hunk = nil } }
	State.setDetails(approvedState, comment)
	approvedPr.reviews.threads = { { author = "maria-k", bot = false } }
	approvedPr.reviews.unresolved = 1
	State.project(approvedState)
	local approvedCard = card(approvedState, d.requested.key)
	assert(approvedCard.reasons[1] == "feedback" and approvedCard.main and approvedCard.main.act == "card-summarize")
	local bodyBot = livePr("commented")
	bodyBot.reviews.latest = { { author = "review-bot[bot]", bot = true, verdict = "commented", at = Fixture.asOfIso, oid = HEAD } }
	assert(#Summary.current(review, bodyBot).threads == 1)
	-- A body-only review with no recorded commit is never current, here or for the card's A.
	bodyBot.reviews.latest[1].oid = ""
	assert(#Summary.current(review, bodyBot).threads == 0, "a review with no commit is not current feedback")
	bodyBot.reviews.threadsKnown, bodyBot.reviews.threads = false, {}
	assert(not State.botActionable(bodyBot), "a commented bot review with no commit is not actionable")
	bodyBot.reviews.latest[1].verdict = "changes_requested"
	assert(State.botActionable(bodyBot), "a requested-changes review keeps its compatibility rule")
	bodyBot.reviews.latest[1].verdict, bodyBot.reviews.latest[1].oid = "commented", HEAD
	assert(State.botActionable(bodyBot))
	bodyBot.reviews.latest[1].verdict = "approved"
	assert(#Summary.current(review, bodyBot).threads == 0, "a bot that later approved has no live review comment")

	-- The summary command is built only from validated fields: an option, an @file attachment or a prompt that
	-- does not start with the fixed line never produces a command, so the runner is never reached.
	local goodPrompt = Summary.prompt(d.comments)
	assert(Summary.plan("/omp", "provider/model", "high", goodPrompt) ~= nil and Summary.plan("omp", "provider/model:high", nil, goodPrompt) ~= nil)
	for _, bad in {
		{ "/omp", "provider/model", "high", "@/etc/passwd" }, { "/omp", "provider/model", "high", "--tools=bash" },
		{ "/omp", "provider/model", "high", "-p" }, { "/omp", "provider/model", "high", "\n" .. goodPrompt },
		{ "/omp", "provider/model", "high", " " .. goodPrompt }, { "/omp", "provider/model", "high", "@" .. goodPrompt },
		{ "/omp", "provider/model", "high", goodPrompt .. "\0" }, { "/omp", "--tools=bash", "high", goodPrompt },
		{ "/omp", "@/etc/passwd", "high", goodPrompt }, { "/omp", "provider/model", "--tools", goodPrompt },
		{ "/omp", "provider/model", "high;rm", goodPrompt }, { "--version", "provider/model", "high", goodPrompt },
		{ "/bin/sh", "provider/model", "high", goodPrompt }, { "/omp\n", "provider/model", "high", goodPrompt },
		{ "relative/omp", "provider/model", "high", goodPrompt },
	} do assert(Summary.plan(bad[1], bad[2], bad[3], bad[4]) == nil, table.concat(bad, " | ")) end
	local planned = Summary.plan("/omp", "provider/model", "high", goodPrompt) :: { string }
	assert(planned[#planned] == goodPrompt and string.sub(planned[#planned], 1, 1) ~= "@" and string.sub(planned[#planned], 1, 1) ~= "-")

	-- The bot worker's profile: writes only under the worktree (not its .git pointer) and three device nodes.
	-- Temp folders and OMP's state are not writable, and a single file is denied by `literal`, not `subpath`.
	local profile = AgentFix.sandboxProfile(WORKTREE, "/home/prguide") :: string
	local allowed = string.match(profile, "%(allow file%-write%*(.-)%)\n%(deny file%-write%*\n") :: string
	assert(allowed == '\n  (subpath "' .. WORKTREE .. '")\n  (literal "/dev/null")\n  (literal "/dev/tty")\n  (literal "/dev/dtracehelper")', allowed)
	assert(string.find(profile, "(deny file-write*)", 1, true) and not string.find(profile, "(allow file-write*)", 1, true))
	assert(string.find(profile, '(literal "' .. WORKTREE .. '/.git")', 1, true) and string.find(profile, '(subpath "' .. WORKTREE .. '/.git")', 1, true))
	assert(string.find(profile, '(subpath "/home/prguide/.omp")', 1, true), "OMP state is denied")
	assert(not string.find(allowed, "/tmp", 1, true) and not string.find(allowed, "/var/folders", 1, true) and not string.find(allowed, ".omp", 1, true))
	assert(not string.find(profile, '"/clone', 1, true) and not string.find(profile, '(subpath "/")', 1, true))
	-- A worktree or home under /tmp is matched by its resolved /private path, and only the worktree is allowed.
	local temp = AgentFix.sandboxProfile("/tmp/pool/wt", "/tmp/home") :: string
	local tempAllowed = string.match(temp, "%(allow file%-write%*(.-)%)\n%(deny file%-write%*\n") :: string
	assert(string.find(tempAllowed, '(subpath "/private/tmp/pool/wt")', 1, true) and string.find(tempAllowed, '(subpath "/tmp/pool/wt")', 1, true))
	assert(not string.find(tempAllowed, '(subpath "/private/tmp")', 1, true) and not string.find(tempAllowed, '(subpath "/tmp")', 1, true))
	assert(string.find(temp, '(literal "/private/tmp/pool/wt/.git")', 1, true) and string.find(temp, '(subpath "/private/tmp/home/.omp")', 1, true))
	for _, bad in { "relative", '/pool/"quote', "/pool/back\\slash", "/pool/new\nline", "/pool/../outside", "/pool/.." } do
		assert(AgentFix.sandboxProfile(bad, "/home/prguide") == nil, bad)
	end

	-- GitHub feedback can change with no new head: a refresh with different review metadata drops the summary
	-- and the details, and a read that was out while that happened is rejected by its signature.
	local refreshed = fresh()
	State.installSummary(refreshed, d.comments, Fixture.transcripts.comments.stdout)
	assert(refreshed.summaries[d.comments.key] ~= nil and refreshed.details[d.comments.key] ~= nil)
	local before = State.feedbackSignature(State.prOf(refreshed, d.comments.key) :: any)
	local same = copy(refreshed.prs)
	State.replace(refreshed, same, Fixture.asOf, nil)
	assert(refreshed.summaries[d.comments.key] ~= nil and refreshed.details[d.comments.key] ~= nil, "identical feedback keeps both")
	local resolved = copy(refreshed.prs)
	for _, pr in resolved do
		if pr.key == d.comments.key then pr.reviews.threads, pr.reviews.unresolved = {}, 0 end
	end
	State.replace(refreshed, resolved, Fixture.asOf, nil)
	assert(refreshed.summaries[d.comments.key] == nil and refreshed.details[d.comments.key] == nil)
	assert(State.feedbackSignature(State.prOf(refreshed, d.comments.key) :: any) ~= before)

	-- An edited comment changes no review field the board reads, only the PR's last activity: that alone drops
	-- the summary and the details, and a summary for the old text can no longer be installed.
	local edited = fresh()
	State.installSummary(edited, d.comments, Fixture.transcripts.comments.stdout)
	local activity = copy(edited.prs)
	for _, pr in activity do
		if pr.key == d.comments.key then pr.lastActivityAt = "2026-10-10T12:00:00Z" end
	end
	State.replace(edited, activity, Fixture.asOf, nil)
	assert(edited.summaries[d.comments.key] == nil and edited.details[d.comments.key] == nil, "an edit drops the summary")
	assert(not State.installSummary(edited, d.comments, Fixture.transcripts.comments.stdout), "no details: nothing installs")
	local rewritten = copy(d.comments)
	rewritten.threads[1].body = "Edited after the model started."
	State.setDetails(edited, rewritten)
	assert(not State.installSummary(edited, d.comments, Fixture.transcripts.comments.stdout), "an answer for the old text is dropped")
	assert(Summary.prompt(rewritten) ~= Summary.prompt(d.comments))

	-- Fix bot comments reads its feedback before the PR refs. What it read is the prompt and board signature it
	-- must still match when the refs arrive, so a thread resolved or a review superseded meanwhile is caught.
	local live = fresh()
	local botKey = d.bot.key
	local input, expectedPrompt = State.botFeedback(live, botKey)
	assert(input and expectedPrompt and string.find(expectedPrompt, "Guard the empty value.", 1, true))
	local expectedSignature = State.feedbackSignature(State.prOf(live, botKey) :: any)
	local again, samePrompt = State.botFeedback(live, botKey)
	assert(again and samePrompt == expectedPrompt, "unchanged feedback is the same prompt")
	local resolvedBot = copy(live.prs)
	for _, pr in resolvedBot do
		if pr.key == botKey then pr.reviews.threads, pr.reviews.unresolved = {}, 0 end
	end
	State.replace(live, resolvedBot, Fixture.asOf, nil)
	local afterResolve, resolvedPrompt = State.botFeedback(live, botKey)
	assert(afterResolve == nil and resolvedPrompt == nil, "a resolved thread leaves no details to start from")
	-- With the fixes page open the details stay, and the signature alone must refuse the start.
	local open = fresh()
	State.openFixes(open, botKey)
	local openPrs = copy(open.prs)
	for _, pr in openPrs do
		if pr.key == botKey then pr.reviews.threads, pr.reviews.unresolved = {}, 0 end
	end
	State.replace(open, openPrs, Fixture.asOf, nil)
	assert(open.details[botKey] ~= nil)
	assert(State.feedbackSignature(State.prOf(open, botKey) :: any) ~= expectedSignature, "the start is refused by signature")
	-- A body-only review superseded while the refs were out leaves no feedback to start from.
	local bodyOnly = fresh()
	local bodyDetails = copy(Fixture.reviewBot)
	bodyDetails.key = botKey
	State.setDetails(bodyOnly, bodyDetails)
	local bodyInput, bodyPrompt = State.botFeedback(bodyOnly, botKey)
	assert(bodyInput and bodyPrompt and string.find(bodyPrompt, "review comment", 1, true))
	local bodyPr = State.prOf(bodyOnly, botKey) :: any
	bodyPr.reviews.latest[1].oid = COMMIT
	local gone, gonePrompt = State.botFeedback(bodyOnly, botKey)
	assert(gone == nil and gonePrompt == nil, "a review left on another commit is not the feedback that was read")

	-- fixture=cases: the comments-only boards keep Summarize with the details that load for them.
	for _, key in { "acme/api#118", "acme/api#119" } do
		local recorded = Fixture.cases[key]
		assert(recorded and Summary.onlyComments(recorded) and #recorded.threads == 1 and not recorded.threads[1].bot)
		local parsed = Summary.parse(Fixture.answer(recorded))
		assert(parsed and Summary.matches(recorded, parsed) and string.find(parsed.verdict, "^Reply to @"))
	end

	-- The pure plan is the same argv Block gives Fetch. The injected adapter runs only an
	-- explicit action. Host Block/Fetch execution remains a parent integration check.
	local calls: { { string } } = {}
	local function clicked(action: Keys.Action)
		assert(action.act == "card-summarize" and action.value == d.comments.key)
		local argv = Summary.argv("/omp", "provider/model", "high", Summary.prompt(d.comments))
		table.insert(calls, argv)
		assert(State.installSummary(s, s.details[d.comments.key], Fixture.transcripts.comments.stdout))
	end
	State.project(s)
	State.openFixes(s, d.comments.key)
	assert(#calls == 0 and s.summaries[d.comments.key] == nil, "drawing/preparing details must not run a model")
	local pressed = Keys.hubAction(s, { name = "a" } :: any)
	assert(pressed); clicked(pressed)
	assert(#calls == 1)
	local argv = calls[1]
	equal(argv, { "/omp", "-p", "--no-tools", "--no-session", "--no-extensions", "--no-skills", "--no-rules", "--no-lsp", "--no-title",
		"--system-prompt", "Summarize supplied feedback only. Use no tools and return only the requested summary envelope.",
		"--model", "provider/model", "--thinking", "high", Summary.prompt(d.comments) })
	for _, word in argv do assert(word ~= "git" and word ~= "treehouse" and word ~= "get" and word ~= "write" and word ~= "push") end
	assert(card(s, d.comments.key).detail == "Reply to @maria-k")
	assert((State.saved(s) :: any).summaries == nil and (State.saved(s) :: any).details == nil)
	assert(State.new(copy(Fixture.prs), Fixture.asOf, State.saved(s)).summaries[d.comments.key] == nil)
	assert(not State.installSummary(s, d.comments, "bad output"))
	assert(s.summaries[d.comments.key].verdict == "Reply to @maria-k", "bad output preserves the previous summary")
	local changed = copy(d.comments); changed.threads[1].body = "Different feedback"; State.setDetails(s, changed)
	assert(s.summaries[d.comments.key] == nil and not State.installSummary(s, d.comments, Fixture.transcripts.comments.stdout))
	local moved = fresh(); local pr = State.prOf(moved, d.comments.key); assert(pr); pr.headOid = COMMIT
	assert(not State.installSummary(moved, d.comments, Fixture.transcripts.comments.stdout))

	local hunks = AgentFix.botHunks(Fixture.botDiff)
	assert(hunks and #hunks == 1 and hunks[1].id == "bot:1" and hunks[1].path == "src/retry.luau" and hunks[1].start == 1)
	assert(table.concat(hunks[1].ours, "\n") == "local function valueOrZero(value)\nreturn value\nend")
	assert(hunks[1].resolved and hunks[1].resolved.lines[2].text == "return value or 0")
	for _, diff in { "", string.gsub(Fixture.botDiff, "%+%+%+ b/src/retry.luau", "+++ /dev/null"),
		Fixture.botDiff .. "diff --git a/empty b/empty\nnew file mode 100644\nindex 0000000..1111111\n",
		string.gsub(Fixture.botDiff, "100644", "120000"), string.gsub(Fixture.botDiff, "@@ %-1,3 %+1,3 @@", "@@ -1,4 +1,3 @@"),
		Fixture.botDiff .. "\\ No newline at end of file\n", Fixture.botDiff .. "Binary files a/image and b/image differ\n" } do assert(AgentFix.botHunks(diff) == nil) end
	local reviewOnly = copy(d.bot)
	reviewOnly.threads = {}
	reviewOnly.reviews = { { author = "review-bot[bot]", body = "Guard the empty value.", at = Fixture.asOfIso, url = "" } }
	assert(not AgentFix.hasBotFeedback(reviewOnly, nil))
	assert(AgentFix.hasBotFeedback(reviewOnly, { "review-bot[bot]" }))
	assert(string.find(AgentFix.botPrompt(reviewOnly, { "review-bot[bot]" }), "Guard the empty value.", 1, true))
	assert(not AgentFix.hasBotFeedback(d.requested, nil), "human requested changes never become bot input")
	local botPrompt = AgentFix.botPrompt(d.three)
	assert(string.find(botPrompt, "Guard the empty value.", 1, true) and not string.find(botPrompt, "Explain the retry limit.", 1, true))
	assert(not string.find(botPrompt, "DIFF_HUNK_SENTINEL", 1, true))
	botEngine("ready")
	botEngine("stop")
	botEngine("unsandboxed")
	botEngine("unconfined")
	botEngine("tracked")
	botEngine("exists")
	botEngine("failed")
	botEngine("unclean")
	blockPaths()
end
