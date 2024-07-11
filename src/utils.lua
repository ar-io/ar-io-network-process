local base64 = require("base64")
local crypto = require("crypto.init")
local utils = {}

function utils.hasMatchingTag(tag, value)
	return Handlers.utils.hasMatchingTag(tag, value)
end

function utils.reply(msg)
	Handlers.utils.reply(msg)
end

-- Then, check for a 43-character base64url pattern.
-- The pattern checks for a string of length 43 containing alphanumeric characters, hyphens, or underscores.
function utils.isValidBase64Url(url)
	local isValidBase64Url = #url == 43 and string.match(url, "^[%w-_]+$") ~= nil

	if not isValidBase64Url then
		error("String pattern is invalid.")
	end
	return url
end

function utils.isInteger(value)
	if type(value) == "string" then
		value = tonumber(value)
	end
	return value % 1 == 0
end

function utils.slice(tbl, first, last, step)
	local sliced = {}

	for i = first or 1, last or #tbl, step or 1 do
		sliced[#sliced + 1] = tbl[i]
	end

	return sliced
end

function utils.parsePaginationTags(msg)
	local cursor = tonumber(msg.Tags.Cursor) or msg.Tags.Cursor
	local limit = tonumber(msg.Tags["Limit"]) or 100
	local sortOrder = msg.Tags["Sort-Order"] and string.lower(msg.Tags["Sort-Order"]) or "desc"
	local sortBy = msg.Tags["Sort-By"] and msg.Tags["Sort-By"]
	return {
		cursor = cursor,
		limit = limit,
		sortBy = sortBy,
		sortOrder = sortOrder,
	}
end

function utils.sortTableByField(prevTable, field, order)
	local tableCopy = utils.deepCopy(prevTable)

	if order ~= "asc" and order ~= "desc" then
		error("Invalid sort order")
	end

	if not tableCopy or #tableCopy == 0 then
		return tableCopy
	end

	table.sort(tableCopy, function(a, b)
		if order == "asc" then
			return a[field] < b[field]
		else
			return a[field] > b[field]
		end
	end)
	return tableCopy
end

function utils.paginateTableWithCursor(tableArray, cursor, cursorField, limit, sortBy, sortOrder)
	local sortedTable = utils.sortTableByField(tableArray, sortBy, sortOrder)
	if not sortedTable or #sortedTable == 0 then
		return {
			items = {},
			limit = limit,
			totalItems = 0,
			totalPages = 0,
			sortBy = sortBy,
			sortOrder = sortOrder,
			nextCursor = nil,
		}
	end

	local startIndex = 1

	if cursor then
		for i, obj in ipairs(sortedTable) do
			if obj[cursorField] == cursor then
				startIndex = i + 1
				break
			end
		end
	end

	local items = {}
	local endIndex = math.min(startIndex + limit - 1, #sortedTable)

	for i = startIndex, endIndex do
		table.insert(items, sortedTable[i])
	end

	local nextCursor = nil
	if endIndex < #sortedTable then
		nextCursor = sortedTable[endIndex][cursorField]
	end

	return {
		items = items,
		limit = limit,
		totalItems = #sortedTable,
		totalPages = math.ceil(#sortedTable / limit),
		sortBy = sortBy,
		sortOrder = sortOrder,
		nextCursor = nextCursor,
	}
end

function utils.isValidArweaveAddress(address)
	return #address == 43 and string.match(address, "^[%w-_]+$") ~= nil
end

function utils.validateFQDN(fqdn)
	-- Check if the fqdn is not nil and not empty
	if not fqdn or fqdn == "" then
		error("FQDN is empty")
	end

	-- Split the fqdn into parts by dot and validate each part
	local parts = {}
	for part in fqdn:gmatch("[^%.]+") do
		table.insert(parts, part)
	end

	-- Validate each part of the domain
	for _, part in ipairs(parts) do
		-- Check that the part length is between 1 and 63 characters
		if #part < 1 or #part > 63 then
			error("Invalid fqdn format: each part must be between 1 and 63 characters")
		end
		-- Check that the part does not start or end with a hyphen
		if part:match("^-") or part:match("-$") then
			error("Invalid fqdn format: parts must not start or end with a hyphen")
		end
		-- Check that the part contains only alphanumeric characters and hyphen
		if not part:match("^[A-Za-z0-9-]+$") then
			error("Invalid fqdn format: parts must contain only alphanumeric characters or hyphen")
		end
	end

	-- Check if there is at least one top-level domain (TLD)
	if #parts < 2 then
		error("Invalid fqdn format: missing top-level domain")
	end

	return fqdn
end

function utils.findInArray(array, predicate)
	for i = 1, #array do
		if predicate(array[i]) then
			return i -- Return the index of the found element
		end
	end
	return nil -- Return nil if the element is not found
end

function utils.walletHasSufficientBalance(wallet, quantity)
	return Balances[wallet] ~= nil and Balances[wallet] >= quantity
end

function utils.copyTable(table)
	local copy = {}
	for key, value in pairs(table) do
		copy[key] = value
	end
	return copy
end

function utils.deepCopy(original)
	if not original then
		return nil
	end

	if type(original) ~= "table" then
		return original
	end

	local copy = {}
	for key, value in pairs(original) do
		if type(value) == "table" then
			copy[key] = utils.deepCopy(value) -- Recursively copy the nested table
		else
			copy[key] = value
		end
	end
	return copy
end

function utils.lengthOfTable(table)
	local count = 0
	for _ in pairs(table) do
		count = count + 1
	end
	return count
end
function utils.getHashFromBase64URL(str)
	local decodedHash = base64.decode(str, base64.URL_DECODER)
	local hashStream = crypto.utils.stream.fromString(decodedHash)
	return crypto.digest.sha2_256(hashStream).asBytes()
end

function utils.splitString(str, delimiter)
	local result = {}
	for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
		result[#result + 1] = match
	end
	return result
end

return utils
