local arns = require("arns")
local balances = require("balances")
local utils = require("utils")

PrimaryNames = PrimaryNames or {}

local PRIMARY_NAME_COST = 100000000 -- 100 IO
---@class PrimaryNames table<string, PrimaryName>

---@class PrimaryName
---@field name string
---@field startTimestamp number

---@class PrimaryNameWithOwner
---@field name string
---@field owner string
---@field startTimestamp number

local primaryNames = {}
--- Claim a primary name
--- @param name string -- the name being claimed, this could be an undername provided by the ant
--- @param newOwner string -- the new owner of the primary name
--- @param from string -- the process id that is claiming the primary name for the owner
--- @param timestamp number -- the timestamp of the claim
--- @return PrimaryName
function primaryNames.setPrimaryName(name, newOwner, from, timestamp)
	-- get the last part of the name after any underscores
	local apexName = name:match("[^_]+$") or name

	-- assert it's not already owned
	local existingOwner = primaryNames.findPrimaryNameOwner(name)
	assert(not existingOwner, "Primary name is already owned")

	-- check apex name exits on arns records, and the process id matches the from
	local arnsRecord = arns.getRecord(apexName)
	assert(arnsRecord, "ArNS record '" .. apexName .. "' does not exist")
	assert(arnsRecord.processId == from, "Process id does not match")

	-- validate the new owner has the balance to claim the name
	assert(
		balances.walletHasSufficientBalance(newOwner, PRIMARY_NAME_COST),
		"Insufficient balance to claim primary name"
	)

	PrimaryNames[newOwner] = {
		name = name,
		startTimestamp = timestamp,
	}
	return PrimaryNames[newOwner]
end

--- Find the owner of a primary name, returns nil if the name is not owned
--- @param name string  - the name to find the owner of
--- @return string|nil - the owner of the name, or nil if the name is not owned
function primaryNames.findPrimaryNameOwner(name)
	for owner, primaryName in pairs(PrimaryNames) do
		if primaryName.name == name then
			return owner
		end
	end
end

--- Release a primary name for the owner
--- @param from string - the wallet address releasing its primary name
--- @param name string - the name being released
--- @return PrimaryNameWithOwner
function primaryNames.releasePrimaryName(from, name)
	local existingOwner = primaryNames.findPrimaryNameOwner(name)
	local existingPrimaryName = utils.deepCopy(PrimaryNames[existingOwner])
	assert(existingOwner == from, "Primary name is not owned by " .. from)
	assert(existingPrimaryName, "Primary name is not owned and cannot be released")
	PrimaryNames[from] = nil
	return {
		name = existingPrimaryName.name,
		owner = existingOwner,
		startTimestamp = existingPrimaryName.startTimestamp,
	}
end

--- Get a primary name
--- @param name string
--- @return PrimaryNameWithOwner|nil
function primaryNames.getPrimaryName(name)
	local owner = primaryNames.findPrimaryNameOwner(name)
	if not owner then
		return nil
	end
	local primaryName = PrimaryNames[owner]
	if not primaryName then
		return nil
	end
	return {
		name = name,
		owner = owner,
		startTimestamp = primaryName.startTimestamp,
	}
end

--- Get a primary name for a given address
--- @param address string
--- @return PrimaryNameWithOwner|nil
function primaryNames.getPrimaryNameForAddress(address)
	local primaryName = utils.deepCopy(PrimaryNames[address])
	if not primaryName then
		return nil
	end
	return {
		name = primaryName.name,
		owner = address,
		startTimestamp = primaryName.startTimestamp,
	}
end

---Finds all primary names with a given apex name
--- @param apexName string
--- @return PrimaryNameWithOwner[]
function primaryNames.findPrimaryNamesWithApexName(apexName)
	local primaryNamesForApexName = {}
	local unsafePrimaryNames = PrimaryNames
	for owner, primaryName in pairs(unsafePrimaryNames) do
		local undername = primaryName.name
		if undername:match("_" .. apexName .. "$") or undername == apexName then
			table.insert(primaryNamesForApexName, {
				name = undername,
				owner = owner,
				startTimestamp = primaryName.startTimestamp,
			})
		end
	end
	-- sort by name length
	table.sort(primaryNamesForApexName, function(a, b)
		return #a.name < #b.name
	end)
	return primaryNamesForApexName
end

--- Remove all primary names with a given apex name
--- @param apexName string
--- @return string[]
function primaryNames.removePrimaryNamesWithApexName(apexName)
	local removedNames = {}
	local primaryNamesForApexName = primaryNames.findPrimaryNamesWithApexName(apexName)
	for _, nameForApexName in pairs(primaryNamesForApexName) do
		PrimaryNames[nameForApexName.owner] = nil
		table.insert(removedNames, nameForApexName.name)
	end
	return removedNames
end

--- Get paginated primary names
--- @param cursor string|nil
--- @param limit number
--- @param sortBy string
--- @param sortOrder string
--- @return PaginatedTable<PrimaryNameWithOwner>
function primaryNames.getPaginatedPrimaryNames(cursor, limit, sortBy, sortOrder)
	local primaryNamesArray = {}
	local cursorField = "name"
	for owner, primaryName in ipairs(PrimaryNames) do
		table.insert(primaryNamesArray, {
			name = primaryName.name,
			owner = owner,
			startTimestamp = primaryName.startTimestamp,
		})
	end
	return utils.paginateTableWithCursor(primaryNamesArray, cursor, cursorField, limit, sortBy, sortOrder)
end

return primaryNames
