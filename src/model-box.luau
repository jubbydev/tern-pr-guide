--!strict
-- The model and lens menu's state and what its actions do to the agent's picks, shared by the review
-- page's model menu and the PR hub's Settings. Effects (saving, closing, focusing) stay with each block.
local Agent = require("./agent")
local Fields = require("./text-field")
local Lens = require("./lens")

-- The menu: the pass it picks for, its filter and the text the list was last filtered by, the
-- highlighted row (an index into `choices`), the effort the next pick gets, and the first row its
-- list shows.
export type ModelBox = { slot: Agent.Pass, field: Fields.Field, query: string, selected: number, effort: string?, top: number }

local M = {}

-- The Review slot's first row, which turns the review off.
M.OFF = { selector = "", name = "Off", efforts = {} } :: Agent.Model

-- Rows the model list fits before it scrolls.
local MODEL_ROWS = 8

-- Whether `model` is the one `slot` uses; Off is when the review is off.
function M.inUse(agent: Agent.Agent, slot: Agent.Pass, model: Agent.Model): boolean
 if slot == "review" and not agent.review then return model == M.OFF end
 return model ~= M.OFF and model.selector == Agent.choiceFor(agent, slot).model
end

-- The rows matching the filter: the models, under Off on the Review slot.
function M.choices(box: ModelBox, agent: Agent.Agent): { Agent.Model }
 local models = Agent.matching(agent.models, box.field.text)
 if box.slot ~= "review" or #Agent.matching({ M.OFF }, box.field.text) == 0 then return models end
 local rows = { M.OFF }
 table.move(models, 1, #models, 2, rows)
 return rows
end

-- The menu on `slot`, highlighting what that pass uses.
function M.open(agent: Agent.Agent, slot: Agent.Pass): ModelBox
 local box: ModelBox = { slot = slot, field = Fields.create(), query = "", selected = 1, effort = Agent.choiceFor(agent, slot).effort, top = 1 }
 for i, model in M.choices(box, agent) do
  if M.inUse(agent, slot, model) then box.selected = i end
 end
 box.top = math.max(1, box.selected - 3)
 return box
end

-- The lines the list draws from row `top` down to row `last`: each row, a provider heading where the
-- provider changes, the pinned Off row and the "more" row above a list that starts lower down.
local function linesTo(choices: { Agent.Model }, top: number, last: number): number
 local pinned = choices[1] == M.OFF
 local first = if pinned then 2 else 1
 local from = math.max(top, first)
 local lines, group = (if pinned then 1 else 0) + (if from > first then 1 else 0), nil
 for n = from, last do
  local name = string.match(choices[n].selector, "^([^/]+)/") or ""
  if name ~= group then
   group = name
   lines += 1
  end
  lines += 1
 end
 return lines
end

-- Starts the list far enough down that the highlighted model is among the lines it fits, headings
-- included. The list is never scrolled to it: Tern's reveal into a scroller pins it, so the wheel
-- stops working.
local function keepShown(box: ModelBox, choices: { Agent.Model })
 if box.selected < box.top then
  box.top = box.selected
  return
 end
 while box.top < box.selected and linesTo(choices, box.top, box.selected) > MODEL_ROWS do
  box.top += 1
 end
end

function M.move(box: ModelBox, agent: Agent.Agent, delta: number)
 local choices = M.choices(box, agent)
 box.selected = math.clamp(box.selected + delta, 1, math.max(1, #choices))
 keepShown(box, choices)
end

-- Steps the effort the highlighted model will get through the levels it takes.
function M.stepEffort(box: ModelBox, agent: Agent.Agent, delta: number)
 local model = M.choices(box, agent)[box.selected]
 if not model or #model.efforts == 0 then return end
 local at = table.find(model.efforts, Agent.effortFor(model, box.effort) :: string) :: number
 box.effort = model.efforts[(at - 1 + delta) % #model.efforts + 1]
end

-- Makes the highlighted model, with the effort it can take, the one the slot's pass runs with, or
-- turns the review off; false when the filter matches nothing.
function M.choose(box: ModelBox, agent: Agent.Agent): boolean
 local model = M.choices(box, agent)[box.selected]
 if not model then return false end
 if model == M.OFF then
  agent.review = false
  return true
 end
 local effort = Agent.effortFor(model, box.effort)
 if box.slot == "review" then
  agent.model, agent.effort, agent.review = model.selector, effort, true
 else
  agent.explain = { model = model.selector, effort = effort }
 end
 box.effort = effort
 return true
end

-- Whether the menu offers the lens: on the Review slot, while the review is on.
function M.showsLens(box: ModelBox, agent: Agent.Agent): boolean
 return box.slot == "review" and agent.review
end

-- What a menu action left behind: the box to show (a fresh one when the slot switched), whether the
-- agent's picks changed and want saving, and whether the menu closes.
export type Outcome = { box: ModelBox, save: boolean, close: boolean }

-- Runs the menu action `act` with `value` on `box`. A key steps or chooses; ⏎ (`models-pick`) chooses
-- and closes; a click on a model, an effort or a lens chooses it and leaves the menu open for the rest.
-- The lens acts only where it shows. Nil for an action the menu doesn't know.
function M.act(box: ModelBox, agent: Agent.Agent, act: string, value: string): Outcome?
 local function stay(save: boolean): Outcome return { box = box, save = save, close = false } end
 if act == "models-slot" then
  if value == box.slot or (value ~= "explain" and value ~= "review") then return stay(false) end
  return { box = M.open(agent, value :: Agent.Pass), save = false, close = false }
 elseif act == "models-filter" then
  if box.field.text ~= box.query then box.query, box.selected, box.top = box.field.text, 1, 1 end
  return stay(false)
 elseif act == "models-move" then
  M.move(box, agent, tonumber(value) :: number)
  return stay(false)
 elseif act == "models-top" then
  box.top = 1
  return stay(false)
 elseif act == "models-effort" then
  M.stepEffort(box, agent, tonumber(value) :: number)
  return stay(false)
 elseif act == "models-pick" then
  local chosen = M.choose(box, agent)
  return { box = box, save = chosen, close = chosen }
 elseif act == "model-row" then
  box.selected = tonumber(value) :: number
  return stay(M.choose(box, agent))
 elseif act == "model-effort" then
  box.effort = value
  return stay(M.choose(box, agent))
 elseif act == "models-lens" then
  if not M.showsLens(box, agent) then return stay(false) end
  agent.lens = Lens.step(agent.lenses, agent.lens, tonumber(value) :: number).name
  return stay(true)
 elseif act == "model-lens" then
  local lens = agent.lenses[tonumber(value) :: number]
  if not M.showsLens(box, agent) or not lens then return stay(false) end
  agent.lens = lens.name
  return stay(true)
 end
 return nil
end

return M
