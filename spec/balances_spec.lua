local balances = require("balances")

local testAddress1 = "test-this-is-valid-arweave-wallet-address-1"
local testAddress2 = "test-this-is-valid-arweave-wallet-address-2"
local testAddressEth = "0xFCAd0B19bB29D4674531d6f115237E16AfCE377c"
local unsafeAddress = "not-a-real-address"

describe("balances", function()
	before_each(function()
		_G.Balances = {
			[testAddress1] = 100,
		}
	end)

	it("should return the balance with getBalance", function()
		assert.are.equal(100, balances.getBalance(testAddress1))
	end)

	it("should transfer tokens", function()
		local result = balances.transfer(testAddress2, testAddress1, 100, false)
		assert.are.same(result[testAddress2], _G.Balances[testAddress2])
		assert.are.same(result[testAddress1], _G.Balances[testAddress1])
		assert.are.equal(100, _G.Balances[testAddress2])
		assert.are.equal(0, _G.Balances[testAddress1])
	end)

	it("should transfer tokens between Arweave and ETH addresses", function()
		local result = balances.transfer(testAddressEth, testAddress1, 100, false)
		assert.are.same(result[testAddressEth], _G.Balances[testAddressEth])
		assert.are.same(result[testAddress1], _G.Balances[testAddress1])
		assert.are.equal(100, _G.Balances[testAddressEth])
		assert.are.equal(0, _G.Balances[testAddress1])
	end)

	it("should fail when transferring to unsafe address and unsafe flag is true", function()
		local status, result = pcall(balances.transfer, unsafeAddress, testAddress1, 100, false)
		assert.is_false(status)
		assert.match("Invalid recipient", result)
		assert.are.equal(nil, _G.Balances[unsafeAddress])
		assert.are.equal(100, _G.Balances[testAddress1])
	end)

	it("should not fail when transferring to unsafe address and unsafe flag is false", function()
		local result = balances.transfer(unsafeAddress, testAddress1, 100, true)
		assert.are.same(result[unsafeAddress], _G.Balances[unsafeAddress])
		assert.are.same(result[testAddress1], _G.Balances[testAddress1])
		assert.are.equal(100, _G.Balances[unsafeAddress])
		assert.are.equal(0, _G.Balances[testAddress1])
	end)

	it("should error on insufficient balance", function()
		local status, result = pcall(balances.transfer, testAddress2, testAddress1, 101)
		assert.is_false(status)
		assert.match("Insufficient balance", result)
		assert.are.equal(nil, _G.Balances[testAddress2])
		assert.are.equal(100, _G.Balances[testAddress1])
	end)

	it("should error on insufficient balance (ETH)", function()
		local status, result = pcall(balances.transfer, testAddressEth, testAddress1, 101)
		assert.is_false(status)
		assert.match("Insufficient balance", result)
		assert.are.equal(nil, _G.Balances[testAddress2])
		assert.are.equal(100, _G.Balances[testAddress1])
	end)

	describe("getPaginatedBalances", function()
		it("should return paginated balances", function()
			local returnedBalances = balances.getPaginatedBalances(nil, 10, "balance", "desc")
			assert.are.same({
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
			}, returnedBalances)
		end)
	end)

	describe("batchTransfer", function()
		before_each(function()
			-- Reset balances table before each test
			_G.Balances = {}
		end)

		it("should transfer to multiple recipients correctly", function()
			_G.Balances[testAddress1] = 100

			local balanceIncreases = {
				[testAddress2] = 30, -- Bob
				[testAddressEth] = 20, -- Carol
			}

			local result = balances.batchTransfer(testAddress1, balanceIncreases, false)

			assert.are.equal(50, _G.Balances[testAddress1])
			assert.are.equal(30, _G.Balances[testAddress2])
			assert.are.equal(20, _G.Balances[testAddressEth])

			-- Validate that each recipient has the correct quantity,
			-- and that the 'from' value is *either* 70 or 50 depending on order, since Lua has non-deterministic table ordering
			local bob = result[testAddress2]
			local carol = result[testAddressEth]

			assert.are.equal(30, bob.recipient)
			assert.is_true(bob.from == 80 or bob.from == 70 or bob.from == 50)

			assert.are.equal(20, carol.recipient)
			assert.is_true(carol.from == 80 or carol.from == 70 or carol.from == 50)

			-- Validate that total sum still adds up correctly
			assert.are.equal(30 + 20, 100 - _G.Balances[testAddress1])
		end)

		it("should throw if sender does not have sufficient balance", function()
			_G.Balances[testAddress1] = 10

			local balanceIncreases = {
				[testAddress2] = 15,
			}

			local status, err = pcall(function()
				balances.batchTransfer(testAddress1, balanceIncreases, false)
			end)

			assert.is_false(status)
			assert.match("Insufficient balance", err)
		end)

		it("should throw if sender and recipient are the same", function()
			_G.Balances[testAddress1] = 100

			local balanceIncreases = {
				[testAddress1] = 10,
			}

			local status, err = pcall(function()
				balances.batchTransfer(testAddress1, balanceIncreases, false)
			end)

			assert.is_false(status)
			assert.match("Cannot transfer to self", err)
		end)

		it("should throw if balanceIncreases is not a table", function()
			local status, err = pcall(function()
				balances.batchTransfer(testAddress1, "not-a-table", false)
			end)

			assert.is_false(status)
			assert.match("balanceIncreases must be a table", err)
		end)

		it("should throw if sender is not a string", function()
			local status, err = pcall(function()
				balances.batchTransfer({}, {}, false)
			end)

			assert.is_false(status)
			assert.match("Sender address must be a string", err)
		end)
	end)
end)
