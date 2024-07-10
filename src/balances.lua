-- balances.lua
Balances = Balances or {}

-- Utility functions that modify global Balance object
local balances = {}
local utils = require("utils")

-- TODO: if we need to append state at all we would do it here on token

function balances.transfer(recipient, from, qty)
	assert(type(recipient) == "string", "Recipient is required!")
	assert(type(from) == "string", "From is required!")
	assert(type(qty) == "number", "Quantity is required and must be a number!")
	assert(utils.isInteger(qty), "Quantity must be an integer")

	balances.reduceBalance(from, qty)
	balances.increaseBalance(recipient, qty)

	return {
		[from] = Balances[from],
		[recipient] = Balances[recipient],
	}
end

function balances.getBalance(target)
	local balance = balances.getBalances()[target]
	return balance or 0
end

function balances.getBalances()
	local balances = utils.deepCopy(Balances)
	return balances or {}
end

function balances.reduceBalance(target, qty)
	local prevBalance = balances.getBalance(target) or 0
	if prevBalance < qty then
		error("Insufficient balance")
	end

	Balances[target] = prevBalance - qty
end

function balances.increaseBalance(target, qty)
	local prevBalance = balances.getBalance(target) or 0
	Balances[target] = prevBalance + qty
end

function balances.getPaginatedBalances(cursor, limit, sortBy, sortOrder)
	local balances = balances.getBalances()
	local balancesArray = {}
	local cursorField = "address" -- the cursor will be the wallet address
	for address, balance in pairs(balances) do
		table.insert(balancesArray, {
			address = address,
			balance = balance,
		})
	end

	return utils.paginateTableWithCursor(balancesArray, cursor, cursorField, limit, sortBy, sortOrder)
end

return balances
