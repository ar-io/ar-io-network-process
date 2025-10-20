-- hb.lua needs to be in its own file and not in balances.lua to avoid circular dependencies
local hb = {}

--[[
	PrimaryNames changes are tracked AUTOMATICALLY via the listen module (see globals.lua).
	When you write: PrimaryNames.names[key] = value
	A listener automatically sets: HyperbeamSync.primaryNames.names[key] = true
	Same for owners and requests. No manual tracking needed in primary_names.lua!
]]

---@param oldBalances table<string, number> A table of addresses and their balances
---@return table<string, boolean> affectedBalancesAddresses table of addresses that have had balance changes
function hb.patchBalances(oldBalances)
	assert(type(oldBalances) == "table", "Old balances must be a table")
	local affectedBalancesAddresses = {}
	for address, _ in pairs(oldBalances) do
		if Balances[address] ~= oldBalances[address] then
			affectedBalancesAddresses[address] = true
		end
	end
	for address, _ in pairs(Balances) do
		if oldBalances[address] ~= Balances[address] then
			affectedBalancesAddresses[address] = true
		end
	end

	--- For simplicity we always include the protocol balance in the patch message
	--- this also prevents us from sending an empty patch message and deleting the entire hyperbeam balances table\

	local patchMessage = {
		device = "patch@1.0",
		balances = { [ao.id] = tostring(Balances[ao.id] or 0) },
	}
	for address, _ in pairs(affectedBalancesAddresses) do
		patchMessage.balances[address] = tostring(Balances[address] or 0)
	end

	-- only send the patch message if there are affected balances, otherwise we'll end up deleting the entire hyperbeam balances table
	if next(patchMessage.balances) == nil then
		return {}
	else
		ao.send(patchMessage)
	end

	return affectedBalancesAddresses
end

---@return PrimaryNames|nil affectedPrimaryNamesAddresses
function hb.createPrimaryNamesPatch()
	---@type PrimaryNames
	local affectedPrimaryNamesAddresses = {
		names = {},
		owners = {},
		requests = {},
	}

	print(HyperbeamSync)

	-- if no changes, return early. This will allow downstream code to not send the patch state for this key ('primary-names')
	if
		next(HyperbeamSync.primaryNames.names) == nil
		and next(HyperbeamSync.primaryNames.owners) == nil
		and next(HyperbeamSync.primaryNames.requests) == nil
	then
		return nil
	end

	print(PrimaryNames)

	-- build the affected primary names addresses table for the patch message
	for name, _ in pairs(HyperbeamSync.primaryNames.names) do
		-- we need to send an empty string to remove the name
		affectedPrimaryNamesAddresses.names[name] = PrimaryNames.names[name] or ""
	end
	for owner, _ in pairs(HyperbeamSync.primaryNames.owners) do
		-- we need to send an empty table to remove the owner primary name data
		affectedPrimaryNamesAddresses.owners[owner] = PrimaryNames.owners[owner] or {}
	end
	for address, _ in pairs(HyperbeamSync.primaryNames.requests) do
		-- we need to send an empty table to remove the request
		affectedPrimaryNamesAddresses.requests[address] = PrimaryNames.requests[address] or {}
	end

	local shouldSendEmptyNames = next(PrimaryNames.names) == nil
	local shouldSendEmptyOwners = next(PrimaryNames.owners) == nil
	local shouldSendEmptyRequests = next(PrimaryNames.requests) == nil

	-- if we're not sending any data, we need to remove the table from the patch message to not delete the entire primary names table
	--- with this ifelse pattern we are saying that if the global state for that key is empty, we can remove the data from the hyperbeam state
	--- by sending the empty table.
	---
	--- unlikely case for names and owners, but possible for requests
	if not shouldSendEmptyNames then
		affectedPrimaryNamesAddresses.names = nil
	elseif next(affectedPrimaryNamesAddresses.names) == nil then
		affectedPrimaryNamesAddresses.names = {}
	end
	if not shouldSendEmptyOwners then
		affectedPrimaryNamesAddresses.owners = nil
	elseif next(affectedPrimaryNamesAddresses.owners) == nil then
		affectedPrimaryNamesAddresses.owners = {}
	end

	if not shouldSendEmptyRequests then
		affectedPrimaryNamesAddresses.requests = nil
	elseif next(affectedPrimaryNamesAddresses.requests) == nil then
		affectedPrimaryNamesAddresses.requests = {}
	end

	-- if we're not sending any data, return nil which will allow downstream code to not send the patch message
	if next(affectedPrimaryNamesAddresses) == nil then
		return nil
	end

	return affectedPrimaryNamesAddresses
end

function hb.resetHyperbeamSync()
	HyperbeamSync = {
		balances = {},
		primaryNames = {
			names = {},
			owners = {},
			requests = {},
		},
	}
end

--[[
	1. Create the data patches
	2. Send the patch message if there are any data patches
	3. Reset the hyperbeam sync
]]
function hb.patchHyperbeamState()
	local patchMessageFields = {
		["primary-names"] = hb.createPrimaryNamesPatch(),
	}

	--- just seperating out the device field to make it easier to predicate on
	if next(patchMessageFields) ~= nil then
		patchMessageFields.device = "patch@1.0"
		ao.send(patchMessageFields)
	end

	hb.resetHyperbeamSync()
end

return hb
