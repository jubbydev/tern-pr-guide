--!strict
-- The PR hub's Settings: the review page's model and lens menu on the hub's agent, saving the same choice, with
-- L for where links open while the search field is empty.
local Block: any = require("../src/hub/block")
local Host: any = require("../src/host")
local ModelBox = require("../src/model-box")
local Paths = require("../src/view/hub/paths")
local Ui: any = require("../src/view/ui")

-- The node the view draws at `path`; parts[1] names `root` itself.
local function nodeAt(root: any, path: string): any
	local node = root
	local parts = string.split(path, ".")
	for i = 2, #parts do
		local found = nil
		for _, child in node.c or {} do
			if child.p and child.p.key == parts[i] then found = child end
		end
		if not found then return nil end
		node = found
	end
	return node
end

return function()
	local fieldEnv: any = getfenv(Ui.field)
	local hostField = fieldEnv.tern
	local kv: { [string]: any } = {}
	local stub: { [string]: any } = {
		timer = function(_ms: number, fn: () -> ()): any
			fn()
			return { cancel = function() end }
		end,
		json = { decode = function(): any return nil end, encode = function(): string return "" end },
		getenv = function(): string? return nil end,
		kv = { get = function(key: string): any return kv[key] end, set = function(key: string, value: any) kv[key] = value end },
		plugin = { data = "/data" },
		fs = {
			exists = function(path: string): boolean return path == "lenses" end,
			list = function(): { string } return { "security.md" } end,
			read = function(): string return "# Security\n\nFlags what could be misused.\n\nLook for abuse." end,
		},
	}
	local hostFields: { [string]: any } = {}
	for name, value in stub do
		hostFields[name] = Host[name]
		Host[name] = value
	end
	fieldEnv.tern = { ui = { node = function(kind: string, props: any): any return { k = kind, p = props } end } }

	local ok, err = pcall(function()
		local frames: { any } = {}
		local cx: any = { cwd = "/reader" }
		function cx:render() end
		function cx:toast() end
		function cx:open() end
		function cx:frame(ops: { any })
			for _, op in ops do table.insert(frames, op) end
		end
		local b: any = Block.init(cx, { "fixture=cases" }, nil)
		-- Picks on a sample board are never saved; this one stands in for a live board.
		b.fixture = nil
		local function press(name: string, shift: boolean?, text: string?)
			Block.key(b, { name = name, text = text, shift = shift or false, meta = false, ctrl = false, alt = false } :: any, cx)
		end
		local function typed(text: string)
			for _, char in string.split(text, "") do press(char, false, char) end
		end
		local function box(): ModelBox.ModelBox
			assert(b.s.menu == "settings" and b.s.models, "Settings is open")
			return b.s.models
		end
		local function names(): string
			local out = {}
			for _, model in ModelBox.choices(box(), b.s.agent) do table.insert(out, model.name) end
			return table.concat(out, ",")
		end

		press("s", true)
		assert(box().slot == "explain" and box().field.text == "", "⇧S opens on Explanation with an empty search")
		local op = frames[#frames]
		assert(op and op[1] == "focus" and op[2] == Paths.settingsField, "opening focuses the search field")
		local field = nodeAt(Block.view(b).layer, Paths.settingsField)
		assert(field and field.k == "input", "the field is drawn at Paths.settingsField")
		assert(b.s.agent.lenses[2] and b.s.agent.lenses[2].name == "Security", "opening reads the lenses")

		press("l")
		assert(b.s.links == "browser" and kv.links == "browser", "L with an empty field switches where links open")
		press("down")
		press("down")
		assert(box().selected == 3, "↓ moves down the list")
		typed("gpt-6")
		assert(box().field.text == "gpt-6" and names() == "GPT-6.1 Sol,GPT-6.1 Sol mini", "letters type into the search and filter: " .. names())
		assert(box().selected == 1, "a new filter highlights its first match")
		press("l", false, "l")
		assert(box().field.text == "gpt-6l" and b.s.links == "browser", "with text in the field, L types")
		press("backspace")
		press("enter")
		assert(b.s.menu == nil, "⏎ chooses and closes")
		assert(kv.model and kv.model.explainModel == "openai-codex/gpt-6.1-sol" and kv.model.explainEffort == "high", "the explanation model is saved")
		assert(kv.model.model == "anthropic/claude-fable-5-1" and kv.model.review == true, "and the review model is kept")

		press("s", true)
		press("tab")
		assert(box().slot == "review" and string.sub(names(), 1, 4) == "Off,", "Tab goes to Review, Off first: " .. names())
		press("up")
		press("enter")
		assert(b.s.menu == nil and kv.model.review == false and kv.model.model == "anthropic/claude-fable-5-1", "Off turns the review off and keeps its model")

		press("s", true)
		press("tab")
		assert(box().selected == 1 and not ModelBox.showsLens(box(), b.s.agent), "Off is in use, so no lens")
		Block.event(b, { ev = "action", act = "model-row", value = "2" } :: any, cx)
		assert(b.s.menu == "settings" and kv.model.review == true, "a click turns the review back on and stays open")
		press("right", true)
		assert(kv.model.lens == "Security", "⇧→ steps the lens and saves it")
		press("escape")
		assert(b.s.menu == nil and b.s.models == nil, "Esc closes")
		assert(kv.model.explainModel == "openai-codex/gpt-6.1-sol" and kv.model.model == "anthropic/claude-fable-5-1" and kv.model.review == true and kv.model.lens == "Security",
			"the saved choice carries the explanation, the review and the lens")
	end)
	for name in stub do Host[name] = hostFields[name] end
	fieldEnv.tern = hostField
	if not ok then error(err, 0) end
end
