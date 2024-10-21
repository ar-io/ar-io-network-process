local balances = require("balances")

local testAddress1 = "test-this-is-valid-arweave-wallet-address-1"
local testAddress2 = "test-this-is-valid-arweave-wallet-address-2"
local testAddressEth = "0xFCAd0B19bB29D4674531d6f115237E16AfCE377c"

describe("balances", function()
	before_each(function()
		_G.Balances = {
			[testAddress1] = 100,
		}
	end)

	it("should transfer tokens", function()
		local status, result = pcall(balances.transfer, testAddress2, testAddress1, 100)
		assert.is_true(status)
		assert.are.same(result[testAddress2], balances.getBalance(testAddress2))
		assert.are.same(result[testAddress1], balances.getBalance(testAddress1))
		assert.are.equal(100, balances.getBalance(testAddress2))
		assert.are.equal(0, balances.getBalance(testAddress1))
	end)

	it("should transfer tokens between Arweave and ETH addresses", function()
		local status, result = pcall(balances.transfer, testAddressEth, testAddress1, 100)
		assert.is_true(status)
		assert.are.same(result[testAddressEth], balances.getBalance(testAddressEth))
		assert.are.same(result[testAddress1], balances.getBalance(testAddress1))
		assert.are.equal(100, balances.getBalance(testAddressEth))
		assert.are.equal(0, balances.getBalance(testAddress1))
	end)

	it("should error on insufficient balance", function()
		local status, result = pcall(balances.transfer, testAddress2, testAddress1, 101)
		assert.is_false(status)
		assert.match("Insufficient balance", result)
		assert.are.equal(0, balances.getBalance(testAddress2))
		assert.are.equal(100, balances.getBalance(testAddress1))
	end)

	it("should error on insufficient balance (ETH)", function()
		local status, result = pcall(balances.transfer, testAddressEth, testAddress1, 101)
		assert.is_false(status)
		assert.match("Insufficient balance", result)
		assert.are.equal(0, balances.getBalance(testAddress2))
		assert.are.equal(100, balances.getBalance(testAddress1))
	end)

	describe("getPaginatedBalances", function()
		it("should return paginated balances", function()
			local balances = balances.getPaginatedBalances(nil, 10, "balance", "desc")
			assert.are.same(balances, {
				limit = 10,
				sortBy = "balance",
				sortOrder = "desc",
				hasMore = false,
				totalItems = 1,
				items = {
					{
						address = testAddress1,
						balance = 100,
					},
				},
			})
		end)
	end)
end)
