local vaults = require("vaults")
local constants = require("constants")
local startTimestamp = 0

describe("vaults", function()
	before_each(function()
		_G.Balances = {
			["test-this-is-valid-arweave-wallet-address-1"] = 100,
		}
		_G.Vaults = {}
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
			assert.are.same(expectation, result)
			assert.are.same(expectation, vaults.getVault("test-this-is-valid-arweave-wallet-address-1", "msgId"))
		end)

		it("should throw an insufficient balance error if not enough tokens to create the vault", function()
			Balances["test-this-is-valid-arweave-wallet-address-1"] = 50
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
		end)

		it("should throw an error if the lock length would be larger than the maximum", function()
			local status, result = pcall(
				vaults.createVault,
				"test-this-is-valid-arweave-wallet-address-1",
				100,
				constants.MAX_TOKEN_LOCK_TIME_MS + 1,
				startTimestamp,
				"msgId"
			)
			assert.is_false(status)
		end)

		it("should throw an error if the lock length is less than the minimum", function()
			local status, error = pcall(
				vaults.createVault,
				"test-this-is-valid-arweave-wallet-address-1",
				100,
				constants.MIN_TOKEN_LOCK_TIME_MS - 1,
				startTimestamp,
				"msgId"
			)
			assert.is_false(status)
		end)

		it("should throw an error if the vault already exists", function()
			local status, result = pcall(
				vaults.createVault,
				"test-this-is-valid-arweave-wallet-address-1",
				100,
				constants.MIN_TOKEN_LOCK_TIME_MS,
				startTimestamp,
				"msgId"
			)
			assert.is_true(status)
			local status, result = pcall(
				vaults.createVault,
				"test-this-is-valid-arweave-wallet-address-1",
				100,
				constants.MIN_TOKEN_LOCK_TIME_MS,
				startTimestamp,
				"msgId"
			)
			assert.is_false(status)
			assert.match("Vault with id msgId already exists", result)
		end)
	end)

	describe("increaseVault", function()
		it("should increase the vault", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 200
			local vaultOwner = "test-this-is-valid-arweave-wallet-address-1"
			local lockLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local msgId = "msgId"
			local vault = vaults.createVault(vaultOwner, 100, lockLengthMs, startTimestamp, msgId)
			local increaseAmount = 100
			local currentTimestamp = vault.startTimestamp + 1000
			local increasedVault = vaults.increaseVault(vaultOwner, increaseAmount, msgId, currentTimestamp)
			assert.are.same(vault.balance + increaseAmount, increasedVault.balance)
			assert.are.same(vault.startTimestamp, increasedVault.startTimestamp)
			assert.are.same(vault.endTimestamp, increasedVault.endTimestamp)
		end)

		it("should throw an error if insufficient balance", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 100
			local vaultOwner = "test-this-is-valid-arweave-wallet-address-1"
			local lockLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local msgId = "msgId"
			local vault = vaults.createVault(vaultOwner, 100, lockLengthMs, startTimestamp, msgId)
			local increaseAmount = 101
			local currentTimestamp = vault.startTimestamp + 1000
			local status, result = pcall(vaults.increaseVault, vaultOwner, increaseAmount, msgId, currentTimestamp)
			assert.is_false(status)
			assert.match("Insufficient balance", result)
		end)

		it("should throw an error if the vault is expired", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 200
			local vaultOwner = "test-this-is-valid-arweave-wallet-address-1"
			local lockLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local msgId = "msgId"
			local vault = vaults.createVault(vaultOwner, 100, lockLengthMs, startTimestamp, msgId)
			local increaseAmount = 100
			local currentTimestamp = vault.endTimestamp + 1
			local status, result = pcall(vaults.increaseVault, vaultOwner, increaseAmount, msgId, currentTimestamp)
			assert.is_false(status)
			assert.match("This vault has ended.", result)
		end)

		it("should throw an error if the vault does not exist", function()
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
			local msgId = "msgId"
			local vault = vaults.createVault(vaultOwner, 100, lockLengthMs, startTimestamp, msgId)
			local extendLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local currentTimestamp = vault.startTimestamp + 1000
			local extendedVault = vaults.extendVault(vaultOwner, extendLengthMs, currentTimestamp, msgId)
			assert.are.same(vault.balance, extendedVault.balance)
			assert.are.same(vault.startTimestamp, extendedVault.startTimestamp)
			assert.are.same(vault.endTimestamp + extendLengthMs, extendedVault.endTimestamp)
		end)

		it("should throw an error if the vault is expired", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 100
			local vaultOwner = "test-this-is-valid-arweave-wallet-address-1"
			local lockLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local msgId = "msgId"
			local vault = vaults.createVault(vaultOwner, 100, lockLengthMs, startTimestamp, msgId)
			local extendLengthMs = constants.MIN_TOKEN_LOCK_TIME_MS
			local currentTimestamp = vault.endTimestamp + 1000
			local status, result = pcall(vaults.extendVault, vaultOwner, extendLengthMs, currentTimestamp, msgId)
			assert.is_false(status)
			assert.match("This vault has ended.", result)
		end)

		it("should throw an error if the lock length would be larger than the maximum", function()
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 100
			local vaultOwner = "test-this-is-valid-arweave-wallet-address-1"
			local lockLengthMs = constants.MAX_TOKEN_LOCK_TIME_MS
			local msgId = "msgId"
			local vault = vaults.createVault(vaultOwner, 100, lockLengthMs, startTimestamp, msgId)
			local extendLengthMs = constants.MAX_TOKEN_LOCK_TIME_MS + 1
			local currentTimestamp = vault.startTimestamp + 1000
			local status, result = pcall(vaults.extendVault, vaultOwner, extendLengthMs, currentTimestamp, msgId)
			assert.is_false(status)
			assert.match(
				"Invalid vault extension. Total lock time cannot be greater than "
					.. constants.MAX_TOKEN_LOCK_TIME_MS
					.. " ms",
				result
			)
		end)

		it("should throw an error if the vault does not exist", function()
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
			local msgId = "msgId"
			local vault = vaults.createVault(vaultOwner, 100, lockLengthMs, startTimestamp, msgId)
			local extendLengthMs = 0
			local currentTimestamp = vault.startTimestamp + 1000
			local status, result = pcall(vaults.extendVault, vaultOwner, extendLengthMs, currentTimestamp, msgId)
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
			local msgId = "msgId"
			local result, vault =
				pcall(vaults.vaultedTransfer, from, recipient, quantity, lockLengthMs, timestamp, msgId)
			assert.is_true(result)
			assert.is_not_nil(vault)
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
			local msgId = "msgId"
			local status, result =
				pcall(vaults.vaultedTransfer, from, recipient, quantity, lockLengthMs, timestamp, msgId)
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
			local msgId = "msgId"
			local status, result =
				pcall(vaults.vaultedTransfer, from, recipient, quantity, lockLengthMs, timestamp, msgId)
			assert.is_false(status)
		end)
	end)

	describe("pruneVaults", function()
		it("should prune expired vaults and return balance to owners", function()
			local currentTimestamp = 1000000

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

			-- Check that balances were returned to owners
			assert.are.equal(600, _G.Balances["owner1"]) -- 500 + 100 from expired vault
			assert.are.equal(1300, _G.Balances["owner2"]) -- 1000 + 300 from expired vault
		end)
	end)
end)
