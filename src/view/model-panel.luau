--!strict
-- The model and lens menu: an Explanation | Review switch with a hint for the slot shown, a filter,
-- the slot's models matching it grouped by provider (Off first on Review), the efforts the highlighted
-- model takes as one segmented control, and on Review the lens. The review page shows it as Tern's
-- overlay under the model button; the PR hub's Settings puts it in its own overlay.
local Agent = require("../agent")
local ModelBox = require("../model-box")
local Ui = require("./ui")

local el, span = Ui.el, Ui.span

local SLOTS: { { id: Agent.Pass, label: string, hint: string } } = {
 { id = "explain", label = "Explanation", hint = "Explains what the PR changes, step by step. A fast model at low effort is enough." },
 { id = "review", label = "Review", hint = "Drafts comments on problems and questions. Use a strong model; higher effort finds more." },
}
local OFF_HINT = "Explanation only; no drafted comments."

local M = {}

local function provider(model: Agent.Model): string
 return string.match(model.selector, "^([^/]+)/") or ""
end

-- The slot switch, its key, and what the slot shown is for.
local function slots(box: ModelBox.ModelBox): Node
 local segments, hint = {}, ""
 for _, slot in SLOTS do
  if slot.id == box.slot then hint = slot.hint end
  table.insert(segments, el("span", {
   class = "gp-md-seg" .. (if slot.id == box.slot then " gp-md-seg-on" else ""),
   key = slot.id,
   text = slot.label,
   actions = { click = "models-slot=" .. slot.id },
  }))
 end
 return el("div", { class = "gp-md-slots", key = "slots" }, {
  el("div", { class = "gp-md-slots-row", key = "switch" }, {
   el("div", { class = "gp-md-segs", key = "segs" }, segments),
   Ui.spacer(),
   Ui.keys("tab"),
  }),
  span("gp-md-hint", hint),
 })
end

-- The effort control for `model`; nil when nothing matches the filter, which the list already says,
-- or on Off, which has none.
local function efforts(box: ModelBox.ModelBox, model: Agent.Model?): Node?
 if not model or model == ModelBox.OFF then return nil end
 if #model.efforts == 0 then
  return el("div", { class = "gp-md-foot", key = "efforts" }, { span("gp-md-none", "This model has no effort setting") })
 end
 local current = Agent.effortFor(model, box.effort)
 local segments = {}
 for _, effort in model.efforts do
  table.insert(segments, el("span", {
   class = "gp-md-seg" .. (if effort == current then " gp-md-seg-on" else ""),
   text = effort,
   actions = { click = "model-effort=" .. effort },
  }))
 end
 return el("div", { class = "gp-md-foot", key = "efforts" }, {
  span("gp-md-label", "Effort"),
  el("div", { class = "gp-md-segs" }, segments),
  Ui.spacer(),
  Ui.keys("← →"),
 })
end

-- The review lens control: every lens as a segment, the chosen one's description under them, and
-- the way to the folder of the reader's own lenses.
local function lenses(agent: Agent.Agent): Node
 local current = Agent.currentLens(agent)
 local segments = {}
 for n, lens in agent.lenses do
  table.insert(segments, el("span", {
   class = "gp-md-seg" .. (if lens.name == current.name then " gp-md-seg-on" else ""),
   key = "l" .. n,
   text = lens.name,
   actions = { click = "model-lens=" .. n },
  }))
 end
 return el("div", { class = "gp-md-foot gp-md-lens", key = "lenses" }, {
  el("div", { class = "gp-md-lens-row", key = "pick" }, {
   span("gp-md-label", "Lens"),
   el("div", { class = "gp-md-segs gp-md-segs-wrap", key = "segs" }, segments),
   Ui.keys("⇧← →"),
  }),
  el("div", { class = "gp-md-lens-row", key = "about" }, {
   span("gp-md-lens-desc", current.description),
   el("span", { class = "gp-md-edit", key = "edit", actions = { click = "edit-lenses" } }, {
    span("gp-md-edit-label", "Edit lenses…"),
    Ui.keys("⌃E"),
   }),
  }),
 })
end

-- The menu's parts, top to bottom, keyed "slots", "box" (its field "field"), the list, "efforts"
-- and "lenses". The list starts at row `box.top`, under a row offering the ones above it. Its key
-- changes with `top` and the slot, so the list draws as a fresh scroller at its own start and the
-- wheel scrolls it freely.
function M.parts(box: ModelBox.ModelBox, agent: Agent.Agent): { Node }
 local choices = ModelBox.choices(box, agent)
 local rows, group = {}, nil
 -- Off stays pinned first however far the list starts, so it is never hidden under "more".
 local first = if choices[1] == ModelBox.OFF then 2 else 1
 local from = math.max(box.top, first)
 local function row(n: number)
  local model = choices[n]
  local name = if model == ModelBox.OFF then "" else provider(model)
  if name ~= group and model ~= ModelBox.OFF then
   group = name
   table.insert(rows, el("div", { class = "gp-md-group", key = "g-" .. name, text = name }))
  end
  local kids = { span("gp-md-name", model.name), Ui.spacer() }
  if model == ModelBox.OFF then table.insert(kids, span("gp-md-row-hint", OFF_HINT)) end
  table.insert(kids, el("span", { class = "gp-md-check" }, if ModelBox.inUse(agent, box.slot, model) then { Ui.icon("check") } else nil))
  table.insert(rows, el("div", { class = "gp-md-row" .. (if n == box.selected then " gp-md-row-on" else ""), key = "m" .. n, actions = { click = "model-row=" .. n } }, kids))
 end
 if first == 2 then row(1) end
 if from > first then
  table.insert(rows, el("div", { class = "gp-md-more", key = "above", text = "↑  " .. (from - first) .. " more", actions = { click = "models-top" } }))
 end
 for n = from, #choices do row(n) end
 if #agent.models == 0 then
  table.insert(rows, span("gp-md-empty", "Listing models…"))
 elseif #choices == 0 then
  table.insert(rows, span("gp-md-empty", "Nothing matches “" .. box.field.text .. "”"))
 end
 local kids = {
  slots(box),
  el("div", { class = "gp-md-search", key = "box" }, { Ui.icon("search"), Ui.field(box.field, "field", "Search models") }),
  el("div", { class = "gp-md-list", key = box.slot .. "list" .. box.top }, rows),
 }
 local foot = efforts(box, choices[box.selected])
 if foot then table.insert(kids, foot) end
 if ModelBox.showsLens(box, agent) then table.insert(kids, lenses(agent)) end
 return kids
end

-- The review page's menu. `anchor` is the full node id of the button the card opens under. The rows
-- fade between states only under `soft`, as on the page: a key never animates.
function M.view(box: ModelBox.ModelBox, agent: Agent.Agent, anchor: string, soft: boolean): Node
 local body = el("div", { class = "gp-md" .. (if soft then " gp-soft" else ""), key = "body" }, M.parts(box, agent))
 return { k = "overlay", p = { key = "models", role = "gp.models", aria = "Models, effort and lens", anchor = { node = anchor, side = "below" }, size = "md" }, c = { body } } :: any
end

return M
