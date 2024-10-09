local testProcessId = "NdZ3YRwMB2AMwwFYjKn1g88Y9nRybTo0qhS1ORq_E7g"
local constants = require("constants")
local arns = require("arns")
local balances = require("balances")
local demand = require("demand")
local utils = require("utils")

describe("arns", function()
	local timestamp = 0
	local testAddressArweave = "test-this-is-valid-arweave-wallet-address-1"
	local testAddressEth = "0xFCAd0B19bB29D4674531d6f115237E16AfCE377c"
	local testAddresses = { arweave = testAddressArweave, eth = testAddressEth }
	local startBalance = 5000000000000000

	before_each(function()
		_G.NameRegistry = {
			records = {},
			reserved = {},
		}
		_G.Balances = {
			[testAddressArweave] = startBalance,
			[testAddressEth] = startBalance,
		}
	end)

	for addressType, testAddress in pairs(testAddresses) do
		-- stub out the global state for these tests

		describe("buyRecord", function()
			it(
				"should add a valid lease buyRecord to records object and transfer balance to the protocol: ["
					.. addressType
					.. "]",
				function()
					local demandBefore = demand.getCurrentPeriodRevenue()
					local purchasesBefore = demand.getCurrentPeriodPurchases()
					local status, result =
						pcall(arns.buyRecord, "test-name", "lease", 1, testAddress, timestamp, testProcessId)

					assert.is_true(status)
					assert.are.same({
						purchasePrice = 600000000,
						type = "lease",
						undernameLimit = 10,
						processId = testProcessId,
						startTimestamp = 0,
						endTimestamp = timestamp + constants.oneYearMs * 1,
					}, result.record)
					assert.are.same({
						["test-name"] = {
							purchasePrice = 600000000,
							type = "lease",
							undernameLimit = 10,
							processId = testProcessId,
							startTimestamp = 0,
							endTimestamp = timestamp + constants.oneYearMs * 1,
						},
					}, arns.getRecords())
					assert.are.equal(balances.getBalance(testAddress), startBalance - 600000000)
					assert.are.equal(balances.getBalance(_G.ao.id), 600000000)
					assert.are.equal(demandBefore + 600000000, demand.getCurrentPeriodRevenue())
					assert.are.equal(purchasesBefore + 1, demand.getCurrentPeriodPurchases())
				end
			)

			it(
				"should default lease to 1 year and lease when not values are not provided[" .. addressType .. "]",
				function()
					local demandBefore = demand.getCurrentPeriodRevenue()
					local purchasesBefore = demand.getCurrentPeriodPurchases()
					local status, result =
						pcall(arns.buyRecord, "test-name", nil, nil, testAddress, timestamp, testProcessId)
					assert.is_true(status)
					assert.are.same({
						purchasePrice = 600000000,
						type = "lease",
						undernameLimit = 10,
						processId = testProcessId,
						startTimestamp = 0,
						endTimestamp = timestamp + constants.oneYearMs,
					}, result.record)
					assert.are.same({
						purchasePrice = 600000000,
						type = "lease",
						undernameLimit = 10,
						processId = testProcessId,
						startTimestamp = 0,
						endTimestamp = timestamp + constants.oneYearMs,
					}, arns.getRecord("test-name"))

					local balances = balances.getBalances()

					assert.is.equal(
						balances[testAddress],
						startBalance - 600000000,
						"Balance should be reduced by the purchase price"
					)
					assert.is.equal(
						balances[_G.ao.id],
						600000000,
						"Protocol balance should be increased by the purchase price"
					)
					assert.are.equal(demandBefore + 600000000, demand.getCurrentPeriodRevenue())
					assert.are.equal(purchasesBefore + 1, demand.getCurrentPeriodPurchases())
				end
			)

			it("should error when years is greater than max allowed [" .. addressType .. "]", function()
				local status, result = pcall(
					arns.buyRecord,
					"test-name",
					"lease",
					constants.maxLeaseLengthYears + 1,
					testAddress,
					timestamp,
					testProcessId
				)
				assert.is_false(status)
				assert.match("Years is invalid. Must be an integer between 1 and 5", result)
			end)

			it("should throw an error if the record already exists [" .. addressType .. "]", function()
				local existingRecord = {
					endTimestamp = timestamp + constants.oneYearMs,
					processId = testProcessId,
					purchasePrice = 600000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				NameRegistry.records["test-name"] = existingRecord
				local status, result =
					pcall(arns.buyRecord, "test-name", "lease", 1, testAddress, timestamp, testProcessId)
				assert.is_false(status)
				assert.match("Name is already registered", result)
				assert.are.same(existingRecord, NameRegistry.records["test-name"])
			end)

			it("should throw an error if the record is reserved for someone else [" .. addressType .. "]", function()
				local reservedName = {
					target = "test",
					endTimestamp = 1000,
				}
				NameRegistry.reserved["test-name"] = reservedName
				local status, result =
					pcall(arns.buyRecord, "test-name", "lease", 1, testAddress, timestamp, testProcessId)
				assert.is_false(status)
				assert.match("Name is reserved", result)
				assert.are.same({}, arns.getRecords())
				assert.are.same(reservedName, NameRegistry.reserved["test-name"])
			end)

			it("should allow you to buy a reserved name if reserved for caller [" .. addressType .. "]", function()
				local demandBefore = demand.getCurrentPeriodRevenue()
				local purchasesBefore = demand.getCurrentPeriodPurchases()
				NameRegistry.reserved["test-name"] = {
					target = testAddress,
					endTimestamp = 1000,
				}
				local status, result =
					pcall(arns.buyRecord, "test-name", "lease", 1, testAddress, timestamp, testProcessId)
				local expectation = {
					endTimestamp = timestamp + constants.oneYearMs,
					processId = testProcessId,
					purchasePrice = 600000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				assert.is_true(status)
				assert.are.same(expectation, result.record)
				assert.are.same({ ["test-name"] = expectation }, arns.getRecords())

				local balances = balances.getBalances()

				assert.is.equal(
					balances[testAddress],
					startBalance - 600000000,
					"Balance should be reduced by the purchase price"
				)

				assert.is.equal(
					balances[_G.ao.id],
					600000000,
					"Protocol balance should be increased by the purchase price"
				)

				assert.are.equal(demandBefore + 600000000, demand.getCurrentPeriodRevenue())
				assert.are.equal(purchasesBefore + 1, demand.getCurrentPeriodPurchases())
			end)

			it("should throw an error if the user does not have enough balance [" .. addressType .. "]", function()
				Balances[testAddress] = 0
				local status, result =
					pcall(arns.buyRecord, "test-name", "lease", 1, testAddress, timestamp, testProcessId)
				assert.is_false(status)
				assert.match("Insufficient balance", result)
				assert.are.same({}, arns.getRecords())
			end)
		end)

		describe("increaseundernameLimit [" .. addressType .. "]", function()
			it("should throw an error if name is not active", function()
				local status, error = pcall(arns.increaseundernameLimit, testAddress, "test-name", 50, timestamp)
				assert.is_false(status)
				assert.match("Name is not registered", error)
			end)

			--  throw an error on insufficient balance
			it("should throw an error on insufficient balance [" .. addressType .. "]", function()
				NameRegistry.records["test-name"] = {
					endTimestamp = timestamp + constants.oneYearMs,
					processId = testProcessId,
					purchasePrice = 600000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				Balances[testAddress] = 0
				local status, error = pcall(arns.increaseundernameLimit, testAddress, "test-name", 50, timestamp)
				assert.is_false(status)
				assert.match("Insufficient balance", error)
			end)


			it("should throw an error if the name is in the grace period [" .. addressType .. "]", function()
				NameRegistry.records["test-name"] = {
					endTimestamp = timestamp + constants.oneYearMs,
					processId = testProcessId,
					purchasePrice = 600000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				local status, error =
					pcall(arns.increaseundernameLimit, testAddress, "test-name", 1, timestamp + constants.oneYearMs + 1)
				assert.is_false(status)
				assert.match("Name must be extended before additional unernames can be purchase", error)
			end)

			it("should increase the undername count and properly deduct balance [" .. addressType .. "]", function()
				NameRegistry.records["test-name"] = {
					endTimestamp = timestamp + constants.oneYearMs,
					processId = testProcessId,
					purchasePrice = 600000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				local demandBefore = demand.getCurrentPeriodRevenue()
				local purchasesBefore = demand.getCurrentPeriodPurchases()
				local status, result = pcall(arns.increaseundernameLimit, testAddress, "test-name", 50, timestamp)
				local expectation = {
					endTimestamp = timestamp + constants.oneYearMs,
					processId = testProcessId,
					purchasePrice = 600000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 60,
				}
				assert.is_true(status)
				assert.are.same(expectation, result.record)
				assert.are.same({ ["test-name"] = expectation }, arns.getRecords())

				local balances = balances.getBalances()

				assert.is.equal(
					balances[testAddress],
					startBalance - 25000000,
					"Balance should be reduced by the purchase price"
				)

				assert.is.equal(
					balances[_G.ao.id],
					25000000,
					"Protocol balance should be increased by the purchase price"
				)

				assert.are.equal(demandBefore + 25000000, demand.getCurrentPeriodRevenue())
				assert.are.equal(purchasesBefore + 1, demand.getCurrentPeriodPurchases())
			end)
		end)

		describe("extendLease", function()
			it("should throw an error if name is not active [" .. addressType .. "]", function()
				local status, error = pcall(arns.extendLease, testAddress, "test-name", 1)
				assert.is_false(status)
				assert.match("Name is not registered", error)
			end)

			it(
				"should throw an error if the lease is expired and beyond the grace period [" .. addressType .. "]",
				function()
					NameRegistry.records["test-name"] = {
						endTimestamp = timestamp + constants.oneYearMs,
						processId = testProcessId,
						purchasePrice = 600000000,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 10,
					}
					local status, error = pcall(
						arns.extendLease,
						testAddress,
						"test-name",
						1,
						timestamp + constants.oneYearMs + constants.gracePeriodMs + 1
					)
					assert.is_false(status)
					assert.match("Name is expired", error)
				end
			)

			it("should throw an error if the lease is permabought [" .. addressType .. "]", function()
				NameRegistry.records["test-name"] = {
					endTimestamp = nil,
					processId = testProcessId,
					purchasePrice = 600000000,
					startTimestamp = 0,
					type = "permabuy",
					undernameLimit = 10,
				}
				local status, error = pcall(arns.extendLease, testAddress, "test-name", 1, timestamp)
				assert.is_false(status)
				assert.match("Name is permabought and cannot be extended", error)
			end)

			-- throw an error of insufficient balance
			it("should throw an error on insufficient balance [" .. addressType .. "]", function()
				NameRegistry.records["test-name"] = {
					endTimestamp = timestamp + constants.oneYearMs,
					processId = testProcessId,
					purchasePrice = 600000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				Balances[testAddress] = 0
				local status, error = pcall(arns.extendLease, testAddress, "test-name", 1, timestamp)
				assert.is_false(status)
				assert.match("Insufficient balance", error)
			end)

			it("should allow extension for existing lease up to 5 years [" .. addressType .. "]", function()
				NameRegistry.records["test-name"] = {
					-- 1 year lease
					endTimestamp = timestamp + constants.oneYearMs,
					processId = testProcessId,
					purchasePrice = 600000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				local demandBefore = demand.getCurrentPeriodRevenue()
				local purchasesBefore = demand.getCurrentPeriodPurchases()
				local status, result = pcall(arns.extendLease, testAddress, "test-name", 4, timestamp)
				assert.is_true(status)
				assert.are.same({
					endTimestamp = timestamp + constants.oneYearMs * 5,
					processId = testProcessId,
					purchasePrice = 600000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}, result.record)
				assert.are.same({
					["test-name"] = {
						endTimestamp = timestamp + constants.oneYearMs * 5,
						processId = testProcessId,
						purchasePrice = 600000000,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 10,
					},
				}, arns.getRecords())

				local balances = balances.getBalances()

				assert.is.equal(
					balances[testAddress],
					startBalance - 400000000,
					"Balance should be reduced by the purchase price"
				)
				assert.is.equal(
					balances[_G.ao.id],
					400000000,
					"Protocol balance should be increased by the purchase price"
				)

				assert.are.equal(demandBefore + 400000000, demand.getCurrentPeriodRevenue())
				assert.are.equal(purchasesBefore + 1, demand.getCurrentPeriodPurchases())
			end)

			it("should throw an error when trying to extend beyond 5 years [" .. addressType .. "]", function()
				NameRegistry.records["test-name"] = {
					-- 1 year lease
					endTimestamp = timestamp + constants.oneYearMs,
					processId = testProcessId,
					purchasePrice = 600000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				local status, error = pcall(arns.extendLease, testAddress, "test-name", 6, timestamp)
				assert.is_false(status)
				assert.match("Cannot extend lease beyond 5 years", error)
			end)
		end)

		describe("calculateLeaseFee [" .. addressType .. "]", function()
			it("should return the correct fee for a lease", function()
				local name = "test-name" -- 9 character name
				local baseFee = demand.getFees()[#name] -- base fee is 500 IO
				local fee = arns.calculateRegistrationFee("lease", baseFee, 1, 1)
				assert.are.equal(600000000, fee)
			end)

			it("should return the correct fee for a permabuy [" .. addressType .. "]", function()
				local name = "test-name" -- 9 character name
				local baseFee = demand.getFees()[#name] -- base fee is 500 IO
				local fee = arns.calculateRegistrationFee("permabuy", baseFee, 1, 1)
				local expected = (baseFee * 0.2 * 20) + baseFee
				assert.are.equal(expected, fee)
			end)
		end)
	end

	describe("pruneRecords", function()
		it("should prune records", function()
			local currentTimestamp = 1000000000

			_G.NameRegistry = {
				records = {
					["active-record"] = {
						endTimestamp = currentTimestamp + 1000000, -- far in the future
						processId = "active-process-id",
						purchasePrice = 600000000,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 10,
					},
					["expired-record"] = {
						endTimestamp = currentTimestamp - constants.gracePeriodMs - 1, -- expired and past the grace period
						processId = "expired-process-id",
						purchasePrice = 400000000,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 5,
					},
					["grace-period-record"] = {
						endTimestamp = currentTimestamp - constants.gracePeriodMs + 10, -- expired, but within grace period
						processId = "grace-process-id",
						purchasePrice = 500000000,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 8,
					},
					["permabuy-record"] = {
						endTimestamp = nil,
						processId = "permabuy-process-id",
						purchasePrice = 600000000,
						startTimestamp = 0,
						type = "permabuy",
						undernameLimit = 10,
					},
				},
			}
			arns.pruneRecords(currentTimestamp)
			assert.are.same({
				["active-record"] = {
					endTimestamp = currentTimestamp + 1000000, -- far in the future
					processId = "active-process-id",
					purchasePrice = 600000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				},
				["grace-period-record"] = {
					endTimestamp = currentTimestamp - constants.gracePeriodMs + 10, -- expired, but within grace period
					processId = "grace-process-id",
					purchasePrice = 500000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 8,
				},
				["permabuy-record"] = {
					endTimestamp = nil,
					processId = "permabuy-process-id",
					purchasePrice = 600000000,
					startTimestamp = 0,
					type = "permabuy",
					undernameLimit = 10,
				},
			}, _G.NameRegistry.records)
		end)
	end)
	describe("pruneReservedNames", function()
		it("should remove expired reserved names", function()
			local currentTimestamp = 1000000
			_G.NameRegistry.reserved = {
				["active-reserved"] = {
					endTimestamp = currentTimestamp + 1000000, -- far in the future
				},
				["expired-reserved"] = {
					endTimestamp = currentTimestamp - 1000, -- expired
				},
				["expired-exact-reserved"] = {
					endTimestamp = currentTimestamp, -- expired at the exact timestamp
				},
			}
			arns.pruneReservedNames(currentTimestamp)
			assert.are.same({
				["active-reserved"] = {
					endTimestamp = currentTimestamp + 1000000, -- far in the future
				},
			}, _G.NameRegistry.reserved)
		end)
	end)

	describe("getRegistrationFees", function()
		it("should return the correct registration prices", function()
			local registrationFees = arns.getRegistrationFees()

			-- check first, middle and last name lengths
			assert.are.equal(utils.lengthOfTable(registrationFees), 51)
			assert.are.equal(registrationFees["1"].lease["1"], 2400000000000)
			assert.are.equal(registrationFees["5"].lease["3"], 6400000000)
			assert.are.equal(registrationFees["10"].permabuy, 2500000000)
			assert.are.equal(registrationFees["10"].lease["5"], 1000000000)
			assert.are.equal(registrationFees["51"].lease["1"], 480000000)
		end)
	end)
end)
