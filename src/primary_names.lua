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
---@field requests table<WalletAddress, PrimaryNameRequest> - map indexed by owner address containing the request, used for pruning expired requests

PrimaryNames = PrimaryNames or {
	requests = {},
	names = {},
	owners = {},
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

---@class PrimaryNameRequest
---@field name ArNSName -- the name being requested
---@field baseName ArNSName -- the base name, identified when creating the name request
---@field initiator WalletAddress -- the process id that made the request
---@field startTimestamp number -- the timestamp of the request
---@field endTimestamp number -- the timestamp of the request expiration

--- Creates a transient request for a primary name. This is done by a user and must be approved by the name owner of the base name.
--- @param name string -- the name being requested, this could be an undername provided by the ant
--- @param initiator string -- the address that is creating the primary name request, e.g. the ANT process id
--- @param timestamp number -- the timestamp of the request
--- @return PrimaryNameRequest primaryNameRequest - the request created
function primaryNames.createPrimaryNameRequest(name, initiator, timestamp)
	local baseName = name:match("[^_]+$") or name

	--- existing request for primary name from wallet?
	local existingRequest = primaryNames.getPrimaryNameRequest(name)
	assert(not existingRequest, "Primary name request for '" .. name .. "' already exists") -- TODO: should we error here or just let them create a new request and pay the fee again?

	--- check the primary name is not already owned
	local primaryNameOwner = primaryNames.getAddressForPrimaryName(name)
	assert(not primaryNameOwner, "Primary name is already owned")

	local record = arns.getRecord(baseName)
	assert(record, "ArNS record '" .. baseName .. "' does not exist")

	--- TODO: replace with funding plan
	assert(balances.walletHasSufficientBalance(initiator, PRIMARY_NAME_COST), "Insufficient balance")

	--- transfer the primary name cost from the initiator to the treasury
	balances.transfer(ao.id, initiator, PRIMARY_NAME_COST)

	local request = {
		name = name,
		baseName = baseName,
		startTimestamp = timestamp,
		endTimestamp = timestamp + 7 * 24 * 60 * 60 * 1000, -- 7 days
	}
	PrimaryNames.requests[initiator] = request
	return request
end

--- Get a primary name request, safely deep copying the request
--- @param address string
--- @return PrimaryNameRequest|nil primaryNameClaim - the request found, or nil if it does not exist
function primaryNames.getPrimaryNameRequest(address)
	return utils.deepCopy(primaryNames.getUnsafePrimaryNameRequests()[address])
end

--- Unsafe access to the primary name requests
--- @return table<string, PrimaryNameRequest> primaryNameClaims - the primary name requests
function primaryNames.getUnsafePrimaryNameRequests()
	return PrimaryNames.requests or {}
end

function primaryNames.getUnsafePrimaryNames()
	return PrimaryNames.names or {}
end

--- Unsafe access to the primary name owners
--- @return table<string, PrimaryName> primaryNames - the primary names
function primaryNames.getUnsafePrimaryNameOwners()
	return PrimaryNames.owners or {}
end

--- Action taken by the owner of a primary name. This is who pays for the primary name.
--- @param recipient string -- the address that is requesting the primary name
--- @param from string -- the process id that is requesting the primary name for the owner
--- @param timestamp number -- the timestamp of the request
--- @return PrimaryNameWithOwner primaryNameWithOwner - the primary name with owner data
function primaryNames.approvePrimaryNameRequest(recipient, name, from, timestamp)
	local request = primaryNames.getPrimaryNameRequest(recipient)
	assert(request, "Primary name request not found")
	assert(request.endTimestamp > timestamp, "Primary name request has expired")

	-- assert the process id in the initial request still owns the name
	local record = arns.getRecord(request.baseName)
	assert(record, "ArNS record '" .. request.baseName .. "' does not exist")
	assert(record.processId == from, "Primary name request must be approved by the owner of the base name")

	-- assert the name matches the request
	assert(request.name == name, "Provided name does not match the primary name request")

	-- set the primary name
	local newPrimaryName = primaryNames.setPrimaryNameFromRequest(recipient, request, timestamp)
	return newPrimaryName
end

--- Update the primary name maps and return the primary name. Removes the request from the requests map.
--- @param recipient string -- the address that is requesting the primary name
--- @param request PrimaryNameRequest
--- @param startTimestamp number
--- @return PrimaryNameWithOwner primaryNameWithOwner - the primary name with owner data
function primaryNames.setPrimaryNameFromRequest(recipient, request, startTimestamp)
	PrimaryNames.names[request.name] = recipient
	PrimaryNames.owners[recipient] = {
		name = request.name,
		baseName = request.baseName,
		startTimestamp = startTimestamp,
	}
	PrimaryNames.requests[recipient] = nil
	return {
		name = request.name,
		owner = recipient,
		startTimestamp = startTimestamp,
		baseName = request.baseName,
		-- TODO: add base name owner if useful
	}
end

--- Remove primary names, returning the results of the name removals
--- @param names string[]
--- @param from string
--- @return RemovedPrimaryNameResult[] removedPrimaryNameResults - the results of the name removals
function primaryNames.removePrimaryNames(names, from)
	local removedPrimaryNamesAndOwners = {}
	for _, name in pairs(names) do
		local removedPrimaryNameAndOwner = primaryNames.removePrimaryName(name, from)
		table.insert(removedPrimaryNamesAndOwners, removedPrimaryNameAndOwner)
	end
	return removedPrimaryNamesAndOwners
end

--- @class RemovedPrimaryNameResult
--- @field owner WalletAddress
--- @field name ArNSName

--- Release a primary name
--- @param name ArNSName -- the name being released
--- @param from WalletAddress -- the address that is releasing the primary name, or the owner of the base name
--- @return RemovedPrimaryNameResult
function primaryNames.removePrimaryName(name, from)
	--- assert the from is the current owner of the name
	local primaryName = primaryNames.getPrimaryNameDataWithOwnerFromName(name)
	assert(primaryName, "Primary name '" .. name .. "' does not exist")
	local record = arns.getRecord(primaryName.baseName)
	assert(
		primaryName.owner == from or (record and record.processId == from),
		"Caller is not the owner of the primary name, or the owner of the " .. primaryName.baseName .. " record"
	)

	PrimaryNames.requests[name] = nil -- should never happen, but cleanup anyway
	PrimaryNames.names[name] = nil
	PrimaryNames.owners[primaryName.owner] = nil
	return {
		name = name,
		owner = primaryName.owner,
	}
end

--- Get the address for a primary name, allowing for forward lookups (e.g. "foo.bar" -> "0x123")
--- @param name string
--- @return WalletAddress|nil address - the address for the primary name, or nil if it does not exist
function primaryNames.getAddressForPrimaryName(name)
	return PrimaryNames.names[name]
end

--- Get the name data for an address, allowing for reverse lookups (e.g. "0x123" -> "foo.bar")
--- @param address string
--- @return PrimaryNameWithOwner|nil primaryNameWithOwner - the primary name with owner data, or nil if it does not exist
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
--- @return PrimaryNameWithOwner|nil primaryNameWithOwner - the primary name with owner data, or nil if it does not exist
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
--- @return PrimaryNameWithOwner[] primaryNamesForArNSName - the primary names with owner data
function primaryNames.getPrimaryNamesForBaseName(baseName)
	local primaryNamesForArNSName = {}
	for name, _ in pairs(primaryNames.getUnsafePrimaryNames()) do
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
--- @return RemovedPrimaryName[] removedPrimaryNames - the results of the name removals
function primaryNames.removePrimaryNamesForBaseName(baseName)
	local removedNames = {}
	local primaryNamesForBaseName = primaryNames.getPrimaryNamesForBaseName(baseName)
	for _, nameData in pairs(primaryNamesForBaseName) do
		local removedName = primaryNames.removePrimaryName(nameData.name, nameData.owner)
		table.insert(removedNames, removedName)
	end
	return removedNames
end

--- Get paginated primary names
--- @param cursor string|nil
--- @param limit number
--- @param sortBy string
--- @param sortOrder string
--- @return PaginatedTable<PrimaryNameWithOwner> paginatedPrimaryNames - the paginated primary names
function primaryNames.getPaginatedPrimaryNames(cursor, limit, sortBy, sortOrder)
	local primaryNamesArray = {}
	local cursorField = "name"
	for owner, primaryName in ipairs(primaryNames.getUnsafePrimaryNameOwners()) do
		table.insert(primaryNamesArray, {
			name = primaryName.name,
			owner = owner,
			startTimestamp = primaryName.startTimestamp,
		})
	end
	return utils.paginateTableWithCursor(primaryNamesArray, cursor, cursorField, limit, sortBy, sortOrder)
end

--- Prune expired primary name requests
--- @param timestamp number
--- @return table<string, PrimaryNameRequest> prunedNameClaims - the names of the requests that were pruned
function primaryNames.prunePrimaryNameRequests(timestamp)
	local prunedNameRequests = {}
	for name, request in pairs(primaryNames.getUnsafePrimaryNameRequests()) do
		if request.endTimestamp <= timestamp then
			PrimaryNames.requests[name] = nil
			prunedNameRequests[name] = request
		end
	end
	return prunedNameRequests
end

return primaryNames
