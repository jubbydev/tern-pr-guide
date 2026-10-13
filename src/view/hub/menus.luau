--!strict
-- The hub's menus (filters, repositories, sort, a card's other actions) and Settings (the review page's model and lens
-- menu, then where links open and background guides) as Tern overlays under their buttons. A menu opened by a
-- key draws without animation: Tern's overlay pops only for the mouse.
local ModelPanel = require("../model-panel")
local Paths = require("./paths")
local State = require("../../hub/state")
local Ui = require("../ui")

local el, span = Ui.el, Ui.span

local M = {}

local TITLES: { [string]: string } = {
	filters = "Filter",
	["title-filter"] = "Filter by title",
	["check-repository"] = "Choose repository",
	["check-filter"] = "Ignore check in Needs fixes",
	repositories = "Filter by repository",
	sort = "Sort by",
	settings = "Settings",
	actions = "More actions",
	merge = "Merge method",
}

local function anchorOf(s: State.State): string
	if s.menu == "filters" or s.menu == "repositories" or s.menu == "check-repository" or s.filterEdit then return Paths.repositoriesButton end
	if s.menu == "sort" then return Paths.sortButton end
	if s.menu == "settings" then return Paths.settingsButton end
	local card = State.selectedCard(s)
	return if card then Paths.moreButton(card) else Paths.titleLabel
end

local function rowNode(s: State.State, row: State.MenuRow, index: number): Node
	local kids: { Node } = {}
	if row.kind == "check" or row.kind == "rule" then
		table.insert(kids, el("span", {
			class = "gp-hm-box" .. (if row.on then " gp-hm-box-on" else ""),
			key = "toggle", aria = if row.on then "Disable filter" else "Enable filter",
			actions = if row.kind == "rule" then { click = "hub-filter-toggle=" .. index } else nil,
		}, if row.on then { Ui.icon("check") } else nil))
	elseif row.kind == "choice" then
		table.insert(kids, el("span", { class = "gp-hm-tick" }, if row.on then { Ui.icon("check") } else nil))
	end
	if s.menu == "filters" then
		local lines = { span("gp-hm-label", row.label) }
		if row.value then table.insert(lines, span("gp-hf-value", row.value)) end
		if row.sub then table.insert(lines, span("gp-hf-scope", row.sub)) end
		table.insert(kids, el("span", { class = "gp-hf-rule" }, lines))
	else table.insert(kids, span("gp-hm-label", row.label)) end
	if s.menu ~= "filters" then table.insert(kids, Ui.spacer()) end
	if row.count then table.insert(kids, span("gp-hm-count", tostring(row.count))) end
	if row.sub and s.menu ~= "filters" then table.insert(kids, span("gp-hm-sub", row.sub)) end
	if row.kind == "navigate" or row.kind == "rule" then table.insert(kids, Ui.icon("chev-r")) end
	return el("div", {
		class = "gp-md-row gp-hm-row" .. (if index == s.menuCursor and not (s.filterEdit and s.filterEdit.typing) then " gp-md-row-on" else "") .. (if row.kind == "clear" then " gp-hm-clear" else "") .. (if s.menu == "filters" or s.menu == "check-repository" or s.menu == "check-filter" then " gp-hf-row" else ""),
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

-- Whether AI guides are prepared in the background, as a box that ticks.
local function guides(s: State.State): Node
	local on = s.prepareGuides
	return el("div", { class = "gp-hs-row", key = "guides" }, {
		el("div", { class = "gp-hs-top gp-hs-toggle", key = "top", actions = { click = "hub-guides=" .. (if on then "false" else "true") } }, {
			el("span", { class = "gp-hm-box" .. (if on then " gp-hm-box-on" else "") }, if on then { Ui.icon("check") } else nil),
			span("gp-hm-label", "Prepare AI guides in the background"),
			Ui.spacer(),
			Ui.keys("⇧G"),
		}),
	})
end

-- Settings: the model and lens menu on the hub's agent, then where links open and background guides.
local function settings(s: State.State): { Node }
	local agent, box = s.agent, s.models
	local missing = if s.noAgent then "Couldn't find OMP: " .. s.noAgent .. "." else "Couldn't find the agent: no models to choose from."
	local kids: { Node } = if agent and box then ModelPanel.parts(box, agent) else { span("gp-md-empty", missing) }
	table.insert(kids, links(s))
	table.insert(kids, guides(s))
	return kids
end

-- Filters reuse menu rows, checkboxes and the merge menu's text field. Text edits stay still.
local function filterEdit(s: State.State): Node?
	local edit = s.filterEdit
	if not edit then return nil end
	local placeholder = if s.menu == "title-filter" then "Title text" else "Exact check name"
	local kids: { Node } = { span("gp-md-label", placeholder) }
	if edit.repo then table.insert(kids, span("gp-hf-scope", edit.repo)) end
	table.insert(kids, el("div", { class = "gp-sr-box gp-hm-field" .. (if edit.typing then " gp-hub-search-on" else ""), key = "box", actions = { click = "hub-filter-focus=input" } }, { Ui.field(edit.field, "field", placeholder) }))
	return el("div", { class = "gp-hs-row gp-hf-edit", key = "edit" }, kids)
end

local function filterEditFoot(s: State.State): Node?
	if not s.filterEdit then return nil end
	return el("div", { class = "gp-hs-row gp-hf-edit", key = "edit-foot" }, {
		el("div", { class = "gp-hs-top" }, {
			el("span", { class = "gp-btn gp-btn-sm", actions = { click = "hub-filter-back" } }, { span("gp-hb-label", "Back"), Ui.keys("esc") }),
			Ui.spacer(),
			el("span", { class = "gp-btn gp-btn-sm gp-btn-primary", actions = { click = "hub-filter-save" } }, { span("gp-hb-label", "Apply"), Ui.keys("⏎") }),
		}),
	})
end

local function filterFoot(s: State.State): Node?
	if s.menu ~= "filters" or s.board.hidden == 0 then return nil end
	return el("div", { class = "gp-hs-row", key = "foot" }, { span("gp-md-label", s.board.hidden .. " pull requests hidden") })
end

function M.view(s: State.State): Node
	local kids: { Node }
	if s.menu == "settings" then
		kids = settings(s)
	else
		local rows: { Node } = {}
		for index, row in State.menuRows(s) do table.insert(rows, rowNode(s, row, index)) end
		if #rows == 0 and not s.filterEdit then table.insert(rows, span("gp-md-empty", "No options.")) end
		kids = { span("gp-hm-head", TITLES[s.menu :: string]), el("div", { class = "gp-md-list gp-hm-list", key = "list" }, rows) }
		local edit = filterEdit(s)
		if edit then table.insert(kids, 2, edit) end
		local foot = filterEditFoot(s) or filterFoot(s) or mergeFoot(s)
		if foot then table.insert(kids, foot) end
	end
	local body = el("div", { class = "gp-md gp-hm" .. (if s.keyed or s.filterEdit then "" else " gp-soft"), key = "body" }, kids)
	local role = if s.menu == "settings" then "gp.hubsettings" elseif s.menu == "filters" or s.menu == "title-filter" or s.menu == "check-filter" or s.menu == "check-repository" then "gp.hubfilter" else "gp.hubmenu"
	return { k = "overlay", p = { key = "menu", role = role, aria = TITLES[s.menu :: string], anchor = { node = anchorOf(s), side = "below" }, size = "md" }, c = { body } } :: any
end

return M
