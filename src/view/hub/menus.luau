--!strict
-- The hub's menus (repositories, sort, a card's other actions) and Settings (the review page's model and lens
-- menu, then where links open) as Tern overlays under their buttons. A menu opened by a key draws without
-- animation: Tern's overlay pops only for the mouse.
local ModelPanel = require("../model-panel")
local Paths = require("./paths")
local State = require("../../hub/state")
local Ui = require("../ui")

local el, span = Ui.el, Ui.span

local M = {}

local TITLES: { [string]: string } = {
	repositories = "Filter by repository",
	sort = "Sort by",
	settings = "Settings",
	actions = "More actions",
	merge = "Merge method",
}

local function anchorOf(s: State.State): string
	if s.menu == "repositories" then return Paths.repositoriesButton end
	if s.menu == "sort" then return Paths.sortButton end
	if s.menu == "settings" then return Paths.settingsButton end
	local card = State.selectedCard(s)
	return if card then Paths.moreButton(card) else Paths.titleLabel
end

local function rowNode(s: State.State, row: State.MenuRow, index: number): Node
	local kids: { Node } = {}
	if row.kind == "check" then
		table.insert(kids, el("span", { class = "gp-hm-box" .. (if row.on then " gp-hm-box-on" else "") }, if row.on then { Ui.icon("check") } else nil))
	elseif row.kind == "choice" then
		table.insert(kids, el("span", { class = "gp-hm-tick" }, if row.on then { Ui.icon("check") } else nil))
	end
	table.insert(kids, span("gp-hm-label", row.label))
	table.insert(kids, Ui.spacer())
	if row.count then table.insert(kids, span("gp-hm-count", tostring(row.count))) end
	if row.sub then table.insert(kids, span("gp-hm-sub", row.sub)) end
	return el("div", {
		class = "gp-md-row gp-hm-row" .. (if index == s.menuCursor then " gp-md-row-on" else "") .. (if row.kind == "clear" then " gp-hm-clear" else ""),
		key = "r" .. index, actions = { click = "hub-menu-pick=" .. index },
	}, kids)
end

-- The merge menu's foot: where the setting came from, or the field a comment or label method asks for.
local function mergeFoot(s: State.State): Node?
	if s.menu ~= "merge" then return nil end
	local edit = s.methodEdit
	if edit then
		local what = if edit.kind == "comment" then "Command" else "Label"
		local placeholder = if edit.kind == "comment" then "/merge | /cancel" else "ready-to-merge"
		return el("div", { class = "gp-md-foot gp-hm-edit", key = "edit" }, {
			span("gp-md-label", what),
			el("div", { class = "gp-sr-box gp-hm-field", key = "box" }, { Ui.field(edit.field, "field", placeholder) }),
			Ui.keys("⏎"),
		})
	end
	local source = State.mergeSource(s)
	if source == nil then return nil end
	return el("div", { class = "gp-md-foot", key = "source" }, { span("gp-md-label", source) })
end

-- Where GitHub links open, as a two-sided toggle.
local function links(s: State.State): Node
	local function side(to: string, label: string): Node
		return el("span", { class = "gp-md-seg" .. (if s.links == to then " gp-md-seg-on" else ""), key = to, text = label, actions = { click = "hub-links=" .. to } })
	end
	return el("div", { class = "gp-hs-row gp-hs-links", key = "links" }, {
		el("div", { class = "gp-hs-top", key = "top" }, { span("gp-md-label", "Open links in"), Ui.spacer(), Ui.keys("L") }),
		el("div", { class = "gp-md-segs gp-hs-segs", key = "segs" }, { side("tern", "Tern"), side("browser", "Default browser") }),
	})
end

-- Settings: the model and lens menu on the hub's agent, then where links open.
local function settings(s: State.State): { Node }
	local agent, box = s.agent, s.models
	local kids: { Node } = if agent and box then ModelPanel.parts(box, agent) else { span("gp-md-empty", "Couldn't find the agent: no models to choose from.") }
	table.insert(kids, links(s))
	return kids
end

function M.view(s: State.State): Node
	local kids: { Node }
	if s.menu == "settings" then
		kids = settings(s)
	else
		local rows: { Node } = {}
		for index, row in State.menuRows(s) do table.insert(rows, rowNode(s, row, index)) end
		if #rows == 0 then table.insert(rows, span("gp-md-empty", "No options.")) end
		kids = { span("gp-hm-head", TITLES[s.menu :: string]), el("div", { class = "gp-md-list gp-hm-list", key = "list" }, rows) }
		local foot = mergeFoot(s)
		if foot then table.insert(kids, foot) end
	end
	local body = el("div", { class = "gp-md gp-hm" .. (if s.keyed then "" else " gp-soft"), key = "body" }, kids)
	local role = if s.menu == "settings" then "gp.hubsettings" else "gp.hubmenu"
	return { k = "overlay", p = { key = "menu", role = role, aria = TITLES[s.menu :: string], anchor = { node = anchorOf(s), side = "below" }, size = "md" }, c = { body } } :: any
end

return M
