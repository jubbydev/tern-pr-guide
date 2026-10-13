--!strict
-- The keys that apply right now, pinned to the bottom: move, open, the selected card's action, and ? for the rest.
local Model = require("../../hub/model")
local ModelBox = require("../../model-box")
local State = require("../../hub/state")
local Ui = require("../ui")

local el, span = Ui.el, Ui.span

local FIXED: { [string]: { title: string, keys: { { string } } } } = {
	search = { title = "Searching", keys = { { "↑ ↓", "Move" }, { "⏎", "Done" }, { "esc", "Clear" } } },
	menu = { title = "Choosing", keys = { { "j k", "Move" }, { "⏎", "Choose" }, { "esc", "Close" } } },
	link = { title = "Adding", keys = { { "⏎", "Add" }, { "⇧⏎", "Open" }, { "esc", "Clear" } } },
	confirm = { title = "Confirm", keys = { { "⌘⏎", "Confirm" }, { "esc", "Cancel" } } },
	help = { title = "All shortcuts", keys = { { "esc", "Close" } } },
}

local M = {}

function M.view(s: State.State): Node
	local fixed = FIXED[s.mode]
	local title, keys = "Pick a pull request", { { "h j k l", "Move" }, { "⏎", "Open" } }
	if s.mode == "menu" and s.menu == "settings" and s.models and s.agent then
		-- The model menu's keys, as on the review page; letters type into its search.
		title, keys = "Settings", { { "↑ ↓", "Model" }, { "← →", "Effort" } }
		if ModelBox.showsLens(s.models, s.agent) then table.insert(keys, { "⇧← →", "Lens" }) end
		table.insert(keys, { "⏎", "Use it" })
		table.insert(keys, { "esc", "Close" })
	elseif fixed then
		title, keys = fixed.title, fixed.keys
	else
		local card = State.selectedCard(s)
		local main = card and card.main
		local selection = State.selection(s)
		if selection then
			title, keys = "Selecting", { { "h j k l", "Move" }, { "Space", "Select" }, { selection.key, selection.verb .. " " .. selection.count }, { "esc", "Clear" } }
		else
			if main and main.key and main.key ~= "⏎" then table.insert(keys, { main.key, main.label }) end
			if card and Model.selectGroup(card.pr, s.now) then table.insert(keys, { "Space", "Select" }) end
		end
	end
	local kids: { Node } = { span("gp-hb-mode", title), Ui.spacer() }
	for _, key in keys do
		table.insert(kids, el("span", { class = "gp-hb-item" }, { Ui.keys(key[1]), span("gp-hb-label", key[2]) }))
	end
	if s.mode == "board" then
		table.insert(kids, el("span", { class = "gp-hb-item gp-hb-more", key = "more", actions = { click = "hub-help" } }, { Ui.keys("?"), span("gp-hb-label", "All shortcuts") }))
	end
	return el("div", { class = "gp-hintbar", key = "hints" }, kids)
end

return M
