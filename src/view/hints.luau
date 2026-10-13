--!strict
-- The keys that matter right now, pinned to the bottom of the pane. It follows the mode (reading,
-- writing a comment, finishing the review) and offers a suggestion's keys only when one is in reach.
local ModelBox = require("../model-box")
local Review = require("../review")
local State = require("../state")
local Ui = require("./ui")

local el, span = Ui.el, Ui.span

local FIXED: { [State.Mode]: { title: string, keys: { { string } } } } = {
 search = { title = "Searching", keys = { { "↑ ↓", "choose" }, { "⏎", "go there" }, { "esc", "close" } } },
 composer = { title = "Writing a comment", keys = { { "⏎", "save" }, { "⇧ ⏎", "new line" }, { "esc", "cancel" } } },
 summary = { title = "Editing the summary", keys = { { "⏎", "done" }, { "⇧ ⏎", "new line" }, { "esc", "done" } } },
 review = { title = "Finishing your review", keys = { { "j k", "move" }, { "x", "include or leave out" }, { "a", "include / exclude all" }, { "1 2 3", "verdict" }, { "e", "edit summary" }, { "⌘ ⏎", "submit" }, { "esc", "close" } } },
}

local M = {}

local function readingKeys(s: State.State): (string, { { string } })
 local r = s.review
 local step = State.currentStep(s)
 local unit = if r.guide.guided then "step" else "file"
 local keys = { { "j k", "next / previous " .. unit }, { "⏎", "mark reviewed" } }
 local suggestion = Review.currentSuggestion(r)
 if suggestion and r.decisions[suggestion.id] == nil then
  table.insert(keys, { "a d", "add / dismiss " .. r.guide.author .. "'s " .. string.lower(Ui.kinds[suggestion.kind].word) })
 end
 table.insert(keys, { "c", "comment" })
 table.insert(keys, { "r", "submit review" })
 table.insert(keys, { "/", "search" })
 if State.switchable(s) then table.insert(keys, { "t", if s.view == "guided" then "file view" else "guided view" }) end
 if not r.guide.guided then return "File " .. r.cur .. " of " .. #r.steps .. "  ·  " .. step.file, keys end
 return "Step " .. r.cur .. " of " .. #r.steps .. "  ·  " .. step.title, keys
end

-- The model menu's keys; the lens's only where the menu shows it. Tab shows in the menu itself.
local function modelKeys(s: State.State): { { string } }
 local keys = { { "↑ ↓", "model" }, { "← →", "effort" } }
 local box, run = s.models, s.ai
 if box and run and ModelBox.showsLens(box, run.agent) then table.insert(keys, { "⇧ ← →", "lens" }) end
 table.insert(keys, { "⏎", "use it" })
 table.insert(keys, { "esc", "close" })
 return keys
end

function M.view(s: State.State): Node
 local mode = State.mode(s)
 local fixed = FIXED[mode]
 local title, keys
 if fixed then
  title, keys = fixed.title, fixed.keys
 elseif mode == "models" then
  title, keys = "Choosing models", modelKeys(s)
 else
  title, keys = readingKeys(s)
 end
 local kids = { span("gp-hb-mode", title), Ui.spacer() }
 for _, key in keys do
  table.insert(kids, el("span", { class = "gp-hb-item" }, { Ui.keys(key[1]), span("gp-hb-label", key[2]) }))
 end
 table.insert(kids, el("span", { class = "gp-hb-item gp-hb-more", actions = { click = "toggle-help" } }, { Ui.keys("?"), span("gp-hb-label", "all shortcuts") }))
 return el("div", { class = "gp-hintbar", key = "hints" }, kids)
end

return M
