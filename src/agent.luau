--!strict
-- The reader's own AI agent (OMP) writing a guide in two passes the reader starts on their own: a
-- fast explanation of the PR, and a review that drafts comments. Holds the model and effort of each, the
-- models there are to pick from, and the files a run reads. src/agent-host.luau finds the agent and runs it.
local Lens = require("./lens")
local Platform = require("./platform")
local Pr = require("./pr")
local Text = require("./text")

-- One model `omp models` lists: what `--model` takes, its display name, and the thinking levels
-- `--thinking` takes for it (none when it can't think).
export type Model = { selector: string, name: string, efforts: { string } }

-- The two passes of a run: the explanation writes the walkthrough, the review the comments.
export type Pass = "explain" | "review"

-- A model as `--model` takes it, and the effort `--thinking` gets (none for a model that can't think).
export type Choice = { model: string, effort: string? }

-- `omp` as the login shell finds it, that shell's PATH (`omp` runs on an interpreter found there),
-- the review model and effort (agent fixes and the feedback summary run with them too), the
-- explanation's and whether the reader picked it (else it is OMP's fast model), the models there are
-- to choose from (empty until listed), the lenses there are to review through and the name of the
-- one a review uses.
export type Agent = {
 command: string, path: string, model: string, effort: string?, explain: Choice, explainPicked: boolean,
 models: { Model }, lenses: { Lens.Lens }, lens: string,
}

-- What the reader picked, as kept between starts: `Agent` without what is found or listed.
export type Picks = { model: string, effort: string?, explain: Choice, explainPicked: boolean, lens: string }

-- The models OMP's config names for each pass when the reader picked none.
export type Defaults = { review: Choice?, explain: Choice? }

-- The page's AI passes: which are going, the seconds since each started, how long each is expected
-- to take, and the first line of why the explanation last failed.
export type Run = { agent: Agent, explaining: boolean, reviewing: boolean, seconds: { [Pass]: number }, expected: { [Pass]: number }, error: string? }

local MARKS = { ctx = " ", add = "+", del = "-" }

-- Every thinking level `omp --thinking` takes.
local EFFORTS: { [string]: boolean } = { off = true, minimal = true, low = true, medium = true, high = true, xhigh = true, max = true, auto = true }
-- The effort a newly picked model gets when it can't keep the current one.
local DEFAULT_EFFORT = "high"
-- The effort an explanation runs with when neither the reader nor OMP's role names one: it writes a
-- walkthrough, it doesn't hunt for bugs.
local EXPLAIN_EFFORT = "medium"

local M = {}

-- How far along a run `seconds` in probably is, 0 to 1, when one takes about `expected` seconds:
-- `omp -p` reports nothing until it ends, so this eases toward 90% at `expected` and then creeps,
-- never claiming more than 95% before the run is done.
function M.progress(seconds: number, expected: number): number
 return math.min(0.95, 1 - math.exp(-2.3 * seconds / math.max(expected, 1)))
end

-- OMP's settings, under the home directory.
M.CONFIG = "/.omp/agent/config.yml"

-- `raw` as OMP writes a model role ("provider/id:effort"), split into the model and its effort.
function M.parseChoice(raw: string): (string, string?)
 local model, effort = string.match(raw, "^(.*):(%a+)$")
 if model and EFFORTS[effort :: string] then return model, effort end
 return raw, nil
end

-- The picks kept under the "model" key, `saved`, over OMP's `defaults`: the review model, the
-- explanation's (OMP's fast model until the reader picks one, else the review model at medium
-- effort, never the review's effort), and the lens. A `review` key an older version kept is ignored.
-- Nil when there is no model at all.
function M.picks(saved: any, defaults: Defaults): Picks?
 local kept = if type(saved) == "table" then saved else {}
 local review: Choice? = if type(kept.model) == "string"
  then { model = kept.model, effort = if type(kept.effort) == "string" then kept.effort else nil }
  else defaults.review
 if not review then return nil end
 local picked = type(kept.explainModel) == "string"
 local explain: Choice = if picked
  then { model = kept.explainModel, effort = if type(kept.explainEffort) == "string" then kept.explainEffort else nil }
  else defaults.explain or { model = review.model, effort = EXPLAIN_EFFORT }
 return {
  model = review.model, effort = review.effort, explain = explain, explainPicked = picked,
  lens = if type(kept.lens) == "string" then kept.lens else Lens.DEFAULT,
 }
end

-- What `M.picks` reads back. The explanation's model is kept only once the reader picked it, so a
-- default never hardens into a pick.
function M.saved(agent: Agent): { [string]: any }
 return {
  model = agent.model, effort = agent.effort,
  explainModel = if agent.explainPicked then agent.explain.model else nil,
  explainEffort = if agent.explainPicked then agent.explain.effort else nil,
  lens = agent.lens,
 }
end

function M.new(command: string, path: string, picks: Picks): Agent
 return {
  command = command, path = path, model = picks.model, effort = picks.effort, explain = picks.explain,
  explainPicked = picks.explainPicked, models = {}, lenses = {}, lens = picks.lens,
 }
end

-- The model and effort `pass` runs with.
function M.choiceFor(agent: Agent, pass: Pass): Choice
 return if pass == "review" then { model = agent.model, effort = agent.effort } else agent.explain
end

-- A model selector without its provider, as the page names it.
function M.shortName(model: string): string
 return string.match(model, "[^/]+$") or model
end

-- A run with no pass going.
function M.idle(agent: Agent): Run
 return { agent = agent, explaining = false, reviewing = false, seconds = { explain = 0, review = 0 }, expected = { explain = 0, review = 0 }, error = nil }
end

-- Starts `pass` of `run`, expected to take `expected` seconds. Starting the explanation clears why
-- the last one failed.
function M.start(run: Run, pass: Pass, expected: number)
 run.seconds[pass], run.expected[pass] = 0, expected
 if pass == "explain" then
  run.explaining, run.error = true, nil
 else
  run.reviewing = true
 end
end

-- Whether either pass is still going.
function M.busy(run: Run): boolean
 return run.explaining or run.reviewing
end

-- The lens a run reviews through.
function M.currentLens(agent: Agent): Lens.Lens
 return Lens.pick(agent.lenses, agent.lens)
end

-- The chat models in `omp models --json` output, decoded; empty when it isn't that shape.
function M.parseModels(raw: any): { Model }
 local models = {}
 if type(raw) ~= "table" or type(raw.models) ~= "table" then return models end
 for _, item in raw.models do
  if type(item) == "table" and type(item.selector) == "string" and (item.kind == nil or item.kind == "chat") then
   local efforts = {}
   if type(item.thinking) == "table" then
    for _, level in item.thinking do
     if type(level) == "string" then table.insert(efforts, level) end
    end
   end
   table.insert(models, { selector = item.selector, name = if type(item.name) == "string" then item.name else item.selector, efforts = efforts })
  end
 end
 return models
end

-- The models whose name or selector contains `query`, ignoring case, in list order.
function M.matching(models: { Model }, query: string): { Model }
 local needle = string.lower(query)
 if needle == "" then return models end
 local found = {}
 for _, model in models do
  if string.find(string.lower(model.name), needle, 1, true) or string.find(string.lower(model.selector), needle, 1, true) then
   table.insert(found, model)
  end
 end
 return found
end

-- The effort `model` runs with when `wanted` was asked for: `wanted` when it takes it, else high,
-- else its strongest; nil for a model that can't think.
function M.effortFor(model: Model, wanted: string?): string?
 if #model.efforts == 0 then return nil end
 if wanted and table.find(model.efforts, wanted) then return wanted end
 if table.find(model.efforts, DEFAULT_EFFORT) then return DEFAULT_EFFORT end
 return model.efforts[#model.efforts]
end

-- What makes the explanation one request: no saved session, no skills, rules, extensions or title
-- to load, and only the tools it needs to open a caller or definition.
local ONE_REQUEST = { "--no-session", "--no-skills", "--no-rules", "--no-extensions", "--no-title", "--tools=read,grep,bash" }

-- The `omp` command that has `agent` follow the prompt at `promptPath` with `pass`'s model. The
-- explanation gets the prompt and the diff at `diffPath` attached and replies with the guide; the
-- review reads its prompt and writes its file.
function M.argv(agent: Agent, pass: Pass, promptPath: string, diffPath: string): { string }
 local choice = M.choiceFor(agent, pass)
 local argv = { agent.command, "-p" }
 if pass == "explain" then table.move(ONE_REQUEST, 1, #ONE_REQUEST, #argv + 1, argv) end
 table.insert(argv, "--model")
 table.insert(argv, choice.model)
 if choice.effort then
  table.insert(argv, "--thinking")
  table.insert(argv, choice.effort)
 end
 if pass == "explain" then
  table.insert(argv, "@" .. promptPath)
  table.insert(argv, "@" .. diffPath)
  table.insert(argv, "Follow the attached instructions exactly.")
 else
  table.insert(argv, "Read " .. promptPath .. " and follow it exactly.")
 end
 return argv
end

-- The guide JSON in the explanation's reply: what a ```json fence holds, else the whole reply.
function M.replyJson(reply: string): string
 return string.match(reply, "```%w*[ \t]*\n(.-)\n%s*```") or (string.match(reply, "^%s*(.-)%s*$") :: string)
end

-- A YAML scalar without its quotes or trailing comment.
local function scalar(raw: string): string
 local quoted = string.match(raw, "^\"([^\"]*)\"") or string.match(raw, "^'([^']*)'")
 if quoted then return quoted end
 return (string.gsub(raw, "%s+#.*$", ""))
end

-- The roles in the `modelRoles:` block of OMP's config.yml, each as "provider/id:effort".
local function modelRoles(config: string): { [string]: string }
 local roles: { [string]: string } = {}
 local inRoles = false
 for line in string.gmatch(config .. "\n", "([^\n]*)\n") do
  line = string.gsub(line, "%s+$", "")
  if line == "" or string.match(line, "^%s*#") then continue end
  if string.match(line, "^%S") then
   inRoles = string.match(line, "^modelRoles:%s*$") ~= nil or string.match(line, "^modelRoles:%s+#") ~= nil
  elseif inRoles then
   local key, value = string.match(line, "^  ([%w_%-]+):%s*(.*)$")
   if key and value then roles[key] = scalar(value) end
  end
 end
 return roles
end

-- The first of `names` that `roles` sets, as a model and its effort.
local function role(roles: { [string]: string }, names: { string }): Choice?
 for _, name in names do
  if roles[name] and roles[name] ~= "" then
   local model, effort = M.parseChoice(roles[name])
   return { model = model, effort = effort }
  end
 end
 return nil
end

-- What OMP's config.yml says each pass runs with: the review its `review` role, else its `default`
-- one; the explanation its `smol` role (at medium effort unless the role names one), else the
-- `default` model at medium effort.
function M.defaults(config: string): Defaults
 local roles = modelRoles(config)
 local fast, plain = role(roles, { "smol" }), role(roles, { "default" })
 local explain: Choice? = if fast then { model = fast.model, effort = fast.effort or EXPLAIN_EFFORT }
  elseif plain then { model = plain.model, effort = EXPLAIN_EFFORT }
  else nil
 return { review = role(roles, { "review", "default" }), explain = explain }
end

-- Where a run for `pr` keeps the diff and prompt it reads.
function M.workDir(pr: Pr.PR): string
 return Platform.temp() .. "/prguide-" .. string.gsub(pr.repo, "/", "-") .. "-" .. pr.number
end

-- What the first line of the numbered diff says about the columns after it.
M.DIFF_LEGEND = "Columns: old line number, new line number, then a mark (space = unchanged, + = added, - = removed) and the line. "
 .. "Added lines have only a new number; removed lines have only an old number."

-- Folders whose files are someone else's code, wherever they sit in a path.
local VENDORED: { [string]: boolean } = { vendor = true, node_modules = true, third_party = true }
-- A line longer than this is a minified file's.
local LONG_LINE = 2000
-- Extensions where indentation is meaning, so a whitespace-only change is read like any other.
local INDENTED: { [string]: boolean } = { py = true, yml = true, yaml = true }

-- Why the agent reads `file` as one line instead of its diff: a generated or vendored file, a
-- minified one (by name, or a line too long to be written by hand), or a test snapshot. Nil when
-- it reads the diff.
function M.cutReason(file: Pr.File): string?
 if file.group == "generated" then return "generated" end
 local parts = string.split(file.path, "/")
 local name = table.remove(parts) :: string
 for _, dir in parts do
  if VENDORED[dir] then return "vendored" end
  if dir == "__snapshots__" then return "snapshot" end
 end
 if string.match(name, "%.snap$") then return "snapshot" end
 if string.match(name, "%.min%.js$") or string.match(name, "%.min%.css$") then return "minified" end
 for _, row in file.rows do
  if row.kind ~= "hunk" and #row.text > LONG_LINE then return "minified" end
 end
 return nil
end

-- `n` with a comma between each group of three digits: 1,204.
local function count(n: number): string
 local digits = tostring(n)
 return (string.reverse((string.gsub(string.reverse(digits), "(%d%d%d)(%d)", "%1,%2"))))
end

-- `rows` cut at each hunk header: each hunk is its header and the lines under it.
local function hunks(rows: { Pr.Row }): { { Pr.Row } }
 local cut: { { Pr.Row } } = {}
 for _, row in rows do
  if row.kind == "hunk" or #cut == 0 then table.insert(cut, {}) end
  table.insert(cut[#cut], row)
 end
 return cut
end

-- How many lines `hunk` changes when it only changes whitespace: its removed and added lines say
-- the same once every space is gone. Zero when it changes anything else.
local function whitespaceOnly(hunk: { Pr.Row }): number
 local removed, added, changed = {}, {}, 0
 for _, row in hunk do
  if row.kind == "del" or row.kind == "add" then
   changed += 1
   table.insert(if row.kind == "del" then removed else added, (string.gsub(row.text, "%s", "")))
  end
 end
 return if changed > 0 and table.concat(removed) == table.concat(added) then changed else 0
end

-- Every changed file's diff with the line numbers in front of each line, so the agent can point at
-- lines without counting: the old-file number (blank on an added line), the new-file number (blank
-- on a removed line), the mark and the text. A file the agent needn't read (see `cutReason`) is
-- one line under its header, and hunks that only change whitespace are left out, said in one line,
-- except where indentation is meaning.
function M.numberedDiff(files: { Pr.File }): string
 local out = { M.DIFF_LEGEND, "" }
 for _, file in files do
  table.insert(out, "=== " .. file.path .. " (" .. file.status .. ")")
  local reason = M.cutReason(file)
  if file.binary then
   table.insert(out, "(binary, no lines)")
  elseif reason then
   local lines = 0
   for _, row in file.rows do
    if row.kind ~= "hunk" then lines += 1 end
   end
   table.insert(out, "(" .. reason .. ", " .. count(lines) .. (if lines == 1 then " line" else " lines") .. " not shown)")
  else
   local keepWhitespace, leftOut, shown = INDENTED[string.lower(Text.extension(file.path))], 0, {}
   for _, hunk in hunks(file.rows) do
    local cut = if keepWhitespace then 0 else whitespaceOnly(hunk)
    leftOut += cut
    if cut > 0 then continue end
    for _, row in hunk do
     if row.kind == "hunk" then
      table.insert(shown, "")
      table.insert(shown, "@@ -" .. row.oldStart .. " +" .. row.newStart .. " @@" .. (if row.label then " " .. row.label else ""))
     else
      table.insert(shown, string.format("%5s %5s %s %s", if row.old then tostring(row.old) else "", if row.new then tostring(row.new) else "", MARKS[row.kind], row.text))
     end
    end
   end
   if leftOut > 0 then
    table.insert(out, "(" .. count(leftOut) .. " whitespace-only " .. (if leftOut == 1 then "line" else "lines") .. " not shown)")
   end
   table.move(shown, 1, #shown, #out + 1, out)
  end
  table.insert(out, "")
 end
 return table.concat(out, "\n")
end

-- The prompt template with its `{{placeholders}}` filled in.
function M.prompt(template: string, values: { [string]: string }): string
 return (string.gsub(template, "{{(%w+)}}", function(name: string): string
  return values[name] or "{{" .. name .. "}}"
 end))
end

-- The prompt section that has the review go through `lens`: nothing for a lens without
-- instructions, so a plain review reads as it always did.
function M.focus(lens: Lens.Lens): string
 if lens.instructions == "" then return "" end
 return "## Review lens: " .. lens.name .. "\n\n"
  .. "The reader chose this lens. It changes what you look for and how you word comments, never the "
  .. "format you write below, which stays exactly the same.\n\n"
  .. lens.instructions .. "\n\n"
end

return M
