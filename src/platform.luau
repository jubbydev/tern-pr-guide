--!strict
-- What differs by operating system: the home and temp folders, how a PATH value splits and what a program's file is
-- called on it, the Python that runs PR Guide's scripts, and the command that opens a link or folder outside Tern.
-- It reads `Host.runtime` and `Host.getenv` on every call, so tests that swap them see the change.
local Host = require("./host")

local M = {}

function M.windows(): boolean
	local runtime = Host.runtime
	return runtime ~= nil and runtime.os == "windows"
end

local function env(name: string): string?
	local value = Host.getenv(name)
	return if value and value ~= "" then value else nil
end

-- The reader's home folder, or nil. Windows keeps it in USERPROFILE, which is where OMP looks too; HOME there, when set
-- at all, may be a Unix-style path from Git Bash.
function M.home(): string?
	if M.windows() then return env("USERPROFILE") or env("HOME") end
	return env("HOME")
end

-- The folder scratch files go in.
function M.temp(): string
	if M.windows() then return env("TEMP") or env("TMP") or "C:\\Windows\\Temp" end
	return "/tmp"
end

-- What separates the folders in a PATH value.
function M.pathSeparator(): string
	return if M.windows() then ";" else ":"
end

-- The folders of a PATH value, in order. Windows entries may be quoted and may end in a backslash.
function M.pathDirs(path: string): { string }
	local dirs = {}
	for dir in string.gmatch(path, "[^" .. M.pathSeparator() .. "]+") do
		if M.windows() then dir = string.gsub(string.gsub(dir, '^"(.*)"$', "%1"), "[\\/]+$", "") end
		if dir ~= "" then table.insert(dirs, dir) end
	end
	return dirs
end

-- Whether `program` names a file by its path, rather than a name to look up on PATH.
function M.isPath(program: string): boolean
	return string.find(program, "/", 1, true) ~= nil or (M.windows() and string.find(program, "\\", 1, true) ~= nil)
end

-- The extensions Windows runs a program file by, from PATHEXT; other kinds there (scripts for other hosts) can't be
-- started as a process.
local RUNNABLE: { [string]: boolean } = { [".exe"] = true, [".cmd"] = true, [".bat"] = true, [".com"] = true }

local function extensions(): { string }
	local found = {}
	for ext in string.gmatch(env("PATHEXT") or ".COM;.EXE;.BAT;.CMD", "[^;]+") do
		local lower = string.lower(ext)
		if RUNNABLE[lower] then table.insert(found, lower) end
	end
	return found
end

-- The file names `program` may have on PATH: on Windows, with each runnable extension, unless it already has one.
function M.programNames(program: string): { string }
	if not M.windows() then return { program } end
	local ext = string.match(string.lower(program), "%.%w+$")
	if ext and RUNNABLE[ext] then return { program } end
	local names = {}
	for _, extension in extensions() do table.insert(names, program .. extension) end
	return names
end

-- The first file for `program` in the folders of `path` that `exists`, or nil.
function M.which(program: string, path: string, exists: (string) -> boolean): string?
	local slash = if M.windows() then "\\" else "/"
	for _, dir in M.pathDirs(path) do
		for _, name in M.programNames(program) do
			local candidate = dir .. slash .. name
			if exists(candidate) then return candidate end
		end
	end
	return nil
end

-- The Python that runs PR Guide's scripts. Windows ignores their `#!` line, and its `python3` is often the Microsoft
-- Store's stand-in rather than an installed Python.
function M.python(): string
	return if M.windows() then "python" else "python3"
end

-- The argv that opens `target`, a link or a folder, with the system's default app.
function M.openCommand(target: string): { string }
	if M.windows() then
		-- rundll32 hands `target` to the shell as one argument, with no command line to quote it into.
		return { (env("SystemRoot") or "C:\\Windows") .. "\\System32\\rundll32.exe", "url.dll,FileProtocolHandler", target }
	end
	local runtime = Host.runtime
	return { if runtime and runtime.os == "linux" then "xdg-open" else "open", target }
end

return M
