local utils = require(".src.utils")
local balances = {}

--- @alias mARIO number

--- Transfers tokens from one address to another
---@param recipient string The address to receive tokens
---@param from string The address sending tokens
---@param qty number The amount of tokens to transfer (must be integer)
---@param allowUnsafeAddresses boolean Whether to allow unsafe addresses
---@return table Updated balances for sender and recipient addresses
function balances.transfer(recipient, from, qty, allowUnsafeAddresses)
	assert(type(recipient) == "string", "Recipient is required!")
	assert(type(from) == "string", "From is required!")
	assert(from ~= recipient, "Cannot transfer to self")
	assert(utils.isValidAddress(recipient, allowUnsafeAddresses), "Invalid recipient")
	assert(type(qty) == "number", "Quantity is required and must be a number!")
	assert(recipient ~= from, "Cannot transfer to self")
	assert(utils.isInteger(qty), "Quantity must be an integer: " .. qty)
	assert(qty > 0, "Quantity must be greater than 0")

	balances.reduceBalance(from, qty)
	balances.increaseBalance(recipient, qty)

	return {
		[from] = Balances[from],
		[recipient] = Balances[recipient],
	}
end

--- Gets the balance for a specific address
---@param target WalletAddress The address to get balance for
---@return mARIO The balance amount (0 if address has no balance)
function balances.getBalance(target)
	return Balances[target] or 0
end

--- Gets a deep copy of all balances in the system
---@return table<WalletAddress, mARIO> # All address:balance pairs
function balances.getBalances()
	return utils.deepCopy(Balances) or {}
end

--- Gets all balances in the system
---@return table<WalletAddress, mARIO> # All address:balance pairs
function balances.getBalancesUnsafe()
	return Balances or {}
end

--- Reduces the balance of an address
---@param target string The address to reduce balance for
---@param qty number The amount to reduce by (must be integer)
---@throws error If target has insufficient balance
function balances.reduceBalance(target, qty)
	assert(balances.walletHasSufficientBalance(target, qty), "Insufficient balance")
	assert(qty > 0, "Quantity must be greater than 0")

	local prevBalance = balances.getBalance(target)
	Balances[target] = prevBalance - qty
end

--- Increases the balance of an address
--- @param target string The address to increase balance for
--- @param qty number The amount to increase by (must be integer)
function balances.increaseBalance(target, qty)
	assert(utils.isInteger(qty), "Quantity must be an integer: " .. qty)
	local prevBalance = balances.getBalance(target) or 0
	Balances[target] = prevBalance + qty
end

--- Gets paginated list of all balances
--- @param cursor string|nil The address to start from
--- @param limit number Max number of results to return
--- @param sortBy string|nil Field to sort by
--- @param sortOrder string "asc" or "desc" sort direction
--- @return table Array of {address, balance} objects
function balances.getPaginatedBalances(cursor, limit, sortBy, sortOrder)
	local allBalances = balances.getBalances()
	local balancesArray = {}
	local cursorField = "address" -- the cursor will be the wallet address
	for address, balance in pairs(allBalances) do
		table.insert(balancesArray, {
			address = address,
			balance = balance,
		})
	end

	return utils.paginateTableWithCursor(balancesArray, cursor, cursorField, limit, sortBy, sortOrder)
end

--- Checks if a wallet has a sufficient balance
--- @param wallet string The address of the wallet
--- @param quantity number The amount to check against the balance
--- @return boolean True if the wallet has a sufficient balance, false otherwise
function balances.walletHasSufficientBalance(wallet, quantity)
	return Balances[wallet] ~= nil and Balances[wallet] >= quantity
end

---@param oldBalances table<string, number> A table of addresses and their balances
---@param newBalances table<string, number> A table of addresses and their balances
---@return table<string, boolean> affectedBalancesAddresses table of addresses that have had balance changes
function balances.patchBalances(oldBalances, newBalances)
	assert(type(oldBalances) == "table", "Old balances must be a table")
	assert(type(newBalances) == "table", "New balances must be a table")
	local affectedBalancesAddresses = {}
	for address, _ in pairs(oldBalances) do
		if Balances[address] ~= oldBalances[address] then
			affectedBalancesAddresses[address] = true
		end
	end
	for address, _ in pairs(newBalances) do
		if oldBalances[address] ~= newBalances[address] then
			affectedBalancesAddresses[address] = true
		end
	end

	--- For simplicity we always include the protocol balance in the patch message
	--- this also prevents us from sending an empty patch message and deleting the entire hyperbeam balances table
	local patchMessage = { device = "patch@1.0", balances = { [ao.id] = Balances[ao.id] or 0 } }
	for address, _ in pairs(affectedBalancesAddresses) do
		patchMessage.balances[address] = Balances[address] or 0
	end

	-- only send the patch message if there are affected balances, otherwise we'll end up deleting the entire hyperbeam balances table
	if patchMessage.balances == {} then
		return {}
	else
		ao.send(patchMessage)
	end

	return affectedBalancesAddresses
end

return balances
