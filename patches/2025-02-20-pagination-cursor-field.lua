--[[
    Fixes a bug in pagination where a unique cursor field was not being used for pagination, causing non-deterministic results for paginated requests.
    By default, all tables will be sorted using the unique cursor field, and then sorted by the requested sortBy field.
    This ensures that the same cursor will always return the same results.

    Reviewers: Dylan, Jonathon, Phil, Ariel
]]
--

local utils = require(".src.utils")

_G.package.loaded[".src.utils"].paginateTableWithCursor = function(
	tableArray,
	cursor,
	cursorField,
	limit,
	sortBy,
	sortOrder
)
	-- Sort first by cursorField for a stable sort
	if cursorField ~= nil then
		table.sort(tableArray, function(a, b)
			return a[cursorField] < b[cursorField]
		end)
	end

	local sortedArray = utils.sortTableByFields(tableArray, { { order = sortOrder, field = sortBy } })

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

-- vault fix
local vaults = require(".src.vaults")
_G.package.loaded[".src.vaults"].getPaginatedVaults = function(cursor, limit, sortOrder, sortBy)
	local allVaults = vaults.getVaultsUnsafe()
	local cursorField = "vaultId"

	local vaultsArray = utils.reduce(allVaults, function(acc, address, vaultsForAddress)
		for vaultId, vault in pairs(vaultsForAddress) do
			table.insert(acc, {
				address = address,
				controller = vault.controller,
				vaultId = vaultId,
				balance = vault.balance,
				startTimestamp = vault.startTimestamp,
				endTimestamp = vault.endTimestamp,
			})
		end
		return acc
	end, {})

	return utils.paginateTableWithCursor(vaultsArray, cursor, cursorField, limit, sortBy or "address", sortOrder)
end
