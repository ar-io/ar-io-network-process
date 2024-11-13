local arns = require("arns")
local balances = require("balances")
local utils = require("utils")
local primaryNames = {}

local PRIMARY_NAME_COST = 100000000 -- 100 IO

---@alias WalletAddress string
---@alias ArNSName string

---@class PrimaryNames
---@field owners table<WalletAddress, PrimaryName> - map indexed by owner address containing the primary name and all metadata, used for reverse lookups
---@field names table<ArNSName, WalletAddress> - map indexed by primary name containing the owner address, used for reverse lookups
---@field claims table<ArNSName, PrimaryNameClaim> - map indexed by primary name containing the claim, used for pruning expired claims

PrimaryNames = PrimaryNames or {
	owners = {},
	names = {},
	claims = {},
}

---@class PrimaryName
---@field name ArNSName
---@field baseName ArNSName
---@field startTimestamp number

---@class PrimaryNameWithOwner
---@field name ArNSName
---@field baseName ArNSName
---@field owner WalletAddress
---@field startTimestamp number

---@class PrimaryNameClaim
---@field name ArNSName -- the name being claimed
---@field baseName ArNSName -- the base name, identified when creating the name claim
---@field recipient WalletAddress -- the owner of the primary name the claim is for
---@field initiator WalletAddress -- the process id that made the claim
---@field startTimestamp number -- the timestamp of the claim
---@field endTimestamp number -- the timestamp of the claim expiration

--- Creates a transient claim for a primary name. This is done by the ANT process that owns the base name. The assigned owner of the name must claim it within 30 days.
--- @param name string -- the name being claimed, this could be an undername provided by the ant
--- @param recipient string -- the recipient of the primary name
--- @param initiator string -- the address that is creating the primary name claim, e.g. the ANT process id
--- @param timestamp number -- the timestamp of the claim
--- @return PrimaryNameClaim
function primaryNames.createNameClaim(name, recipient, initiator, timestamp)
	local baseName = name:match("[^_]+$") or name

	--- check the primary name is not already owned
	--- TODO: this could be o(1) with a lookup table
	local primaryNameOwner = primaryNames.getAddressForPrimaryName(baseName)
	assert(not primaryNameOwner, "Primary name is already owned")

	local record = arns.getRecord(baseName)
	assert(record, "ArNS record '" .. baseName .. "' does not exist")
	assert(record.processId == initiator, "Caller is not the process id that owns the base name")

	--- TODO: should we allow overrides of existing name claims or throw an error? I favor allowing overrides, if the ant wants to modify an existing claim it jsut resubmits
	local claim = {
		name = name,
		recipient = recipient,
		initiator = initiator,
		baseName = baseName,
		startTimestamp = timestamp,
		endTimestamp = timestamp + 30 * 24 * 60 * 60 * 1000, -- 30 days
	}
	PrimaryNames.claims[name] = claim
	return claim
end

--- Get a primary name claim
--- @param name string
--- @return PrimaryNameClaim|nil
function primaryNames.getPrimaryNameClaim(name)
	return utils.deepCopy(PrimaryNames.claims[name])
end

---@class ClaimPrimaryNameResult
---@field primaryName PrimaryNameWithOwner
---@field claim PrimaryNameClaim

--- Action taken by the owner of a primary name. This is who pays for the primary name.
--- @param name string -- the name being claimed, this could be an undername provided by the ant
--- @param from string -- the process id that is claiming the primary name for the owner
--- @param timestamp number -- the timestamp of the claim
--- @return ClaimPrimaryNameResult
function primaryNames.claimPrimaryName(name, from, timestamp)
	local claim = primaryNames.getPrimaryNameClaim(name)
	assert(claim, "Primary name claim for '" .. name .. "' does not exist")
	assert(claim.recipient == from, "Primary name claim for '" .. name .. "' is not for " .. from)
	assert(claim.endTimestamp > timestamp, "Primary name claim for '" .. name .. "' has expired")

	-- validate the owner has the balance to claim the name
	assert(balances.walletHasSufficientBalance(from, PRIMARY_NAME_COST), "Insufficient balance to claim primary name")

	-- assert the process id in the initial claim still owns the name
	local record = arns.getRecord(name)
	assert(record, "ArNS record '" .. name .. "' does not exist")
	assert(record.processId == claim.initiator, "Name is no longer owned by the address that made the initial claim")

	-- transfer the primary name cost from the owner to the treasury
	-- TODO: apply funding sources here
	balances.transfer(ao.id, from, PRIMARY_NAME_COST)

	-- set the primary name
	local newPrimaryName = primaryNames.setPrimaryNameFromClaim(from, claim, timestamp)
	return {
		primaryName = newPrimaryName,
		claim = claim,
	}
end

--- Update the primary name maps and return the primary name. Removes the claim from the claims map.
--- @param owner string
--- @param claim PrimaryNameClaim
--- @param startTimestamp number
--- @return PrimaryNameWithOwner
function primaryNames.setPrimaryNameFromClaim(owner, claim, startTimestamp)
	PrimaryNames.names[claim.name] = owner
	PrimaryNames.owners[owner] = {
		name = claim.name,
		baseName = claim.baseName,
		startTimestamp = startTimestamp,
	}
	PrimaryNames.claims[claim.name] = nil
	return {
		name = claim.name,
		owner = owner,
		startTimestamp = startTimestamp,
		baseName = claim.baseName,
	}
end

--- Remove primary names
--- @param names string[]
--- @param from string
--- @return RemovedPrimaryNameResult[]
function primaryNames.removePrimaryNames(names, from)
	local removedPrimaryNamesAndOwners = {}
	for _, name in pairs(names) do
		local removedPrimaryNameAndOwner = primaryNames.removePrimaryName(name, from)
		table.insert(removedPrimaryNamesAndOwners, removedPrimaryNameAndOwner)
	end
	return removedPrimaryNamesAndOwners
end

--- @class RemovedPrimaryNameResult
--- @field releasedName PrimaryName
--- @field releasedOwner WalletAddress

--- Release a primary name
--- @param name ArNSName -- the name being released
--- @param from WalletAddress -- the address that is releasing the primary name, or the owner of the base name
--- @return RemovedPrimaryNameResult
function primaryNames.removePrimaryName(name, from)
	--- assert the from is the current owner of the name
	local primaryName = primaryNames.getPrimaryNameDataWithOwnerFromName(name)
	assert(primaryName, "Primary name '" .. name .. "' does not exist")
	assert(
		primaryName.owner == from or arns.getRecord(primaryName.baseName).processId == from,
		"Caller is not the owner of the primary name, or the owner of the " .. primaryName.baseName .. " record"
	)

	PrimaryNames.claims[name] = nil -- should never happen, but cleanup anyway
	PrimaryNames.names[name] = nil
	PrimaryNames.owners[primaryName.owner] = nil
	return {
		name = name,
		owner = primaryName.owner,
	}
end

--- Get the address for a primary name, allowing for forward lookups (e.g. "foo.bar" -> "0x123")
--- @param name string
--- @return string
function primaryNames.getAddressForPrimaryName(name)
	return PrimaryNames.names[name]
end

--- Get the name data for an address, allowing for reverse lookups (e.g. "0x123" -> "foo.bar")
--- @param address string
--- @return PrimaryNameWithOwner|nil
function primaryNames.getPrimaryNameDataWithOwnerFromAddress(address)
	local nameData = PrimaryNames.owners[address]
	if not nameData then
		return nil
	end
	return {
		owner = address,
		name = nameData.name,
		startTimestamp = nameData.startTimestamp,
		baseName = nameData.baseName,
	}
end

--- Complete name resolution, returning the owner and name data for a name
--- @param name string
--- @return PrimaryNameWithOwner|nil
function primaryNames.getPrimaryNameDataWithOwnerFromName(name)
	local owner = primaryNames.getAddressForPrimaryName(name)
	local nameData = primaryNames.getPrimaryNameDataWithOwnerFromAddress(owner)
	if not owner or not nameData then
		return nil
	end
	return {
		name = name,
		owner = owner,
		startTimestamp = nameData.startTimestamp,
		baseName = nameData.baseName,
	}
end

---Finds all primary names with a given base  name
--- @param baseName string -- the base name to find primary names for (e.g. "test" to find "undername_test")
--- @return PrimaryNameWithOwner[]
function primaryNames.getPrimaryNamesForBaseName(baseName)
	local primaryNamesForArNSName = {}
	local unsafePrimaryNames = PrimaryNames.names -- TODO: unsafe copy
	for name, _ in pairs(unsafePrimaryNames) do
		local nameData = primaryNames.getPrimaryNameDataWithOwnerFromName(name)
		if nameData and nameData.baseName == baseName then
			table.insert(primaryNamesForArNSName, nameData)
		end
	end
	-- sort by name length
	table.sort(primaryNamesForArNSName, function(a, b)
		return #a.name < #b.name
	end)
	return primaryNamesForArNSName
end

---@class RemovedPrimaryName
---@field owner WalletAddress
---@field name ArNSName

--- Remove all primary names with a given base  name
--- @param baseName string
--- @return RemovedPrimaryName[]
function primaryNames.removePrimaryNamesForBaseName(baseName)
	local removedNames = {}
	local primaryNamesForBaseName = primaryNames.getPrimaryNamesForBaseName(baseName)
	for _, nameData in pairs(primaryNamesForBaseName) do
		local removedName = primaryNames.removePrimaryName(nameData.name, nameData.owner)
		table.insert(removedNames, removedName)
	end
	return removedNames
end

--- Revoke claims created by a given process id
--- @param initiator string -- the process id to revoke claims for, validated against the initiator of the claims
--- @param names string[] -- the names to revoke claims for, if nil all claims for the initiator will be revoked
--- @return PrimaryNameClaim[]
function primaryNames.revokeClaimsForInitiator(initiator, names)
	local revokedClaims = {}
	names = names or utils.keys(PrimaryNames.claims)
	for _, name in pairs(names) do
		local claim = utils.deepCopy(PrimaryNames.claims[name])
		if claim and claim.initiator == initiator then
			PrimaryNames.claims[name] = nil
			table.insert(revokedClaims, claim)
		end
	end
	return revokedClaims
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
	for owner, primaryName in ipairs(PrimaryNames.owners) do
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
	local unsafeClaims = PrimaryNames.claims or {} -- unsafe access to primary name claims
	for name, claim in pairs(unsafeClaims) do
		if claim.endTimestamp <= timestamp then
			PrimaryNames.claims[name] = nil
			prunedNameClaims[name] = claim
		end
	end
	return prunedNameClaims
end

return primaryNames
