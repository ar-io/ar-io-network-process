--[[
	Fixes the undernameForName function to handle names with dashes.

	Reviewers: Dylan, Ariel, Atticus
]]
--
-- utils.lua - override undernameForName function
_G.package.loaded[".src.utils"].undernameForName = function(name)
	local reversedName = name:reverse()

	local startIndex = reversedName:find("_", nil, true)
	if not startIndex then
		return nil
	end
	return reversedName:sub(startIndex + 1):reverse()
end
