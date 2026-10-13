--!strict
-- What differs on Windows: the home and temp folders, PATH lookup with PATHEXT, the Python name and the opener. The
-- Host table's `runtime` and `getenv` are swapped for each operating system and put back.
local Host = require("../src/host")
local Platform = require("../src/platform")

local function on(os: string, env: { [string]: string }, body: () -> ())
	local runtime, getenv = Host.runtime, Host.getenv
	Host.runtime, Host.getenv = { os = os }, function(name: string): string? return env[name] end
	local ok, err = pcall(body)
	Host.runtime, Host.getenv = runtime, getenv
	if not ok then error(err, 0) end
end

local function same(actual: { string }, expected: { string })
	assert(#actual == #expected, "length: " .. table.concat(actual, " | "))
	for i, value in expected do assert(actual[i] == value, "at " .. i .. ": " .. tostring(actual[i])) end
end

return function()
	on("windows", { USERPROFILE = "C:\\Users\\dev", HOME = "/c/Users/dev", TEMP = "C:\\Users\\dev\\AppData\\Local\\Temp",
		PATHEXT = ".COM;.EXE;.BAT;.CMD;.VBS;.JS", SystemRoot = "C:\\WINDOWS" }, function()
		assert(Platform.windows())
		-- OMP reads its config under USERPROFILE; a Git Bash HOME is a Unix path Windows can't open.
		assert(Platform.home() == "C:\\Users\\dev")
		assert(Platform.temp() == "C:\\Users\\dev\\AppData\\Local\\Temp")
		-- `;` separates, drive letters keep their colon, and quotes and trailing slashes go.
		same(Platform.pathDirs('C:\\Program Files\\Git\\cmd;"C:\\Tools\\bin\\";;C:\\omp\\'), { "C:\\Program Files\\Git\\cmd", "C:\\Tools\\bin", "C:\\omp" })
		-- Only extensions a process can start as; a name that has one is kept.
		same(Platform.programNames("omp"), { "omp.com", "omp.exe", "omp.bat", "omp.cmd" })
		same(Platform.programNames("gh.exe"), { "gh.exe" })
		assert(Platform.isPath("C:\\Tools\\omp.exe") and Platform.isPath("C:/Tools/omp.exe") and not Platform.isPath("omp"))
		local files = { ["C:\\Tools\\bin\\omp.cmd"] = true, ["C:\\Later\\omp.exe"] = true }
		local function exists(path: string): boolean return files[path] == true end
		-- The first folder wins, whatever the extension.
		assert(Platform.which("omp", "C:\\Missing;C:\\Tools\\bin;C:\\Later", exists) == "C:\\Tools\\bin\\omp.cmd")
		assert(Platform.which("omp", "C:\\Missing", exists) == nil)
		assert(Platform.python() == "python")
		same(Platform.openCommand("https://github.com/a/b/pull/1"), { "C:\\WINDOWS\\System32\\rundll32.exe", "url.dll,FileProtocolHandler", "https://github.com/a/b/pull/1" })
	end)
	on("windows", { HOME = "D:\\home" }, function()
		assert(Platform.home() == "D:\\home", "HOME stands in when USERPROFILE is missing")
		assert(Platform.temp() == "C:\\Windows\\Temp")
		same(Platform.programNames("omp"), { "omp.com", "omp.exe", "omp.bat", "omp.cmd" })
	end)
	on("windows", {}, function() assert(Platform.home() == nil) end)

	on("macos", { HOME = "/Users/dev", USERPROFILE = "C:\\nope" }, function()
		assert(not Platform.windows() and Platform.home() == "/Users/dev" and Platform.temp() == "/tmp")
		same(Platform.pathDirs("/usr/bin:/opt/homebrew/bin"), { "/usr/bin", "/opt/homebrew/bin" })
		same(Platform.programNames("omp"), { "omp" })
		local function exists(path: string): boolean return path == "/opt/homebrew/bin/omp" end
		assert(Platform.which("omp", "/usr/bin:/opt/homebrew/bin", exists) == "/opt/homebrew/bin/omp")
		assert(Platform.python() == "python3")
		same(Platform.openCommand("/tmp/wt"), { "open", "/tmp/wt" })
	end)
	on("linux", {}, function()
		assert(Platform.home() == nil)
		same(Platform.openCommand("https://x"), { "xdg-open", "https://x" })
	end)
end
