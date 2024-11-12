local arns = require("arns")
local balances = require("balances")
local utils = require("utils")

PrimaryNames = PrimaryNames or {}
PrimaryNameClaims = PrimaryNameClaims or {}

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

---@class PrimaryNameClaim
---@field name string -- the name being claimed
---@field recipient string -- the owner of the primary name the claim is for
---@field processId string -- the process id that made the claim
---@field startTimestamp number -- the timestamp of the claim
---@field endTimestamp number -- the timestamp of the claim expiration

--- Creates a transient claim for a primary name. This is done by the ANT process that owns the base name. The assigned owner of the name must claim it within 30 days.
--- @param name string -- the name being claimed, this could be an undername provided by the ant
--- @param recipient string -- the recipient of the primary name
--- @param from string -- the process id that is claiming the primary name for the owner
--- @param timestamp number -- the timestamp of the claim
--- @return PrimaryNameClaim
function primaryNames.createNameClaim(name, recipient, from, timestamp)
	local rootName = name:match("[^_]+$") or name

	--- check the primary name is not already owned
	--- TODO: this could be o(1) with a lookup table
	local primaryNameOwned = primaryNames.findPrimaryNameOwner(name)
	assert(not primaryNameOwned, "Primary name is already owned")

	local record = arns.getRecord(rootName)
	assert(record, "ArNS record '" .. rootName .. "' does not exist")
	assert(record.processId == from, "Caller is not the process id that owns the base name")

	--- TODO: should we allow overrides of existing name claims or throw an error? I favor allowing overrides, if the ant wants to modify an existing claim it jsut resubmits
	local claim = {
		name = name,
		recipient = recipient,
		processId = from,
		rootName = rootName,
		startTimestamp = timestamp,
		endTimestamp = timestamp + 30 * 24 * 60 * 60 * 1000, -- 30 days
	}
	PrimaryNameClaims[name] = claim
	return claim
end

--- Get a primary name claim
--- @param name string
--- @return PrimaryNameClaim|nil
function primaryNames.getPrimaryNameClaim(name)
	return utils.deepCopy(PrimaryNameClaims[name])
end

--- Action taken by the owner of a primary name. This is who pays for the primary name.
--- @param name string -- the name being claimed, this could be an undername provided by the ant
--- @param recipient string -- the process id that is claiming the primary name for the owner
--- @param timestamp number -- the timestamp of the claim
--- @return PrimaryName
function primaryNames.claimPrimaryName(name, recipient, timestamp)
	local claim = primaryNames.getPrimaryNameClaim(name)
	assert(claim, "Primary name claim for '" .. name .. "' does not exist")
	assert(claim.recipient == recipient, "Primary name claim for '" .. name .. "' is not for " .. recipient)
	assert(claim.endTimestamp > timestamp, "Primary name claim for '" .. name .. "' has expired")

	-- validate the owner has the balance to claim the name
	assert(
		balances.walletHasSufficientBalance(recipient, PRIMARY_NAME_COST),
		"Insufficient balance to claim primary name"
	)

	-- assert the process id in the initial claim still owns the name
	local record = arns.getRecord(name)
	assert(record, "ArNS record '" .. name .. "' does not exist")
	assert(record.processId == claim.processId, "Name is no longer owned by the process id that made the initial claim")

	-- transfer the primary name cost from the owner to the treasury
	balances.transfer(ao.id, recipient, PRIMARY_NAME_COST)

	local newPrimaryName = {
		name = name,
		startTimestamp = timestamp,
	}

	-- set the primary name
	PrimaryNames[recipient] = newPrimaryName
	return {
		primaryName = newPrimaryName,
		claim = claim,
	}
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
--- @param name string
--- @return PrimaryNameWithOwner[]
function primaryNames.findPrimaryNamesForArNSName(name)
	local primaryNamesForArNSName = {}
	local unsafePrimaryNames = PrimaryNames
	for owner, primaryName in pairs(unsafePrimaryNames) do
		local undername = primaryName.name
		if undername:match("_" .. name .. "$") or undername == name then
			table.insert(primaryNamesForArNSName, {
				name = undername,
				owner = owner,
				startTimestamp = primaryName.startTimestamp,
			})
		end
	end
	-- sort by name length
	table.sort(primaryNamesForArNSName, function(a, b)
		return #a.name < #b.name
	end)
	return primaryNamesForArNSName
end

--- Remove all primary names with a given apex name
--- @param name string
--- @return string[]
function primaryNames.removePrimaryNamesForArNSName(name)
	local removedNames = {}
	local primaryNamesForArNSName = primaryNames.findPrimaryNamesForArNSName(name)
	for _, nameForArNSName in pairs(primaryNamesForArNSName) do
		PrimaryNames[nameForArNSName.owner] = nil
		table.insert(removedNames, nameForArNSName.name)
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

--- Prune expired primary name claims
--- @param timestamp number
--- @return table<string, PrimaryNameClaim> the names of the claims that were pruned
function primaryNames.prunePrimaryNameClaims(timestamp)
	local prunedNameClaims = {}
	-- unsafe access to primary name claims
	for name, claim in pairs(PrimaryNameClaims) do
		if claim.endTimestamp <= timestamp then
			PrimaryNameClaims[name] = nil
			prunedNameClaims[name] = claim
		end
	end
	return prunedNameClaims
end

return primaryNames
