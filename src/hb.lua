-- hb.lua needs to be in its own file and not in balances.lua to avoid circular dependencies
local hb = {}
local listen = require(".src.listen")

--[[
	Setup listeners to state changes here.
]]

-- Wrap PrimaryNames sub-tables with listeners that automatically track changes in HyperbeamSync
-- When you write: PrimaryNames.names[key] = value
-- It stores the value AND sets HyperbeamSync.primaryNames.names[key] = true
if not getmetatable(PrimaryNames.names) then
	PrimaryNames.names = listen.addListener(PrimaryNames.names, function(ctx)
		HyperbeamSync.primaryNames.names[ctx.key] = true
	end)
end
if not getmetatable(PrimaryNames.owners) then
	PrimaryNames.owners = listen.addListener(PrimaryNames.owners, function(ctx)
		HyperbeamSync.primaryNames.owners[ctx.key] = true
	end)
end
if not getmetatable(PrimaryNames.requests) then
	PrimaryNames.requests = listen.addListener(PrimaryNames.requests, function(ctx)
		HyperbeamSync.primaryNames.requests[ctx.key] = true
	end)
end

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

	-- if no changes, return early. This will allow downstream code to not send the patch state for this key ('primary-names')
	if
		next(HyperbeamSync.primaryNames.names) == nil
		and next(HyperbeamSync.primaryNames.owners) == nil
		and next(HyperbeamSync.primaryNames.requests) == nil
	then
		return nil
	end

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

	-- If PrimaryNames.<thing> is empty, send an empty table to clear hyperbeam state
	-- Otherwise, only include fields that have changes
	if next(PrimaryNames.names) == nil then
		affectedPrimaryNamesAddresses.names = {}
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
