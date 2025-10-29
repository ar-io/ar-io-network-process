local patch_files = {}

-- they are organized by date (YYYY-MM-DD-<patch-name>.lua)

local patch_dir = "./patches"

-- Use io.popen and ls/dir to list files in the directory, cross-platform
local function list_patch_files(dir)
	local files = {}
	local command
	if package.config:sub(1, 1) == "\\" then
		-- Windows
		command = 'dir "' .. dir .. '" /b'
	else
		-- Unix
		command = 'ls -1 "' .. dir .. '"'
	end
	local p = io.popen(command)
	if p then
		for file in p:lines() do
			if file:match("^%d%d%d%d-%d%d-%d%d-.*%.lua$") then
				table.insert(files, file)
			end
		end
		p:close()
	end
	return files
end

patch_files = list_patch_files(patch_dir)
table.sort(patch_files)

for _, file in ipairs(patch_files) do
	dofile("patches/" .. file)
end
