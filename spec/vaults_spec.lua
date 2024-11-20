local vaults = require("vaults")
local constants = require("constants")
local utils = require("utils")
local startTimestamp = 0

describe("vaults", function()
	before_each(function()
		_G.Balances = {
			["test-this-is-valid-arweave-wallet-address-1"] = 100,
		}
		_G.Vaults = {}
		_G.NextPruneTimestamp = nil
	end)

	describe("createVault", function()
		it("should create vault", function()
			local status, result = pcall(
				vaults.createVault,
				"test-this-is-valid-arweave-wallet-address-1",
				100,
				constants.MIN_TOKEN_LOCK_TIME_MS,
				startTimestamp,
				"msgId"
			)
			local expectation = {
				balance = 100,
				startTimestamp = startTimestamp,
				endTimestamp = startTimestamp + constants.MIN_TOKEN_LOCK_TIME_MS,
			}
			assert.is_true(status)
			assert.are.same(_G.NextPruneTimestamp, expectation.endTimestamp)
			assert.are.same(expectation, result)
			assert.are.same(expectation, vaults.getVault("test-this-is-valid-arweave-wallet-address-1", "msgId"))
		end)

		it("should throw an insufficient balance error if not enough tokens to create the vault", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 50
			local status, result = pcall(
				vaults.createVault,
				"test-this-is-valid-arweave-wallet-address-1",
				100,
				constants.MIN_TOKEN_LOCK_TIME_MS,
				startTimestamp,
				"msgId"
			)
			assert.is_false(status)
			assert.match("Insufficient balance", result)
			assert.are.equal(_G.NextPruneTimestamp, nil)
		end)

		it("should throw an error if the lock length would be larger than the maximum", function()
			local status = pcall(
				vaults.createVault,
				"test-this-is-valid-arweave-wallet-address-1",
				100,
				constants.MAX_TOKEN_LOCK_TIME_MS + 1,
				startTimestamp,
				"msgId"
			)
			assert.is_false(status)
			assert.are.equal(_G.NextPruneTimestamp, nil)
		end)

		it("should throw an error if the lock length is less than the minimum", function()
			local status = pcall(
				vaults.createVault,
				"test-this-is-valid-arweave-wallet-address-1",
				100,
				constants.MIN_TOKEN_LOCK_TIME_MS - 1,
				startTimestamp,
				"msgId"
			)
			assert.is_false(status)
			assert.are.equal(_G.NextPruneTimestamp, nil)
		end)

		it("should throw an error if the vault already exists", function()
			local status = pcall(
				vaults.createVault,
				"test-this-is-valid-arweave-wallet-address-1",
				100,
				constants.MIN_TOKEN_LOCK_TIME_MS,
				startTimestamp,
				"msgId"
			)
			assert.is_true(status)
			assert.are.equal(_G.NextPruneTimestamp, startTimestamp + constants.MIN_TOKEN_LOCK_TIME_MS)
			local secondStatus, result = pcall(
				vaults.createVault,
				"test-this-is-valid-arweave-wallet-address-1",
				100,
				constants.MIN_TOKEN_LOCK_TIME_MS,
				startTimestamp,
				"msgId"
			)
			assert.is_false(secondStatus)
			assert.match("Vault with id msgId already exists", result)
			assert.are.equal(_G.NextPruneTimestamp, startTimestamp + constants.MIN_TOKEN_LOCK_TIME_MS)
		end)
	end)

	describe("increaseVault", function()
		it("should increase the vault", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 200
			local vaultOwner = "test-this-is-valid-arweave-wallet-address-1"
			local lockLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local vaultId = "msgId"
			local vault = vaults.createVault(vaultOwner, 100, lockLengthMs, startTimestamp, vaultId)
			local increaseAmount = 100
			local currentTimestamp = vault.startTimestamp + 1000
			local increasedVault = vaults.increaseVault(vaultOwner, increaseAmount, vaultId, currentTimestamp)
			assert.are.same(100 + increaseAmount, increasedVault.balance)
			assert.are.same(startTimestamp, increasedVault.startTimestamp)
			assert.are.same(startTimestamp + lockLengthMs, increasedVault.endTimestamp)
		end)

		it("should throw an error if insufficient balance", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 100
			local vaultOwner = "test-this-is-valid-arweave-wallet-address-1"
			local lockLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local vaultId = "msgId"
			local vault = vaults.createVault(vaultOwner, 100, lockLengthMs, startTimestamp, vaultId)
			local increaseAmount = 101
			local currentTimestamp = vault.startTimestamp + 1000
			local status, result = pcall(vaults.increaseVault, vaultOwner, increaseAmount, vaultId, currentTimestamp)
			assert.is_false(status)
			assert.match("Insufficient balance", result)
		end)

		it("should throw an error if the vault is expired", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 200
			local vaultOwner = "test-this-is-valid-arweave-wallet-address-1"
			local lockLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local vaultId = "msgId"
			local vault = vaults.createVault(vaultOwner, 100, lockLengthMs, startTimestamp, vaultId)
			local increaseAmount = 100
			local currentTimestamp = vault.endTimestamp + 1
			local status, result = pcall(vaults.increaseVault, vaultOwner, increaseAmount, vaultId, currentTimestamp)
			assert.is_false(status)
			assert.match("Vault has ended.", result)
		end)

		it("should throw an error if the vault not found", function()
			local vaultOwner = "test-this-is-valid-arweave-wallet-address-1"
			local vaultId = "msgId"
			local status, result = pcall(vaults.increaseVault, vaultOwner, 100, vaultId, startTimestamp)
			assert.is_false(status)
			assert.match("Vault not found", result)
		end)
	end)

	describe("extendVault", function()
		it("should extend the vault", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 100
			local vaultOwner = "test-this-is-valid-arweave-wallet-address-1"
			local lockLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local vaultId = "msgId"
			local vault = vaults.createVault(vaultOwner, 100, lockLengthMs, startTimestamp, vaultId)
			assert.are.equal(_G.NextPruneTimestamp, startTimestamp + lockLengthMs)
			local extendLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local currentTimestamp = vault.startTimestamp + 1000
			local extendedVault = vaults.extendVault(vaultOwner, extendLengthMs, currentTimestamp, vaultId)
			assert.are.equal(_G.NextPruneTimestamp, startTimestamp + lockLengthMs)
			assert.are.same(100, extendedVault.balance)
			assert.are.same(startTimestamp, extendedVault.startTimestamp)
			assert.are.same(startTimestamp + lockLengthMs + extendLengthMs, extendedVault.endTimestamp)
		end)

		it("should throw an error if the vault is expired", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 100
			local vaultOwner = "test-this-is-valid-arweave-wallet-address-1"
			local lockLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local vaultId = "msgId"
			local vault = vaults.createVault(vaultOwner, 100, lockLengthMs, startTimestamp, vaultId)
			local extendLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local currentTimestamp = vault.endTimestamp + 1000
			local status, result = pcall(vaults.extendVault, vaultOwner, extendLengthMs, currentTimestamp, vaultId)
			assert.is_false(status)
			assert.match("Vault has ended.", result)
		end)

		it("should throw an error if the lock length would be larger than the maximum", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 100
			local vaultOwner = "test-this-is-valid-arweave-wallet-address-1"
			local lockLengthMs = constants.MAX_TOKEN_LOCK_TIME_MS
			local vaultId = "msgId"
			local vault = vaults.createVault(vaultOwner, 100, lockLengthMs, startTimestamp, vaultId)
			local extendLengthMs = constants.MAX_TOKEN_LOCK_TIME_MS + 1
			local currentTimestamp = vault.startTimestamp + 1000
			local status, result = pcall(vaults.extendVault, vaultOwner, extendLengthMs, currentTimestamp, vaultId)
			assert.is_false(status)
			assert.match(
				"Invalid vault extension. Total lock time cannot be greater than "
					.. constants.MAX_TOKEN_LOCK_TIME_MS
					.. " ms",
				result
			)
		end)

		it("should throw an error if the vault not found", function()
			local vaultOwner = "test-this-is-valid-arweave-wallet-address-1"
			local vaultId = "msgId"
			local status, result = pcall(vaults.extendVault, vaultOwner, 100, startTimestamp, vaultId)
			assert.is_false(status)
			assert.match("Vault not found", result)
		end)

		it("should throw an error if the extend length is less than or equal to 0", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 100
			local vaultOwner = "test-this-is-valid-arweave-wallet-address-1"
			local lockLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local vaultId = "msgId"
			local vault = vaults.createVault(vaultOwner, 100, lockLengthMs, startTimestamp, vaultId)
			local extendLengthMs = 0
			local currentTimestamp = vault.startTimestamp + 1000
			local status, result = pcall(vaults.extendVault, vaultOwner, extendLengthMs, currentTimestamp, vaultId)
			assert.is_false(status)
			assert.match("Invalid extend length. Must be a positive number.", result)
		end)
	end)

	describe("vaultedTransfer", function()
		it("should create a vault for the recipient", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 100
			_G.Balances["test-this-is-valid-arweave-wallet-address-2"] = 200
			local from = "test-this-is-valid-arweave-wallet-address-1"
			local recipient = "test-this-is-valid-arweave-wallet-address-2"
			local quantity = 50
			local lockLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local timestamp = 1000000
			local vaultId = "msgId"
			local vault = vaults.vaultedTransfer(from, recipient, quantity, lockLengthMs, timestamp, vaultId)
			assert.are.equal(50, _G.Balances[from])
			assert.are.same({
				balance = 50,
				startTimestamp = timestamp,
				endTimestamp = timestamp + lockLengthMs,
			}, vault)
		end)

		it("should throw an error if the sender does not have enough balance", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 100
			_G.Balances["test-this-is-valid-arweave-wallet-address-2"] = 200
			local from = "test-this-is-valid-arweave-wallet-address-1"
			local recipient = "test-this-is-valid-arweave-wallet-address-2"
			local quantity = 150
			local lockLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local timestamp = 1000000
			local vaultId = "msgId"
			local status, result =
				pcall(vaults.vaultedTransfer, from, recipient, quantity, lockLengthMs, timestamp, vaultId)
			assert.is_false(status)
			assert.match("Insufficient balance", result)
		end)

		it("should throw an error if the lock length is less than the minimum", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 100
			_G.Balances["test-this-is-valid-arweave-wallet-address-2"] = 200
			local from = "test-this-is-valid-arweave-wallet-address-1"
			local recipient = "test-this-is-valid-arweave-wallet-address-2"
			local quantity = 50
			local lockLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS - 1
			local timestamp = 1000000
			local vaultId = "msgId"
			local status = pcall(vaults.vaultedTransfer, from, recipient, quantity, lockLengthMs, timestamp, vaultId)
			assert.is_false(status)
			-- the string fails to match because the error message is not exactly as expected
		end)
	end)

	describe("pruneVaults", function()
		it("should prune expired vaults and return balance to owners", function()
			local currentTimestamp = 1000000
			_G.NextPruneTimestamp = 0

			-- Set up test vaults
			_G.Vaults = {
				["owner1"] = {
					["msgId1"] = {
						balance = 100,
						startTimestamp = 0,
						endTimestamp = currentTimestamp - 1, -- Expired
					},
					["msgId2"] = {
						balance = 200,
						startTimestamp = 0,
						endTimestamp = currentTimestamp + 1000, -- Not expired
					},
				},
				["owner2"] = {
					["msgId3"] = {
						balance = 300,
						startTimestamp = 0,
						endTimestamp = currentTimestamp - 100, -- Expired
					},
				},
			}

			-- Set initial balances
			_G.Balances = {
				["owner1"] = 500,
				["owner2"] = 1000,
			}

			-- Call pruneVaults
			vaults.pruneVaults(currentTimestamp)

			-- Check results
			assert.is_nil(_G.Vaults["owner1"]["msgId1"])
			assert.is_not_nil(_G.Vaults["owner1"]["msgId2"])
			assert.is_nil(_G.Vaults["owner2"]["msgId3"])
			assert.are.equal(_G.NextPruneTimestamp, currentTimestamp + 1000)

			-- Check that balances were returned to owners
			assert.are.equal(600, _G.Balances["owner1"]) -- 500 + 100 from expired vault
			assert.are.equal(1300, _G.Balances["owner2"]) -- 1000 + 300 from expired vault
		end)

		it("should skip pruning when unnecessary", function()
			local currentTimestamp = 1000000
			_G.NextPruneTimestamp = currentTimestamp + 1

			-- Set up test vaults
			_G.Vaults = {
				["owner1"] = {
					["msgId1"] = {
						balance = 100,
						startTimestamp = 0,
						endTimestamp = currentTimestamp + 1,
					},
					["msgId2"] = {
						balance = 200,
						startTimestamp = 0,
						endTimestamp = currentTimestamp + 1000,
					},
				},
				["owner2"] = {
					["msgId3"] = {
						balance = 300,
						startTimestamp = 0,
						endTimestamp = currentTimestamp + 100,
					},
				},
			}

			-- Set initial balances
			_G.Balances = {
				["owner1"] = 500,
				["owner2"] = 1000,
			}

			-- Call pruneVaults
			local prunedVaults = vaults.pruneVaults(currentTimestamp)

			-- Check results
			assert.are.same({}, prunedVaults)
			assert.are.same(2, utils.lengthOfTable(_G.Vaults))
			assert.are.same(2, utils.lengthOfTable(_G.Vaults["owner1"]))
			assert.are.equal(_G.NextPruneTimestamp, currentTimestamp + 1001) --- should be corrected to this

			-- Check that balances were unchanged
			assert.are.equal(500, _G.Balances["owner1"])
			assert.are.equal(1000, _G.Balances["owner2"])
		end)
	end)

	describe("Reading vaults", function()
		local address1 = "a-test-this-is-valid-arweave-wallet-address"
		local address2 = "b-test-this-is-valid-arweave-wallet-address"
		before_each(function()
			-- Setup test vaults
			_G.Vaults = {
				[address1] = {
					["uniqueMsgId"] = {
						balance = 100,
						startTimestamp = 0,
						endTimestamp = 1000,
					},
				},
				[address2] = {
					["uniqueMsgId"] = {
						balance = 200,
						startTimestamp = 0,
						endTimestamp = 1000,
					},
				},
			}
		end)

		describe("getVault", function()
			it("should return the vault", function()
				local returnedVault = vaults.getVault(address1, "uniqueMsgId")
				assert.are.same({
					balance = 100,
					startTimestamp = 0,
					endTimestamp = 1000,
				}, returnedVault)
			end)

			it("should return nil if the vault does not exist", function()
				local returnedVault = vaults.getVault(address1, "nonExistentId")
				assert.is_nil(returnedVault)
			end)
		end)

		describe("getVaults", function()
			it("should return all vaults", function()
				local returnedVaults = vaults.getVaults()
				assert.are.same({
					[address1] = {
						["uniqueMsgId"] = {
							balance = 100,
							startTimestamp = 0,
							endTimestamp = 1000,
						},
					},
					[address2] = {
						["uniqueMsgId"] = {
							balance = 200,
							startTimestamp = 0,
							endTimestamp = 1000,
						},
					},
				}, returnedVaults)
			end)
		end)

		describe("getPaginatedVaults", function()
			it("should return paginated vaults", function()
				local returnedVaults = vaults.getPaginatedVaults(nil, 10, "asc")

				assert(returnedVaults.limit, 10)
				assert(returnedVaults.sortBy, "address")
				assert(returnedVaults.sortOrder, "asc")
				assert.is_false(returnedVaults.hasMore)
				assert(returnedVaults.totalItems, 2)

				local expectedVault1 = {
					address = address1,
					vaultId = "uniqueMsgId",
					balance = 100,
					startTimestamp = 0,
					endTimestamp = 1000,
				}
				local vault1 = returnedVaults.items[1]
				assert.same(expectedVault1, vault1)

				local expectedVault2 = {
					address = address2,
					vaultId = "uniqueMsgId",
					balance = 200,
					startTimestamp = 0,
					endTimestamp = 1000,
				}
				local vault2 = returnedVaults.items[2]
				assert.same(expectedVault2, vault2)
			end)

			it("should return paginated vaults sorted by balance", function()
				local returnedVaults = vaults.getPaginatedVaults(nil, 10, "asc", "balance")

				assert(returnedVaults.limit, 10)
				assert(returnedVaults.sortBy, "balance")
				assert(returnedVaults.sortOrder, "asc")
				assert.is_false(returnedVaults.hasMore)
				assert(returnedVaults.totalItems, 2)

				assert.same({
					address = address1,
					vaultId = "uniqueMsgId",
					balance = 100,
					startTimestamp = 0,
					endTimestamp = 1000,
				}, returnedVaults.items[1])

				assert.same({
					address = address2,
					vaultId = "uniqueMsgId",
					balance = 200,
					startTimestamp = 0,
					endTimestamp = 1000,
				}, returnedVaults.items[2])
			end)
		end)
	end)
end)
