--!strict
-- The PR hub block: reads its arguments, opens the board from the shared cache (or a recorded sample), draws it, and
-- turns clicks and keys into state changes plus the scrolling, focusing and toasts only a live window can do. Clicks
-- (`event`) and keys (`key`) both run one ACTIONS table. The work an action starts lives in the hub modules it calls:
-- hub/ops (GitHub and agent actions), hub/agent-run (an agent fix), hub/details (the pages' reads), hub/tandem, and
-- hub/refresh (the timers), all over hub/store (the shared cache) and hub/runtime (the Block record).
local Actions = require("../ci/actions")
local Agent = require("../agent")
local AgentHost = require("../agent-host")
local AgentRun = require("./agent-run")
local Board = require("../view/hub/board")
local Buildkite = require("../ci/buildkite")
local Details = require("./details")
local Fetch = require("../fetch")
local Fields = require("../text-field")
local Fixes = require("./fixes")
local FixesPage = require("../view/hub/fixes")
local Github = require("../github")
local Host = require("../host")
local HubTandem = require("./tandem")
local Keys = require("../keys")
local Log = require("../ci/log")
local Lookups = require("./lookups")
local Model = require("./model")
local ModelBox = require("../model-box")
local Ops = require("./ops")
local Paths = require("../view/hub/paths")
local Refresh = require("./refresh")
local ReviewFixPage = require("../view/hub/review-fix")
local Runtime = require("./runtime")
local State = require("./state")
local Store = require("./store")
local Sync = require("./sync")

type State = State.State
type Block = Runtime.Block
type Handler = Runtime.Handler

local FIXTURES, frameLater, revealSelected, draw = Runtime.FIXTURES, Runtime.frameLater, Runtime.revealSelected, Runtime.draw
local readCache, storedId, flagged, writeStatus, syncOwnership = Store.readCache, Store.storedId, Store.flagged, Store.writeStatus, Store.syncOwnership
local loadMerges, detectRepo, setUserMethod = Lookups.loadMerges, Lookups.detectRepo, Lookups.setUserMethod
local rearm, refetch, stepFixture = Refresh.rearm, Refresh.refetch, Refresh.stepFixture
local openFixes, openReviewFix = Details.openFixes, Details.openReviewFix
local beginAgent, advanceAgentFixture = AgentRun.beginAgent, AgentRun.advanceAgentFixture
local reviewEffect, fixTarget = Ops.reviewEffect, Ops.fixTarget
local loadTandem = HubTandem.loadTandem

local ARGS = "generate=true|false and fixture=<name> (cases, rereview, agent-cards, review-fix, summary)"

-- The recently opened pull requests a fixture board shows, so the fold has rows without a kv store.
local SAMPLE_RECENT: { Sync.Opened } = {
	{ repo = "acme/api", number = 412, title = "Add retry budget to the billing client", author = "dana", at = "2026-10-08T09:12:33Z" },
	{ repo = "acme/web", number = 977, title = "Move the settings tabs into the sidebar", author = "ruben", at = "2026-10-06T16:40:02Z" },
	{ repo = "acme/api", number = 398, title = "Drop the unused webhook table", author = "mei", at = "2026-09-29T11:05:48Z" },
}


-- The merged pull requests a fixture board shows, against its clock: the last one is past the 7 days, so it stays hidden.
local SAMPLE_MERGED: { Sync.Opened } = {
	{ repo = "acme/web", number = 981, title = "Cache the avatar sprites", author = "", at = "2026-10-08T15:02:10Z" },
	{ repo = "acme/api", number = 405, title = "Retry webhook deliveries with backoff", author = "", at = "2026-10-05T10:44:51Z" },
	{ repo = "acme/api", number = 377, title = "Log slow queries", author = "", at = "2026-09-01T08:00:00Z" },
}

-- The models a fixture board's Settings offers, so it has something to choose from without running omp. Names
-- and efforts are as long as omp's real ones, and there are enough that the Review list scrolls under Off.
local SAMPLE_MODELS: { Agent.Model } = {
	{ selector = "anthropic/claude-fable-5-1", name = "Claude Fable 5.1", efforts = { "low", "medium", "high", "xhigh", "max" } },
	{ selector = "anthropic/claude-haiku-4-5", name = "Claude Haiku 4.5", efforts = { "minimal", "low", "medium", "high", "xhigh" } },
	{ selector = "anthropic/claude-opus-5-5", name = "Claude Opus 5.5", efforts = { "low", "medium", "high", "xhigh", "max" } },
	{ selector = "anthropic/claude-3-5-sonnet-v2", name = "Claude Sonnet 3.5 v2", efforts = {} },
	{ selector = "anthropic/claude-sonnet-5-5", name = "Claude Sonnet 5.5", efforts = { "low", "medium", "high", "xhigh" } },
	{ selector = "google/gemini-3-pro", name = "Gemini 3 Pro", efforts = { "low", "high" } },
	{ selector = "openai-codex/gpt-5.6-luna", name = "GPT-5.6 Luna", efforts = { "minimal", "low", "medium", "high" } },
	{ selector = "openai-codex/gpt-6.1-sol", name = "GPT-6.1 Sol", efforts = { "minimal", "low", "medium", "high", "xhigh", "max" } },
	{ selector = "openai-codex/gpt-6.1-sol-mini", name = "GPT-6.1 Sol mini", efforts = { "minimal", "low", "medium", "high" } },
}

-- A sample board's agent; its picks are never saved.
local function sampleAgent(): Agent.Agent
	local agent = Agent.new("", "", (Agent.picks(nil, { model = "anthropic/claude-fable-5-1", effort = "high" }) :: Agent.Picks))
	agent.models = table.clone(SAMPLE_MODELS)
	return agent
end

-- Reads `name=value` block arguments.
local function options(args: { string }): ({ generate: boolean, fixture: string? }?, string?)
	local out: { generate: boolean, fixture: string? } = { generate = false, fixture = nil }
	for _, arg in args do
		local name, value = string.match(arg, "^(%a+)=(.*)$")
		if name ~= "generate" and name ~= "fixture" then
			return nil, "Unknown argument \"" .. arg .. "\". The block takes " .. ARGS .. "."
		end
		if name == "generate" then
			if value ~= "true" and value ~= "false" then
				return nil, "generate= takes true or false, not \"" .. (value :: string) .. "\". The block takes " .. ARGS .. "."
			end
			out.generate = value == "true"
		elseif FIXTURES[value :: string] == nil then
			return nil, "Unknown fixture \"" .. (value :: string) .. "\". The block takes " .. ARGS .. "."
		else
			out.fixture = value
		end
	end
	return out, nil
end

-- Opens PR `number` of `slug` ("owner/repo") in the guide. The block can't open blocks, so it finds a
-- checkout of the repo (beside the hub's folder, else PR Guide's own copy) and opens a link the window
-- routes to the guide (`State.openPlan`). With no checkout and no copy to make, it says why and opens
-- nothing. A card's open action uses this too.
local function openPr(b: Block, cx: BlockCx, slug: string, number: number, generate: boolean)
	local dir = cx.cwd or Host.getenv("HOME") or ""
	Fetch.checkoutFor(nil, dir, slug, function(found)
		if b.closed then return end
		local _, why = Fetch.savedCopy("github.com", slug)
		local plan = State.openPlan(slug, number, generate, if found then found.root else nil, why, dir)
		if plan.kind == "open" then
			cx:open(plan.url)
		else
			cx:toast("error", plan.text, plan.sub)
		end
	end)
end

-- ⏎ and a click open the row; ⇧⏎ (or a hub opened for AI guides) starts the AI guide too.
local function openRow(b: Block, cx: BlockCx, value: string, withGuide: boolean)
	local s = b.s
	if value ~= "" then State.select(s, value) end
	local generate = withGuide or b.generate
	local recent = State.selectedRecent(s)
	if recent then return openPr(b, cx, recent.repo, recent.number, generate) end
	local card = State.selectedCard(s)
	if card == nil then return end
	if card.agent and card.agent.kind == "ready" then return openReviewFix(b, cx, card.pr.key) end
	-- A Needs fixes card opens at what needs fixing; the AI guide still opens the whole pull request.
	if card.column == "needs_fixes" and not generate then return openFixes(b, cx, card.pr.key) end
	openPr(b, cx, card.pr.repo, card.pr.number, generate)
end

local function openCard(b: Block, cx: BlockCx, value: string)
	openRow(b, cx, value, false)
end

-- Opens a GitHub link where Settings says: Tern's browser, or the system's default browser.
local function openLink(b: Block, cx: BlockCx, url: string)
	if Fetch.linkTarget() == "tern" then return cx:open(url) end
	Fetch.openInBrowser(url, function(err)
		if err and not b.closed then cx:toast("error", "Couldn't open the link: " .. err, url) end
	end)
end

local function closeMenu(b: Block)
	State.closeMenu(b.s)
end

-- Runs a Settings model menu action on the agent, saving what it changed: the same choice the review
-- page's model menu saves. The review model is also what agent fixes and summaries run with.
local function modelAction(b: Block, act: string, value: string)
	local s = b.s
	local agent, box = s.agent, s.models
	if s.menu ~= "settings" or not agent or not box then return end
	local outcome = ModelBox.act(box, agent, act, value) :: ModelBox.Outcome
	if outcome.save and not b.fixture then AgentHost.saveChoice(agent) end
	if outcome.close then State.closeMenu(s) else s.models = outcome.box end
end

local chooseMergeRow: (b: Block, cx: BlockCx, index: number) -> ()

-- Chooses the highlighted row: a card's other action runs.
local function pickRow(b: Block, cx: BlockCx, index: number, ACTIONS: { [string]: Handler })
	local s = b.s
	if s.menu == "actions" then
		local more = State.actionAt(s, index)
		local card = State.selectedCard(s)
		State.closeMenu(s)
		local handler = if more then ACTIONS[more.act] else nil
		if handler and card then handler(b, cx, card.pr.key) end
		return
	end
	if s.menu == "merge" then return chooseMergeRow(b, cx, index) end
	State.menuPick(s, index)
end

local ACTIONS: { [string]: Handler } = {}

-- The window sends this when the hub's pane gains focus; the schedule applies the debounce.
ACTIONS["hub-focused"] = function(b, cx)
	if b.fixture then return end
	State.setRecent(b.s, Fetch.recentPrs())
	b.sched.focusedAt = Host.time()
	rearm(b, cx)
end

-- The window sends this when ⌥⇧⌘R (true) or ⌥⌘R (false) finds the hub already open.
ACTIONS["set-generate"] = function(b, cx, value)
	b.generate = value == "true"
end

ACTIONS["hub-select"] = function(b, cx, key)
	State.select(b.s, key)
end
ACTIONS["hub-open"] = openCard
ACTIONS["hub-open-generate"] = function(b, cx, value)
	openRow(b, cx, value, true)
end
ACTIONS["open"] = openCard
ACTIONS["hub-move"] = function(b, cx, direction)
	local moved = State.move(b.s, direction :: any)
	-- On the top row the board scrolls to its start, so the column titles show too, even when k can't move
	-- any higher.
	if State.onTopRow(b.s) then return frameLater(cx, { { "scroll", Paths.body, "start" } }) end
	if moved then revealSelected(b, cx) end
end
ACTIONS["hub-tab"] = function(b, cx, id)
	if id == "mine" then
		State.setTab(b.s, "mine")
	elseif id == "review" then
		State.setTab(b.s, "review")
	else
		State.switchTab(b.s)
	end
end
ACTIONS["hub-next"] = function(b, cx)
	if State.walk(b.s) then revealSelected(b, cx) end
end
-- Opening a fold scrolls its header to the top of the board, so the rows it adds show. Closing doesn't scroll.
ACTIONS["hub-fold"] = function(b, cx, name)
	State.toggleFold(b.s, name)
	if not b.s.folded[name] then frameLater(cx, { { "reveal", Paths.foldHead(name), "start" } }) end
end
ACTIONS["hub-escape"] = function(b, cx)
	local s = b.s
	if State.clearMarks(s) then return end
	if s.search.text ~= "" then
		State.setSearch(s, "")
	else
		State.select(s, nil)
	end
end

-- search
ACTIONS["hub-search"] = function(b, cx)
	State.openSearch(b.s)
	frameLater(cx, { { "focus", Paths.searchField } })
end
ACTIONS["hub-searched"] = function(b)
	State.searched(b.s)
end
ACTIONS["hub-search-done"] = function(b)
	State.closeSearch(b.s, false)
end
ACTIONS["hub-search-clear"] = function(b)
	State.closeSearch(b.s, true)
end

-- menus and the key panel
ACTIONS["hub-menu"] = function(b, cx, id)
	local s = b.s
	if s.menu == id then return closeMenu(b) end
	-- Settings shows what the review page may have saved since, and the lenses as they are now.
	if id == "settings" and s.agent then
		if not b.fixture then AgentHost.refreshChoice(s.agent) end
		Fetch.refreshLenses(s.agent)
	end
	State.openMenu(s, id :: State.MenuId)
	if s.models then frameLater(cx, { { "focus", Paths.settingsField } }) end
end
ACTIONS["hub-actions"] = function(b, cx, key)
	local s = b.s
	State.select(s, key)
	if s.menu == "actions" or s.menu == "merge" then return closeMenu(b) end
	-- A Ready card's only alternative is the merge method, so its ▾ opens the chooser itself.
	local card = State.card(s, key)
	if card and #card.more == 1 and card.more[1].act == "card-method" then return State.openMenu(s, "merge") end
	State.openMenu(s, "actions")
end
ACTIONS["hub-menu-move"] = function(b, cx, delta)
	State.menuMove(b.s, tonumber(delta) or 0)
end
ACTIONS["hub-menu-close"] = function(b)
	closeMenu(b)
end
ACTIONS["hub-menu-pick"] = function(b, cx, index)
	pickRow(b, cx, tonumber(index) or 0, ACTIONS)
end
-- Space chooses the highlighted row (a repository toggles and the menu stays open).
ACTIONS["hub-menu-select"] = function(b, cx)
	pickRow(b, cx, b.s.menuCursor, ACTIONS)
end
-- ⏎ chooses it too, except in the repository list, where it closes the menu on the choices made.
ACTIONS["hub-menu-enter"] = function(b, cx)
	local s = b.s
	local row = State.menuRows(s)[s.menuCursor]
	if s.menu == "repositories" and not (row and row.kind == "clear") then return closeMenu(b) end
	pickRow(b, cx, s.menuCursor, ACTIONS)
end
-- Settings' model and lens menu: the same actions as the review page's, on the hub's agent.
ACTIONS["models-slot"] = function(b, cx, slot) modelAction(b, "models-slot", slot) end
ACTIONS["models-filter"] = function(b) modelAction(b, "models-filter", "") end
ACTIONS["models-move"] = function(b, cx, delta) modelAction(b, "models-move", delta) end
ACTIONS["models-top"] = function(b) modelAction(b, "models-top", "") end
ACTIONS["models-effort"] = function(b, cx, delta) modelAction(b, "models-effort", delta) end
ACTIONS["models-pick"] = function(b) modelAction(b, "models-pick", "") end
ACTIONS["model-row"] = function(b, cx, n) modelAction(b, "model-row", n) end
ACTIONS["model-effort"] = function(b, cx, effort) modelAction(b, "model-effort", effort) end
ACTIONS["models-lens"] = function(b, cx, delta) modelAction(b, "models-lens", delta) end
ACTIONS["model-lens"] = function(b, cx, n) modelAction(b, "model-lens", n) end
ACTIONS["edit-lenses"] = function(b, cx)
	local folder, err = Fetch.prepareLensFolder()
	closeMenu(b)
	if folder then cx:open(folder) else cx:toast("error", "Couldn't open your lenses folder", err) end
end
-- L in Settings, or a click on a side of the toggle: where GitHub links open.
ACTIONS["hub-links"] = function(b, cx, to)
	State.setLinks(b.s, to)
	Fetch.saveLinkTarget(b.s.links)
end
ACTIONS["hub-help"] = function(b)
	State.openHelp(b.s)
end
ACTIONS["hub-help-close"] = function(b)
	State.closeHelp(b.s)
end

-- Card actions: shown with their labels and keys; their effects arrive with the changes that build them.
ACTIONS["card-agent"] = function(b, cx, key)
	local pr = State.prOf(b.s, if key ~= "" then key else b.s.selected or "")
	-- One owner per branch: Tandem's PRs are handed to it, never fixed by an agent here.
	if not pr or pr.tandem then return end
	b.botKeys[pr.key] = Model.classify(pr, b.s.now) == "in_review" and State.botActionable(pr)
	beginAgent(b, cx, pr.key, "fix")
end
ACTIONS["card-agent-clone"] = function(b, cx, key) beginAgent(b, cx, key, "clone") end
ACTIONS["card-agent-folder"] = function(b, cx, key) beginAgent(b, cx, key, "folder") end
ACTIONS["card-agent-stop"] = AgentRun.stopAgent
ACTIONS["card-agent-retry"] = AgentRun.retryAgent
ACTIONS["card-agent-worktree"] = AgentRun.openWorktree
ACTIONS["card-summarize"] = Ops.summarize

ACTIONS["card-method"] = function(b, cx, key)
	if not State.card(b.s, key) then return end
	State.select(b.s, key)
	State.openMenu(b.s, "merge")
end

-- ⌘R: refresh now. The sample board steps through its `refreshes` instead of asking GitHub.
ACTIONS["hub-refresh"] = function(b, cx)
	if b.fixture and advanceAgentFixture(b, cx) then return end
	if b.fixture == "agent-cards" then return end
	if b.fixture then return stepFixture(b, cx) end
	refetch(b, cx)
end

ACTIONS["card-handoff"] = HubTandem.handoff

-- Copy link (C): "title url" as plain text, which is all Tern's clipboard takes.
ACTIONS["card-copy"] = function(b, cx, key)
	local card = State.card(b.s, key)
	if not card then return end
	State.select(b.s, key)
	cx:copy(card.pr.title .. " " .. card.pr.url)
	cx:toast("success", "Copied link")
end

ACTIONS["card-merge"] = Ops.mergeCard
ACTIONS["card-cancel"] = Ops.cancelMerge
ACTIONS["card-auto"] = Ops.autoMerge
ACTIONS["card-rerequest"] = Ops.rerequest

chooseMergeRow = function(b, cx, index)
	local s = b.s
	local kind = s.menu == "merge" and State.MERGE_KINDS[index] or nil
	local repo = State.mergeRepo(s)
	if not kind or not repo then return end
	if kind.id == "comment" or kind.id == "label" then
		s.menuCursor = index
		return State.beginMethodEdit(s, kind.id)
	end
	setUserMethod(b, cx, repo, { kind = kind.id } :: any)
	State.closeMenu(s)
end

ACTIONS["hub-method-save"] = function(b, cx)
	local s = b.s
	local edit = s.methodEdit
	local method = State.methodOfEdit(s)
	if not edit or not method then return end
	setUserMethod(b, cx, edit.repo, method)
	State.closeMenu(s)
end
ACTIONS["hub-method-cancel"] = function(b)
	State.cancelMethodEdit(b.s)
end

-- Select several -------------------------------------------------------------------------------------------

-- Space on the selected card, or a ⌘/⇧-click on `value`: selects it for Merge selected or Close stale.
ACTIONS["hub-mark"] = function(b, cx, value)
	local s = b.s
	local key = if value ~= "" then value else s.selected
	if not key then return end
	local ok, why = State.toggleMark(s, key)
	if ok then return end
	local card = State.card(s, key)
	if card then cx:toast("info", "Can't select #" .. card.pr.number .. ": " .. (why or "it isn't selectable"), card.pr.title) end
end

-- ⇧X and the Inactive fold's Close stale: selects every stale pull request that isn't a draft.
ACTIONS["hub-mark-stale"] = function(b, cx)
	if State.markStale(b.s) == 0 then cx:toast("info", "No stale pull requests to close", "Drafts are selected one by one with Space") end
end

ACTIONS["hub-marks-clear"] = function(b)
	State.clearMarks(b.s)
end

-- A repo whose merge method isn't known yet is looked up first: GitHub's merge is never the guess.
ACTIONS["hub-batch-merge"] = function(b, cx)
	local s = b.s
	if s.mode ~= "board" or State.selection(s) == nil then return end
	if not b.fixture then
		local waiting = false
		for _, card in State.markedCards(s) do
			if not s.merges[card.pr.repo] then
				waiting = true
				detectRepo(b, cx, card.pr.repo)
			end
		end
		if waiting then return cx:toast("info", "Checking how these repositories merge…", "Try again in a moment") end
	end
	State.askBatch(s, "ready")
end
ACTIONS["hub-batch-close"] = function(b)
	local s = b.s
	if s.mode == "board" then State.askBatch(s, "inactive") end
end

ACTIONS["hub-confirm-cancel"] = Ops.confirmCancel
ACTIONS["hub-confirm"] = Ops.confirm
ACTIONS["card-update"] = Ops.updateBranch
ACTIONS["card-rerun"] = Ops.rerun

-- Add by link (N) ---------------------------------------------------------------------------------------

ACTIONS["hub-link"] = function(b, cx)
	State.openLink(b.s)
	frameLater(cx, { { "focus", Paths.linkField } })
end
ACTIONS["hub-link-clear"] = function(b)
	State.closeLink(b.s, true)
end

ACTIONS["hub-link-add"] = Ops.addByLink

-- ⇧⏎: open it without adding it.
ACTIONS["hub-link-open"] = function(b, cx)
	local target = State.linkTarget(b.s)
	if target.kind == "board" or target.kind == "folded" or target.kind == "new" then
		State.closeLink(b.s, true)
		openPr(b, cx, target.repo, target.number, b.generate)
	end
end

ACTIONS["card-remove"] = Ops.remove

ACTIONS["review-fix-close"] = function(b, cx)
	if not b.s.route or b.s.route.kind ~= "review-fix" then return end
	local page = State.reviewPage(b.s)
	if page and (page.busy or page.ask) then return end
	State.closeFixes(b.s)
	revealSelected(b, cx)
end
ACTIONS["review-fix-step"] = function(b, _, index) State.reviewSelect(b.s, tonumber(index) or 1) end
ACTIONS["review-fix-move"] = function(b, _, delta)
	local page = State.reviewPage(b.s)
	if page then State.reviewSelect(b.s, page.cur + (tonumber(delta) or 0)) end
end
ACTIONS["review-fix-reviewed"] = function(b, _, index) State.reviewToggle(b.s, tonumber(index)) end
ACTIONS["review-fix-original"] = function(b) State.reviewOriginal(b.s) end
ACTIONS["review-fix-discard"] = function(b, cx)
	local page = State.reviewPage(b.s)
	if page and page.completion == "push" then return cx:toast("error", "Couldn't discard the fix: return the worktree lease first") end
	State.reviewAsk(b.s, true)
end
ACTIONS["review-fix-discard-cancel"] = function(b) State.reviewAsk(b.s, false) end

ACTIONS["review-fix-push"] = function(b, cx) reviewEffect(b, cx, "push") end
ACTIONS["review-fix-discard-confirm"] = function(b, cx) reviewEffect(b, cx, "discard") end

ACTIONS["fixes-close"] = function(b)
	State.closeFixes(b.s)
end
ACTIONS["fixes-step"] = function(b, cx, index)
	State.fixSelect(b.s, tonumber(index) or 1)
	State.fixFocus(b.s, "steps")
end
ACTIONS["fixes-move"] = function(b, cx, delta)
	State.fixMove(b.s, tonumber(delta) or 0)
end
ACTIONS["fixes-focus"] = function(b, cx, where)
	State.fixFocus(b.s, if where == "panel" then "panel" else "steps")
end
ACTIONS["fixes-bots"] = function(b)
	State.fixToggleBots(b.s)
end

ACTIONS["fixes-reply"] = function(b, cx)
	local route, _, step = fixTarget(b)
	if route == nil or step == nil or step.thread == nil then return end
	if route.resolved[step.thread.id] then return cx:toast("info", "This thread is resolved", step.thread.path) end
	if State.beginReply(b.s) then frameLater(cx, { { "focus", Paths.replyField } }) end
end
ACTIONS["fixes-cancel"] = function(b)
	State.cancelReply(b.s)
end
ACTIONS["fixes-post"] = Ops.postReply
ACTIONS["fixes-resolve"] = Ops.resolveThread

ACTIONS["fixes-rerun"] = function(b, cx)
	local route = b.s.route
	if route then ACTIONS["card-rerun"](b, cx, route.key) end
end
ACTIONS["fixes-log"] = function(b, cx)
	local _, pr, step = fixTarget(b)
	if pr == nil or step == nil or step.check == nil then return end
	local url = Fixes.logUrl(step.check, pr.repo)
	if url == "" then return cx:toast("error", "Couldn't open the log: GitHub gave no link for " .. step.check.name, pr.key) end
	openLink(b, cx, url)
end
-- G: the step on GitHub: the conflict editor, the thread, the check, the review, or the pull request.
ACTIONS["fixes-github"] = function(b, cx)
	local _, pr, step = fixTarget(b)
	if pr == nil then return end
	local url = pr.url
	if step then
		if step.group == "conflict" then url = pr.url .. "/conflicts"
		elseif step.thread then url = step.thread.url
		elseif step.review then url = step.review.url
		elseif step.check and step.check.url ~= "" then url = step.check.url end
	end
	openLink(b, cx, url)
end
-- ⏎ in the panel runs the highlighted action; the agent action is the card's own.
ACTIONS["fixes-press"] = function(b, cx)
	local act = State.fixPress(b.s)
	if act == nil then return end
	local route, pr = fixTarget(b)
	if act == "agent" then
		local main = State.fixMain(b.s)
		local handler = if main then ACTIONS[main.act] else nil
		if handler and pr then handler(b, cx, pr.key) end
		return
	end
	local handler = ACTIONS["fixes-" .. act]
	if handler and route then handler(b, cx, "") end
end

local function dispatch(b: Block, cx: BlockCx, action: Keys.Action)
	local handler = ACTIONS[action.act]
	if not handler then return end
	-- Ownership another window stored joins before the handler reads a guard, so no direct effect reaches a Tandem branch.
	if syncOwnership(b, cx) then draw(b, cx) end
	-- A draw that raised has closed the block: the handler sends nothing for it.
	if b.closed then return end
	handler(b, cx, action.value or "")
end

-- The agent the reader's omp is set to, and the models it can run (a live board only).
local function loadAgent(b: Block, cx: BlockCx)
	Host.timer(0, function()
		AgentHost.findAgent(function(agent)
			if b.closed or not agent then return end
			b.agent, b.s.agent = agent, agent
			draw(b, cx)
			AgentHost.listModels(agent, function(models)
				if b.closed then return end
				agent.models = models
				draw(b, cx)
			end)
		end)
	end)
end

-- Whether a click held `name` (shift, ctrl, alt or meta): Tern lists the held modifiers in `ev.mods`.
local function held(ev: UiEvent, name: string): boolean
	local mods: any = ev.mods
	if type(mods) ~= "table" then return false end
	return table.find(mods, name) ~= nil or mods[name] == true
end

local function actionOf(ev: UiEvent): Keys.Action?
	-- ⌘-click and ⇧-click on a card select it for Merge selected or Close stale instead of opening it.
	if ev.ev == "action" and ev.act == "hub-open" and (held(ev, "meta") or held(ev, "shift")) then
		return { act = "hub-mark", value = ev.value }
	end
	if ev.ev == "action" then return { act = ev.act, value = ev.value } end
	return nil
end

-- Who reads a failing check's log; the first to claim a check reads it. The CI modules never meet but here.
local function ciProviders(run: Log.Run): { Log.Provider }
	return { Buildkite.provider(run, Host.json.decode), Actions.provider(run) }
end

-- The sample board's CI: recorded `gh` and `bk` output, answered at once for the command it was recorded for.
local function sampleRun(argv: { string }, _opts: any, done: (out: Log.Out) -> ())
	local recorded: any = require("../../fixtures/hub/ci-logs")
	local stdout = recorded.outputs[table.concat(argv, " ")]
	if stdout then return done({ status = 0, stdout = stdout, stderr = "", timed_out = false }) end
	done({ status = 1, stdout = "", stderr = "no recording for " .. table.concat(argv, " "), timed_out = false })
end

local block: BlockDef<Block> = {
	init = function(cx: BlockCx, args: { string }, saved: any): Block
		local opts, problem = options(args)
		local prs: { Model.HubPR } = {}
		local now = Host.time()
		local refreshedAt: string? = nil
		local fixture = if opts then opts.fixture else nil
		-- A sample board reads the recorded `tandem watch --json` with no process, and flags every list it shows.
		local watched: { [string]: boolean } = {}
		if fixture then watched = Model.parseTandemWatch(require("../../fixtures/hub/raw-tandem-watch")) or {} end
		local live = opts ~= nil and fixture == nil
		local cache: Sync.Cache? = nil
		if fixture then
			local data = FIXTURES[fixture]()
			prs, now, refreshedAt = flagged(watched, data.prs), data.asOf, data.asOfIso
		elseif live then
			-- Open from the cache with no network wait; the first tick refreshes in the background.
			cache = readCache()
			if cache then
				prs, refreshedAt = cache.prs, cache.refreshedAt
				-- Ownership the cache holds stands until a read of Tandem succeeds: a failed read or an earlier GitHub refresh keeps it.
				for _, pr in prs do
					if pr.tandem then watched[string.lower(pr.repo) .. "#" .. pr.number] = true end
				end
				writeStatus(cache)
			end
		end
		local s = State.new(prs, now, saved)
		s.links = Fetch.linkTarget()
		if fixture then
			State.setRecent(s, SAMPLE_RECENT)
			State.setMerged(s, SAMPLE_MERGED)
		else
			-- The picker's list moves to hub.recent the first time the hub loads.
			Fetch.migrateRecent()
			State.setRecent(s, Fetch.recentPrs())
			State.setMerged(s, if cache then cache.merged else nil)
		end
		s.refreshedAt = refreshedAt
		s.loading = live and cache == nil
		if problem then s.error = { operation = "hub", message = problem } end
		local b: Block = {
			s = s, cache = cache, fixture = fixture, generate = opts ~= nil and opts.generate, agent = nil, agentFlight = nil, botKeys = {},
			github = Github.client(Fetch.runner, Host.json.decode), timers = {},
			ci = ciProviders(if fixture then sampleRun else Fetch.runner),
			flights = { refresh = false, checks = false, probe = false, flake = false, tandem = false }, watched = watched, handoffs = 0, seen = {}, heard = {}, held = if cache then storedId(cache) else nil, replays = {}, retired = {}, unsaved = false, root = nil, rootWaiters = nil,
			sched = {
				probedAt = now, probeChanged = false, focusedAt = if live then now else nil, checksAt = nil,
				refreshTried = nil, lastModified = if cache then cache.lastModified else nil,
			},
			closed = false, refetch = false, show = nil, step = 0, records = {}, detecting = {}, flakeTried = {},
			histories = nil :: any,
		}
		b.histories = Github.historyCache(b.github)
		if fixture then
			-- The sample board's failing checks come with recorded evidence: one flaky, one a real type error.
			local evidence: any = require("../../fixtures/hub/flake")
			for key, name in evidence.board do
				local pr = State.prOf(s, key)
				for _, case in evidence.cases do
					if pr and case.name == name then
						local verdict = Model.flake(evidence.evidence(case))
						s.flakes[key] = { flaky = verdict.flaky, reason = verdict.reason, runs = evidence.runIds[key], headOid = pr.headOid }
					end
				end
			end
			-- A sample may bring how its repos merge and whether they allow auto-merge.
			local data: any = FIXTURES[fixture]()
			for repo, resolution in (data.merges or {}) do s.merges[repo] = resolution end
			for repo, allowed in (data.autoMerge or {}) do s.autoMerge[repo] = allowed end
			for key, agent in (data.agents or {}) do s.agents[key] = agent end
			if data.runningKey then
				b.agentFlight = { key = data.runningKey, settled = false, stopping = false, releasing = false, fixtureStep = data.runningStep }
			end
			State.project(s)
			s.agent = sampleAgent()
		elseif live then
			-- How each repo merges is known from the first frame, before any refresh.
			loadMerges(b)
			loadAgent(b, cx)
			loadTandem(b, cx)
			rearm(b, cx)
		end
		return b
	end,
	title = function(b: Block): string?
		return "Pull requests"
	end,
	view = function(b: Block): BlockView
		local s = b.s
		local motion = { born = s.born, next = {}, booted = s.booted, animate = not s.keyed }
		if s.route then
			local page = if s.route.kind == "review-fix" then ReviewFixPage.view(s, motion) else FixesPage.view(s, motion)
			s.born, s.booted = motion.next, true
			return { main = page, layer = nil }
		end
		local main = Board.view(s, motion)
		s.born, s.booted = motion.next, true
		return { main = main, layer = Board.layer(s) }
	end,
	event = function(b: Block, ev: UiEvent, cx: BlockCx)
		local action = actionOf(ev)
		if not action then return end
		b.s.keyed = false
		dispatch(b, cx, action)
	end,
	key = function(b: Block, key: Key, cx: BlockCx): boolean?
		local s = b.s
		local action = Keys.hubAction(s, key)
		if action then
			s.keyed = true
			dispatch(b, cx, action)
			return true
		end
		if s.mode == "reply" and s.route and s.route.reply then
			-- ⏎ is a new line in a reply; ⌘⏎ posts it (Keys.hubAction).
			local typed = if key.name == "enter" and not (key.meta or key.ctrl) then { name = "enter", shift = true } :: any else key
			Fields.key(s.route.reply, typed)
			return true
		end
		if s.mode == "search" then
			local next = Keys.hubAfterTyping(s.mode, Fields.key(s.search, key))
			if next then
				s.keyed = true
				dispatch(b, cx, next)
			end
			return true
		end
		if s.mode == "link" then
			Fields.key(s.link, key)
			return true
		end
		if s.mode == "menu" and s.methodEdit then
			Fields.key(s.methodEdit.field, key)
			return true
		end
		if s.mode == "menu" and s.menu == "settings" and s.models then
			local next = Keys.afterTyping("models", Fields.key(s.models.field, key))
			if next then
				s.keyed = true
				dispatch(b, cx, next)
			end
			return true
		end
		-- Menus and the key panel swallow the keys they don't use.
		return s.mode ~= "board"
	end,
	save = function(b: Block): any
		return State.saved(b.s)
	end,
}

return block
