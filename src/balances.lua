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

function balances.getPaginatedBalances(page, pageSize, sortBy, sortOrder)
	local balances = balances.getBalances()
	local sortedBalances = {}
	for address, balance in pairs(balances) do
		table.insert(sortedBalances, {
			address = address,
			balance = balance,
		})
	end

	-- sort the records by the named
	table.sort(sortedBalances, function(recordA, recordB)
		local nameAString = recordA[sortBy]
		local nameBString = recordB[sortBy]

		if not nameAString or not nameBString then
			error(
				"Invalid sort by field, not every balance has field "
					.. sortBy
					.. " Comparing:"
					.. recordA.address
					.. " to "
					.. recordB.address
			)
		end

		if sortOrder == "desc" then
			nameAString, nameBString = nameBString, nameAString
		end
		return nameAString < nameBString
	end)

	return {
		items = utils.slice(sortedBalances, (page - 1) * pageSize + 1, page * pageSize),
		page = page,
		pageSize = pageSize,
		totalItems = #sortedBalances,
		totalPages = math.ceil(#sortedBalances / pageSize),
		sortBy = sortBy,
		sortOrder = sortOrder,
		hasNextPage = page * pageSize < #sortedBalances,
	}
end

return balances
