--!strict
-- Hosts review pages in the hub's own pane: the PR hub is the container for a PR's views. Opening a card or a recent
-- row builds a review page (src/review-page.luau) under the "main" root and shows it in place of the board; Esc at the
-- page's rest returns to the board with the card still selected. The hub keeps the last `PageViews.LIMIT` pages alive
-- in `Block.pages` (a page with unsent work is never dropped), so reopening a PR returns to its state at once. A card
-- in Needs fixes also has the fixes page as its first view, which `t` and the tab strips cycle to. Also finds the
-- checkout a PR opens in (`plan`), shared with opening the PR in a pane of its own.
local Details = require("./details")
local Fetch = require("../fetch")
local Keys = require("../keys")
local Links = require("../links")
local PageViews = require("./page-views")
local Platform = require("../platform")
local ReviewPage = require("../review-page")
local Runtime = require("./runtime")
local State = require("./state")
local Ui = require("../view/ui")

type Block = Runtime.Block
type Page = Runtime.Page
type ViewId = PageViews.ViewId

local draw, revealSelected = Runtime.draw, Runtime.revealSelected

local ROOT = "main"

local M = {}

-- Finds a checkout of `slug` (beside the hub's folder, else PR Guide's own copy) and calls `done` with the link the
-- window's route turns into a review of PR `number`, or with nil after a toast saying why it can't (`State.openPlan`).
function M.plan(b: Block, cx: BlockCx, slug: string, number: number, generate: boolean, done: (string?) -> ())
	local dir = cx.cwd or Platform.home() or ""
	Fetch.checkoutFor(nil, dir, slug, function(found)
		if b.closed then return end
		local _, why = Fetch.savedCopy("github.com", slug)
		local plan = State.openPlan(slug, number, generate, if found then found.root else nil, why, dir)
		if plan.kind == "open" then
			done(plan.url)
		else
			cx:toast("error", plan.text, plan.sub)
			done(nil)
		end
	end)
end

local function keyOf(slug: string, number: number): string
	return string.lower(slug) .. "#" .. number
end

local function find(b: Block, key: string): Page?
	for _, entry in b.pages.list do
		if entry.key == key then return entry end
	end
	return nil
end

-- The page on show, if any.
function M.shown(b: Block): Page?
	local key = b.pages.shown
	return if key then find(b, key) else nil
end

-- Whether a card has a Fixes view: it is in Needs fixes with no agent fix to review, or the fixes page is open on it.
local function hasFixes(b: Block, cardKey: string?): boolean
	if not cardKey then return false end
	local s = b.s
	local card = State.card(s, cardKey)
	if card and card.column == "needs_fixes" and not (card.agent and card.agent.kind == "ready") then return true end
	local route = s.route
	return route ~= nil and route.kind == "fixes" and route.key == cardKey
end

type Target = { slug: string, number: number, cardKey: string?, page: Page? }

-- The PR the reader is on: the page on show, else the fixes page's.
local function target(b: Block): Target?
	local entry = M.shown(b)
	if entry then return { slug = entry.slug, number = entry.number, cardKey = entry.cardKey, page = entry } end
	local route = b.s.route
	if not route or route.kind ~= "fixes" then return nil end
	local pr = State.prOf(b.s, route.key)
	if not pr then return nil end
	return { slug = pr.repo, number = pr.number, cardKey = pr.key, page = find(b, keyOf(pr.repo, pr.number)) }
end

local function viewsOf(b: Block, t: Target): { ViewId }
	return PageViews.views(hasFixes(b, t.cardKey), if t.page then ReviewPage.views(t.page.page) :: { ViewId }? else nil)
end

local function currentOf(b: Block, t: Target): ViewId
	if b.pages.shown then return (if t.page then ReviewPage.current(t.page.page) else nil) or "review" end
	return "fixes"
end

-- The tab strip the fixes page shows: Fixes, then Guided and Files once the PR's page has loaded, else Review.
function M.fixesTabs(b: Block): { Ui.ViewTab }
	local t = target(b)
	if not t then return {} end
	return PageViews.tabs(viewsOf(b, t)) :: { Ui.ViewTab }
end

-- Drops the pages beyond the limit, oldest first, keeping any that hold work no file has.
local function evict(b: Block)
	local entries = {}
	for _, entry in b.pages.list do table.insert(entries, { key = entry.key, dirty = ReviewPage.unsaved(entry.page) }) end
	for _, key in PageViews.victims(entries) do
		local at = table.find(b.pages.list, find(b, key) :: Page)
		if at then table.remove(b.pages.list, at) end
	end
end

-- Shows `entry`, most recent, in `view` when it is Guided or Files (a page that hasn't loaded opens in its own).
local function show(b: Block, cx: BlockCx, entry: Page, view: ViewId?)
	local list = b.pages.list
	local at = table.find(list, entry)
	if at then table.remove(list, at) end
	table.insert(list, entry)
	b.pages.shown = entry.key
	entry.hosted.fixes = hasFixes(b, entry.cardKey)
	if view == "guided" or view == "files" then ReviewPage.setView(entry.page, cx, view) end
end

export type Spec = { slug: string, number: number, cardKey: string?, generate: boolean, view: ViewId? }

-- Opens the PR's page in the hub, or shows the one already open. A sample board has no network: it opens the bundled
-- sample. A page found after its checkout is read appears only if the reader is still on the board or the fixes page.
function M.open(b: Block, cx: BlockCx, spec: Spec)
	local key = keyOf(spec.slug, spec.number)
	local entry = find(b, key)
	if entry then
		entry.cardKey = spec.cardKey or entry.cardKey
		show(b, cx, entry, spec.view)
		if spec.view == nil then ReviewPage.resume(entry.page, cx) end
		if spec.generate then ReviewPage.startGuide(entry.page, cx) end
		return
	end
	if b.pages.opening[key] then return end
	local function create(args: { string })
		local hosted: ReviewPage.Hosted = { fixes = hasFixes(b, spec.cardKey) }
		local page = ReviewPage.init(cx, args, ROOT, hosted)
		local made: Page = { key = key, slug = spec.slug, number = spec.number, cardKey = spec.cardKey, page = page, hosted = hosted }
		local waiting = b.pages.shown == nil and (b.s.mode == "board" or b.s.mode == "fixes")
		if waiting then show(b, cx, made, spec.view) else table.insert(b.pages.list, made) end
		evict(b)
		draw(b, cx)
	end
	if b.fixture then return create({}) end
	b.pages.opening[key] = true
	M.plan(b, cx, spec.slug, spec.number, spec.generate, function(url)
		b.pages.opening[key] = nil
		if b.closed or not url then return end
		local route = Links.openRoute(url)
		if route then return create(Links.routeArgs(route)) end
		cx:toast("error", "Couldn't open #" .. spec.number .. " of " .. spec.slug, "The link has no checkout to read it from.")
	end)
end

-- Shows view `to` of the PR the reader is on.
function M.go(b: Block, cx: BlockCx, to: string)
	local t = target(b)
	if not t then return end
	if to == "fixes" then
		local route = b.s.route
		if t.cardKey and not (route and route.kind == "fixes" and route.key == t.cardKey) then Details.openFixes(b, cx, t.cardKey) end
		b.pages.shown = nil
		return
	end
	M.open(b, cx, { slug = t.slug, number = t.number, cardKey = t.cardKey, generate = false, view = to :: ViewId })
end

-- `t`: the next view of the PR the reader is on, wrapping from the last to the first.
function M.cycle(b: Block, cx: BlockCx)
	local t = target(b)
	if not t then return end
	local to = PageViews.next(viewsOf(b, t), currentOf(b, t))
	if to then M.go(b, cx, to) end
end

-- Esc at the page's rest: back to the board with the card still selected. The fixes page, if open under the page,
-- closes too, so the next open starts where an open does.
function M.back(b: Block, cx: BlockCx)
	if not b.pages.shown then return end
	b.pages.shown = nil
	local route = b.s.route
	if route and route.kind == "fixes" then State.closeFixes(b.s) end
	revealSelected(b, cx)
end

-- The page's own nodes, drawn in place of the board.
function M.view(b: Block): BlockView
	local entry = M.shown(b) :: Page
	entry.hosted.fixes = hasFixes(b, entry.cardKey)
	return ReviewPage.view(entry.page)
end

function M.title(b: Block): string?
	local entry = M.shown(b)
	return if entry then ReviewPage.title(entry.page) else nil
end

-- The hub's key for the page on show, before the page's own: Esc at rest and `t` with Fixes beside it.
function M.action(b: Block, key: Key): Keys.Action?
	local entry = M.shown(b)
	if not entry then return nil end
	return Keys.hubPageAction(key, { rest = ReviewPage.atRest(entry.page), reading = ReviewPage.reading(entry.page), fixes = entry.hosted.fixes })
end

function M.key(b: Block, key: Key, cx: BlockCx): boolean?
	local entry = M.shown(b)
	return if entry then ReviewPage.key(entry.page, key, cx) else nil
end

-- A click on the Fixes tab leaves the page for the fixes page, and one on Pull requests goes back to the board:
-- the events the page doesn't take.
function M.tabAction(b: Block, ev: UiEvent): Keys.Action?
	local entry = M.shown(b)
	if entry and ev.ev == "action" and ev.act == "pages-back" then return { act = "pages-back" } end
	if not entry or ev.ev ~= "select" or ev.item ~= "fixes" or ev.id ~= ReviewPage.tabsPath(entry.page) then return nil end
	return { act = "pages-view", value = "fixes" }
end

function M.event(b: Block, ev: UiEvent, cx: BlockCx)
	local entry = M.shown(b)
	if entry then ReviewPage.event(entry.page, ev, cx) end
end

return M
