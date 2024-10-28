local base64 = require("base64")
local crypto = require("crypto.init")
local json = require("json")
local utils = {}

function utils.hasMatchingTag(tag, value)
	return Handlers.utils.hasMatchingTag(tag, value)
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

function utils.sumTableValues(tbl)
	local sum = 0
	for _, value in pairs(tbl) do
		sum = sum + value
	end
	return sum
end

function utils.slice(tbl, first, last, step)
	local sliced = {}

	for i = first or 1, last or #tbl, step or 1 do
		sliced[#sliced + 1] = tbl[i]
	end

	return sliced
end

function utils.parsePaginationTags(msg)
	local cursor = msg.Tags.Cursor
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
		local aField = a[field]
		local bField = b[field]
		-- If one field is nil, ensure it goes to the end
		if aField == nil and bField ~= nil then
			return false
		elseif aField ~= nil and bField == nil then
			return true
		elseif aField == nil and bField == nil then
			-- If both fields are nil, consider them equal
			return false
		end

		if order == "asc" then
			return aField < bField
		else
			return aField > bField
		end
	end)
	return tableCopy
end

function utils.paginateTableWithCursor(tableArray, cursor, cursorField, limit, sortBy, sortOrder)
	local sortedArray = utils.sortTableByField(tableArray, sortBy, sortOrder)

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
			if obj[cursorField] == cursor then
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
		nextCursor = sortedArray[endIndex][cursorField]
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

function utils.isValidArweaveAddress(address)
	return type(address) == "string" and #address == 43 and string.match(address, "^[%w-_]+$") ~= nil
end

function utils.isValidEthAddress(address)
	return type(address) == "string" and #address == 42 and string.match(address, "^0x[%x]+$") ~= nil
end

function utils.isValidAOAddress(url)
	return utils.isValidArweaveAddress(url) or utils.isValidEthAddress(url)
end

-- Convert address to EIP-55 checksum format
-- assumes address has been validated as a valid Ethereum address (see utils.isValidEthAddress)
-- Reference: https://eips.ethereum.org/EIPS/eip-55
function utils.formatEIP55Address(address)
	local hex = string.lower(string.sub(address, 3))

	local hash = crypto.digest.keccak256(hex)
	local hashHex = hash.asHex()

	local checksumAddress = "0x"

	for i = 1, #hashHex do
		local hexChar = string.sub(hashHex, i, i)
		local hexCharValue = tonumber(hexChar, 16)
		local char = string.sub(hex, i, i)
		if hexCharValue > 7 then
			char = string.upper(char)
		end
		checksumAddress = checksumAddress .. char
	end

	return checksumAddress
end

function utils.formatAddress(address)
	if utils.isValidEthAddress(address) then
		return utils.formatEIP55Address(address)
	end
	return address
end

function utils.safeDecodeJson(jsonString)
	if not jsonString then
		return nil
	end
	local status, result = pcall(json.decode, jsonString)
	if not status then
		print("Failed to decode JSON: " .. jsonString)
		return nil
	end
	return result
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
	for _, val in pairs(table) do
		if val then
			count = count + 1
		end
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

function utils.checkAndConvertTimestamptoMs(timestamp)
	-- Check if the timestamp is an integer
	if type(timestamp) ~= "number" or timestamp % 1 ~= 0 then
		return error("Timestamp must be an integer")
	end

	-- Define the plausible range for Unix timestamps in seconds
	local min_timestamp = 0
	local max_timestamp = 4102444800 -- Corresponds to 2100-01-01

	if timestamp >= min_timestamp and timestamp <= max_timestamp then
		-- The timestamp is already in seconds, convert it to milliseconds
		return timestamp * 1000
	end

	-- If the timestamp is outside the range for seconds, check for milliseconds
	local min_timestamp_ms = min_timestamp * 1000
	local max_timestamp_ms = max_timestamp * 1000

	if timestamp >= min_timestamp_ms and timestamp <= max_timestamp_ms then
		return timestamp
	end

	return error("Timestamp is out of range")
end

function utils.reduce(tbl, fn, init)
	local acc = init
	for k, v in pairs(tbl) do
		acc = fn(acc, k, v)
	end
	return acc
end

function utils.map(tbl, fn)
	local newTbl = {}
	for k, v in pairs(tbl) do
		newTbl[k] = fn(k, v)
	end
	return newTbl
end

function utils.toTrainCase(str)
	-- Replace underscores and spaces with hyphens
	str = str:gsub("[_%s]+", "-")

	-- Handle camelCase and PascalCase by adding a hyphen before uppercase letters that follow lowercase letters
	str = str:gsub("(%l)(%u)", "%1-%2")

	-- Capitalize the first letter of every word (after hyphen) and convert to Train-Case
	str = str:gsub("(%a)([%w]*)", function(first, rest)
		-- If the word is all uppercase (like "GW"), preserve it
		if first:upper() == first and rest:upper() == rest then
			return first:upper() .. rest
		else
			return first:upper() .. rest:lower()
		end
	end)
	return str
end

return utils
