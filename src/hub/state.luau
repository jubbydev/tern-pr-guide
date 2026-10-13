--!strict
-- The hub's interaction state (tab, selection, filter, sort, search, open menus) and the board
-- built from it. Views read `State.board` and never filter, sort or classify: every rule is `model`'s.
-- Pure: no clock, no network, no Tern. `now` is passed in.
local Agent = require("../agent")
local Checks = require("./checks")
local Fields = require("../text-field")
local AgentFix = require("./agent-fix")
local Fixes = require("./fixes")
local Links = require("../links")
local ModelBox = require("../model-box")
local Model = require("./model")
local ReviewFix = require("./review-fix")
local Summary = require("./summary")

type HubPR = Model.HubPR
type Tab = Model.Tab
type Column = Model.Column
type Sort = Model.Sort

export type Opened = Model.Opened
export type Summary = Summary.Summary
export type FixDetails = Fixes.FixDetails

export type Mode = "board" | "search" | "link" | "menu" | "confirm" | "help" | "fixes" | "reply" | "review-fix" | "checks"
export type HelpPage = "board" | "fixes" | "review-fix"
export type MenuId = "filters" | "title-filter" | "check-repository" | "check-filter" | "repositories" | "sort" | "merge" | "actions" | "settings"
export type Ring = "bad" | "good" | "bad-out" | "good-out" -- red ring, green wash, then the same fading
-- What the flake evidence says about a card's failing checks, for the commit it was read on.
export type Flake = { flaky: boolean, reason: string?, headOid: string }
export type CardAction = { act: string, value: string?, label: string, key: string?, confirm: boolean }

export type AgentFixState =
	{ kind: "no_clone", slug: string }
	| { kind: "running", run: AgentFix.Run }
	| { kind: "ready", fix: AgentFix.Fix, reviewed: { [string]: boolean }, review: ReviewFix.Review?, completion: ("push" | "discard")? }
	| { kind: "pushing", fix: AgentFix.Fix }
	| { kind: "failed", reason: string, worktree: string?, held: boolean? } -- `held`: the engine still holds the worktree's lease, so its return can be retried

-- A pill on a card's chip line. `kind` picks its look.
export type Chip = { text: string, kind: "bad" | "bad-soft" | "info" | "wait" | "done" | "agent" }

export type Card = {
	pr: HubPR,
	chips: { Chip }, -- the job, or who the card waits on; empty on done cards
	detail: string?, -- the first job's detail, after the chips
	detailKind: ("bad" | "info")?, -- the detail's color: red on your PRs, blue on review requests
	column: Column,
	reasons: { Model.Reason },
	flake: string?, -- "Likely flaky: failed 3 of the last 20 runs on main", shown under the title
	main: CardAction?, -- the split button's action
	more: { CardAction }, -- behind the attached ▾
	agent: AgentFixState?,
	agentSlot: boolean, -- a reserved two-line note region, including before a fix starts
	agentMessage: string?, agentPath: string?, agentCommit: string?,
	summary: Summary?,
	merge: Model.MergeResolution?,
	note: string?, -- a merge in flight ("Commented /merge · waiting for the merge") or new commits on an approval; shown under the title
	asking: string?, -- an inline question the card is waiting on ("Squash and merge #412?"); the split button gives way to Confirm and Cancel
	busy: string?, -- an action in flight ("Merging…"); the split button gives way to it
	ring: Ring?, -- the arrival ring or wash; the "-out" kinds are fading
	selected: boolean,
	marked: boolean,
}
-- The selection bar over the group being selected, and its confirm once M or X was pressed.
export type BatchRow = { ref: string, title: string } -- "web #412" and its title
export type BatchConfirm = { question: string, rows: { BatchRow }, more: number, lines: { string }, go: string, act: string }
export type Selection = { group: Model.Group, count: number, verb: string, key: string, act: string, confirm: BatchConfirm? }
export type FilterEdit = { index: number?, operator: Model.TitleOperator, repo: string?, field: Fields.Field, typing: boolean }
export type MethodEdit = { repo: string, kind: "comment" | "label", field: Fields.Field }
export type RepoOption = { repo: string, count: number, on: boolean }

-- A fold of cards under the board (Inactive, Team requests, Approved). `open`: it shows its rows.
export type CardFold = { column: Column, cards: { Card }, open: boolean }

-- Everything a view reads, built by `project`.
export type BoardData = {
	tab: Tab,
	columns: { { column: Column, cards: { Card } } }, -- the tab's columns, left to right, filtered and ordered
	folds: { CardFold }, -- the tab's card folds, in M.FOLDS order
	recent: { Opened }, -- the tab's row fold, last under the board: Recently merged or Recently opened (M.ROW_FOLD)
	open: { recent: boolean }, -- whether that fold shows its rows
	grid: { { string } }, -- keys per column, for h j k l
	counts: { mine: number, review: number }, -- your-turn cards per tab: the blue counts
	repositories: { RepoOption },
	nextUp: Model.NextUp?,
	hidden: number, -- PRs in this tab excluded by durable visibility rules
	empty: boolean,
}

-- The fixes page, open on the Needs fixes card `key`. Its steps come from `s.details[key]` and the card's PR.
export type Route = {
	kind: "fixes" | "review-fix",
	key: string,
	cur: number, -- the step on show, 1-based
	focus: "steps" | "panel", -- h and l move between the two
	item: number, -- the panel's highlighted action, 1-based
	loading: boolean, -- details are on their way
	error: string?, -- why they could not be read
	bots: boolean, -- the "Not counted" bot note is open
	resolved: { [string]: boolean }, -- thread ids resolved from the page
	replies: { [string]: { string } }, -- replies posted from the page, by thread id
	reply: Fields.Field?, -- the reply being written (mode "reply")
	busy: boolean, -- a reply or resolve is in flight
	original: boolean?, -- review-fix's before view
	ask: boolean?, -- the inline question: review-fix's Discard, the fixes page's Push empty commit
}

-- U on a failing check's panel: catch the branch up with its base, or push an empty commit when it is up to date.
export type BranchAction = { kind: "update", behind: number } | { kind: "empty", branch: { repo: string, name: string } }

export type State = {
	prs: { HubPR },
	now: number,
	board: BoardData, -- rebuilt by `project` after any input below changes
	tab: Tab,
	selected: string?,
	marked: { [string]: boolean },
	repositories: { [string]: boolean }?,
	repositoriesEnabled: boolean,
	titleRules: { Model.TitleRule },
	ignoredChecks: { Model.IgnoredCheck },
	filterEdit: FilterEdit?,
	sort: Sort,
	search: Fields.Field,
	link: Fields.Field,
	mode: Mode,
	helpPage: HelpPage?, -- the page to return to, and show shortcuts for, while help is open
	route: Route?, -- the fixes page, while it is open
	checks: Checks.Popover?, -- the checks popover, while it is open (mode "checks")
	checkLists: { [string]: Checks.Load }, -- check lists by "key@headOid"
	menu: MenuId?,
	menuCursor: number,
	confirm: { kind: string, keys: { string } }?, -- kind "merge" (a GitHub method) or "learned" (a suggested comment command)
	methodEdit: MethodEdit?, -- the merge menu is asking for a command or a label
	folded: { [string]: boolean }, -- true: the fold is closed. Every fold starts closed
	recent: { Opened }, -- hub.recent, newest first; the block sets it, `project` builds the Review requests fold from it
	merged: { Opened }, -- the cache's Recently merged list, newest first; `project` keeps the last ACTIVE_DAYS of it
	walking: boolean, -- Next up is being walked: the banner shows "2 of 11"
	ringed: { [string]: Ring },
	agents: { [string]: AgentFixState },
	details: { [string]: FixDetails },
	flakes: { [string]: Flake }, -- by card key; the block reads the evidence, so a card without one has no label
	summaries: { [string]: Summary },
	merges: { [string]: Model.MergeResolution }, -- by repo
	autoMerge: { [string]: boolean }, -- by repo: its "Allow auto-merge" setting, once detection has read it
	acted: { [string]: boolean }, -- cards the viewer just acted on (merged, updated): their arrival is not toasted
	busy: { [string]: string }, -- by card key: the action in flight
	refreshedAt: string?,
	loading: boolean,
	error: Model.Error?,
	agent: Agent.Agent?, -- what Settings picks for: the reader's agent once the block finds it, or a sample's
	noAgent: string?, -- why the reader's agent wasn't found, once looked for
	models: ModelBox.ModelBox?, -- Settings' model and lens menu, read only while `menu` is "settings"
	links: "tern" | "browser", -- where GitHub links open; the block loads and saves it
	prepareGuides: boolean, -- Settings: prepare AI guides for review requests in the background; the block loads and saves it
	keyed: boolean, -- the change being drawn came from a key: it never animates
	born: { [string]: string },
	booted: boolean, -- arrival motion, as src/state.luau
}

export type MenuKind = "choice" | "check" | "clear" | "rule" | "navigate"
export type MenuRow = { label: string, sub: string?, count: number?, on: boolean, kind: MenuKind, value: string? }

local M = {}
M.SUMMARIZING = "Summarizing feedback…"

-- Lifecycle data only. The block owns the engine, cancellation and lease effects.
function M.agentRunning(s: State): string?
	for key, agent in s.agents do
		if agent.kind == "running" then return key end
	end
	return nil
end

function M.beginAgent(s: State, key: string, now: number): boolean
	local previous = s.agents[key]
	if M.agentRunning(s) or (previous and (previous.kind == "ready" or previous.kind == "pushing")) then return false end
	if not M.prOf(s, key) then return false end
	s.agents[key] = { kind = "running", run = AgentFix.start(key, now) }
	M.project(s)
	return true
end

function M.agentOutcome(s: State, key: string, outcome: AgentFix.Outcome): boolean
	local current = s.agents[key]
	-- Terminal and duplicate callbacks cannot resurrect a stopped or settled run.
	if not current or current.kind ~= "running" then return false end
	if outcome.kind == "running" then
		if outcome.run.key ~= key then return false end
		s.agents[key] = { kind = "running", run = outcome.run }
	elseif outcome.kind == "ready" then
		s.agents[key] = { kind = "ready", fix = outcome.fix, reviewed = {} }
	elseif outcome.kind == "failed" then
		s.agents[key] = { kind = "failed", reason = outcome.reason, worktree = outcome.worktree or current.run.worktree }
	else
		s.agents[key] = nil
	end
	M.project(s)
	return true
end

function M.agentEvent(s: State, key: string, event: AgentFix.Event): boolean
	local current = s.agents[key]
	if not current or current.kind ~= "running" then return false end
	return M.agentOutcome(s, key, AgentFix.step(current.run, event))
end

function M.noAgentClone(s: State, key: string, slug: string)
	s.agents[key] = { kind = "no_clone", slug = slug }
	M.project(s)
end

function M.agentFailed(s: State, key: string, reason: string, worktree: string?, held: boolean?)
	s.agents[key] = { kind = "failed", reason = reason, worktree = worktree, held = held }
	M.project(s)
end

-- An ephemeral snapshot from Block, never stored in State. A terminal event's path
-- describes where work happened; only the engine's held lease proves current ownership.
export type AgentFlightFacts = {
	settled: boolean, starting: boolean, releasing: boolean, busy: boolean, worktree: string?,
}

function M.agentFlight(s: State, key: string, facts: AgentFlightFacts): "wait" | "release" | "forget" | "ready"
	local agent = s.agents[key]
	if agent and (agent.kind == "ready" or agent.kind == "pushing") then return "ready" end
	if agent and agent.kind == "failed" and (agent.worktree ~= facts.worktree or (agent.held == true) ~= (facts.worktree ~= nil)) then
		agent.worktree, agent.held = facts.worktree, facts.worktree ~= nil
		M.project(s)
	end
	if not facts.settled or facts.starting or facts.releasing then return "wait" end
	-- busy may be false after settlement even when the lease return failed.
	if facts.worktree then return "release" end
	if facts.busy then return "wait" end
	return "forget"
end

-- Closing stops only running fixes. Ready worktrees and their leases belong to #16.
function M.closeAgent(s: State): string?
	local key = M.agentRunning(s)
	if key then M.agentOutcome(s, key, { kind = "stopped" }) end
	return key
end

function M.reviewed(fix: AgentFix.Fix, reviewed: { [string]: boolean }): boolean
	return ReviewFix.allReviewed(fix, reviewed)
end

local STAGES: { [AgentFix.Stage]: string } = {
	worktree = "Preparing worktree…", merge = "Merging base branch…", rules = "Regenerating files…",
	agent = "Resolving conflicts…", commit = "Committing fix…",
}

function M.agentMessage(agent: AgentFixState): (string, string?, string?)
	if agent.kind == "running" then return STAGES[agent.run.stage], agent.run.worktree, nil end
	if agent.kind == "no_clone" then return "No local copy of " .. agent.slug, nil, nil end
	if agent.kind == "failed" then
		local reason = string.match(agent.reason, "^Couldn't [^:]*: (.*)$") or agent.reason
		return "Couldn't fix pull request: " .. Fixes.firstLine(reason), agent.worktree, nil
	end
	local fix = agent.fix
	return string.sub(fix.commit, 1, 7) .. " · " .. Fixes.firstLine(fix.summary), fix.worktree, string.sub(fix.commit, 1, 7)
end

local askingOf: (s: State, pr: HubPR) -> string?

M.TABS = {
	{ id = "mine" :: Tab, label = "Your pull requests" },
	{ id = "review" :: Tab, label = "Review requests" },
}

M.COLUMNS = {
	mine = { "needs_fixes", "in_review", "ready" },
	review = { "to_review", "waiting_on_author" },
} :: { [Tab]: { Column } }

-- The card folds under each tab's board, top to bottom. Recently opened follows them on Review requests.
M.FOLDS = {
	mine = { "inactive" },
	review = { "inactive", "team", "approved" },
} :: { [Tab]: { Column } }

-- The fold of PR rows that ends each tab's board, by its `folded` name.
M.ROW_FOLD = { mine = "merged", review = "recent" } :: { [Tab]: string }

M.SORTS = {
	{ id = "repository" :: Sort, label = "Repository", sub = "Priority within each" },
	{ id = "priority" :: Sort, label = "Priority", sub = "What to do first" },
	{ id = "newest" :: Sort, label = "Newest first", sub = "Most recently opened" },
	{ id = "oldest" :: Sort, label = "Oldest first", sub = "Waiting longest" },
	{ id = "smallest" :: Sort, label = "Smallest first", sub = "Fewest lines changed" },
}

local function emptyBoard(tab: Tab): BoardData
	return {
		tab = tab, columns = {}, folds = {}, recent = {}, open = { recent = false },
		grid = {}, counts = { mine = 0, review = 0 }, repositories = {}, nextUp = nil, hidden = 0, empty = true,
	}
end

local function validTab(value: any): Tab?
	if value == "mine" or value == "review" then return value end
	return nil
end

local function validSort(value: any): Sort?
	for _, sort in M.SORTS do
		if sort.id == value then return sort.id end
	end
	return nil
end

-- Saved filters. Text rules combine with AND; a repository selection is one rule.
M.TITLE_OPERATORS = {
	{ id = "contains", label = "contains" }, { id = "not_contains", label = "does not contain" },
	{ id = "starts", label = "starts with" }, { id = "not_starts", label = "does not start with" },
}

function M.titleOperator(id: any): string?
	for _, option in M.TITLE_OPERATORS do if option.id == id then return option.label end end
	return nil
end

function M.filter(s: State, search: string): Model.Filter
	return { repositories = if s.repositoriesEnabled then s.repositories else nil, titles = s.titleRules, search = search }
end

function M.filterCount(s: State): number
	local count = if s.repositories and s.repositoriesEnabled then 1 else 0
	for _, rule in s.titleRules do if rule.enabled then count += 1 end end
	for _, rule in s.ignoredChecks do if rule.enabled then count += 1 end end
	return count
end

function M.checkRepositories(s: State): { string }
	local seen: { [string]: boolean } = {}
	for _, pr in s.prs do seen[pr.repo] = true end
	local out: { string } = {}
	for repo in seen do table.insert(out, repo) end
	table.sort(out)
	return out
end

function M.ignoredRepositories(s: State): { [string]: boolean }
	local out: { [string]: boolean } = {}
	for _, rule in s.ignoredChecks do if rule.enabled then out[string.lower(rule.repo)] = true end end
	return out
end

-- `saved` is what the block's `save` returned last time (tab, sort, repositories, folded), or anything at all.
function M.new(prs: { HubPR }, now: number, saved: any): State
	local tab: Tab = "mine"
	local sort: Sort = "repository"
	local repositories: { [string]: boolean }? = nil
	local folded: { [string]: boolean } = { inactive = true, team = true, approved = true, recent = true, merged = true }
	if type(saved) == "table" then
		tab = validTab(saved.tab) or tab
		sort = validSort(saved.sort) or sort
		if type(saved.repositories) == "table" and #saved.repositories > 0 then
			local set: { [string]: boolean } = {}
			for _, repo in saved.repositories do
				if type(repo) == "string" then set[repo] = true end
			end
			repositories = set
		end
		if type(saved.folded) == "table" then
			for name, value in saved.folded do
				if type(name) == "string" and type(value) == "boolean" then folded[name] = value end
			end
		end
	end
	local s: State = {
		prs = prs, now = now, board = emptyBoard(tab), tab = tab, selected = nil, marked = {},
		repositories = repositories, repositoriesEnabled = not (type(saved) == "table" and saved.repositoriesEnabled == false),
		titleRules = {}, ignoredChecks = {}, filterEdit = nil, sort = sort, search = Fields.create(""), link = Fields.create(""),
		mode = "board", helpPage = nil, route = nil, checks = nil, checkLists = {}, menu = nil, menuCursor = 1, confirm = nil, methodEdit = nil, folded = folded, recent = {}, merged = {}, walking = false,
		ringed = {}, agents = {}, details = {}, flakes = {}, summaries = {}, merges = {}, autoMerge = {}, acted = {}, busy = {},
		refreshedAt = nil, loading = false, error = nil, agent = nil, models = nil, links = "tern", prepareGuides = false,
		keyed = false, born = {}, booted = false,
	}
	if type(saved) == "table" then
		for _, rule in if type(saved.titleRules) == "table" then saved.titleRules else {} do
			if type(rule) == "table" and type(rule.value) == "string" and rule.value ~= "" and type(rule.enabled) == "boolean" and M.titleOperator(rule.operator) then
				table.insert(s.titleRules, { operator = rule.operator, value = rule.value, enabled = rule.enabled })
			end
		end
		for _, rule in if type(saved.ignoredChecks) == "table" then saved.ignoredChecks else {} do
			if type(rule) == "table" and type(rule.repo) == "string" and string.match(rule.repo, "^[%w_.%-]+/[%w_.%-]+$") and type(rule.name) == "string" and rule.name ~= "" and type(rule.enabled) == "boolean" then
				table.insert(s.ignoredChecks, { repo = rule.repo, name = rule.name, enabled = rule.enabled })
			end
		end
	end
	M.project(s)
	return s
end

-- Swaps in a refresh's pull requests: records the time, clears loading and the error, and rebuilds the board.
function M.replace(s: State, prs: { HubPR }, now: number, refreshedAt: string?)
	-- GitHub feedback changes without the head moving (a review, a resolved thread, a dismissal), so a
	-- summary and its details are dropped whenever the board's feedback metadata for the PR changed.
	-- An open fixes page keeps its details: its actions read live before they trust them.
	local function changed(key: string): boolean
		local previous = M.prOf(s, key)
		local latest: HubPR? = nil
		for _, pr in prs do if pr.key == key then latest = pr; break end end
		return not latest or not previous or M.feedbackSignature(latest) ~= M.feedbackSignature(previous)
	end
	for key in s.summaries do
		if changed(key) then s.summaries[key] = nil end
	end
	for key in s.details do
		if changed(key) and not (s.route and s.route.key == key) then s.details[key] = nil end
	end
	s.prs, s.now, s.refreshedAt = prs, now, refreshedAt
	s.loading, s.error = false, nil
	M.project(s)
end

-- Sets the Recently opened list (hub.recent) and rebuilds the board.
function M.setRecent(s: State, recent: { Opened })
	s.recent = recent
	M.project(s)
end

-- Sets the Recently merged list (the cache's `merged`) and rebuilds the board.
function M.setMerged(s: State, merged: { Opened }?)
	s.merged = merged or {}
	M.project(s)
end

-- The block's reading of the flake evidence for card `key` (nil forgets it, as after a re-run). The cards follow.
function M.setFlake(s: State, key: string, flake: Flake?)
	s.flakes[key] = flake
	M.project(s)
end

-- The flake evidence on hand for `key`, while it is for the commit now at the head.
function M.flakeOf(s: State, key: string): Flake?
	local pr = M.prOf(s, key)
	local flake = s.flakes[key]
	if pr and flake and flake.headOid == pr.headOid then return flake end
	return nil
end

-- What a saved state holds, for the block's `save`.
function M.saved(s: State): any
	local repositories: { string }? = nil
	if s.repositories then
		local list: { string } = {}
		for repo in s.repositories do table.insert(list, repo) end
		table.sort(list)
		repositories = list
	end
	return { tab = s.tab, sort = s.sort, repositories = repositories, repositoriesEnabled = s.repositoriesEnabled, titleRules = s.titleRules, ignoredChecks = s.ignoredChecks, folded = s.folded }
end

-- The account preference record contains filters only; pane navigation stays in `saved`.
function M.savedFilters(s: State): any
	local saved = M.saved(s)
	return { schema = 1, repositories = saved.repositories, repositoriesEnabled = s.repositoriesEnabled, titleRules = s.titleRules, ignoredChecks = s.ignoredChecks }
end

function M.loadFilters(s: State, saved: any)
	if type(saved) ~= "table" or saved.schema ~= 1 then return end
	local restored = M.new({}, s.now, saved)
	s.repositories, s.repositoriesEnabled = restored.repositories, restored.repositoriesEnabled
	s.titleRules, s.ignoredChecks = restored.titleRules, restored.ignoredChecks
	M.project(s)
end

-- The actions a card offers, from the spec's "Cards and actions" table. Keys are the shortcuts the
-- selected card answers to. Only the pieces that exist at this stage of the hub are listed.
local function action(act: string, label: string, key: string?): CardAction
	return { act = act, value = nil, label = label, key = key, confirm = false }
end

-- What the board knows of a PR's feedback, as one string: equal strings mean the same head, reviews and threads.
-- The PR's last activity stands in for an edited comment, which changes no other field the board reads.
function M.feedbackSignature(pr: HubPR): string
	local parts = { pr.headOid, pr.reviews.decision, tostring(pr.reviews.unresolved), tostring(pr.reviews.comments), pr.lastActivityAt }
	for _, review in pr.reviews.latest do
		table.insert(parts, review.author .. ":" .. review.verdict .. ":" .. review.oid .. ":" .. review.at)
	end
	for _, thread in pr.reviews.threads do
		table.insert(parts, thread.author .. (if thread.bot then "!" else ""))
	end
	return table.concat(parts, "\n")
end

-- Bot feedback the details can supply: an unresolved bot thread, or a bot review at the current head that
-- requested changes or commented (the details carry the bodies of both).
function M.botActionable(pr: HubPR): boolean
	if not Model.botFeedback(pr) then return false end
	if pr.reviews.threadsKnown then
		for _, thread in pr.reviews.threads do
			if thread.bot then return true end
		end
	end
	for _, review in pr.reviews.latest do
		if review.bot and ((review.verdict == "changes_requested" and (review.oid == "" or review.oid == pr.headOid))
			or (review.verdict == "commented" and review.oid ~= "" and review.oid == pr.headOid)) then return true end
	end
	return false
end

-- What Fix bot comments would hand the agent right now: the cached details narrowed to the feedback that is
-- live on the PR, its bot reviewers, and the exact prompt. Equal prompts mean the same feedback; nil when the
-- details are missing, belong to another head or hold no bot feedback.
function M.botFeedback(s: State, key: string): (AgentFix.Input?, string?)
	local pr, known = M.prOf(s, key), s.details[key]
	if not pr or not known or known.headOid ~= pr.headOid then return nil, nil end
	local authors: { string } = {}
	for _, review in pr.reviews.latest do
		if review.bot and not table.find(authors, review.author) then table.insert(authors, review.author) end
	end
	local details = Summary.current(known, pr)
	if not AgentFix.hasBotFeedback(details, authors) then return nil, nil end
	return { kind = "bot", details = details, authors = authors }, AgentFix.botPrompt(details, authors)
end

local function actionsFor(pr: HubPR, column: Column, reasons: { Model.Reason }, merge: Model.MergeResolution?, flake: Flake?, autoMerge: boolean?, details: FixDetails?): (CardAction?, { CardAction })
	if column == "needs_fixes" then
		local feedback, checks = false, false
		for _, reason in reasons do
			if reason == "feedback" then feedback = true end
			if reason == "checks" then checks = true end
		end
		local main, more
		local commentsOnly = false
		if details and details.headOid == pr.headOid then
			commentsOnly = Summary.onlyComments(Summary.current(details, pr))
		else
			-- Before details arrive, a live changes-requested review keeps A on Fix with agent.
			commentsOnly = pr.reviews.threadsKnown
			for _, review in pr.reviews.latest do
				if not review.bot and review.author ~= pr.author and review.verdict == "changes_requested"
					and (review.oid == "" or review.oid == pr.headOid) then commentsOnly = false end
			end
		end
		if feedback and #reasons == 1 and commentsOnly then
			main, more = action("card-summarize", "Summarize", "A"), {}
		else
			main = if pr.tandem then action("card-handoff", "Hand off to Tandem", "A") else action("card-agent", "Fix with agent", "A")
			more = if feedback then { action("card-summarize", "Summarize", "⇧A") } else {}
		end
		if checks then
			-- Behind Fix checks ▾ for every failing check. It moves first only when the evidence says flaky and the
			-- checks are all that is wrong; the agent stays first when an annotation points at a changed file.
			local rerun = action("card-rerun", "Re-run failed checks", "⇧R")
			if flake and flake.flaky and #reasons == 1 then
				table.insert(more, 1, main :: CardAction)
				return rerun, more
			end
			table.insert(more, rerun)
		end
		return main, more
	elseif column == "in_review" then
		local copy = action("card-copy", "Copy link", "C")
		local main, more = copy, {}
		-- A reviewer waits on the author to say the fix is in: asking again is the card's job until they have been asked.
		local again = Model.awaitingReReview(pr)
		if pr.tandem then
			-- Tandem owns the branch, so the card offers the hand-off and never an agent of its own.
			main, more = action("card-handoff", "Hand off to Tandem", "A"), { copy }
			if again and #again.ask > 0 then table.insert(more, action("card-rerequest", "Re-request review", "Q")) end
		elseif M.botActionable(pr) then
			main, more = action("card-agent", "Fix bot comments", "A"), { copy, action("card-summarize", "Summarize", "⇧A") }
			if again and #again.ask > 0 then table.insert(more, action("card-rerequest", "Re-request review", "Q")) end
		elseif again and #again.ask > 0 then
			main, more = action("card-rerequest", "Re-request review", "Q"), { copy }
		end
		if pr.pending then
			local method = if merge then merge.method else nil
			if not (method and method.kind == "comment" and not method.cancel) then
				table.insert(more, action("card-cancel", "Cancel merge", "M"))
			end
		elseif not pr.tandem and Model.canMergeWhenReady(merge, autoMerge) then
			-- Tandem owns the branch: no new merge is offered, only Cancel merge for one already pending.
			table.insert(more, action("card-auto", "Merge when ready", "M"))
		end
		return main, more
	elseif column == "ready" then
		if pr.pending then
			-- A merge in flight: only Cancel merge, and only when the method can be taken back.
			local method = if merge then merge.method else nil
			if method and method.kind == "comment" and not method.cancel then return nil, {} end
			return action("card-cancel", "Cancel merge", "M"), {}
		end
		if pr.behind then return action("card-update", "Update branch", "U"), { action("card-method", "Merge method", ",") } end
		return action("card-merge", "Merge", "M"), { action("card-method", "Merge method", ",") }
	elseif column == "to_review" then
		return action("open", "Review", "⏎"), if pr.addedByMe then { action("card-remove", "Remove from Review requests", "X") } else {}
	end
	return nil, {}
end

local function chip(text: string, kind: "bad" | "bad-soft" | "info" | "wait" | "done" | "agent"): Chip
	return { text = text, kind = kind }
end

-- The chip line's labels and detail text, from the mockup's job names.
local function chipsFor(pr: HubPR, placement: Model.Placement, now: number): ({ Chip }, string?, ("bad" | "info")?)
	local column = placement.column
	local chips: { Chip } = {}
	local detail: string? = nil
	local kind: ("bad" | "info")? = nil
	if column == "needs_fixes" then
		kind = "bad"
		local function add(text: string, why: string)
			table.insert(chips, chip(text, "bad"))
			if detail == nil then detail = why end
		end
		for _, reason in placement.reasons do
			if reason == "merge_failed" then
				add("Merge failed", if pr.mergeFailure then pr.mergeFailure.reason else "Merge failed")
			elseif reason == "feedback" then
				local asker: string? = nil
				for _, review in pr.reviews.latest do
					if review.verdict == "changes_requested" and not review.bot then asker = review.author end
				end
				local open = 0
				if pr.reviews.threadsKnown then
					for _, thread in pr.reviews.threads do
						if not thread.bot then open += 1 end
					end
				else
					open = pr.reviews.unresolved
				end
				if asker then add("Address changes", "Changes requested by @" .. asker) end
				if open > 0 or not asker then add("Reply", open .. (if open == 1 then " unresolved comment" else " unresolved comments")) end
			elseif reason == "checks" then
				local total = pr.checks.passing + pr.checks.failing + pr.checks.pending
				add("Fix checks", pr.checks.failing .. "/" .. total .. (if total == 1 then " check failing" else " checks failing"))
			elseif reason == "conflict" then
				add("Resolve conflicts", "Conflicts with main")
			end
		end
	elseif column == "to_review" then
		kind = "info"
		local mine = pr.reviews.mine
		if mine and (pr.reviews.requestedMe or mine.verdict == "dismissed") then
			table.insert(chips, chip("Re-review", "info"))
			detail = if pr.reviews.requestedMe then "Requested again" else "Review dismissed"
		else
			table.insert(chips, chip("Review", "info"))
			if pr.reviews.requestedMe then
				detail = "@" .. pr.author .. " asked " .. Model.ago(pr.lastActivityAt, now)
			elseif pr.addedByMe then
				detail = "Added by you"
			end
		end
	elseif column == "in_review" then
		local again = Model.awaitingReReview(pr)
		if pr.tandem then
			table.insert(chips, chip("Waiting on Tandem", "agent"))
		elseif again then
			table.insert(chips, chip("Waiting on " .. Model.reviewerList(again.waiting) .. " to re-review", "wait"))
		elseif pr.checks.state == "pending" or (pr.checks.state == "failing" and pr.reviews.decision == "approved") then
			table.insert(chips, chip("Waiting on checks", "wait"))
		else
			table.insert(chips, chip("Waiting on review", "wait"))
		end
	elseif column == "waiting_on_author" then
		local mine = pr.reviews.mine
		if mine and mine.verdict == "changes_requested" then
			table.insert(chips, chip("You requested changes", "bad-soft"))
		else
			table.insert(chips, chip("You commented", "wait"))
		end
	elseif column == "inactive" then
		table.insert(chips, chip(if pr.draft and pr.role == "mine" then "Draft" else "No recent activity", "wait"))
	elseif column == "team" then
		local owner = string.match(pr.repo, "^[^/]+") or pr.repo
		local teams: { string } = {}
		for _, slug in pr.reviews.teams do table.insert(teams, owner .. "/" .. slug) end
		table.insert(chips, chip(if #teams > 0 then "Requested from " .. Model.reviewerList(teams) else "Requested from a team", "wait"))
	end
	return chips, detail, kind
end

local MERGE_LABELS: { [string]: string } = { squash = "Squash and merge", merge = "Create a merge commit", rebase = "Rebase and merge" }

-- The repo's GitHub merge method: the resolved one when it is squash, merge or rebase, else squash
-- (viewerDefaultMergeMethod arrives with the method detection).
function M.mergeMethodFor(s: State, pr: HubPR): "squash" | "merge" | "rebase"
	local resolved = s.merges[pr.repo]
	local kind = if resolved then resolved.method.kind else "squash"
	if kind == "merge" or kind == "rebase" then return kind end
	return "squash"
end

function M.mergeLabel(kind: string): string
	return MERGE_LABELS[kind] or MERGE_LABELS.squash
end

-- What a merge in flight reads on its card.
function M.pendingNote(s: State, pr: HubPR): string?
	local pending = pr.pending
	if not pending then return nil end
	local resolved = s.merges[pr.repo]
	local method = if resolved then resolved.method else nil
	-- Asked for before the PR is ready: whatever the method, it merges by itself once approved and green.
	if Model.classify(pr, s.now, s.ignoredChecks) == "in_review" then return "Merges when ready" end
	if pending.method == "queue" then return "In the merge queue" end
	if pending.method == "label" then
		return "Labeled " .. (if method and method.kind == "label" then method.label else "for merge") .. " · waiting for the merge"
	end
	local command = if method and method.kind == "comment" then method.command else "/merge"
	if string.sub(command, 1, 8) == "/aviator" then return "Queued in Aviator" end
	return "Commented " .. command .. " · waiting for the merge"
end

-- The quiet line under a card's title: a merge in flight, or commits the viewer's approval predates.
local function noteFor(s: State, pr: HubPR, column: Column): string?
	local mine = pr.reviews.mine
	if column == "approved" and mine and mine.oid ~= "" and mine.oid ~= pr.headOid then return "New commits since you approved" end
	return M.pendingNote(s, pr)
end

-- What M does on a card: a GitHub method asks first ("confirm"), a suggested comment asks once ("ask"), and
-- a method the repo or the viewer chose (comment, label, queue) just runs: it can be cancelled.
function M.mergeStep(s: State, pr: HubPR): "confirm" | "ask" | "run"
	local resolved = s.merges[pr.repo]
	if resolved == nil then return "confirm" end
	local kind = resolved.method.kind
	if resolved.ask then return "ask" end
	if kind == "squash" or kind == "merge" or kind == "rebase" then return "confirm" end
	return "run"
end

function askingOf(s: State, pr: HubPR): string?
	local confirm = s.confirm
	if confirm and confirm.keys[1] == pr.key then
		if confirm.kind == "merge" then return M.mergeLabel(M.mergeMethodFor(s, pr)) .. " #" .. pr.number .. "?" end
		local resolved = s.merges[pr.repo]
		if confirm.kind == "learned" and resolved and resolved.method.kind == "comment" then
			return "Comment " .. resolved.method.command .. ", as this repository usually does?"
		end
	end
	return nil
end

local function toCard(pr: HubPR, placement: Model.Placement, s: State): Card
	local known = s.flakes[pr.key]
	local flake = if known and known.headOid == pr.headOid then known else nil
	local main, more = actionsFor(pr, placement.column, placement.reasons, s.merges[pr.repo], flake, s.autoMerge[pr.repo], s.details[pr.key])
	local chips, detail, detailKind = chipsFor(pr, placement, s.now)
	local agent = s.agents[pr.key]
	local summary = s.summaries[pr.key]
	local message: string? = nil
	local path: string? = nil
	local commit: string? = nil
	if summary then
		-- Keep the first job and give the verdict room on narrow cards. The full reasons
		-- still determine actions and remain available on the fixes page.
		if #chips > 1 then chips = { chips[1] } end
		detail, detailKind = summary.verdict, if pr.role == "mine" then "bad" else "info"
	end
	if agent then
		message, path, commit = M.agentMessage(agent)
		if agent.kind == "running" and placement.column == "in_review" and M.botActionable(pr) then
			if agent.run.stage == "agent" then message = "Fixing bot comments…"
			elseif agent.run.stage == "merge" then message = "Preparing worktree…" end
		end
		detail, detailKind = nil, nil
		if agent.kind == "running" then
			main, more, chips = action("card-agent-stop", "Stop", "A"), {}, { chip("Agent running", "agent") }
		elseif agent.kind == "no_clone" then
			main, more, chips = action("card-agent-clone", "Clone repo", "A"), { action("card-agent-folder", "Choose folder…", "O") }, { chip("No local clone", "wait") }
		elseif agent.kind == "failed" then
			if pr.tandem then
				-- A worktree is still held: Open worktree stays, while the branch's owner is Tandem. A lease whose return failed
				-- keeps its retry as Return worktree (⇧A, free on this card), which returns it and starts no fixer.
				main, more = action("card-handoff", "Hand off to Tandem", "A"), {}
				if agent.held and agent.worktree then table.insert(more, action("card-agent-retry", "Return worktree", "⇧A")) end
			else
				main, more, chips = action("card-agent-retry", "Try again", "A"), {}, { chip("Fix failed", "bad-soft") }
			end
			if agent.worktree then table.insert(more, action("card-agent-worktree", "Open worktree", "O")) end
		else
			-- Enter and a click use hub-open for Review fix; keep the lifecycle card's stable action slot.
			main, more, chips = nil, {}, { chip(if agent.kind == "ready" then "Fix ready" else "Pushing fix…", "done") }
		end
	end
	return {
		flake = if flake and flake.flaky and flake.reason then "Likely flaky: " .. flake.reason else nil,
		pr = pr, chips = chips, detail = detail, detailKind = detailKind, column = placement.column, reasons = placement.reasons, main = main, more = more,
		agent = agent, agentSlot = agent ~= nil or placement.column == "needs_fixes" or (placement.column == "in_review" and not pr.tandem and M.botActionable(pr)),
		agentMessage = message, agentPath = path, agentCommit = commit,
		summary = if agent then nil else summary, merge = s.merges[pr.repo], note = noteFor(s, pr, placement.column),
		asking = askingOf(s, pr), busy = s.busy[pr.key],
		ring = s.ringed[pr.key], selected = s.selected == pr.key, marked = s.marked[pr.key] == true,
	}
end

-- Every list of cards on the board: the columns', then the folds', in order.
function M.cardLists(s: State): { { Card } }
	local out: { { Card } } = {}
	for _, column in s.board.columns do table.insert(out, column.cards) end
	for _, fold in s.board.folds do table.insert(out, fold.cards) end
	return out
end

local function shortRepo(repo: string): string
	return string.match(repo, "[^/]+$") or repo
end

-- The key a row fold's row is selected and clicked by. A card's key is a node id, so the two never clash.
function M.recentKey(opened: Opened): string
	return "rc:" .. string.lower(opened.repo) .. "#" .. opened.number
end

local function recentMatches(opened: Opened, needle: string): boolean
	for _, text in { "#" .. opened.number, opened.title, opened.author, opened.repo } do
		if string.find(string.lower(text), needle, 1, true) then return true end
	end
	return false
end

-- Rebuilds the Next up banner's data: the item after the selection while walking, else the first.
local function refreshNext(s: State)
	local visible: { HubPR } = {}
	for _, pr in s.prs do
		if Model.visible(pr, M.filter(s, "")) then table.insert(visible, pr) end
	end
	s.board.nextUp = Model.nextUp(visible, s.now, if s.walking then s.selected else nil, s.ignoredChecks)
end

-- A mark lasts while its card is still selectable and shows on the board (this tab, the filter, an open fold).
-- Marks are of one group: a refresh that leaves two groups (a Ready card went behind main) keeps the first's.
local function pruneMarks(s: State, byKey: { [string]: HubPR }, present: { [string]: boolean })
	if next(s.marked) == nil then return end
	local group: Model.Group? = nil
	for _, cards in M.cardLists(s) do
		for _, card in cards do
			if s.marked[card.pr.key] and group == nil then group = Model.selectGroup(card.pr, s.now) end
		end
	end
	local kept: { [string]: boolean } = {}
	for key in s.marked do
		local pr = byKey[key]
		if pr and present[key] and group ~= nil and Model.selectGroup(pr, s.now) == group then kept[key] = true end
	end
	s.marked = kept
	if next(kept) == nil and s.confirm and (s.confirm.kind == "batch-merge" or s.confirm.kind == "batch-close") then
		s.confirm = nil
		if s.mode == "confirm" then s.mode = "board" end
	end
	for _, cards in M.cardLists(s) do
		for _, card in cards do card.marked = kept[card.pr.key] == true end
	end
end

-- Recomputes `s.board` from `s.prs` and the inputs. Keeps the selection only while its card is on the board.
-- One owner per branch: a no_clone or failed state with no worktree on a PR Tandem watches is obsolete (its Clone repo
-- and Try again start nothing now), so it is dropped. A failed state that still names a worktree is kept for its cleanup.
local function dropObsoleteAgents(s: State)
	for _, pr in s.prs do
		local agent = s.agents[pr.key]
		if pr.tandem and agent and (agent.kind == "no_clone" or (agent.kind == "failed" and not agent.worktree)) then s.agents[pr.key] = nil end
	end
end

function M.project(s: State)
	dropObsoleteAgents(s)
	local filter = M.filter(s, s.search.text)
	local placements: { [string]: Model.Placement } = {}
	local counts = { mine = 0, review = 0 }
	local inTab: { HubPR } = {}
	local hidden = 0
	local byKey: { [string]: HubPR } = {}
	for _, pr in s.prs do
		local placement = Model.placement(pr, s.now, s.ignoredChecks)
		placements[pr.key] = placement
		byKey[pr.key] = pr
		if placement.tab == s.tab and not Model.visible(pr, M.filter(s, "")) then hidden += 1 end
		if Model.visible(pr, filter) then
			if placement.column == "needs_fixes" then counts.mine += 1 end
			if placement.column == "to_review" then counts.review += 1 end
			if placement.tab == s.tab then table.insert(inTab, pr) end
		end
	end

	local columns: { { column: Column, cards: { Card } } } = {}
	local grid: { { string } } = {}
	local present: { [string]: boolean } = {}
	local total = 0
	for _, column in M.COLUMNS[s.tab] do
		local cards: { Card } = {}
		local keys: { string } = {}
		for _, pr in Model.order(inTab, column, s.sort, s.now, s.ignoredChecks) do
			table.insert(cards, toCard(pr, placements[pr.key], s))
			table.insert(keys, pr.key)
			present[pr.key] = true
		end
		total += #cards
		table.insert(columns, { column = column, cards = cards })
		table.insert(grid, keys)
	end
	-- A fold opens on its own while a search is typed, so its matches show.
	local searching = s.search.text ~= ""
	local folds: { CardFold } = {}
	local folded = 0
	for _, column in M.FOLDS[s.tab] do
		local cards: { Card } = {}
		for _, pr in Model.order(inTab, column, s.sort, s.now, s.ignoredChecks) do table.insert(cards, toCard(pr, placements[pr.key], s)) end
		local open = #cards > 0 and (not s.folded[column] or searching)
		if open then
			for _, card in cards do present[card.pr.key] = true end
		end
		folded += #cards
		table.insert(folds, { column = column, cards = cards, open = open })
	end

	-- The row fold: Recently opened under Review requests, Recently merged (the last 7 days) under Your pull requests.
	-- Narrowed by the search, and open on its own while a search finds some.
	local recent: { Opened } = {}
	local needle = string.lower(s.search.text)
	for _, opened in if s.tab == "review" then s.recent else s.merged do
		local current = s.tab == "review" or s.now - (Model.epoch(opened.at) or 0) < Model.ACTIVE_DAYS * 86400
		if current and Model.titleMatches(opened.title, s.titleRules) and (not s.repositoriesEnabled or not s.repositories or s.repositories[opened.repo]) and (needle == "" or recentMatches(opened, needle)) then table.insert(recent, opened) end
	end
	local recentOpen = #recent > 0 and (not s.folded[M.ROW_FOLD[s.tab]] or searching)
	if recentOpen then
		for _, opened in recent do present[M.recentKey(opened)] = true end
	end

	-- Every repository in this tab that the search matches, most pull requests first. A chosen repository
	-- with nothing left to show stays listed, so it can be unchosen.
	local counted: { [string]: number } = {}
	for _, pr in s.prs do
		if placements[pr.key].tab == s.tab and Model.visible(pr, { repositories = nil, search = s.search.text, titles = s.titleRules }) then
			counted[pr.repo] = (counted[pr.repo] or 0) + 1
		end
	end
	if s.repositories then
		for repo in s.repositories do counted[repo] = counted[repo] or 0 end
	end
	local repositories: { RepoOption } = {}
	for repo, count in counted do
		table.insert(repositories, { repo = repo, count = count, on = s.repositories ~= nil and s.repositories[repo] == true })
	end
	table.sort(repositories, function(a: RepoOption, b: RepoOption): boolean
		if a.count ~= b.count then return a.count > b.count end
		return string.lower(shortRepo(a.repo)) < string.lower(shortRepo(b.repo))
	end)

	s.board = {
		tab = s.tab, columns = columns, folds = folds, recent = recent,
		open = { recent = recentOpen },
		grid = grid, counts = counts, repositories = repositories, nextUp = nil, hidden = hidden,
		empty = total == 0 and folded == 0 and #recent == 0,
	}
	if s.selected and not present[s.selected] then s.selected = nil end
	if not s.selected then s.walking = false end
	refreshNext(s)
	pruneMarks(s, byKey, present)
end

function M.mode(s: State): Mode
	return s.mode
end

-- The card fold for `column` under this tab's board, if the tab has one.
function M.fold(s: State, column: Column): CardFold?
	for _, fold in s.board.folds do
		if fold.column == column then return fold end
	end
	return nil
end

-- The card with `key` on the board.
function M.card(s: State, key: string): Card?
	for _, cards in M.cardLists(s) do
		for _, card in cards do
			if card.pr.key == key then return card end
		end
	end
	return nil
end

-- The row fold's row with `key`, while that fold shows its rows.
function M.recentRow(s: State, key: string): Opened?
	if s.board.open.recent then
		for _, opened in s.board.recent do
			if M.recentKey(opened) == key then return opened end
		end
	end
	return nil
end

-- The selected row of the row fold, if one is selected.
function M.selectedRecent(s: State): Opened?
	if s.selected then return M.recentRow(s, s.selected) end
	return nil
end

function M.selectedCard(s: State): Card?
	if s.selected then return M.card(s, s.selected) end
	return nil
end

local function refreshSelection(s: State)
	for _, cards in M.cardLists(s) do
		for _, card in cards do card.selected = card.pr.key == s.selected end
	end
end

-- Whether cards in `column` show in a fold under the board instead of a column.
function M.isFold(column: Column): boolean
	return column == "inactive" or column == "team" or column == "approved"
end

-- Opens the fold `column` is shown in, so a card about to be selected there shows.
local function unfold(s: State, column: Column)
	if M.isFold(column) then s.folded[column] = false end
end

function M.select(s: State, key: string?)
	-- Choosing another card drops an inline question about the first, and leaves the add field.
	if s.confirm and s.confirm.kind ~= "batch-merge" and s.confirm.kind ~= "batch-close" and (key == nil or s.confirm.keys[1] ~= key) then M.cancelConfirm(s) end
	if s.mode == "link" and key ~= nil then s.mode = "board" end
	s.selected = key
	s.walking = false
	refreshSelection(s)
	refreshNext(s)
end

-- Moves the selection one step: "down" and "up" within a column (down from the last card enters the open
-- folds, one after another; up from their first row returns), "left" and "right" to the card at the same height
-- in the next column that has any. Nothing selected: any direction selects the first card of the first column.
function M.move(s: State, direction: "up" | "down" | "left" | "right"): boolean
	local grid = s.board.grid
	local fold: { string } = {}
	for _, cardFold in s.board.folds do
		if cardFold.open then
			for _, card in cardFold.cards do table.insert(fold, card.pr.key) end
		end
	end
	if s.board.open.recent then
		for _, opened in s.board.recent do table.insert(fold, M.recentKey(opened)) end
	end
	local selected = s.selected
	local function go(key: string): boolean
		if key == selected then return false end
		M.select(s, key)
		return true
	end
	if selected == nil then
		for _, keys in grid do
			if #keys > 0 then return go(keys[1]) end
		end
		if #fold > 0 then return go(fold[1]) end
		return false
	end
	local inFold = table.find(fold, selected)
	if inFold then
		if direction == "down" then return go(fold[math.min(#fold, inFold + 1)]) end
		if direction == "up" then
			if inFold > 1 then return go(fold[inFold - 1]) end
			for index = 1, #grid do
				local keys = grid[index]
				if #keys > 0 then return go(keys[#keys]) end
			end
		end
		return false
	end
	local column, row = 0, 0
	for index, keys in grid do
		local at = table.find(keys, selected)
		if at then column, row = index, at end
	end
	if column == 0 then return false end
	local keys = grid[column]
	if direction == "down" then
		if row == #keys and #fold > 0 then return go(fold[1]) end
		return go(keys[math.min(#keys, row + 1)])
	elseif direction == "up" then
		return go(keys[math.max(1, row - 1)])
	end
	local step = if direction == "right" then 1 else -1
	local index = column + step
	while index >= 1 and index <= #grid do
		local next = grid[index]
		if #next > 0 then return go(next[math.min(#next, row)]) end
		index += step
	end
	return false
end

-- Whether the selected card is the first in its column, where the page's header sits just above it.
function M.onTopRow(s: State): boolean
	for _, keys in s.board.grid do
		if s.selected ~= nil and keys[1] == s.selected then return true end
	end
	return false
end

function M.setTab(s: State, tab: Tab)
	if s.tab == tab then return end
	s.tab = tab
	M.project(s)
	refreshSelection(s)
end

function M.switchTab(s: State)
	M.setTab(s, if s.tab == "mine" then "review" else "mine")
end

function M.setSort(s: State, sort: Sort)
	s.sort = sort
	M.project(s)
end

-- Chooses or unchooses `repo`; with none chosen every repository shows.
function M.toggleRepository(s: State, repo: string)
	local set: { [string]: boolean } = {}
	if s.repositories then
		for name in s.repositories do set[name] = true end
	end
	if set[repo] then set[repo] = nil else set[repo] = true end
	s.repositories = if next(set) == nil then nil else set
	s.repositoriesEnabled = true
	M.project(s)
end

function M.clearRepositories(s: State)
	s.repositories = nil
	M.project(s)
end

-- Replaces the search text (tests, and a cleared field).
function M.setSearch(s: State, text: string)
	s.search = Fields.create(text)
	M.project(s)
end

-- A key typed into the search field changed its text.
function M.searched(s: State)
	M.project(s)
end

function M.openSearch(s: State)
	s.mode = "search"
	s.menu = nil
end

-- Leaves the search field; `clear` also empties it (Esc).
function M.closeSearch(s: State, clear: boolean)
	s.mode = "board"
	if clear and s.search.text ~= "" then M.setSearch(s, "") end
end

-- Opening a fold selects its first row, so j and k carry on from there.
function M.toggleFold(s: State, name: string)
	s.folded[name] = not s.folded[name]
	M.project(s)
	if s.folded[name] then return end
	if name == M.ROW_FOLD[s.tab] then
		if s.board.open.recent and #s.board.recent > 0 then M.select(s, M.recentKey(s.board.recent[1])) end
		return
	end
	local fold = M.fold(s, name :: Column)
	if fold and fold.open then M.select(s, fold.cards[1].pr.key) end
end

-- The card the Next up banner shows: the next item as a board card, whichever tab it sits on.
function M.nextCard(s: State): Card?
	local next = s.board.nextUp
	if not next then return nil end
	for _, pr in s.prs do
		if pr.key == next.item.key then return toCard(pr, Model.placement(pr, s.now, s.ignoredChecks), s) end
	end
	return nil
end

-- Selects the next item in the queue (`.` and the banner's Go), switching tabs when needed and clearing the
-- temporary search only if it hides the item. Durable filters narrow the queue. Walking then reads "n of N". Returns whether it moved.
function M.walk(s: State): boolean
	local next = s.board.nextUp
	if not next then return false end
	for _, pr in s.prs do
		if pr.key == next.item.key then
			local placement = Model.placement(pr, s.now, s.ignoredChecks)
			s.tab = placement.tab
			if not Model.visible(pr, M.filter(s, s.search.text)) then
				s.search = Fields.create("")
			end
			unfold(s, placement.column)
			s.mode, s.menu = "board", nil
			M.project(s)
			M.select(s, pr.key)
			s.walking = true
			refreshNext(s)
			return true
		end
	end
	return false
end

function M.openHelp(s: State)
	s.helpPage = if s.mode == "fixes" or s.mode == "review-fix" then s.mode else "board"
	s.mode = "help"
	s.menu = nil
end

function M.closeHelp(s: State)
	if s.mode == "help" then
		s.mode = s.helpPage or "board"
		s.helpPage = nil
	end
end

-- The rows of the open menu.
local function row(label: string, sub: string?, count: number?, on: boolean, kind: MenuKind): MenuRow
	return { label = label, sub = sub, count = count, on = on, kind = kind }
end

function M.menuRows(s: State): { MenuRow }
	local rows: { MenuRow } = {}
	if s.menu == "filters" then
		local chosen: { string } = {}
		for repo in s.repositories or {} do table.insert(chosen, repo) end
		table.sort(chosen)
		table.insert(rows, row("Repository", if #chosen == 0 then "All repositories" else table.concat(chosen, ", "), nil, s.repositoriesEnabled and #chosen > 0, if #chosen > 0 then "rule" else "navigate"))
		for _, rule in s.titleRules do
			local item = row("Title " .. (M.titleOperator(rule.operator) or ""), nil, nil, rule.enabled, "rule")
			item.value = rule.value
			table.insert(rows, item)
		end
		for _, rule in s.ignoredChecks do
			local item = row("Ignore check in Needs fixes", rule.repo, nil, rule.enabled, "rule")
			item.value = rule.name
			table.insert(rows, item)
		end
		table.insert(rows, row("Add title filter", nil, nil, false, "navigate"))
		table.insert(rows, row("Ignore a check…", nil, nil, false, "navigate"))
		if s.repositories or #s.titleRules > 0 or #s.ignoredChecks > 0 then table.insert(rows, row("Clear filters", nil, nil, false, "clear")) end
	elseif s.menu == "title-filter" and s.filterEdit then
		for _, option in M.TITLE_OPERATORS do table.insert(rows, row(option.label, nil, nil, option.id == s.filterEdit.operator, "choice")) end
		if s.filterEdit.index then table.insert(rows, row("Remove filter", nil, nil, false, "clear")) end
	elseif s.menu == "check-repository" then
		for _, repo in M.checkRepositories(s) do table.insert(rows, row(repo, nil, nil, false, "navigate")) end
	elseif s.menu == "check-filter" and s.filterEdit then
		local names: { [string]: boolean } = {}
		for _, pr in s.prs do
			if pr.repo == s.filterEdit.repo then
				for _, name in pr.checks.failedNames or {} do names[name] = true end
			end
		end
		local sorted: { string } = {}
		for name in names do table.insert(sorted, name) end
		table.sort(sorted)
		for _, name in sorted do table.insert(rows, row(name, nil, nil, false, "navigate")) end
		if s.filterEdit.index then table.insert(rows, row("Remove filter", nil, nil, false, "clear")) end
	elseif s.menu == "sort" then
		for _, sort in M.SORTS do
			table.insert(rows, row(sort.label, sort.sub, nil, s.sort == sort.id, "choice"))
		end
	elseif s.menu == "repositories" then
		for _, option in s.board.repositories do
			table.insert(rows, row(shortRepo(option.repo), nil, option.count, option.on, "check"))
		end
		if s.repositories then table.insert(rows, row("Clear filter", nil, nil, false, "clear")) end
	elseif s.menu == "merge" then
		local repo = M.mergeRepo(s)
		local current = if repo and s.merges[repo] then s.merges[repo].method else nil
		for _, kind in M.MERGE_KINDS do
			local sub: string? = nil
			if current and current.kind == kind.id then
				if current.kind == "comment" then sub = current.command elseif current.kind == "label" then sub = current.label end
			end
			table.insert(rows, row(kind.label, sub, nil, current ~= nil and current.kind == kind.id, "choice"))
		end
	elseif s.menu == "actions" then
		local card = M.selectedCard(s)
		if card then
			for _, more in card.more do table.insert(rows, row(more.label, more.key, nil, false, "choice")) end
		end
	end
	return rows
end

function M.openMenu(s: State, menu: MenuId)
	s.menu = menu
	s.mode = "menu"
	s.menuCursor = 1
	if menu == "sort" then
		for index, sort in M.SORTS do
			if sort.id == s.sort then s.menuCursor = index end
		end
	elseif menu == "settings" then
		s.models = if s.agent then ModelBox.open(s.agent, "explain") else nil
	elseif menu == "merge" then
		local repo = M.mergeRepo(s)
		local current = if repo and s.merges[repo] then s.merges[repo].method.kind else "squash"
		for index, kind in M.MERGE_KINDS do
			if kind.id == current then s.menuCursor = index end
		end
	end
	s.methodEdit = nil
	s.filterEdit = nil
end

function M.closeMenu(s: State)
	s.filterEdit = nil
	s.menu = nil
	s.models = nil
	s.methodEdit = nil
	if s.mode == "menu" then s.mode = "board" end
end

function M.menuMove(s: State, delta: number)
	s.menuCursor = math.clamp(s.menuCursor + delta, 1, math.max(1, #M.menuRows(s)))
end

-- Where GitHub links open: `to`, else the other one.
function M.setLinks(s: State, to: string?)
	s.links = if to == "tern" or to == "browser" then to elseif s.links == "tern" then "browser" else "tern"
end

-- Space or the checkbox toggles a saved rule, retaining its values. Enter or the row edits it.
function M.toggleFilter(s: State, index: number)
	if s.menu ~= "filters" then return end
	if index == 1 and s.repositories then s.repositoriesEnabled = not s.repositoriesEnabled
	elseif index > 1 and index <= #s.titleRules + 1 then
		local rule = s.titleRules[index - 1]
		rule.enabled = not rule.enabled
	else
		local rule = s.ignoredChecks[index - #s.titleRules - 1]
		if rule then rule.enabled = not rule.enabled end
	end
	M.project(s)
end

function M.beginFilterEdit(s: State, kind: "title" | "check", index: number?, repo: string?)
	local title = if kind == "title" and index then s.titleRules[index] else nil
	local check = if kind == "check" and index then s.ignoredChecks[index] else nil
	M.openMenu(s, if kind == "title" then "title-filter" else "check-filter")
	s.filterEdit = { index = index, operator = if title then title.operator else "not_starts", repo = if check then check.repo else repo, field = Fields.create(if title then title.value elseif check then check.name else ""), typing = true }
	if kind == "title" then
		local operator = if title then title.operator else "not_starts"
		for i, option in M.TITLE_OPERATORS do if option.id == operator then s.menuCursor = i end end
	end
end

function M.saveFilter(s: State): boolean
	local edit = s.filterEdit
	if not edit then return false end
	local value = string.gsub(string.gsub(edit.field.text, "^%s+", ""), "%s+$", "")
	if value == "" then return false end
	if s.menu == "title-filter" then
		local old = if edit.index then s.titleRules[edit.index] else nil
		local rule: Model.TitleRule = { operator = edit.operator, value = value, enabled = old == nil or old.enabled }
		if edit.index then s.titleRules[edit.index] = rule else table.insert(s.titleRules, rule) end
	elseif s.menu == "check-filter" and edit.repo then
		local old = if edit.index then s.ignoredChecks[edit.index] else nil
		local rule: Model.IgnoredCheck = { repo = edit.repo, name = value, enabled = old == nil or old.enabled }
		if edit.index then s.ignoredChecks[edit.index] = rule else table.insert(s.ignoredChecks, rule) end
	else return false end
	M.project(s)
	M.openMenu(s, "filters")
	return true
end

function M.removeFilter(s: State)
	local edit = s.filterEdit
	if edit and edit.index then
		if s.menu == "title-filter" then table.remove(s.titleRules, edit.index)
		elseif s.menu == "check-filter" then table.remove(s.ignoredChecks, edit.index) end
	end
	M.project(s)
	M.openMenu(s, "filters")
end

-- Whether AI guides are prepared in the background: `to` ("true" or "false"), else the other one.
function M.setPrepareGuides(s: State, to: string?)
	s.prepareGuides = if to == "true" then true elseif to == "false" then false else not s.prepareGuides
end

-- Applies row `index` of the open menu: a sort is chosen and the menu closes; a repository is
-- toggled and the menu stays; Clear filter clears and closes. Returns whether the menu closed.
function M.menuPick(s: State, index: number): boolean
	local rows = M.menuRows(s)
	local row = rows[index]
	if not row then return false end
	s.menuCursor = index
	if s.menu == "filters" then
		local titles, checks = #s.titleRules, #s.ignoredChecks
		if index == 1 then M.openMenu(s, "repositories")
		elseif index <= titles + 1 then M.beginFilterEdit(s, "title", index - 1, nil)
		elseif index <= titles + checks + 1 then M.beginFilterEdit(s, "check", index - titles - 1, nil)
		elseif index == titles + checks + 2 then M.beginFilterEdit(s, "title", nil, nil)
		elseif index == titles + checks + 3 then M.openMenu(s, "check-repository")
		else
			s.repositories, s.repositoriesEnabled, s.titleRules, s.ignoredChecks = nil, true, {}, {}
			M.project(s)
			M.closeMenu(s)
			return true
		end
		return false
	elseif s.menu == "title-filter" and s.filterEdit then
		if row.kind == "clear" then M.removeFilter(s)
		else s.filterEdit.operator = M.TITLE_OPERATORS[index].id :: Model.TitleOperator; s.filterEdit.typing = true end
		return false
	elseif s.menu == "check-repository" then
		M.beginFilterEdit(s, "check", nil, row.label)
		return false
	elseif s.menu == "check-filter" and s.filterEdit then
		if row.kind == "clear" then M.removeFilter(s)
		else s.filterEdit.field = Fields.create(row.label); M.saveFilter(s) end
		return false
	elseif s.menu == "sort" then
		M.setSort(s, M.SORTS[index].id)
		M.closeMenu(s)
		return true
	elseif s.menu == "repositories" then
		if row.kind == "clear" then
			M.clearRepositories(s)
			M.closeMenu(s)
			return true
		end
		M.toggleRepository(s, s.board.repositories[index].repo)
		return false
	end
	return false
end

-- The alternative the open "actions" menu has highlighted at `index`.
function M.actionAt(s: State, index: number): CardAction?
	local card = M.selectedCard(s)
	if s.menu == "actions" and card then return card.more[index] end
	return nil
end

-- The merge chooser ----------------------------------------------------------------------------------------

M.MERGE_KINDS = {
	{ id = "squash", label = "Squash and merge" }, { id = "merge", label = "Create a merge commit" },
	{ id = "rebase", label = "Rebase and merge" }, { id = "queue", label = "Merge when ready" },
	{ id = "comment", label = "Comment a command" }, { id = "label", label = "Add a label" },
}

-- Where the repo's current setting came from, for the chooser's foot.
local SOURCES: { [string]: string } = {
	user = "Set by you", declared = "Declared by the repository", learned = "Learned from the last 8 merges",
	viewer = "Your GitHub default",
}

function M.mergeSource(s: State): string?
	local repo = M.mergeRepo(s)
	local resolved = if repo then s.merges[repo] else nil
	return if resolved then SOURCES[resolved.source] else nil
end

-- The repository the open merge menu is about: the selected card's.
function M.mergeRepo(s: State): string?
	local card = M.selectedCard(s)
	return if card then card.pr.repo else nil
end

-- Sets the repo's resolution (the block resolves it from kv evidence).
function M.setMerge(s: State, repo: string, resolution: Model.MergeResolution)
	s.merges[repo] = resolution
	M.project(s)
end

-- The repo's "Allow auto-merge" setting, read by detection: Merge when ready shows only where it's on.
function M.setAutoMerge(s: State, repo: string, allowed: boolean)
	s.autoMerge[repo] = allowed
	M.project(s)
end

-- Reviewers just asked again: their requests show at once, until a refresh brings GitHub's own.
function M.reRequested(s: State, key: string, logins: { string })
	for _, pr in s.prs do
		if pr.key == key then
			local requested = {}
			for _, name in pr.reviews.requested do table.insert(requested, name) end
			for _, name in logins do
				if not table.find(requested, name) then table.insert(requested, name) end
			end
			local reviews = {}
			for k, v in pr.reviews do reviews[k] = v end
			reviews.requested = requested
			pr.reviews = reviews :: any
		end
	end
	M.project(s)
end

-- Row `index` of the merge menu wants text (a command, a label): the menu shows a field, prefilled with the current one.
function M.beginMethodEdit(s: State, kind: "comment" | "label")
	local repo = M.mergeRepo(s)
	if not repo then return end
	local current = if s.merges[repo] then s.merges[repo].method else nil
	local text = ""
	if current and current.kind == "comment" and kind == "comment" then
		text = current.command .. (if current.cancel then " | " .. current.cancel else "")
	elseif current and current.kind == "label" and kind == "label" then
		text = current.label
	end
	s.methodEdit = { repo = repo, kind = kind, field = Fields.create(text) }
end

function M.cancelMethodEdit(s: State)
	s.methodEdit = nil
end

local function trimmed(text: string): string
	local start = string.gsub(text, "^%s+", "")
	return (string.gsub(start, "%s+$", ""))
end

-- The method the field names: "/merge" or "/merge | /cancel" for a comment, a label's name for a label; nil when empty.
function M.methodOfEdit(s: State): Model.MergeMethod?
	local edit = s.methodEdit
	if not edit then return nil end
	local text = trimmed(edit.field.text)
	if text == "" then return nil end
	if edit.kind == "label" then return { kind = "label", label = text } end
	local command, cancel = string.match(text, "^(.-)%s*|%s*(.*)$")
	command = trimmed(command or text)
	if command == "" then return nil end
	cancel = if cancel and trimmed(cancel) ~= "" then trimmed(cancel) else nil
	return { kind = "comment", command = command, cancel = cancel }
end

-- Card actions --------------------------------------------------------------------------------------------

-- Opens the merge question on the card `key` when it offers Merge and nothing else is running on it.
function M.askMerge(s: State, key: string): boolean
	local card = M.card(s, key)
	if not card or not card.main or card.main.act ~= "card-merge" or s.busy[key] then return false end
	M.select(s, key)
	s.confirm = { kind = if M.mergeStep(s, card.pr) == "ask" then "learned" else "merge", keys = { key } }
	s.mode, s.menu = "confirm", nil
	M.project(s)
	return true
end

function M.cancelConfirm(s: State)
	local had = s.confirm ~= nil
	s.confirm = nil
	if s.mode == "confirm" then s.mode = "board" end
	if had then M.project(s) end
end

-- Selecting several ---------------------------------------------------------------------------------------

-- The marked cards in column order: Ready's cards, or the Inactive rows.
function M.markedCards(s: State): { Card }
	local out: { Card } = {}
	for _, cards in M.cardLists(s) do
		for _, card in cards do
			if s.marked[card.pr.key] then table.insert(out, card) end
		end
	end
	return out
end

-- Space: marks or unmarks the card. Marking in one group clears the other's. Returns false, and why, for a card
-- that can't be selected.
function M.toggleMark(s: State, key: string): (boolean, string?)
	local card = M.card(s, key)
	if not card then return false, nil end
	local group, why = Model.selectGroup(card.pr, s.now)
	if not group then return false, why end
	if s.marked[key] then
		s.marked[key] = nil
	else
		for other in s.marked do
			local mark = M.card(s, other)
			if not mark or Model.selectGroup(mark.pr, s.now) ~= group then s.marked[other] = nil end
		end
		s.marked[key] = true
	end
	M.project(s)
	return true, nil
end

-- Pull requests Close stale would select: no activity for 7 days, not a draft.
function M.staleCount(s: State): number
	local count = 0
	local fold = M.fold(s, "inactive")
	for _, card in if fold then fold.cards else {} do
		if Model.stale(card.pr, s.now) then count += 1 end
	end
	return count
end

-- ⇧X: replaces the selection with every stale non-draft Inactive row, and opens the fold. Returns how many.
function M.markStale(s: State): number
	if s.tab ~= "mine" then return 0 end
	local marked: { [string]: boolean } = {}
	local count = 0
	local fold = M.fold(s, "inactive")
	for _, card in if fold then fold.cards else {} do
		if Model.stale(card.pr, s.now) then
			marked[card.pr.key] = true
			count += 1
		end
	end
	if count == 0 then return 0 end
	s.marked = marked
	s.folded.inactive = false
	M.project(s)
	return count
end

-- Esc: drops the selection (and a confirm about it). Returns whether there was one.
function M.clearMarks(s: State): boolean
	if next(s.marked) == nil then return false end
	s.marked = {}
	if s.confirm and (s.confirm.kind == "batch-merge" or s.confirm.kind == "batch-close") then
		s.confirm = nil
		if s.mode == "confirm" then s.mode = "board" end
	end
	M.project(s)
	return true
end

-- M or X on a selection: opens the confirm over the bar. Returns false when nothing of that group is marked.
function M.askBatch(s: State, group: Model.Group): boolean
	local cards = M.markedCards(s)
	if #cards == 0 or Model.selectGroup(cards[1].pr, s.now) ~= group then return false end
	local keys: { string } = {}
	for _, card in cards do table.insert(keys, card.pr.key) end
	s.confirm = { kind = if group == "ready" then "batch-merge" else "batch-close", keys = keys }
	s.mode, s.menu = "confirm", nil
	M.project(s)
	return true
end

-- The method the repo's merge uses; squash until it is known.
local function methodOf(s: State, pr: HubPR): Model.MergeMethod
	local resolved = s.merges[pr.repo]
	return if resolved then resolved.method else { kind = "squash" }
end

-- What the selection bar shows, or nil with nothing selected.
function M.selection(s: State): Selection?
	local cards = M.markedCards(s)
	if #cards == 0 then return nil end
	local group = Model.selectGroup(cards[1].pr, s.now)
	if not group then return nil end
	local merge = group == "ready"
	local n = #cards
	local verb = if merge then "Merge" else "Close"
	local selection: Selection = {
		group = group, count = n, verb = verb, key = if merge then "M" else "X",
		act = if merge then "hub-batch-merge" else "hub-batch-close", confirm = nil,
	}
	local confirm = s.confirm
	if confirm and (confirm.kind == "batch-merge" or confirm.kind == "batch-close") then
		local prs: { HubPR } = {}
		local methods: { Model.MergeMethod } = {}
		for _, card in cards do
			table.insert(prs, card.pr)
			table.insert(methods, methodOf(s, card.pr))
		end
		local list = Model.confirmList(prs)
		local rows: { BatchRow } = {}
		for _, pr in list.shown do table.insert(rows, { ref = shortRepo(pr.repo) .. " #" .. pr.number, title = pr.title }) end
		selection.confirm = {
			question = verb .. " " .. n .. (if n == 1 then " pull request?" else " pull requests?"),
			rows = rows, more = list.more,
			lines = if merge then Model.methodLines(methods) else { "Closed pull requests can be reopened." },
			go = verb .. " " .. n, act = "hub-confirm",
		}
	end
	return selection
end

-- Marks `key` as running `text`, or clears it with nil.
function M.setBusy(s: State, key: string, text: string?)
	s.busy[key] = text
	M.project(s)
end

-- Records (or clears, with nil) a merge asked for through a queue, comment or label.
function M.setPending(s: State, key: string, pending: Model.PendingMerge?)
	for _, pr in s.prs do
		if pr.key == key then pr.pending = pending end
	end
	M.project(s)
end

-- Takes the pull request off the board (merged, or removed from a refresh the viewer just made).
function M.dropPr(s: State, key: string)
	local kept: { HubPR } = {}
	for _, pr in s.prs do
		if pr.key ~= key then table.insert(kept, pr) end
	end
	s.prs = kept
	s.busy[key] = nil
	M.project(s)
end

-- Updating the branch makes its checks run again: the card waits on them until a refresh says otherwise.
function M.branchUpdated(s: State, key: string)
	-- The new head is unread: no U until the details at it say how it stands against the base.
	local known = s.details[key]
	if known then known.behindBy = nil end
	for _, pr in s.prs do
		if pr.key == key then
			pr.behind = false
			pr.checks = { state = "pending", passing = 0, failing = 0, pending = 0 }
		end
	end
	s.busy[key] = nil
	M.project(s)
end

-- Marks a pull request on the board as added by link, which moves a folded review request into To review.
function M.markAdded(s: State, key: string)
	for _, pr in s.prs do
		if pr.key == key then pr.addedByMe = true end
	end
	M.project(s)
end

-- Removes a pull request the viewer added by link: it leaves the board unless it is on it for another
-- reason, in which case only the "Added by you" mark goes. A refresh settles the rest.
function M.unadd(s: State, key: string)
	for _, pr in s.prs do
		if pr.key == key then
			pr.addedByMe = false
			if not pr.reviews.requestedMe and pr.reviews.mine == nil and #pr.reviews.teams == 0 then return M.dropPr(s, key) end
		end
	end
	M.project(s)
end

-- Add by link ---------------------------------------------------------------------------------------------

M.ADDED_CAP = 50

export type LinkTarget =
	{ kind: "empty" }
	| { kind: "invalid" }
	| { kind: "new", repo: string, number: number }
	| { kind: "board", repo: string, number: number, pr: HubPR }
	| { kind: "folded", repo: string, number: number, pr: HubPR, column: Column } -- a review request in Inactive or Team requests

-- The pull request the add field's text names: a github.com pull request link, or `owner/repo#123`.
local function parseRef(text: string): Model.PRRef?
	local trimmed = string.match(text, "^%s*(.-)%s*$") :: string
	-- A link pasted without its scheme ("github.com/owner/repo/pull/123") is the same link.
	local lowered = string.lower(trimmed)
	if string.find(lowered, "^github%.com/") or string.find(lowered, "^www%.github%.com/") then trimmed = "https://" .. trimmed end
	local repo: string?
	local number: number?
	local host = Links.linkHost(trimmed)
	if host then
		local lowerHost = string.lower(host)
		if lowerHost ~= "github.com" and lowerHost ~= "www.github.com" then return nil end
		repo, number = Links.linkRepo(trimmed), Links.named(trimmed)
	else
		local r, n = string.match(trimmed, "^([%w_.%-]+/[%w_.%-]+)#(%d+)$")
		repo, number = r, tonumber(n)
	end
	if repo == nil or number == nil or string.match(repo, "^[%w_.%-]+/[%w_.%-]+$") == nil then return nil end
	if (number :: number) < 1 then return nil end
	return { repo = repo, number = number :: number }
end

-- The pull request on the board named by `repo` (any case) and `number`.
function M.find(s: State, repo: string, number: number): HubPR?
	for _, pr in s.prs do
		if pr.number == number and string.lower(pr.repo) == string.lower(repo) then return pr end
	end
	return nil
end

function M.linkTarget(s: State): LinkTarget
	local text = s.link.text
	if string.match(text, "^%s*$") then return { kind = "empty" } end
	local ref = parseRef(text)
	if not ref then return { kind = "invalid" } end
	local pr = M.find(s, ref.repo, ref.number)
	if pr then
		local placement = Model.placement(pr, s.now, s.ignoredChecks)
		if placement.tab == "review" and (placement.column == "inactive" or placement.column == "team") then
			return { kind = "folded", repo = pr.repo, number = pr.number, pr = pr, column = placement.column }
		end
		return { kind = "board", repo = pr.repo, number = pr.number, pr = pr }
	end
	return { kind = "new", repo = ref.repo, number = ref.number }
end

-- N: the add field, on Review requests.
function M.openLink(s: State)
	s.menu = nil
	M.setTab(s, "review")
	s.mode = "link"
end

-- Leaves the add field; `clear` empties it too.
function M.closeLink(s: State, clear: boolean)
	if s.mode == "link" then s.mode = "board" end
	if clear and s.link.text ~= "" then s.link = Fields.create("") end
end

-- Brings the pull request `key` into view and selects it: its tab, with the search and repository filter
-- cleared if they hide it, and its fold open if it sits in one. Returns whether it was found.
function M.show(s: State, key: string): boolean
	for _, pr in s.prs do
		if pr.key == key then
			local placement = Model.placement(pr, s.now, s.ignoredChecks)
			s.tab = placement.tab
			s.search = Fields.create("")
			s.repositories = nil
			for _, rule in s.titleRules do
				if not Model.titleMatches(pr.title, { rule }) then rule.enabled = false end
			end
			unfold(s, placement.column)
			s.mode, s.menu = "board", nil
			M.project(s)
			M.select(s, key)
			return true
		end
	end
	return false
end

-- Adds `ref` to the added set. Returns the new set, or nil with why it can't (the set is full).
function M.withAdded(added: { [string]: Model.PRRef }, ref: Model.PRRef): ({ [string]: Model.PRRef }?, string?)
	local key = ref.repo .. "#" .. ref.number
	if added[key] then return added, nil end
	local count = 0
	for _ in added do count += 1 end
	if count >= M.ADDED_CAP then
		return nil, M.ADDED_CAP .. " pull requests are added already. Remove one first."
	end
	local out = table.clone(added)
	out[key] = ref
	return out, nil
end

-- `added` with each entry that names a fetched PR under that PR's own spelling of the repo ("Acme/API#5"
-- becomes "acme/api#5"). Returns the set and whether anything changed.
function M.canonicalAdded(added: { [string]: Model.PRRef }, prs: { HubPR }): ({ [string]: Model.PRRef }, boolean)
	local out = table.clone(added)
	local changed = false
	for _, pr in prs do
		local wrong = nil
		for key, ref in added do
			if key ~= pr.key and ref.number == pr.number and string.lower(ref.repo) == string.lower(pr.repo) then wrong = key end
		end
		if wrong then
			out[wrong] = nil
			out[pr.key] = { repo = pr.repo, number = pr.number }
			changed = true
		end
	end
	return out, changed
end

-- Opening a pull request ----------------------------------------------------------------------------------

export type OpenPlan = { kind: "open", url: string } | { kind: "refuse", text: string, sub: string }

-- What opening PR `number` of `slug` does, given what the block found: `root` is a checkout of the repo (or
-- nil), `why` is why PR Guide can't keep its own copy (or nil when it can), `dir` is the folder searched.
function M.openPlan(slug: string, number: number, generate: boolean, root: string?, why: string?, dir: string): OpenPlan
	if root then return { kind = "open", url = Links.openLink(slug, number, root, generate, false) } end
	if why or dir == "" then
		return { kind = "refuse", text = "Couldn't open #" .. number .. " of " .. slug, sub = why or "No folder to look for a checkout in." }
	end
	return { kind = "open", url = Links.openLink(slug, number, dir, generate, true) }
end

-- The checks popover -------------------------------------------------------------------------------------------
-- Opened from a card's checks mark (or V), or from the fixes page's All checks row, over whichever page is open.
-- Its list is read once per commit and again while a check is unfinished; the block does the reading.

export type ChecksPress = { kind: "open", url: string, name: string } | { kind: "expand" } | { kind: "retry" }

local function checksKey(pr: HubPR): string
	return pr.key .. "@" .. pr.headOid
end

-- The check list for `key` at the commit now at its head: loading, loaded or failed, or nil before any read.
function M.checkLoad(s: State, key: string): Checks.Load?
	local pr = M.prOf(s, key)
	return if pr then s.checkLists[checksKey(pr)] else nil
end

-- Whether `key`'s list should be read now: never read at this commit, or the last read failed.
function M.checksWanted(s: State, key: string): boolean
	local load = M.checkLoad(s, key)
	return load == nil or load.state == "failed"
end

-- Opens the popover on `key`; false when no such PR is on hand. The highlight starts on the first row.
function M.openChecks(s: State, key: string): boolean
	if M.prOf(s, key) == nil then return false end
	local pop: Checks.Popover = { key = key, hl = 1, passedOpen = false, seen = {}, from = if s.route then "fixes" else "board" }
	s.checks, s.mode, s.menu = pop, "checks", nil
	local load = M.checkLoad(s, key)
	if load and load.state == "loaded" then Checks.observe(pop, load.list) end
	return true
end

function M.closeChecks(s: State)
	s.checks = nil
	if s.mode == "checks" then s.mode = if s.route then "fixes" else "board" end
end

-- Records a read of `key`'s list at `headOid`. While the popover shows it, unfinished checks are noted as seen.
function M.setCheckLoad(s: State, key: string, headOid: string, load: Checks.Load)
	s.checkLists[key .. "@" .. headOid] = load
	local pop = s.checks
	if pop and pop.key == key and load.state == "loaded" then
		Checks.observe(pop, load.list)
		pop.hl = math.clamp(pop.hl, 1, math.max(1, #Checks.choices(Checks.lines(load.list, pop, s.now))))
	end
end

-- The open popover's lines (empty unless its list is loaded) and its load.
function M.checkLines(s: State): ({ Checks.Line }, Checks.Load?)
	local pop = s.checks
	if pop == nil then return {}, nil end
	local load = M.checkLoad(s, pop.key)
	if load == nil or load.state ~= "loaded" then return {}, load end
	return Checks.lines(load.list, pop, s.now), load
end

function M.checksMove(s: State, delta: number)
	local pop = s.checks
	if pop == nil then return end
	local lines = M.checkLines(s)
	pop.hl = math.clamp(pop.hl + delta, 1, math.max(1, #Checks.choices(lines)))
end

-- What ⏎ does on the highlighted row: open a check's link, unfold Passed, or read a failed list again.
function M.checksPress(s: State): ChecksPress?
	local pop = s.checks
	if pop == nil then return nil end
	local lines, load = M.checkLines(s)
	if load and load.state == "failed" then return { kind = "retry" } end
	local line = Checks.choices(lines)[pop.hl]
	if line == nil then return nil end
	if line.kind == "more" then
		pop.passedOpen = true
		return { kind = "expand" }
	end
	if line.kind == "check" then return { kind = "open", url = line.row.url, name = line.row.name } end
	return nil
end

-- Highlights row `index` and presses it, as a click does.
function M.checksPick(s: State, index: number): ChecksPress?
	local pop = s.checks
	if pop == nil then return nil end
	pop.hl = index
	return M.checksPress(s)
end

-- Whether the popover's pull request has a failing check: what its list says, else the board's count.
function M.checksFailing(s: State): boolean
	local pop = s.checks
	local pr = if pop then M.prOf(s, pop.key) else nil
	if pop == nil or pr == nil then return false end
	local load = M.checkLoad(s, pop.key)
	if load and load.state == "loaded" then return Checks.counts(load.list).failing > 0 end
	return pr.checks.failing > 0
end

-- The fixes page ------------------------------------------------------------------------------------------------
-- A route over the board: Esc returns to it with the card still selected. All pure; the block reads the
-- details, runs git and the writes.

-- Opens the page on the PR `key`; false when no such PR is on hand. Details already read for the same
-- commit show at once while the block reads them again.
function M.openFixes(s: State, key: string): boolean
	local pr = M.prOf(s, key)
	if pr == nil then return false end
	local known = s.details[key]
	s.route = {
		kind = "fixes", key = key, cur = 1, focus = "steps", item = 1,
		loading = known == nil or known.headOid ~= pr.headOid, error = nil, bots = false,
		resolved = {}, replies = {}, reply = nil, busy = false,
	}
	s.mode, s.menu, s.confirm = "fixes", nil, nil
	return true
end

function M.closeFixes(s: State)
	s.route, s.mode, s.checks = nil, "board", nil
end

-- The PR with `key`, on the board or not.
function M.prOf(s: State, key: string): HubPR?
	for _, pr in s.prs do
		if pr.key == key then return pr end
	end
	return nil
end

-- Details to build the steps from: what was read, or nothing yet (the PR's own flags still make steps).
function M.fixDetails(s: State): FixDetails?
	local route = s.route
	local pr = if route then M.prOf(s, route.key) else nil
	if route == nil or pr == nil then return nil end
	return s.details[route.key] or {
		key = pr.key, headOid = pr.headOid, fetchedAt = "", reviews = {}, threads = {}, checks = {}, changedPaths = {},
		conflicts = nil, conflictNote = nil, files = nil,
	}
end

function M.fixSteps(s: State): { Fixes.Step }
	local route = s.route
	local pr = if route then M.prOf(s, route.key) else nil
	local details = M.fixDetails(s)
	if route == nil or pr == nil or details == nil then return {} end
	return Fixes.steps(details, pr)
end

function M.fixStep(s: State): Fixes.Step?
	local route = s.route
	if route == nil then return nil end
	return M.fixSteps(s)[route.cur]
end

-- Steps still to do: not a thread resolved from the page.
function M.fixLeft(s: State): number
	local route = s.route
	local left = 0
	for _, step in M.fixSteps(s) do
		if route == nil or step.thread == nil or not route.resolved[step.thread.id] then left += 1 end
	end
	return left
end

-- What U does to `key`'s branch so its checks run again, read from the details at its head: Update branch when the
-- base has commits the head lacks, Push empty commit when it is up to date. Nothing when the branch conflicts with the
-- base or GitHub couldn't compare them.
function M.branchAction(s: State, key: string): BranchAction?
	local pr, known = M.prOf(s, key), s.details[key]
	if pr == nil or known == nil or known.headOid ~= pr.headOid or pr.conflicts or known.behindBy == nil then return nil end
	if known.conflicts and #known.conflicts > 0 then return nil end
	if known.behindBy > 0 then return { kind = "update", behind = known.behindBy } end
	return if known.branch then { kind = "empty", branch = known.branch } else nil
end

-- The actions the panel's j and k move over for `step`; "agent" is the card's own main action.
function M.fixItems(s: State, step: Fixes.Step?): { string }
	if step == nil then return {} end
	local card = if s.route then M.card(s, s.route.key) else nil
	local agent = card ~= nil and card.main ~= nil and card.main.act ~= "open"
	if step.thread then return { "reply", "resolve" } end
	if step.check then return if s.route and M.branchAction(s, s.route.key) then { "log", "rerun", "update" } else { "log", "rerun" } end
	if step.conflict then return if agent then { "agent", "github" } else { "github" } end
	return { "github" }
end

-- The card's main action, which the page shows under the card's own label ("Hand off to Tandem").
function M.fixMain(s: State): CardAction?
	local card = if s.route then M.card(s, s.route.key) else nil
	local main = if card then card.main else nil
	if main and main.act ~= "open" then return main end
	return nil
end

function M.fixSelect(s: State, index: number)
	local route = s.route
	if route == nil then return end
	route.cur = math.clamp(index, 1, math.max(1, #M.fixSteps(s)))
	route.item, route.reply, route.ask = 1, nil, false
	s.mode = "fixes"
end

-- j and k: the next or previous step in the left column, or the next action in the panel.
function M.fixMove(s: State, delta: number)
	local route = s.route
	if route == nil then return end
	if route.focus == "steps" then
		M.fixSelect(s, route.cur + delta)
		return
	end
	route.item = math.clamp(route.item + delta, 1, math.max(1, #M.fixItems(s, M.fixStep(s))))
end

function M.fixFocus(s: State, focus: "steps" | "panel")
	local route = s.route
	if route == nil then return end
	route.focus = focus
	route.item = 1
end

-- ⏎: from the steps into the panel; in the panel, the highlighted action (returned for the block to run).
function M.fixPress(s: State): string?
	local route = s.route
	if route == nil then return nil end
	if route.focus == "steps" then
		M.fixFocus(s, "panel")
		return nil
	end
	return M.fixItems(s, M.fixStep(s))[route.item]
end

-- The Push empty commit question, open or closed; it opens only while the step on show offers it.
function M.fixAsk(s: State, ask: boolean)
	local route, step = s.route, M.fixStep(s)
	if route == nil then return end
	local action = M.branchAction(s, route.key)
	route.ask = ask and step ~= nil and step.check ~= nil and action ~= nil and action.kind == "empty"
end

function M.fixToggleBots(s: State)
	if s.route then s.route.bots = not s.route.bots end
end

-- R: starts a reply on a thread step.
function M.beginReply(s: State): boolean
	local route, step = s.route, M.fixStep(s)
	if route == nil or step == nil or step.thread == nil or route.resolved[step.thread.id] then return false end
	route.reply, route.focus = Fields.create("", true), "panel"
	s.mode = "reply"
	return true
end

function M.cancelReply(s: State)
	if s.route then s.route.reply = nil end
	if s.mode == "reply" then s.mode = "fixes" end
end

-- The details the block read: the page's steps follow them.
function M.setDetails(s: State, details: FixDetails)
	local known = s.details[details.key]
	if known and (known.headOid ~= details.headOid or M.feedbackPrompt(s, known) ~= M.feedbackPrompt(s, details)) then s.summaries[details.key] = nil end
	s.details[details.key] = details
	if s.route and s.route.kind == "fixes" and s.route.key == details.key then
		s.route.loading, s.route.error = false, nil
		s.route.cur = math.clamp(s.route.cur, 1, math.max(1, #M.fixSteps(s)))
	end
	M.project(s)
end

-- The summary prompt for the feedback that is live on the board's PR (the raw details when it has left the board).
function M.feedbackPrompt(s: State, details: FixDetails): string
	local pr = M.prOf(s, details.key)
	return Summary.prompt(if pr then Summary.current(details, pr) else details)
end

-- Installs only a complete answer for the exact feedback and head still on the board. Never saved.
function M.installSummary(s: State, details: FixDetails, text: string): boolean
	local pr, known = M.prOf(s, details.key), s.details[details.key]
	if not pr or pr.headOid ~= details.headOid or not known or known.headOid ~= details.headOid
		or M.feedbackPrompt(s, known) ~= M.feedbackPrompt(s, details) then return false end
	local parsed = Summary.parse(text)
	if not parsed or not Summary.matches(details, parsed) then return false end
	s.summaries[details.key] = parsed
	M.project(s)
	return true
end

-- Review fix reuses the fixes route's frame without changing fixes/reply's fields or keys.
export type ReviewPage = {
	pr: HubPR, fix: AgentFix.Fix, review: ReviewFix.Review?, reviewed: { [string]: boolean },
	current: ReviewFix.Hunk?, lines: { ReviewFix.Line },
	count: number, all: boolean, cur: number, original: boolean, ask: boolean,
	bot: boolean?, -- prepared wording for bot edit hunks; the review and Push contracts are unchanged
	busy: boolean, loading: boolean, error: string?, progress: string?, completion: ("push" | "discard")?,
}

function M.openReviewFix(s: State, key: string): boolean
	local agent, pr = s.agents[key], M.prOf(s, key)
	if not pr or not agent or agent.kind ~= "ready" then return false end
	s.selected = key
	s.route = {
		kind = "review-fix", key = key, cur = 1, focus = "steps", item = 1, loading = agent.review == nil,
		error = nil, bots = false, resolved = {}, replies = {}, busy = s.busy[key] ~= nil, original = false, ask = false,
	}
	s.mode, s.menu, s.confirm = "review-fix", nil, nil
	return true
end

function M.reviewPage(s: State): ReviewPage?
	local route = s.route
	if not route or route.kind ~= "review-fix" then return nil end
	local agent, pr = s.agents[route.key], M.prOf(s, route.key)
	if not agent or agent.kind ~= "ready" or not pr then return nil end
	local count = 0
	for _, hunk in agent.fix.hunks do if agent.reviewed[hunk.id] == true then count += 1 end end
	local current = if agent.review then agent.review.hunks[route.cur] else nil
	return {
		pr = pr, fix = agent.fix, review = agent.review, reviewed = agent.reviewed, count = count,
		current = current, lines = if current then ReviewFix.lines(current, route.original == true) else {},
		all = M.reviewed(agent.fix, agent.reviewed) and agent.review ~= nil and agent.review.verified,
		cur = route.cur, original = route.original == true, ask = route.ask == true,
		busy = s.busy[route.key] ~= nil, loading = route.loading, error = route.error or (if agent.review then agent.review.error else nil),
		progress = s.busy[route.key],
		completion = agent.completion,
		bot = agent.fix.hunks[1] ~= nil and string.sub(agent.fix.hunks[1].id, 1, 4) == "bot:",
	}
end

function M.reviewSelect(s: State, index: number)
	local page, route = M.reviewPage(s), s.route
	if not page or not route or page.busy or page.ask then return end
	route.cur = math.clamp(index, 1, math.max(1, #page.fix.hunks))
end

function M.reviewToggle(s: State, index: number?)
	local page = M.reviewPage(s)
	if not page or page.busy or page.ask or page.completion or not page.review or not page.review.verified then return end
	local hunk = page.fix.hunks[index or page.cur]
	if hunk then page.reviewed[hunk.id] = if page.reviewed[hunk.id] then nil else true end
end

function M.reviewOriginal(s: State)
	local page = M.reviewPage(s)
	if page and not page.busy and not page.ask and s.route then s.route.original = not s.route.original end
end

function M.reviewAsk(s: State, ask: boolean)
	local page = M.reviewPage(s)
	if page and not page.busy and s.route and page.completion ~= "push" then s.route.ask = ask end
end

function M.reviewRequest(s: State): ReviewFix.Request?
	local page, route = M.reviewPage(s), s.route
	if not page or not route or page.busy or page.loading then return nil end
	return {
		kind = "ready", key = route.key, selectedKey = s.selected, routeKey = route.key, repo = page.pr.repo, number = page.pr.number,
		headOid = page.pr.headOid, fix = page.fix, reviewed = table.clone(page.reviewed),
		verified = page.review ~= nil and page.review.verified, completion = page.completion,
	}
end

return M
