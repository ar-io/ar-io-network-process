--[[
	Adds support for nested field filtering using dot notation (e.g., "settings.fqdn").

	This patch adds a getNestedValue utility function and updates createFilterFunction
	to use it, enabling filters like { "settings.fqdn": "example.com" } on paginated
	handlers.

	Reviewers: Dylan
]]
--
local utils = require(".src.utils")

-- utils.lua - add getNestedValue function for dot-notation field access
function utils.getNestedValue(tbl, fieldPath)
	local current = tbl
	for segment in fieldPath:gmatch("[^.]+") do
		if type(current) == "table" then
			current = current[segment]
		else
			return nil
		end
	end
	return current
end

-- utils.lua - update createFilterFunction to use getNestedValue for nested field support
function utils.createFilterFunction(filters)
	if type(filters) ~= "table" then
		return nil
	end

	-- Precompute lookup maps for array values so repeated checks are O(1)
	local lookups = {}
	for field, value in pairs(filters) do
		if type(value) == "table" then
			lookups[field] = utils.createLookupTable(value)
		else
			lookups[field] = value
		end
	end

	return function(item)
		for field, expected in pairs(lookups) do
			local itemValue = type(item) == "table" and utils.getNestedValue(item, field) or nil
			if type(expected) == "table" then
				if not expected[itemValue] then
					return false
				end
			else
				if itemValue ~= expected then
					return false
				end
			end
		end
		return true
	end
end
