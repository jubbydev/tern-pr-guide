--!strict
-- The model and lens menu: its Explanation and Review slots, the Off row, and Tab between them, on the
-- review page and in the PR hub's Settings.
local Agent = require("../src/agent")
local Fields = require("../src/text-field")
local Guide = require("../src/guide")
local Keys = require("../src/keys")
local ModelBox = require("../src/model-box")
local Pr = require("../src/pr")
local State = require("../src/state")

local function page(): State.State
	local rows: { Pr.Row } = { { kind = "hunk", oldStart = 1, newStart = 1 } :: Pr.Hunk, { kind = "add", text = "x", new = 1 } :: Pr.Line }
	local p: Pr.PR = { repo = "acme/api", number = 7, title = "t", body = "", url = "", author = "a", createdAt = "", baseRef = "main", head = "abc",
		files = { { path = "a.ts", status = "modified", adds = 1, dels = 0, rows = rows } } }
	return State.new(p, Guide.defaultGuide(p), {})
end

local function agent(): Agent.Agent
	local a = Agent.new("/omp", "/bin", Agent.picks({ model = "anthropic/opus-5", effort = "high" }, nil) :: Agent.Picks)
	a.models = {
		{ selector = "anthropic/haiku-4", name = "Haiku 4", efforts = { "low", "high" } },
		{ selector = "anthropic/opus-5", name = "Opus 5", efforts = { "low", "high", "max" } },
	}
	return a
end

local function names(box: ModelBox.ModelBox, a: Agent.Agent): string
	local out = {}
	for _, model in ModelBox.choices(box, a) do table.insert(out, model.name) end
	return table.concat(out, ",")
end

local function key(name: string, shift: boolean?): Key
	return { name = name, shift = shift or false, meta = false, ctrl = false, alt = false } :: any
end

-- Every text a node tree draws, joined.
local function texts(node: any, out: { string }?): string
	local acc = out or {}
	if node.p and type(node.p.text) == "string" then table.insert(acc, node.p.text) end
	if node.p and node.p.keys then table.insert(acc, "[" .. table.concat(node.p.keys, "+") .. "]") end
	for _, child in node.c or {} do texts(child, acc) end
	return table.concat(acc, "|")
end

-- The menu and the header's AI row as they draw.
local function drawn()
	local ModelPanel = require("../src/view/model-panel")
	local Header = require("../src/view/header")
	local fieldEnv: any = getfenv(require("../src/view/ui").field)
	local host = fieldEnv.tern
	fieldEnv.tern = { ui = { node = function(kind: string, props: any): any return { k = kind, p = props } end } }
	local ok, err = pcall(function()
		local s, a = page(), agent()
		a.lenses = { { name = "Balanced", description = "The comments worth making.", instructions = "" } }
		s.models = ModelBox.open(a, "explain")
		local explain = texts(ModelPanel.view(s.models :: ModelBox.ModelBox, a, "anchor", false))
		assert(string.find(explain, "Explains what the PR changes, step by step.", 1, true) and string.find(explain, "[tab]", 1, true), explain)
		assert(not string.find(explain, "Lens", 1, true) and not string.find(explain, "Off", 1, true), "Explanation has no lens and no Off")
		s.models = ModelBox.open(a, "review")
		local review = texts(ModelPanel.view(s.models :: ModelBox.ModelBox, a, "anchor", false))
		assert(string.find(review, "Off||Explanation only; no drafted comments.", 1, true) and string.find(review, "Lens", 1, true), review)

		local motion = { born = {}, next = {}, booted = true, animate = false }
		s.models = nil
		a.explain = { model = "anthropic/haiku-4", effort = "low" }
		s.ai = Agent.idle(a)
		local idle = texts(Header.view(s, motion))
		assert(string.find(idle, "Explain|haiku-4|low|·|Review|opus-5|high|·|Balanced", 1, true), idle)
		a.review = false
		assert(string.find(texts(Header.view(s, motion)), "Explain|haiku-4|low|·|No review", 1, true), "Off reads as no review, without a lens")
		a.review = true
		Agent.start(s.ai :: Agent.Run, { explain = 60, review = 180 })
		assert(string.find(texts(Header.view(s, motion)), "E|x|p|l|a|i|n", 1, true), "the explanation writes its phrase in")
		;(s.ai :: Agent.Run).explaining = false
		assert(string.find(texts(Header.view(s, motion)), "Reviewing for issues…", 1, true), "then the quiet review row")
		s.review.guide.guided = true
		local guided = texts(Header.view(s, motion))
		assert(string.find(guided, "0 of 1 files reviewed|·|Reviewing for issues… 0:00", 1, true), "over a guide, the status line says the review is going: " .. guided)
		assert(not string.find(guided, "Generate AI Guided Review", 1, true), "and no AI row takes a line of its own")
		s.review.guide.guided = false

		s.models = ModelBox.open(a, "review")
		local box = s.models :: ModelBox.ModelBox
		box.top = 3
		local scrolled = texts(ModelPanel.view(box, a, "anchor", false))
		assert(string.find(scrolled, "Off||Explanation only; no drafted comments.", 1, true) and string.find(scrolled, "↑  1 more", 1, true), "Off stays pinned above a scrolled list: " .. scrolled)
		s.models = nil
	end)
	fieldEnv.tern = host
	if not ok then error(err, 0) end
end

return function()
	drawn()
	local s, a = page(), agent()

	s.models = ModelBox.open(a, "explain")
	local box = s.models :: ModelBox.ModelBox
	assert(names(box, a) == "Haiku 4,Opus 5", "the Explanation slot has no Off row: " .. names(box, a))
	assert(box.selected == 2 and box.effort == "high", "the explanation starts on the review model it defaults to")
	assert(not ModelBox.showsLens(box, a), "no lens on the Explanation slot")
	box.selected, box.effort = 1, "low"
	assert(ModelBox.choose(box, a))
	assert(a.explain.model == "anthropic/haiku-4" and a.explain.effort == "low", "picking on Explanation sets the explanation")
	assert(a.model == "anthropic/opus-5" and a.effort == "high", "and leaves the review model")

	assert(Keys.action(s, key("tab")).act == "models-slot" and Keys.action(s, key("tab")).value == "review", "Tab goes to Review")
	s.models = ModelBox.open(a, "review")
	box = s.models :: ModelBox.ModelBox
	assert(Keys.action(s, key("tab")).value == "explain", "Tab comes back to Explanation")
	assert(names(box, a) == "Off,Haiku 4,Opus 5", "Off comes first on Review: " .. names(box, a))
	assert(box.selected == 3 and ModelBox.showsLens(box, a), "Review highlights its model and shows the lens")
	box.selected = 1
	assert(ModelBox.choose(box, a))
	assert(a.review == false and a.model == "anthropic/opus-5", "Off turns the review off and keeps its model")
	assert(not ModelBox.showsLens(box, a), "no lens with the review off")

	s.models = ModelBox.open(a, "review")
	box = s.models :: ModelBox.ModelBox
	assert(box.selected == 1 and ModelBox.inUse(a, "review", ModelBox.OFF), "reopened, Off is the one in use")
	box.field = Fields.create("opus")
	assert(names(box, a) == "Opus 5", "a filter that doesn't match Off hides it")
	box.selected = 1
	assert(ModelBox.choose(box, a))
	assert(a.review == true and a.model == "anthropic/opus-5", "picking a review model turns the review back on")
end
