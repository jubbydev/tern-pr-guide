--!strict
-- What each key does in each mode, as the same actions the page's clicks send.
local Fields = require("./text-field")
local HubState = require("./hub/state")
local ModelBox = require("./model-box")
local Review = require("./review")
local State = require("./state")

export type Action = { act: string, value: string? }

local SCROLLS: { [string]: string } = { pageup = "page-up", pagedown = "page-down", home = "start", ["end"] = "end" }

local M = {}

local function act(name: string, value: (string | number)?): Action
 return { act = name, value = if value == nil then nil else tostring(value) }
end

local function isQuestionMark(key: Key): boolean
 return key.name == "?" or key.text == "?"
end

local function searchKey(key: Key): Action?
 local name = key.name
 if name == "down" then return act("search-move", 1) end
 if name == "up" then return act("search-move", -1) end
 if name == "enter" then return act("search-pick") end
 if name == "escape" then return act("search-close") end
 return nil
end

-- The model and lens menu, on the review page and in the hub's Settings. Arrows: up and down pick
-- the model, left and right its effort (the filter's cursor gives them up; model names are short).
-- Tab flips between the Explanation and Review slots. Shift with left and right steps the review
-- lens, and ctrl-E opens the folder of the reader's own lenses. Esc is each surface's own close.
local function modelsKey(box: ModelBox.ModelBox, key: Key): Action?
 local name = key.name
 local plain = not (key.shift or key.ctrl or key.meta or key.alt)
 if name == "down" then return act("models-move", 1) end
 if name == "up" then return act("models-move", -1) end
 local shifted = key.shift and not (key.ctrl or key.meta or key.alt)
 if shifted and name == "right" then return act("models-lens", 1) end
 if shifted and name == "left" then return act("models-lens", -1) end
 if key.ctrl and name == "e" then return act("edit-lenses") end
 if plain and name == "right" then return act("models-effort", 1) end
 if plain and name == "left" then return act("models-effort", -1) end
 if name == "tab" then return act("models-slot", if box.slot == "explain" then "review" else "explain") end
 if name == "enter" then return act("models-pick") end
 return nil
end

local function reviewKey(s: State.State, key: Key): Action?
 local name = key.name
 local typed = key.text or name
 if name == "j" or name == "down" then return act("review-move", 1) end
 if name == "k" or name == "up" then return act("review-move", -1) end
 if name == "x" or name == "space" then return act("toggle-item", s.reviewCursor) end
 if name == "a" then return act("toggle-all") end
 local verdict = Review.verdicts[tonumber(typed) or 0]
 if verdict then return act("verdict", verdict.id) end
 if name == "e" then return act("edit-summary") end
 if name == "enter" and (key.meta or key.ctrl) then return act("submit-review") end
 if name == "escape" or name == "r" then return act("toggle-review") end
 return nil
end

local function readingKey(s: State.State, key: Key): Action?
 local name = key.name
 local step = State.currentStep(s)
 if name == "j" then return act("step", 1) end
 if name == "k" then return act("step", -1) end
 if name == "n" then return act("next-suggestion", 1) end
 if name == "p" then return act("next-suggestion", -1) end
 if name == "enter" and key.shift then return act("mark-change", step.change) end
 if name == "enter" then return act("review-step", step.key) end
 if name == "v" then return act("mark-file", step.file) end
 if name == "a" then return act("decide-current", "added") end
 if name == "d" then return act("decide-current", "dismissed") end
 if name == "c" then return act("comment-step") end
 if name == "r" then return act("open-review") end
 if name == "/" or key.text == "/" then return act("open-search") end
 if (name == "g" and key.shift) or name == "G" then return act("generate-guide") end
 if name == "g" then return act("open-github") end
 if name == "i" then return act("toggle-description") end
 if (name == "m" and key.shift) or name == "M" then return act("toggle-models") end
 if name == "m" then return act("mark-all") end
 if (name == "s" and key.shift) or name == "S" then return act("mark-supporting") end
 if name == "s" then return act("toggle-group") end
 if name == "o" then return act("open-all-supporting") end
 if name == "t" and State.switchable(s) then return act("toggle-view") end
 if name == "b" and not s.review.guide.guided then return act("toggle-tree") end
 if name == "h" or isQuestionMark(key) then return act("toggle-help") end
 if name == "escape" and (s.helpOpen or s.review.focus ~= nil) then return act("dismiss") end
 local scroll = SCROLLS[key.name]
 if scroll then return act("scroll", scroll) end
 return nil
end

-- The action `key` triggers, or nil when it changes nothing or, in a text mode, types into the field.
function M.action(s: State.State, key: Key): Action?
 local mode = State.mode(s)
 if mode == "search" then return searchKey(key) end
 if mode == "models" then
  return if key.name == "escape" then act("toggle-models") else modelsKey(s.models :: ModelBox.ModelBox, key)
 end
 if mode == "composer" or mode == "summary" then return nil end
 if mode == "review" and not isQuestionMark(key) then return reviewKey(s, key) end
 return readingKey(s, key)
end

-- The shortcut label a key press has on a card's split button: "A", "⇧A", ",", "⏎".
local function cardKeyLabel(key: Key): string?
	if key.ctrl or key.meta or key.alt then return nil end
	local name = key.name
	if name == "enter" then return "⏎" end
	if #name ~= 1 then return nil end
	local upper = string.upper(name)
	return if key.shift or name ~= string.lower(name) then "⇧" .. upper else upper
end

local function hubMenuKey(s: HubState.State, key: Key): Action?
	local name = key.name
	-- The merge menu is asking for a command or a label: ⏎ saves, Esc goes back to the list, the rest is typed.
	if s.methodEdit then
		if name == "enter" then return act("hub-method-save") end
		if name == "escape" then return act("hub-method-cancel") end
		return nil
	end
	if name == "escape" then return act("hub-menu-close") end
	-- Settings is the model and lens menu, its search field taking the letters; L switches where links
	-- open while the field is empty.
	if s.menu == "settings" then
		local box = s.models
		if name == "l" and (not box or box.field.text == "") and not (key.ctrl or key.meta or key.alt) then return act("hub-links") end
		return if box then modelsKey(box, key) else nil
	end
	if name == "down" or name == "j" then return act("hub-menu-move", 1) end
	if name == "up" or name == "k" then return act("hub-menu-move", -1) end
	if name == "enter" then return act("hub-menu-enter") end
	if name == "space" then return act("hub-menu-select") end
	return nil
end

-- The fixes page: j and k move over the steps (or the panel's actions), h and l between the two, ⏎ goes in or
-- chooses, Esc goes back to the board. A step's own keys follow the buttons it shows.
local function fixesKey(s: HubState.State, key: Key): Action?
	local name = key.name
	if key.ctrl or key.meta or key.alt then return nil end
	if name == "escape" then return act("fixes-close") end
	if string.match(name, "^%a$") and (s.search.text ~= "" or s.link.text ~= "") then return nil end
	local label = cardKeyLabel(key)
	if label == "⇧L" then return act("fixes-log") end
	if label == "⇧R" then return act("fixes-rerun") end
	if name == "down" or name == "j" then return act("fixes-move", 1) end
	if name == "up" or name == "k" then return act("fixes-move", -1) end
	if name == "left" or name == "h" then return act("fixes-focus", "steps") end
	if name == "right" or name == "l" then return act("fixes-focus", "panel") end
	if name == "enter" then return act("fixes-press") end
	if label == "R" then return act("fixes-reply") end
	if label == "E" then return act("fixes-resolve") end
	if label == "G" then return act("fixes-github") end
	if label == "B" then return act("fixes-bots") end
	local main = HubState.fixMain(s)
	if main and label ~= nil and s.route and (main.key == label or (label == "⇧A" and main.act == "card-summarize")) then return act(main.act, s.route.key) end
	-- When Re-run moved first, the agent is the card's alternative and keeps its key.
	local card = if s.route then HubState.card(s, s.route.key) else nil
	if card and (label == "A" or label == "⇧A" or label == "O") and s.route then
		for _, more in card.more do
			if more.key == label then return act(more.act, s.route.key) end
		end
	end
	return nil
end

local function hubBoardKey(s: HubState.State, key: Key): Action?
	local name = key.name
	if isQuestionMark(key) then return act("hub-help") end
	if name == "/" or key.text == "/" then return act("hub-search") end
	if (key.meta or key.ctrl) and name == "r" then return act("hub-refresh") end
	if key.ctrl or key.meta or key.alt then return nil end
	if name == "escape" then return act("hub-escape") end
	if name == "enter" then return act(if key.shift then "hub-open-generate" else "hub-open") end
	-- Letter shortcuts act only when both fields are empty, even after search lost focus.
	if string.match(name, "^%a$") and (s.search.text ~= "" or s.link.text ~= "") then return nil end
	local label = cardKeyLabel(key)
	if name == "space" then return act("hub-mark") end
	if label == "⇧X" and s.tab == "mine" then return act("hub-mark-stale") end
	-- With a selection, M merges it and X closes it.
	if next(s.marked) ~= nil then
		if label == "M" then return act("hub-batch-merge") end
		if label == "X" then return act("hub-batch-close") end
	end
	if name == "left" or name == "h" then return act("hub-move", "left") end
	if name == "right" or name == "l" then return act("hub-move", "right") end
	if name == "down" or name == "j" then return act("hub-move", "down") end
	if name == "up" or name == "k" then return act("hub-move", "up") end
	if name == "." or key.text == "." then return act("hub-next") end
	if label == "T" then return act("hub-tab") end
	if label == "I" then return act("hub-fold", "inactive") end
	if label == "R" then return act("hub-fold", HubState.ROW_FOLD[s.tab]) end
	if label == "⇧T" and s.tab == "review" then return act("hub-fold", "team") end
	if label == "A" and s.tab == "review" then return act("hub-fold", "approved") end
	if label == "F" then return act("hub-menu", "repositories") end
	if label == "S" then return act("hub-menu", "sort") end
	if label == "⇧S" or label == "⇧M" then return act("hub-menu", "settings") end
	if label == "N" then return act("hub-link") end
	local card = HubState.selectedCard(s)
	if card and label then
		local main = card.main
		if main and (main.key == label or (label == "⇧A" and main.act == "card-summarize")) then return act(main.act, card.pr.key) end
		for _, more in card.more do
			if more.key == label then return act(more.act, card.pr.key) end
		end
	end
	return nil
end

-- The action `key` triggers on the PR hub, or nil when it changes nothing or, in the search field, types
-- into it. Letters act only on the board and in menus: while the filter is typed they are text.
function M.hubAction(s: HubState.State, key: Key): Action?
	local mode = HubState.mode(s)
	if mode == "review-fix" then
		local page = HubState.reviewPage(s)
		if not page then return if key.name == "escape" then act("review-fix-close") else nil end
		if page.busy then return nil end
		if page.ask then
			if key.name == "enter" and (key.meta or key.ctrl) and not key.alt then return act("review-fix-discard-confirm") end
			if key.name == "escape" then return act("review-fix-discard-cancel") end
			return nil
		end
		if key.ctrl or key.meta or key.alt then return nil end
		if key.name == "escape" then return act("review-fix-close") end
		if key.name == "enter" then return act("review-fix-reviewed") end
		if string.match(key.name, "^%a$") and (s.search.text ~= "" or s.link.text ~= "") then return nil end
		if key.name == "down" or key.name == "j" then return act("review-fix-move", 1) end
		if key.name == "up" or key.name == "k" then return act("review-fix-move", -1) end
		local label = cardKeyLabel(key)
		if label == "B" then return act("review-fix-original") end
		if label == "D" then return act("review-fix-discard") end
		if label == "P" then return act("review-fix-push") end
		return nil
	end
	if mode == "search" then
		if key.name == "enter" then return act("hub-search-done") end
		if key.name == "escape" then return act("hub-search-clear") end
		if key.name == "down" then return act("hub-move", "down") end
		if key.name == "up" then return act("hub-move", "up") end
		return nil
	end
	if mode == "menu" then return hubMenuKey(s, key) end
	if mode == "fixes" then return fixesKey(s, key) end
	if mode == "reply" then
		if key.name == "enter" and (key.meta or key.ctrl) then return act("fixes-post") end
		if key.name == "escape" then return act("fixes-cancel") end
		return nil
	end
	if mode == "link" then
		if key.name == "enter" then return act(if key.shift then "hub-link-open" else "hub-link-add") end
		if key.name == "escape" then return act("hub-link-clear") end
		return nil
	end
	if mode == "confirm" then
		if key.name == "enter" and (key.meta or key.ctrl) then return act("hub-confirm") end
		if key.name == "escape" then return act("hub-confirm-cancel") end
		return nil
	end
	if mode == "help" then
		if key.name == "escape" or isQuestionMark(key) then return act("hub-help-close") end
		return nil
	end
	if mode == "board" then return hubBoardKey(s, key) end
	return nil
end

-- The action that follows a key typed into the hub's search field.
function M.hubAfterTyping(mode: HubState.Mode, outcome: Fields.Outcome): Action?
	if mode == "search" and outcome == "changed" then return act("hub-searched") end
	return nil
end

-- The action that follows a key typed into a text mode's field.
function M.afterTyping(mode: State.Mode, outcome: Fields.Outcome): Action?
 if mode == "search" then
  return if outcome == "changed" then act("search-run") else nil
 elseif mode == "models" then
  return if outcome == "changed" then act("models-filter") else nil
 elseif mode == "composer" then
  if outcome == "submit" then return act("comment-save") end
  if outcome == "cancel" then return act("comment-cancel") end
 elseif mode == "summary" then
  if outcome == "submit" or outcome == "cancel" then return act("done-summary") end
 end
 return nil
end

return M
