--[[
	Adds support for providing JSON filters for pagination.

	Reviewers: Dylan, Ariel, Jonathon, Phil
]]
--
local utils = require(".src.utils")

--- Creates a predicate function from a table of filters.
--- Each key/value pair in the filter table must be satisfied for an item to match.
--- A filter value can be a table of acceptable values or a single value.
--- @param filters table|nil The filters to convert
--- @return function|nil predicate - the predicate function or nil if no filters
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
			local itemValue = type(item) == "table" and item[field] or nil
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

function utils.paginateTableWithCursor(tableArray, cursor, cursorField, limit, sortBy, sortOrder, filters)
	local filterFn = nil
	if type(filters) == "table" then
		filterFn = utils.createFilterFunction(filters)
	end

	local filteredArray = filterFn
			and utils.filterArray(tableArray, function(_, value)
				return filterFn(value)
			end)
		or tableArray

	assert(sortOrder == "asc" or sortOrder == "desc", "Invalid sortOrder: expected 'asc' or 'desc'")
	local sortFields = { { order = sortOrder, field = sortBy } }
	if cursorField ~= nil and cursorField ~= sortBy then
		-- Tie-breaker to guarantee deterministic pagination
		table.insert(sortFields, { order = "asc", field = cursorField })
	end
	local sortedArray = utils.sortTableByFields(filteredArray, sortFields)

	if not sortedArray or #sortedArray == 0 then
		return {
			items = {},
			limit = limit,
			totalItems = 0,
			sortBy = sortBy,
			sortOrder = sortOrder,
			nextCursor = nil,
			hasMore = false,
		}
	end

	local startIndex = 1

	if cursor then
		for i, obj in ipairs(sortedArray) do
			if cursorField and obj[cursorField] == cursor or cursor == obj then
				startIndex = i + 1
				break
			end
		end
	end

	local items = {}
	local endIndex = math.min(startIndex + limit - 1, #sortedArray)

	for i = startIndex, endIndex do
		table.insert(items, sortedArray[i])
	end

	local nextCursor = nil
	if endIndex < #sortedArray then
		nextCursor = cursorField and sortedArray[endIndex][cursorField] or sortedArray[endIndex]
	end

	return {
		items = items,
		limit = limit,
		totalItems = #sortedArray,
		sortBy = sortBy,
		sortOrder = sortOrder,
		nextCursor = nextCursor, -- the last item in the current page
		hasMore = nextCursor ~= nil,
	}
end
