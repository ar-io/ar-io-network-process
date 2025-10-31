-- hb.lua needs to be in its own file and not in balances.lua to avoid circular dependencies
local hb = {}

---@return table<string, string>|nil affectedBalancesAddresses table of addresses and their balance values as strings
function hb.createBalancesPatch()
	local affectedBalancesAddresses = {}
	for address, _ in pairs(Balances) do
		if HyperbeamSync.balances[address] ~= Balances[address] then
			affectedBalancesAddresses[address] = true
		end
	end

	for address, _ in pairs(HyperbeamSync.balances) do
		if Balances[address] ~= HyperbeamSync.balances[address] then
			affectedBalancesAddresses[address] = true
		end
	end

	--- For simplicity we always include the protocol balance in the patch message
	--- this also prevents us from sending an empty patch message and deleting the entire hyperbeam balances table
	affectedBalancesAddresses[ao.id] = true

	-- Convert all affected addresses from boolean flags to actual balance values
	local balancesPatch = {}
	for address, _ in pairs(affectedBalancesAddresses) do
		balancesPatch[address] = tostring(Balances[address] or 0)
	end

	if next(balancesPatch) == nil then
		return nil
	end

	return balancesPatch
end

---@return PrimaryNames|nil affectedPrimaryNamesAddresses
function hb.createPrimaryNamesPatch()
	---@type PrimaryNames
	local affectedPrimaryNamesAddresses = {
		names = {},
		owners = {},
		requests = {},
	}

	-- if no changes, return early. This will allow downstream code to not send the patch state for this key ('primary-names')
	if
		next(_G.HyperbeamSync.primaryNames.names) == nil
		and next(_G.HyperbeamSync.primaryNames.owners) == nil
		and next(_G.HyperbeamSync.primaryNames.requests) == nil
	then
		return nil
	end

	-- build the affected primary names addresses table for the patch message
	for name, _ in pairs(_G.HyperbeamSync.primaryNames.names) do
		-- we need to send an empty string to remove the name
		affectedPrimaryNamesAddresses.names[name] = PrimaryNames.names[name] or ""
	end
	for owner, _ in pairs(_G.HyperbeamSync.primaryNames.owners) do
		-- we need to send an empty table to remove the owner primary name data
		affectedPrimaryNamesAddresses.owners[owner] = PrimaryNames.owners[owner] or {}
	end
	for address, _ in pairs(_G.HyperbeamSync.primaryNames.requests) do
		-- we need to send an empty table to remove the request
		affectedPrimaryNamesAddresses.requests[address] = PrimaryNames.requests[address] or {}
	end

	-- Setting the property to {} will nuke the entire table from patch device state
	-- We do this because we want to remove the entire table from patch device state if it's empty
	if next(PrimaryNames.names) == nil then
		affectedPrimaryNamesAddresses.names = {}
	-- setting the property to nil will remove it from the patch message entirely to avoid sending an empty table and nuking patch device state
	-- We do this to AVOID sending an empty table and nuking patch device state if our lua state is not empty.
	elseif next(affectedPrimaryNamesAddresses.names) == nil then
		affectedPrimaryNamesAddresses.names = nil
	end

	if next(PrimaryNames.owners) == nil then
		affectedPrimaryNamesAddresses.owners = {}
	elseif next(affectedPrimaryNamesAddresses.owners) == nil then
		affectedPrimaryNamesAddresses.owners = nil
	end

	if next(PrimaryNames.requests) == nil then
		affectedPrimaryNamesAddresses.requests = {}
	elseif next(affectedPrimaryNamesAddresses.requests) == nil then
		affectedPrimaryNamesAddresses.requests = nil
	end

	-- if we're not sending any data, return nil which will allow downstream code to not send the patch message
	-- We do this to AVOID sending an empty table and nuking patch device state if our lua state is not empty.
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
	local patchMessageFields = {}

	-- Only add patches that have data
	local primaryNamesPatch = hb.createPrimaryNamesPatch()
	if primaryNamesPatch then
		patchMessageFields["primary-names"] = primaryNamesPatch
	end

	local balancesPatch = hb.createBalancesPatch()
	if balancesPatch then
		patchMessageFields["balances"] = balancesPatch
	end

	--- Send patch message if there are any patches
	if next(patchMessageFields) ~= nil then
		patchMessageFields.device = "patch@1.0"
		ao.send(patchMessageFields)
	end

	hb.resetHyperbeamSync()
end

return hb
