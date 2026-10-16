--!strict
-- Opening a PR: an open of a PR already loading waits for that load, a PR loaded lately opens without a process unless
-- the caller knows another head, GitHub is read while the commits are fetched when the caller knows the base, and a
-- saved copy fetches both trees in one request. Host's process, files, JSON and clock are stubbed; each process waits
-- until the scenario settles it.
local Host: any = require("../src/host")
local Prdata = require("../src/prdata")

type Pending = { argv: { string }, stdin: string?, cb: (any) -> () }

local META = { number = 7, title = "T", url = "https://github.com/acme/api/pull/7", baseRefName = "main", headRefOid = "h1" }

local function world()
	local w = { pending = {} :: { Pending }, ran = {} :: { string }, now = 0 }
	Host.process = {
		run = function(argv: { string }, opts: any, cb: (any) -> ())
			if argv[2] == "-lic" then return cb({ status = 0, stdout = "\nPRGUIDE_PATH=/bin\n", stderr = "" }) end
			local words = table.concat(argv, " ")
			table.insert(w.ran, (string.gsub(words, "^git %-%-literal%-pathspecs %-C %S+ ", "git ")))
			table.insert(w.pending, { argv = argv, stdin = opts.stdin, cb = cb })
		end,
	}
	Host.fs = { exists = function() return false end, write = function() end, mkdir = function() end }
	Host.json = { decode = function(): any return table.clone(META) end }
	Host.getenv = function(): string? return nil end
	Host.now = function(): number return w.now end
	-- Settles every waiting process with the output its command would give, until none waits.
	local function settle()
		while #w.pending > 0 do
			local p = table.remove(w.pending, 1) :: Pending
			local words = table.concat(p.argv, " ")
			local out = ""
			if string.find(words, "rev-parse", 1, true) or string.find(words, "merge-base", 1, true) then out = "abc\n" end
			p.cb({ status = 0, stdout = out, stderr = "" })
		end
	end
	local function count(text: string): number
		local n = 0
		for _, words in w.ran do
			if string.find(words, text, 1, true) then n += 1 end
		end
		return n
	end
	return w, settle, count
end

return function()
	do
		local w, settle, count = world()
		local got: { any } = {}
		local target = { pr = "7", repo = "/c/api", head = nil, base = nil }
		Prdata.openPr(target, function() end, function(pr) table.insert(got, pr) end)
		Prdata.openPr(target, function() end, function(pr) table.insert(got, pr) end)
		settle()
		assert(#got == 2 and got[1] == got[2], "both opens get the one load's PR")
		assert(count("gh pr view") == 1, "an open of a PR already loading waits for that load")
		local before = #w.ran
		Prdata.openPr(target, function() end, function(pr) table.insert(got, pr) end)
		assert(#got == 3 and #w.ran == before, "a PR loaded lately opens without a process")
		Prdata.openPr({ pr = "7", repo = "/c/api", head = "h2" }, function() end, function(pr) table.insert(got, pr) end)
		assert(#got == 3 and #w.ran > before, "a kept PR at another head is loaded again")
		settle()
		w.now = 11 * 60_000
		before = #w.ran
		Prdata.openPr(target, function() end, function() end)
		assert(#w.ran > before, "a PR kept too long is loaded again")
		settle()
	end
	do
		local w, settle, count = world()
		Prdata.openPr({ pr = "8", repo = "/c/web", base = "main" }, function() end, function() end)
		assert(#w.ran == 2 and count("gh pr view") == 1 and count("git fetch") == 1, "with the base known, GitHub is read while the commits are fetched")
		assert(count("--recurse-submodules=no") == 1, "fetching a PR never fetches its repository's submodules")
		settle()
	end
	do
		local w, settle, count = world()
		Prdata.openPr({ pr = "9", repo = "/c/copy.git", cache = "acme/api" }, function() end, function() end)
		settle()
		assert(count("--filter=tree:0") == 1, "a saved copy fetches commits without trees")
		assert(count("log --no-walk --format=%T") == 1, "the trees' ids are read from the commits")
		assert(count("rev-parse abc^{tree}") == 0, "no rev-parse that would fetch each tree on its own")
		local treeFetches = 0
		for _, words in w.ran do
			if string.find(words, "--stdin origin", 1, true) then treeFetches += 1 end
		end
		assert(treeFetches == 1, "both trees come in one fetch")
	end
end
