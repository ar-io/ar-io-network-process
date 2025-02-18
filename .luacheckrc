allow_defined = true
exclude_files = {
	"src/crypto",
}
max_line_length = 185
local default_globals = {
	"Handlers",
	"ao",
}
globals = default_globals

local file_globals = dofile("src/globals.lua")

-- Merge the two tables
for _, v in ipairs(file_globals) do
	table.insert(default_globals, v)
end

globals = default_globals
