-- hb.lua needs to be in its own file and not in balances.lua to avoid circular dependencies
local hb = {}

function hb.deepEqual(val1, val2)
	-- If types are different, they're not equal
	if type(val1) ~= type(val2) then
		return false
	end

	-- If not tables, use simple equality
	if type(val1) ~= "table" then
		return val1 == val2
	end

	-- Both are tables, compare recursively
	-- Check if all keys in val1 have equal values in val2
	for key, value in pairs(val1) do
		if not hb.deepEqual(value, val2[key]) then
			return false
		end
	end

	-- Check if val2 has any keys that val1 doesn't have
	for key, _ in pairs(val2) do
		if val1[key] == nil then
			return false
		end
	end

	return true
end

---@param accumulator table<string, any>
---@param oldTable table<string, any>
---@param newTable table<string, any>
---@return table<string, any>
function hb.getTableChanges(accumulator, oldTable, newTable)
	for key, value in pairs(oldTable) do
		if not hb.deepEqual(newTable[key], value) then
			accumulator[key] = newTable[key]
		end
	end
	for key, value in pairs(newTable) do
		if not hb.deepEqual(oldTable[key], value) then
			accumulator[key] = value
		end
	end
	return accumulator
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

---@param oldPrimaryNames PrimaryNames
---@return PrimaryNames affectedPrimaryNamesAddresses
function hb.patchPrimaryNames(oldPrimaryNames)
	assert(type(oldPrimaryNames) == "table", "Old primary names must be a table")
	---@type PrimaryNames
	local affectedPrimaryNamesAddresses = {
		names = hb.getTableChanges({}, oldPrimaryNames.names, PrimaryNames.names),
		owners = hb.getTableChanges({}, oldPrimaryNames.owners, PrimaryNames.owners),
		requests = hb.getTableChanges({}, oldPrimaryNames.requests, PrimaryNames.requests),
	}

	local patchMessage = {
		device = "patch@1.0",
		["primary-names"] = affectedPrimaryNamesAddresses,
	}

	if next(patchMessage["primary-names"]) == nil then
		return {
			names = {},
			owners = {},
			requests = {},
		}
	else
		ao.send(patchMessage)
	end

	return affectedPrimaryNamesAddresses
end

return hb
