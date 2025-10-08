-- hb.lua needs to be in its own file and not in balances.lua to avoid circular dependencies
local hb = {}

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

return hb
