local testProcessId = "NdZ3YRwMB2AMwwFYjKn1g88Y9nRybTo0qhS1ORq_E7g"
local constants = require("constants")
local arns = require("arns")
local demand = require("demand")
local utils = require("utils")
local gar = require("gar")

local stubGatewayAddress = "test-this-is-valid-arweave-wallet-address-1"
local stubObserverAddress = "test-this-is-valid-arweave-wallet-address-2"
local stubRandomAddress = "test-this-is-valid-arweave-wallet-address-3"
local gracePeriodMs = 1209600000 -- 14 days
local returnedNameMs = 1209600000 -- 14 days
local minimumTenureWeightForDiscount = 1
local minimumPerformanceRateForDiscount = 0.90
local operatorDiscountRate = 0.20
local testSettings = {
	fqdn = "test.com",
	protocol = "https",
	port = 443,
	allowDelegatedStaking = true,
	minDelegatedStake = 500000000,
	autoStake = true,
	label = "test",
	delegateRewardShareRatio = 0,
	properties = stubGatewayAddress,
	allowedDelegatesLookup = {
		["test-allowlisted-delegator-address-number-1"] = true,
		["test-allowlisted-delegator-address-number-2"] = true,
	},
}
local testGateway = {
	operatorStake = gar.getSettings().operators.minStake,
	totalDelegatedStake = 0,
	vaults = {},
	delegates = {},
	startTimestamp = 0,
	stats = {
		prescribedEpochCount = 0,
		observedEpochCount = 0,
		totalEpochCount = 0,
		passedEpochCount = 0,
		failedEpochCount = 0,
		failedConsecutiveEpochs = 0,
		passedConsecutiveEpochs = 0,
	},
	settings = testSettings,
	status = "joined",
	observerAddress = stubObserverAddress,
}
local baseFee = 400000000
local basePriceForNineLetterName = 480000000

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
			returned = {},
		}
		_G.Balances = {
			[testAddressArweave] = startBalance,
			[testAddressEth] = startBalance,
		}
		_G.DemandFactor.currentDemandFactor = 1.0
		_G.GatewayRegistry = {}
	end)

	describe("assertValidArNSName", function()
		it("should return false for invalid ArNS names", function()
			local invalidNames = {
				"", -- empty string
				nil, -- nil value
				{}, -- table
				123, -- number
				true, -- boolean
				"test ar", -- space
				"test!.ar", -- !
				"test@.ar", -- @
				"test#.ar", -- #
				"test$.ar", -- $
				"test%.ar", -- %
				"test^.ar", -- ^
				"test&.ar", -- &
				"test*.ar", -- *
				"test(.ar", -- (
				"test).ar", -- )
				"test+.ar", -- +
				"test=.ar", -- =
				"test{.ar", -- {
				"test}.ar", -- }
				string.rep("a", 52), -- too long
			}

			for _, name in ipairs(invalidNames) do
				local status, err = pcall(arns.assertValidArNSName, name)
				assert.is_false(status, "Expected " .. name .. " to be invalid")
				assert.not_nil(err)
			end
		end)

		it("should return true for valid ArNS names", function()
			local validNames = {
				"a", -- single character
				"z", -- single character
				"0", -- single numeric
				"9", -- single numeric
				"test123", -- alphanumeric
				"123test", -- starts with number
				"test-123", -- with hyphen
				"a123456789", -- multiple numbers
				string.rep("a", 51), -- max length
				"abcdefghijklmnopqrstuvwxyz0123456789", -- all valid chars
				"UPPERCASE", -- uppercase allowed
				"MixedCase123", -- mixed case
				"with-hyphens-123", -- multiple hyphens
				"1-2-3", -- numbers and hyphens
				"a-b-c", -- letters and hyphens
			}

			for _, name in ipairs(validNames) do
				local status, err = pcall(arns.assertValidArNSName, name)
				assert.is_true(status, "Expected " .. name .. " to be valid")
				assert.is_nil(err)
			end
		end)
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
					local result =
						arns.buyRecord("test-name", "lease", 1, testAddress, timestamp, testProcessId, "msgId")

					assert.are.same({
						purchasePrice = basePriceForNineLetterName,
						type = "lease",
						undernameLimit = 10,
						processId = testProcessId,
						startTimestamp = 0,
						endTimestamp = timestamp + constants.yearsToMs(1),
					}, result.record)
					assert.are.same({
						["test-name"] = {
							purchasePrice = basePriceForNineLetterName,
							type = "lease",
							undernameLimit = 10,
							processId = testProcessId,
							startTimestamp = 0,
							endTimestamp = timestamp + constants.yearsToMs(1),
						},
					}, _G.NameRegistry.records)
					assert.are.equal(startBalance - basePriceForNineLetterName, _G.Balances[testAddress])
					assert.are.equal(basePriceForNineLetterName, _G.Balances[_G.ao.id])
					assert.are.equal(demandBefore + basePriceForNineLetterName, demand.getCurrentPeriodRevenue())
					assert.are.equal(purchasesBefore + 1, demand.getCurrentPeriodPurchases())
				end
			)

			it(
				"should apply ArNS discount on lease buys when eligibility requirements are met[" .. addressType .. "]",
				function()
					_G.GatewayRegistry[testAddress] = testGateway
					_G.GatewayRegistry[testAddress].weights = {
						tenureWeight = minimumTenureWeightForDiscount,
						gatewayPerformanceRatio = minimumPerformanceRateForDiscount,
						normalizedCompositeWeight = 1,
						stakeWeight = 1,
						observerPerformanceRatio = 1,
						compositeWeight = 1,
					}
					local result = gar.isEligibleForArNSDiscount(testAddress)
					assert.is_true(result)

					local demandBefore = demand.getCurrentPeriodRevenue()
					local purchasesBefore = demand.getCurrentPeriodPurchases()
					local discountTotal = basePriceForNineLetterName
						- (math.floor(basePriceForNineLetterName * operatorDiscountRate))

					local buyRecordResult =
						arns.buyRecord("test-name", "lease", 1, testAddress, timestamp, testProcessId, "msg-id")
					assert.are.same({
						purchasePrice = discountTotal,
						type = "lease",
						undernameLimit = 10,
						processId = testProcessId,
						startTimestamp = 0,
						endTimestamp = timestamp + constants.yearsToMs(1),
					}, buyRecordResult.record)
					assert.are.same({
						["test-name"] = {
							purchasePrice = discountTotal,
							type = "lease",
							undernameLimit = 10,
							processId = testProcessId,
							startTimestamp = 0,
							endTimestamp = timestamp + constants.yearsToMs(1),
						},
					}, _G.NameRegistry.records)
					assert.are.equal(startBalance - discountTotal, _G.Balances[testAddress])
					assert.are.equal(discountTotal, _G.Balances[_G.ao.id])
					assert.are.equal(demandBefore + discountTotal, demand.getCurrentPeriodRevenue())
					assert.are.equal(purchasesBefore + 1, demand.getCurrentPeriodPurchases())
				end
			)

			it(
				"should default lease to 1 year and lease when not values are not provided[" .. addressType .. "]",
				function()
					local demandBefore = demand.getCurrentPeriodRevenue()
					local purchasesBefore = demand.getCurrentPeriodPurchases()
					local result =
						arns.buyRecord("test-name", nil, nil, testAddress, timestamp, testProcessId, "msg-id")
					assert.are.same({
						purchasePrice = basePriceForNineLetterName,
						type = "lease",
						undernameLimit = 10,
						processId = testProcessId,
						startTimestamp = 0,
						endTimestamp = timestamp + constants.yearsToMs(1),
					}, result.record)
					assert.are.same({
						purchasePrice = basePriceForNineLetterName,
						type = "lease",
						undernameLimit = 10,
						processId = testProcessId,
						startTimestamp = 0,
						endTimestamp = timestamp + constants.yearsToMs(1),
					}, arns.getRecord("test-name"))

					assert.is.equal(
						_G.Balances[testAddress],
						startBalance - basePriceForNineLetterName,
						"Balance should be reduced by the purchase price"
					)
					assert.is.equal(
						_G.Balances[_G.ao.id],
						basePriceForNineLetterName,
						"Protocol balance should be increased by the purchase price"
					)
					assert.are.equal(demandBefore + basePriceForNineLetterName, demand.getCurrentPeriodRevenue())
					assert.are.equal(purchasesBefore + 1, demand.getCurrentPeriodPurchases())
				end
			)

			it("should error when years is greater than max allowed [" .. addressType .. "]", function()
				local status, result =
					pcall(arns.buyRecord, "test-name", "lease", 5 + 1, testAddress, timestamp, testProcessId)
				assert.is_false(status)
				assert.match("Years is invalid. Must be an integer between 1 and 5", result)
			end)

			it("should throw an error if the record already exists [" .. addressType .. "]", function()
				local existingRecord = {
					endTimestamp = timestamp + constants.yearsToMs(1),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				_G.NameRegistry.records["test-name"] = existingRecord
				local status, error =
					pcall(arns.buyRecord, "test-name", "lease", 1, testAddress, timestamp, testProcessId, "msg-id")
				assert.is_false(status)
				assert(error, "Expected error")
				assert.match("Name is already registered", error)
				assert.are.same(existingRecord, _G.NameRegistry.records["test-name"])
			end)

			it("should throw an error if the record is reserved for someone else [" .. addressType .. "]", function()
				local reservedName = {
					target = "test",
					endTimestamp = 1000,
				}
				_G.NameRegistry.reserved["test-name"] = reservedName
				local status, result =
					pcall(arns.buyRecord, "test-name", "lease", 1, testAddress, timestamp, testProcessId, "msg-id")
				assert.is_false(status)
				assert.match("Name is reserved", result)
				assert.are.same({}, _G.NameRegistry.records)
				assert.are.same(reservedName, _G.NameRegistry.reserved["test-name"])
			end)

			it("should allow you to buy a reserved name if reserved for caller [" .. addressType .. "]", function()
				local demandBefore = demand.getCurrentPeriodRevenue()
				local purchasesBefore = demand.getCurrentPeriodPurchases()
				_G.NameRegistry.reserved["test-name"] = {
					target = testAddress,
					endTimestamp = 1000,
				}
				local result = arns.buyRecord("test-name", "lease", 1, testAddress, timestamp, testProcessId, "msg-id")
				local expectation = {
					endTimestamp = timestamp + constants.yearsToMs(1),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				assert.are.same(expectation, result.record)
				assert.are.same({ ["test-name"] = expectation }, _G.NameRegistry.records)

				assert.is.equal(
					_G.Balances[testAddress],
					startBalance - basePriceForNineLetterName,
					"Balance should be reduced by the purchase price"
				)

				assert.is.equal(
					_G.Balances[_G.ao.id],
					basePriceForNineLetterName,
					"Protocol balance should be increased by the purchase price"
				)

				assert.are.equal(demandBefore + basePriceForNineLetterName, demand.getCurrentPeriodRevenue())
				assert.are.equal(purchasesBefore + 1, demand.getCurrentPeriodPurchases())
			end)

			it(
				"should allow purchasing returned names with the returned name premium applied [" .. addressType .. "]",
				function()
					_G.NameRegistry.returned["test-name"] = {
						startTimestamp = timestamp,
						name = "test-name",
						initiator = "test-initiator",
					}
					local result =
						arns.buyRecord("test-name", "lease", 1, testAddress, timestamp, testProcessId, "msd-id")
					local expectedPrice = math.floor(basePriceForNineLetterName * 50)
					local expectation = {
						endTimestamp = timestamp + constants.yearsToMs(1),
						processId = testProcessId,
						purchasePrice = expectedPrice,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 10,
					}
					assert.are.same(expectation, result.record)
					assert.are.same({
						initiator = "test-initiator",
						rewardForProtocol = math.floor(expectedPrice / 2),
						rewardForInitiator = math.floor(expectedPrice / 2),
					}, result.returnedName)
					assert.are.same(nil, _G.NameRegistry.returned["test-name"])
				end
			)

			it("should throw an error if the user does not have enough balance [" .. addressType .. "]", function()
				_G.Balances[testAddress] = 0
				local status, result =
					pcall(arns.buyRecord, "test-name", "lease", 1, testAddress, timestamp, testProcessId, "msg-id")
				assert.is_false(status)
				assert.match("Insufficient balance", result)
				assert.are.same({}, _G.NameRegistry.records)
			end)
		end)

		describe("increaseUndernameLimit [" .. addressType .. "]", function()
			it("should throw an error if name is not active", function()
				local status, error =
					pcall(arns.increaseUndernameLimit, testAddress, "test-name", 50, timestamp, "msg-id", "balance")
				assert.is_false(status)
				assert(error)
				assert.match("Name is not registered", error)
			end)

			--  throw an error on insufficient balance
			it("should throw an error on insufficient balance [" .. addressType .. "]", function()
				_G.NameRegistry.records["test-name"] = {
					endTimestamp = timestamp + constants.yearsToMs(1),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				_G.Balances[testAddress] = 0
				local status, error =
					pcall(arns.increaseUndernameLimit, testAddress, "test-name", 50, timestamp, "msg-id", "balance")
				assert.is_false(status)
				assert.match("Insufficient balance", error)
			end)

			it("should throw an error if the name is in the grace period [" .. addressType .. "]", function()
				_G.NameRegistry.records["test-name"] = {
					endTimestamp = timestamp + constants.yearsToMs(1),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				local status, error = pcall(
					arns.increaseUndernameLimit,
					testAddress,
					"test-name",
					1,
					timestamp + constants.yearsToMs(1) + 1,
					"msg-id",
					"balance"
				)
				assert.is_false(status)
				assert.match("Name must be active to increase undername limit", error)
			end)

			it("should increase the undername count and properly deduct balance [" .. addressType .. "]", function()
				_G.NameRegistry.records["test-name"] = {
					endTimestamp = timestamp + constants.yearsToMs(1),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				local demandBefore = demand.getCurrentPeriodRevenue()
				local purchasesBefore = demand.getCurrentPeriodPurchases()
				local result = arns.increaseUndernameLimit(testAddress, "test-name", 50, timestamp, "msg-id")
				local expectation = {
					endTimestamp = timestamp + constants.yearsToMs(1),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 60,
				}
				assert.are.same(expectation, result.record)
				assert.are.same({ ["test-name"] = expectation }, _G.NameRegistry.records)

				assert.is.equal(
					startBalance - 20000000,
					_G.Balances[testAddress],
					"Balance should be reduced by the purchase price"
				)

				assert.is.equal(
					_G.Balances[_G.ao.id],
					20000000,
					"Protocol balance should be increased by the purchase price"
				)

				assert.are.equal(demandBefore + 20000000, demand.getCurrentPeriodRevenue())
				assert.are.equal(purchasesBefore + 1, demand.getCurrentPeriodPurchases())
			end)

			it("should apply ArNS discount for increasing undername limit for eligible gateways", function()
				_G.GatewayRegistry[testAddress] = testGateway
				_G.GatewayRegistry[testAddress].weights = {
					tenureWeight = minimumTenureWeightForDiscount,
					gatewayPerformanceRatio = minimumPerformanceRateForDiscount,
					normalizedCompositeWeight = 1,
					stakeWeight = 1,
					observerPerformanceRatio = 1,
					compositeWeight = 1,
				}
				assert.is_true(gar.isEligibleForArNSDiscount(testAddress))

				_G.NameRegistry.records["test-name"] = {
					endTimestamp = timestamp + constants.yearsToMs(1),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				local demandBefore = demand.getCurrentPeriodRevenue()
				local purchasesBefore = demand.getCurrentPeriodPurchases()
				local result = arns.increaseUndernameLimit(testAddress, "test-name", 50, timestamp, "msg-id", "balance")
				local expectation = {
					endTimestamp = timestamp + constants.yearsToMs(1),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 60,
				}
				assert.are.same(expectation, result.record)
				assert.are.same({ ["test-name"] = expectation }, _G.NameRegistry.records)

				local discountTotal = 20000000 - (math.floor(20000000 * operatorDiscountRate))

				assert.is.equal(
					_G.Balances[testAddress],
					startBalance - discountTotal,
					"Balance should be reduced by the purchase price"
				)

				assert.is.equal(
					_G.Balances[_G.ao.id],
					discountTotal,
					"Protocol balance should be increased by the purchase price"
				)

				assert.are.equal(demandBefore + discountTotal, demand.getCurrentPeriodRevenue())
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
					_G.NameRegistry.records["test-name"] = {
						endTimestamp = timestamp + constants.yearsToMs(1),
						processId = testProcessId,
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 10,
					}
					local status, error = pcall(
						arns.extendLease,
						testAddress,
						"test-name",
						1,
						timestamp + constants.yearsToMs(1) + gracePeriodMs + 1
					)
					assert.is_false(status)
					assert.match("Name is expired", error)
				end
			)

			it("should throw an error if the lease is permanently owned [" .. addressType .. "]", function()
				_G.NameRegistry.records["test-name"] = {
					endTimestamp = nil,
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "permabuy",
					undernameLimit = 10,
				}
				local status, error = pcall(arns.extendLease, testAddress, "test-name", 1, timestamp)
				assert.is_false(status)
				assert.match("Name is permanently owned and cannot be extended", error)
			end)

			-- throw an error of insufficient balance
			it("should throw an error on insufficient balance [" .. addressType .. "]", function()
				_G.NameRegistry.records["test-name"] = {
					endTimestamp = timestamp + constants.yearsToMs(1),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				_G.Balances[testAddress] = 0
				local status, error = pcall(arns.extendLease, testAddress, "test-name", 1, timestamp)
				assert.is_false(status)
				assert.match("Insufficient balance", error)
			end)

			it("should allow extension for existing lease up to 5 years [" .. addressType .. "]", function()
				_G.NameRegistry.records["test-name"] = {
					-- 1 year lease
					endTimestamp = timestamp + constants.yearsToMs(1),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				local demandBefore = demand.getCurrentPeriodRevenue()
				local purchasesBefore = demand.getCurrentPeriodPurchases()
				local result = arns.extendLease(testAddress, "test-name", 4, timestamp, "msg-id", "balance")
				assert.are.same({
					endTimestamp = timestamp + constants.yearsToMs(5),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}, result.record)
				assert.are.same({
					["test-name"] = {
						endTimestamp = timestamp + constants.yearsToMs(5),
						processId = testProcessId,
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 10,
					},
				}, _G.NameRegistry.records)

				assert.is.equal(
					_G.Balances[testAddress],
					startBalance - 320000000,
					"Balance should be reduced by the purchase price"
				)
				assert.is.equal(
					_G.Balances[_G.ao.id],
					320000000,
					"Protocol balance should be increased by the purchase price"
				)

				assert.are.equal(demandBefore + 320000000, demand.getCurrentPeriodRevenue())
				assert.are.equal(purchasesBefore + 1, demand.getCurrentPeriodPurchases())

				assert.are.same({
					address = testAddress,
					balance = 320000000,
					stakes = {},
					shortfall = 0,
				}, result.fundingPlan)
				assert.are.same({
					totalFunded = 320000000,
					newWithdrawVaults = {},
				}, result.fundingResult)
			end)

			it("should throw an error when trying to extend beyond 5 years [" .. addressType .. "]", function()
				_G.NameRegistry.records["test-name"] = {
					-- 1 year lease
					endTimestamp = timestamp + constants.yearsToMs(1),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				local status, error = pcall(arns.extendLease, testAddress, "test-name", 6, timestamp)
				assert.is_false(status)
				assert.match("Cannot extend lease beyond 5 years", error)
			end)

			it("should apply ArNS discount to eligible gateways for extending leases", function()
				_G.GatewayRegistry[testAddress] = testGateway
				_G.GatewayRegistry[testAddress].weights = {
					tenureWeight = minimumTenureWeightForDiscount,
					gatewayPerformanceRatio = minimumPerformanceRateForDiscount,
					normalizedCompositeWeight = 1,
					stakeWeight = 1,
					observerPerformanceRatio = 1,
					compositeWeight = 1,
				}
				local result = gar.isEligibleForArNSDiscount(testAddress)
				assert.is_true(result)

				_G.NameRegistry.records["test-name"] = {
					-- 1 year lease
					endTimestamp = timestamp + constants.yearsToMs(1),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				local demandBefore = demand.getCurrentPeriodRevenue()
				local purchasesBefore = demand.getCurrentPeriodPurchases()
				local extendLeaseResult = arns.extendLease(testAddress, "test-name", 4, timestamp, "msg-id", "balance")
				assert.are.same({
					endTimestamp = timestamp + constants.yearsToMs(5),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}, extendLeaseResult.record)
				assert.are.same({
					["test-name"] = {
						endTimestamp = timestamp + constants.yearsToMs(5),
						processId = testProcessId,
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 10,
					},
				}, _G.NameRegistry.records)

				local discountTotal = 320000000 - (math.floor(320000000 * operatorDiscountRate))

				assert.is.equal(
					_G.Balances[testAddress],
					startBalance - discountTotal,
					"Balance should be reduced by the purchase price"
				)

				assert.is.equal(
					_G.Balances[_G.ao.id],
					discountTotal,
					"Protocol balance should be increased by the discounted price"
				)

				assert.are.equal(demandBefore + discountTotal, demand.getCurrentPeriodRevenue())
				assert.are.equal(purchasesBefore + 1, demand.getCurrentPeriodPurchases())
			end)
		end)

		describe("calculateRegistrationFee [" .. addressType .. "]", function()
			it("should return the correct fee for a lease", function()
				-- base fee is 500 ARIO
				local fee = arns.calculateRegistrationFee("lease", baseFee, 1, 1)
				assert.are.equal(basePriceForNineLetterName, fee)
			end)

			it("should return the correct fee for registring a name permanently [" .. addressType .. "]", function()
				-- base fee is 500 ARIO
				local fee = arns.calculateRegistrationFee("permabuy", baseFee, 1, 1)
				local expected = (baseFee * 0.2 * 20) + baseFee
				assert.are.equal(expected, fee)
			end)
		end)

		describe("reassignName [" .. addressType .. "]", function()
			it("should successfully reassign a name to a new owner", function()
				-- Setup initial record
				_G.NameRegistry.records["test-name"] = {
					endTimestamp = timestamp + constants.yearsToMs(1),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}

				-- Reassign the name
				local newProcessId = "test-this-is-valid-arweave-wallet-address-2"
				local result = arns.reassignName("test-name", testProcessId, timestamp, newProcessId)
				assert.are.same(newProcessId, result.processId)
			end)

			it("should throw an error if the name is not registered", function()
				local newProcessId = "test-this-is-valid-arweave-wallet-address-2"
				local status, error =
					pcall(arns.reassignName, "unregistered-name", testProcessId, timestamp, newProcessId)
				assert.is_false(status)
				assert.match("Name is not registered", error)
			end)

			it("should throw an error if the reassigner is not the current owner", function()
				-- Setup initial record
				_G.NameRegistry.records["test-name"] = {
					endTimestamp = timestamp + constants.yearsToMs(1),
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}

				-- Attempt to reassign
				local newProcessId = "test-this-is-valid-arweave-wallet-address-2"
				local status, error = pcall(arns.reassignName, "test-name", "invalid-owner", timestamp, newProcessId)

				-- Assertions
				assert.is_false(status)
				assert.match("Not authorized to reassign this name", error)
			end)

			it("should throw an error if the name is expired", function()
				-- Setup expired record
				_G.NameRegistry.records["test-name"] = {
					endTimestamp = timestamp - 1, -- expired
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}

				-- Attempt to reassign
				local newProcessId = "test-this-is-valid-arweave-wallet-address-2"
				local status, error = pcall(arns.reassignName, "test-name", testProcessId, timestamp, newProcessId)

				-- Assertions
				assert.is_false(status)
				assert.match("Name must be extended before it can be reassigned", error)
			end)

			it("should not allow reassigning names during the grace period", function()
				-- Setup record in grace period
				_G.NameRegistry.records["test-name"] = {
					endTimestamp = 123456789,
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}

				-- Attempt to reassign
				local newProcessId = "test-this-is-valid-arweave-wallet-address-2"
				local status, error = pcall(
					arns.reassignName,
					"test-name",
					testProcessId,
					-- Just before the grace period ends
					123456789
						+ gracePeriodMs
						- 1,
					newProcessId
				)

				-- Assertions
				assert.is_false(status)
				assert.match("Name must be extended before it can be reassigned", error)
			end)
		end)
	end

	describe("getTokenCost", function()
		it("should return the correct token cost for a buying a lease", function()
			local years = 2
			local demandFactor = 0.974
			local expectedCost = math.floor((years * baseFee * operatorDiscountRate) + baseFee) * demandFactor
			local intendedAction = {
				intent = "Buy-Name",
				purchaseType = "lease",
				years = 2,
				name = "test-name",
				currentTimestamp = timestamp,
			}
			_G.DemandFactor.currentDemandFactor = demandFactor
			assert.are.equal(expectedCost, arns.getTokenCost(intendedAction).tokenCost)
		end)
		it("should return the correct token cost for a buying name permanently", function()
			local demandFactor = 1.052
			local expectedCost = math.floor((baseFee * 0.2 * 20) + baseFee) * demandFactor
			local intendedAction = {
				intent = "Buy-Name",
				purchaseType = "permabuy",
				name = "test-name",
				currentTimestamp = timestamp,
			}
			_G.DemandFactor.currentDemandFactor = demandFactor
			assert.are.equal(expectedCost, arns.getTokenCost(intendedAction).tokenCost)
		end)
		it("should return the correct token cost for increasing undername limit", function()
			_G.NameRegistry.records["test-name"] = {
				endTimestamp = constants.yearsToMs(1),
				processId = testProcessId,
				purchasePrice = basePriceForNineLetterName,
				startTimestamp = 0,
				type = "lease",
				undernameLimit = 10,
			}

			local undernamePercentageFee = 0.001
			local increaseQty = 5
			local demandFactor = 0.60137
			local expectedCost = math.floor(baseFee * increaseQty * undernamePercentageFee * demandFactor)
			local intendedAction = {
				intent = "Increase-Undername-Limit",
				quantity = 5,
				name = "test-name",
				currentTimestamp = constants.yearsToMs(1) / 2,
			}
			_G.DemandFactor.currentDemandFactor = demandFactor
			assert.are.equal(expectedCost, arns.getTokenCost(intendedAction).tokenCost)
		end)
		it("should return the token cost for extending a lease", function()
			_G.NameRegistry.records["test-name"] = {
				endTimestamp = timestamp + constants.yearsToMs(1),
				processId = testProcessId,
				purchasePrice = basePriceForNineLetterName,
				startTimestamp = 0,
				type = "lease",
				undernameLimit = 10,
			}

			local years = 2
			local demandFactor = 1.2405
			local expectedCost = math.floor((years * baseFee * operatorDiscountRate) * demandFactor)
			local intendedAction = {
				intent = "Extend-Lease",
				years = 2,
				name = "test-name",
				currentTimestamp = timestamp + constants.yearsToMs(1),
			}
			_G.DemandFactor.currentDemandFactor = demandFactor
			assert.are.equal(expectedCost, arns.getTokenCost(intendedAction).tokenCost)
		end)

		it("should return the token cost for a fresh returned name", function()
			_G.NameRegistry.returned["test-name"] = {
				startTimestamp = timestamp,
				name = "test-name",
				initiator = "test-initiator",
			}

			local years = 2
			local demandFactor = 0.974
			local expectedCost = math.floor((((years * baseFee * operatorDiscountRate) + baseFee) * demandFactor) * 50)
			local intendedAction = {
				intent = "Buy-Name",
				purchaseType = "lease",
				years = years,
				name = "test-name",
				currentTimestamp = timestamp,
			}
			_G.DemandFactor.currentDemandFactor = demandFactor
			assert.are.equal(expectedCost, arns.getTokenCost(intendedAction).tokenCost)
		end)

		it("should return the correct token cost for an ArNS discount eligible address", function()
			_G.GatewayRegistry[stubRandomAddress] = testGateway
			_G.GatewayRegistry[stubRandomAddress].weights = {
				tenureWeight = minimumTenureWeightForDiscount,
				gatewayPerformanceRatio = minimumPerformanceRateForDiscount,
				normalizedCompositeWeight = 1,
				stakeWeight = 1,
				observerPerformanceRatio = 1,
				compositeWeight = 1,
			}
			local result = gar.isEligibleForArNSDiscount(stubRandomAddress)
			assert.is_true(result)

			local demandFactor = 1.052
			local expectedCost = math.floor((baseFee * 0.2 * 20) + baseFee) * demandFactor
			local intendedAction = {
				intent = "Buy-Name",
				purchaseType = "permabuy",
				name = "test-name",
				currentTimestamp = timestamp,
				from = stubRandomAddress,
			}
			_G.DemandFactor.currentDemandFactor = demandFactor

			local discountTotal = expectedCost - (math.floor(expectedCost * operatorDiscountRate))
			assert.are.equal(discountTotal, arns.getTokenCost(intendedAction).tokenCost)
		end)
		describe("Primary-Name-Request Cost", function()
			local testCriteria = {
				-- leased names
				{
					name = "basename1",
					basename = "basename1",
					purchaseType = "lease",
				},
				{
					-- convert to basename with baseNameForName in intent
					name = "undername_basename2",
					-- use to set the record
					basename = "basename2",
					purchaseType = "lease",
				},
				-- permabought names
				{
					name = "basename3",
					basename = "basename3",
					purchaseType = "permabuy",
				},
				{
					name = "undername_basename4",
					basename = "basename4",
					purchaseType = "permabuy",
				},
			}

			for _, criteria in ipairs(testCriteria) do
				it("should return token cost for " .. criteria.purchaseType .. " " .. criteria.name, function()
					-- Reset demand factor
					local demandFactor = 1.052
					_G.DemandFactor.currentDemandFactor = demandFactor
					local baseNameFee = _G.DemandFactor.fees[constants.PRIMARY_NAME_REQUEST_DEFAULT_NAME_LENGTH]
					local primaryNameExpectedFees = {
						lease = math.floor(baseNameFee * 1 * 0.001) * demandFactor,
						permabuy = math.floor(baseNameFee * 1 * 0.005) * demandFactor,
					}
					_G.NameRegistry.records[criteria.basename] = {
						endTimestamp = criteria.purchaseType == "lease" and 10000000 or nil,
						processId = testProcessId,
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = criteria.purchaseType,
						undernameLimit = 10,
					}

					local intendedAction = {
						intent = "Primary-Name-Request",
						name = utils.baseNameForName(criteria.name),
						currentTimestamp = 0,
					}

					assert.are.equal(
						primaryNameExpectedFees[criteria.purchaseType],
						arns.getTokenCost(intendedAction).tokenCost
					)
				end)
			end
		end)

		it("should not apply discount on a gateway that is found but does not meet the requirements", function()
			_G.GatewayRegistry[stubRandomAddress] = testGateway
			_G.GatewayRegistry[stubRandomAddress].weights = {
				tenureWeight = 0.1,
				gatewayPerformanceRatio = 0.1,
				normalizedCompositeWeight = 1,
				stakeWeight = 1,
				observerPerformanceRatio = 1,
				compositeWeight = 1,
			}
			local result = gar.isEligibleForArNSDiscount(stubRandomAddress)
			assert.is_false(result)

			local demandFactor = 1.052
			local expectedCost = math.floor((baseFee * 0.2 * 20) + baseFee) * demandFactor
			local intendedAction = {
				intent = "Buy-Name",
				purchaseType = "permabuy",
				name = "test-name",
				currentTimestamp = timestamp,
				from = stubRandomAddress,
			}
			_G.DemandFactor.currentDemandFactor = demandFactor

			assert.are.equal(expectedCost, arns.getTokenCost(intendedAction).tokenCost)
		end)

		it(
			"should throw an error if trying to increase undername limit of a leased record in the grace period",
			function()
				_G.NameRegistry.records["test-name"] = {
					endTimestamp = 10000000,
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				local status, error = pcall(arns.getTokenCost, {
					intent = "Increase-Undername-Limit",
					quantity = 5,
					name = "test-name",
					currentTimestamp = 10000000 + 1, -- in the grace period
				})
				assert.is_false(status)
				assert.match("Name must be active to increase undername limit", error)
			end
		)
		it(
			"should throw an error if trying to increase undername limit of a leased record that is expired beyond its grace period",
			function()
				_G.NameRegistry.records["test-name"] = {
					endTimestamp = timestamp - 1, -- expired
					processId = testProcessId,
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				local status, error = pcall(arns.getTokenCost, {
					intent = "Increase-Undername-Limit",
					quantity = 5,
					name = "test-name",
					currentTimestamp = timestamp + gracePeriodMs + 1, -- expired beyond grace period
				})
				assert.is_false(status)
				assert.match("Name must be active to increase undername limit", error)
			end
		)
		it("should throw an error if trying to extend a lease of a permanently owned name", function()
			_G.NameRegistry.records["test-name"] = {
				endTimestamp = nil,
				processId = testProcessId,
				purchasePrice = basePriceForNineLetterName,
				startTimestamp = 0,
				type = "permabuy",
				undernameLimit = 10,
			}
			local status, error = pcall(arns.getTokenCost, {
				intent = "Extend-Lease",
				years = 2,
				name = "test-name",
				currentTimestamp = timestamp + constants.yearsToMs(1),
			})
			assert.is_false(status)
			assert.match("Name is permanently owned and cannot be extended", error)
		end)
	end)

	describe("getCostDetailsForAction", function()
		it("should match getTokenCost logic but with { tokenCost: number, discounts: table } shape", function()
			local years = 2
			local demandFactor = 0.974
			local expectedCost = math.floor((years * baseFee * operatorDiscountRate) + baseFee) * demandFactor
			local intendedAction = {
				intent = "Buy-Name",
				purchaseType = "lease",
				years = 2,
				name = "test-name",
				currentTimestamp = timestamp,
			}
			_G.DemandFactor.currentDemandFactor = demandFactor
			assert.are.equal(expectedCost, arns.getTokenCost(intendedAction).tokenCost)
		end)
	end)

	describe("pruneRecords", function()
		it(
			"should prune records older than the grace period and update the `NextRecordsPruneTimestamp` to the minimum record end timestamp plus grace period",
			function()
				local currentTimestamp = 2000000000

				_G.NameRegistry = {
					returned = {},
					reserved = {},
					records = {
						["active-record"] = {
							endTimestamp = 2001000000, -- far in the future
							processId = "active-process-id",
							purchasePrice = basePriceForNineLetterName,
							startTimestamp = 0,
							type = "lease",
							undernameLimit = 10,
						},
						["active-record-2"] = {
							endTimestamp = 10005000000, -- far in the future
							processId = "active-process-id-2",
							purchasePrice = basePriceForNineLetterName,
							startTimestamp = 0,
							type = "lease",
							undernameLimit = 10,
						},
						["expired-record"] = {
							endTimestamp = 790399999, -- expired and past the grace period
							processId = "expired-process-id",
							purchasePrice = 400000000,
							startTimestamp = 0,
							type = "lease",
							undernameLimit = 5,
						},
						["grace-period-record"] = {
							endTimestamp = currentTimestamp - gracePeriodMs + 10, -- expired, but within grace period
							processId = "grace-process-id",
							purchasePrice = 500000000,
							startTimestamp = 0,
							type = "lease",
							undernameLimit = 8,
						},
						["permabuy-record"] = {
							endTimestamp = nil,
							processId = "permabuy-process-id",
							purchasePrice = basePriceForNineLetterName,
							startTimestamp = 0,
							type = "permabuy",
							undernameLimit = 10,
						},
					},
				}
				local prunedRecords, newGracePeriodRecords =
					arns.pruneRecords(currentTimestamp, _G.LastGracePeriodEntryEndTimestamp)
				assert.are.same({
					["active-record"] = {
						endTimestamp = 2001000000, -- far in the future
						processId = "active-process-id",
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 10,
					},
					["active-record-2"] = {
						endTimestamp = 10005000000, -- very far in the future
						processId = "active-process-id-2",
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 10,
					},
					["grace-period-record"] = {
						endTimestamp = currentTimestamp - gracePeriodMs + 10, -- expired, but within grace period
						processId = "grace-process-id",
						purchasePrice = 500000000,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 8,
					},
					["permabuy-record"] = {
						endTimestamp = nil,
						processId = "permabuy-process-id",
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = "permabuy",
						undernameLimit = 10,
					},
				}, _G.NameRegistry.records)
				assert.are.same({
					["expired-record"] = {
						endTimestamp = currentTimestamp - gracePeriodMs - 1, -- expired and past the grace period
						processId = "expired-process-id",
						purchasePrice = 400000000,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 5,
					},
				}, prunedRecords)
				assert.are.same({
					["grace-period-record"] = {
						endTimestamp = currentTimestamp - gracePeriodMs + 10, -- expired, but within grace period
						processId = "grace-process-id",
						purchasePrice = 500000000,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 8,
					},
				}, newGracePeriodRecords)

				-- advance time, run again, and ensure the grace period record is not in the grace period list again
				local gracePeriodRecordEndTimestamp = currentTimestamp - gracePeriodMs + 10
				currentTimestamp = currentTimestamp + gracePeriodMs + 1
				prunedRecords, newGracePeriodRecords =
					arns.pruneRecords(currentTimestamp, gracePeriodRecordEndTimestamp)
				assert.are.same({
					["active-record"] = {
						endTimestamp = 2001000000,
						processId = "active-process-id",
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 10,
					},
					["active-record-2"] = {
						endTimestamp = 10005000000, -- very far in the future
						processId = "active-process-id-2",
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 10,
					},
					["permabuy-record"] = {
						endTimestamp = nil,
						processId = "permabuy-process-id",
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = "permabuy",
						undernameLimit = 10,
					},
				}, _G.NameRegistry.records)
				assert.are.same({
					["grace-period-record"] = {
						endTimestamp = 790400010,
						processId = "grace-process-id",
						purchasePrice = 500000000,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 8,
					},
				}, prunedRecords)
				-- active record has entered grace period
				assert.are.same({
					["active-record"] = {
						endTimestamp = 2001000000,
						processId = "active-process-id",
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 10,
					},
				}, newGracePeriodRecords)
				-- ensure the next prune timestamp is updated to the grace period record end timestamp
				assert.are.equal(
					_G.NameRegistry.records["active-record"].endTimestamp + constants.daysToMs(14),
					_G.NextRecordsPruneTimestamp
				)
			end
		)

		it("should skip pruning when possible", function()
			local currentTimestamp = 2000000000
			--- force an invariant case (next prune timestamp after next prunable end timestamp) to prove the point
			_G.NextRecordsPruneTimestamp = currentTimestamp + 1
			_G.NameRegistry = {
				returned = {},
				reserved = {},
				records = {
					["expired-record"] = {
						endTimestamp = 790399999, -- expired and past the grace period
						processId = "expired-process-id",
						purchasePrice = 400000000,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 5,
					},
				},
			}
			local prunedRecords, newGracePeriodRecords =
				arns.pruneRecords(currentTimestamp, _G.LastGracePeriodEntryEndTimestamp)
			assert.are.same({
				-- escaped pruning due to the forced invariance
				["expired-record"] = {
					endTimestamp = 790399999,
					processId = "expired-process-id",
					purchasePrice = 400000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 5,
				},
			}, _G.NameRegistry.records)
			assert.are.same({}, prunedRecords)
			assert.are.same({}, newGracePeriodRecords)
			assert.are.equal(currentTimestamp + 1, _G.NextRecordsPruneTimestamp)
		end)
	end)

	describe("getArNSStatsAtTimestamp", function()
		it("should return the correct ArNS stats", function()
			local currentTimestamp = gracePeriodMs
			_G.NameRegistry = {
				returned = {
					["returned-record"] = {
						name = "returned-record",
						startTimestamp = currentTimestamp - 1,
					},
					-- this should not be counted as a returned name since it's expired
					["expired-returned"] = {
						name = "expired-returned",
						startTimestamp = currentTimestamp - returnedNameMs - 1,
					},
				},
				reserved = {
					["reserved-record"] = {
						endTimestamp = 2000000000,
					},
					-- this should not be counted as a reserved name since it's expired
					["expired-reserved"] = {
						endTimestamp = 0,
					},
					["permabuy-reserved"] = {
						target = "some-wallet-address",
					},
				},
				records = {
					["active-record"] = {
						startTimestamp = 0,
						type = "lease",
						endTimestamp = currentTimestamp * 2,
					},
					-- this should not be counted as an active name since it's expired
					["expired-record"] = {
						startTimestamp = 0,
						type = "lease",
						endTimestamp = 0,
					},
					-- this should not be counted as an active name since it starts after the current timestamp
					["future-record"] = {
						startTimestamp = currentTimestamp + 1,
						type = "lease",
						endTimestamp = currentTimestamp * 2,
					},
					["permabuy-record"] = {
						startTimestamp = 0,
						type = "permabuy",
						endTimestamp = nil,
					},
					-- record is in the grace period at the current timestamp
					["grace-period-record"] = {
						startTimestamp = 0,
						type = "lease",
						endTimestamp = currentTimestamp - gracePeriodMs + 1,
					},
				},
			}
			local arnsStats = arns.getArNSStatsAtTimestamp(currentTimestamp)
			assert.are.equal(2, arnsStats.totalActiveNames)
			assert.are.equal(1, arnsStats.totalGracePeriodNames)
			assert.are.equal(2, arnsStats.totalReservedNames)
			assert.are.equal(1, arnsStats.totalReturnedNames)
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

	describe("pruneReturnedNames", function()
		local currentTimestamp = 1000000
		local expiredReturnedName = {
			name = "expired-returned-name",
			startTimestamp = currentTimestamp - returnedNameMs - 1,
			initiator = "test-initiator",
		}
		local activeReturnedName = {
			name = "active-returned-name",
			startTimestamp = currentTimestamp - returnedNameMs + 1,
			initiator = "test-initiator",
		}

		after_each(function()
			_G.NextReturnedNamesPruneTimestamp = 0
		end)

		it("should remove returned names after the returned name period", function()
			_G.NameRegistry.returned = {
				["active-returned-name"] = activeReturnedName,
				["expired-returned-name"] = expiredReturnedName,
			}
			local prunedReturnedNames = arns.pruneReturnedNames(currentTimestamp)
			assert.are.same({
				["expired-returned-name"] = expiredReturnedName,
			}, prunedReturnedNames)
			assert.are.same({
				["active-returned-name"] = activeReturnedName,
			}, _G.NameRegistry.returned)
		end)

		it("should skip pruning returned names when possible", function()
			_G.NextReturnedNamesPruneTimestamp = currentTimestamp + 1 -- force invariant case for test
			_G.NameRegistry.returned = {
				["expired-returned-name"] = expiredReturnedName,
			}
			local prunedReturnedNames = arns.pruneReturnedNames(currentTimestamp)
			assert.are.same({}, prunedReturnedNames)
			assert.are.same({
				["expired-returned-name"] = expiredReturnedName,
			}, _G.NameRegistry.returned)
			assert.are.equal(currentTimestamp + 1, _G.NextReturnedNamesPruneTimestamp)
		end)
	end)

	describe("getRegistrationFees", function()
		it("should return the correct registration prices", function()
			local registrationFees = arns.getRegistrationFees()

			-- check first, middle and last name lengths
			assert.are.equal(utils.lengthOfTable(registrationFees), 51)
			assert.are.equal(registrationFees["1"].lease["1"], 1200000000000)
			assert.are.equal(registrationFees["5"].lease["3"], 4000000000)
			assert.are.equal(registrationFees["10"].permabuy, 1750000000)
			assert.are.equal(registrationFees["10"].lease["5"], 700000000)
			assert.are.equal(registrationFees["51"].lease["1"], 240000000)
		end)
	end)

	describe("returnedNames", function()
		describe("createReturnedName", function()
			it("should create a returned name", function()
				local returnedName = arns.createReturnedName("test-name", 1000000)
				assert(returnedName, "Name should be returned")
				assert.are.equal(returnedName.name, "test-name")
				assert.are.equal(returnedName.startTimestamp, 1000000)
				assert.are.equal(_G.NameRegistry.records["test-name"], nil)
				assert.are.equal(_G.NameRegistry.returned["test-name"], returnedName)
			end)

			it("should throw an error if the name is already in the returned map", function()
				_G.NameRegistry.returned = {
					["test-name"] = {
						name = "test-name",
						startTimestamp = 1000000,
					},
				}
				local status, error = pcall(arns.createReturnedName, "test-name", 1000000)
				assert.is_false(status)
				assert.match("Returned name already exists", error)
			end)

			it("should throw an error if the name is reserved", function()
				_G.NameRegistry.reserved["test-name"] = {
					endTimestamp = 1000000,
				}
				local status, error = pcall(arns.createReturnedName, "test-name", 1000000)
				assert.is_false(status)
				assert.match("Name is reserved. Returned names can only be created for unregistered names.", error)
			end)

			it("should throw an error if the name is registered", function()
				_G.NameRegistry.records["test-name"] = {
					endTimestamp = nil,
					processId = "test-process-id",
					purchasePrice = basePriceForNineLetterName,
					startTimestamp = 0,
					type = "permabuy",
					undernameLimit = 10,
				}
				local status, error = pcall(arns.createReturnedName, "test-name", 1000000)
				assert.is_false(status)
				assert.match("Name is registered. Returned names can only be created for unregistered names.", error)
			end)
		end)

		describe("getReturnedNameUnsafe", function()
			it("should return the returnedName", function()
				local returnedName = arns.createReturnedName("test-name", 1000000, "test-initiator")
				local retrievedReturnedName = arns.getReturnedNameUnsafe("test-name")
				assert.are.same(retrievedReturnedName, returnedName)
			end)

			it("should throw an error if the returnedName is not found", function()
				local nonexistentReturnedName = arns.getReturnedNameUnsafe("nonexistent-returnedName")
				assert.is_nil(nonexistentReturnedName)
			end)
		end)

		describe("getReturnedNamePremiumMultiplier", function()
			it("should return the correct multiplier for a returned name", function()
				local startTimestamp = 1000000
				local currentTimestamp = 1000000 + returnedNameMs / 2
				local multiplier = arns.getReturnedNamePremiumMultiplier(startTimestamp, currentTimestamp)
				assert.are.equal(50 / 2, multiplier)
			end)

			it("should throw an error if provided timestamps fall outside the returned name period", function()
				local startTimestamp = 1000000
				local currentTimestamp = 1000000 + returnedNameMs + 1
				local status, error = pcall(arns.getReturnedNamePremiumMultiplier, startTimestamp, currentTimestamp)
				assert.is_false(status)
				assert.match("Current timestamp is after the returned name period", error)
			end)

			it("should throw an error if the provided timestamp falls before the start timestamp", function()
				local startTimestamp = 1000000
				local currentTimestamp = 999999
				local status, error = pcall(arns.getReturnedNamePremiumMultiplier, startTimestamp, currentTimestamp)
				assert.is_false(status)
				assert.match("Current timestamp must be after the start timestamp", error)
			end)
		end)

		describe("upgradeRecord", function()
			it("should upgrade a leased record to permanently owned", function()
				_G.NameRegistry.records["upgrade-name"] = {
					endTimestamp = 1000000,
					processId = "test-process-id",
					purchasePrice = 1000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				_G.Balances[testAddressArweave] = 1250000000
				local updatedRecord = arns.upgradeRecord(testAddressArweave, "upgrade-name", 1000000, "msgId")
				assert.are.same({
					name = "upgrade-name",
					record = {
						endTimestamp = nil,
						processId = "test-process-id",
						purchasePrice = 1250000000,
						startTimestamp = 0,
						type = "permabuy",
						undernameLimit = 10,
					},
					totalFee = 1250000000,
					baseRegistrationFee = 250000000,
					remainingBalance = 0,
					protocolBalance = 1250000000,
					df = demand.getDemandFactorInfo(),
					fundingPlan = {
						address = testAddressArweave,
						balance = 1250000000,
						stakes = {},
						shortfall = 0,
					},
					fundingResult = {
						totalFunded = 1250000000,
						newWithdrawVaults = {},
					},
				}, updatedRecord)
			end)

			it("should apply the ArNS discount to the upgrade cost", function()
				_G.GatewayRegistry[stubRandomAddress] = testGateway
				_G.GatewayRegistry[stubRandomAddress].weights = {
					tenureWeight = minimumTenureWeightForDiscount,
					gatewayPerformanceRatio = minimumPerformanceRateForDiscount,

					normalizedCompositeWeight = 1,
					stakeWeight = 1,
					observerPerformanceRatio = 1,
					compositeWeight = 1,
				}
				_G.NameRegistry.records["upgrade-name"] = {
					endTimestamp = 1000000,
					processId = "test-process-id",
					purchasePrice = 1000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				_G.Balances[stubRandomAddress] = 1250000000
				assert(gar.isEligibleForArNSDiscount(stubRandomAddress))
				local updatedRecord = arns.upgradeRecord(stubRandomAddress, "upgrade-name", 1000000, "msgId")

				local expectedCost = 1250000000 - (math.floor(1250000000 * operatorDiscountRate))

				assert.are.same({
					name = "upgrade-name",
					record = {
						endTimestamp = nil,
						processId = "test-process-id",
						purchasePrice = expectedCost,
						startTimestamp = 0,
						type = "permabuy",
						undernameLimit = 10,
					},
					totalFee = expectedCost,
					baseRegistrationFee = 250000000,
					remainingBalance = 250000000,
					protocolBalance = expectedCost,
					df = demand.getDemandFactorInfo(),
					fundingPlan = {
						address = stubRandomAddress,
						balance = expectedCost,
						stakes = {},
						shortfall = 0,
					},
					fundingResult = {
						totalFunded = expectedCost,
						newWithdrawVaults = {},
					},
				}, updatedRecord)
			end)

			it("should throw an error if the name is not registered", function()
				local status, error = pcall(arns.upgradeRecord, testAddressArweave, "upgrade-name", 1000000)
				assert.is_false(status)
				assert.match("Name is not registered", error)
			end)

			it("should throw an error if the record is permanently owned", function()
				_G.NameRegistry.records["upgrade-name"] = {
					endTimestamp = nil,
					processId = "test-process-id",
					purchasePrice = 1000000,
					startTimestamp = 0,
					type = "permabuy",
					undernameLimit = 10,
				}
				local status, error = pcall(arns.upgradeRecord, testAddressArweave, "upgrade-name", 1000000)
				assert.is_false(status)
				assert.match("Name is permanently owned", error)
			end)

			it("should throw an error if the record is expired", function()
				local currentTimestamp = 1000000 + returnedNameMs + 1
				_G.NameRegistry.records["upgrade-name"] = {
					endTimestamp = 1000000,
					processId = "test-process-id",
					purchasePrice = 1000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				local status, error = pcall(arns.upgradeRecord, testAddressArweave, "upgrade-name", currentTimestamp)
				assert.is_false(status)
				assert(error, "Expected error")
				assert.match("Name is expired", error)
			end)

			it("should throw an error if the sender does not have enough balance", function()
				_G.NameRegistry.records["upgrade-name"] = {
					endTimestamp = 1000000,
					processId = "test-process-id",
					purchasePrice = 1000000,
					startTimestamp = 0,
					type = "lease",
					undernameLimit = 10,
				}
				_G.Balances[testAddressArweave] = 1250000000 - 1 -- 1 less than the upgrade cost for a 12-letter name
				local status, error = pcall(arns.upgradeRecord, testAddressArweave, "upgrade-name", 1000000)
				assert.is_false(status)
				assert.match("Insufficient balance", error)
			end)
		end)
	end)

	describe("getPaginatedRecords", function()
		before_each(function()
			_G.NameRegistry = {
				records = {
					["active-record"] = {
						endTimestamp = 100, -- far in the future
						processId = "oldest-process-id",
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 10,
					},
					["active-record-1"] = {
						endTimestamp = 10000,
						processId = "middle-process-id",
						purchasePrice = 400000000,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 5,
					},
					["active-record-2"] = {
						endTimestamp = 10000000,
						processId = "newest-process-id",
						purchasePrice = 500000000,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 8,
					},
					["permabuy-record"] = {
						endTimestamp = nil,
						processId = "permabuy-process-id",
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = "permabuy",
						undernameLimit = 10,
					},
				},
			}
		end)

		it("should return the correct paginated records with ascending putting permabuy at the end", function()
			local paginatedRecords = arns.getPaginatedRecords(nil, 1, "endTimestamp", "asc")
			assert.are.same({
				limit = 1,
				sortBy = "endTimestamp",
				sortOrder = "asc",
				hasMore = true,
				totalItems = 4,
				nextCursor = "active-record",
				items = {
					{
						name = "active-record",
						endTimestamp = 100,
						processId = "oldest-process-id",
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 10,
					},
				},
			}, paginatedRecords)
			local paginatedRecords2 = arns.getPaginatedRecords(paginatedRecords.nextCursor, 1, "endTimestamp", "asc")
			assert.are.same({
				limit = 1,
				sortBy = "endTimestamp",
				sortOrder = "asc",
				hasMore = true,
				totalItems = 4,
				nextCursor = "active-record-1",
				items = {
					{
						name = "active-record-1",
						endTimestamp = 10000,
						processId = "middle-process-id",
						purchasePrice = 400000000,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 5,
					},
				},
			}, paginatedRecords2)
			local paginatedRecords3 = arns.getPaginatedRecords(paginatedRecords2.nextCursor, 1, "endTimestamp", "asc")
			assert.are.same({
				limit = 1,
				sortBy = "endTimestamp",
				sortOrder = "asc",
				hasMore = true,
				totalItems = 4,
				nextCursor = "active-record-2",
				items = {
					{
						name = "active-record-2",
						endTimestamp = 10000000,
						processId = "newest-process-id",
						purchasePrice = 500000000,
						startTimestamp = 0,
						type = "lease",
						undernameLimit = 8,
					},
				},
			}, paginatedRecords3)
			local paginatedRecords4 = arns.getPaginatedRecords(paginatedRecords3.nextCursor, 1, "endTimestamp", "asc")
			assert.are.same({
				limit = 1,
				sortBy = "endTimestamp",
				sortOrder = "asc",
				hasMore = false,
				totalItems = 4,
				nextCursor = nil,
				items = {
					{
						name = "permabuy-record",
						endTimestamp = nil,
						processId = "permabuy-process-id",
						purchasePrice = basePriceForNineLetterName,
						startTimestamp = 0,
						type = "permabuy",
						undernameLimit = 10,
					},
				},
			}, paginatedRecords4)
		end)
	end)

	describe("getPaginatedReservedNames", function()
		before_each(function()
			_G.NameRegistry.reserved = {
				["reserved-name-1"] = {
					target = "reserved-name-1-target",
				},
				["reserved-name-2"] = {
					target = "reserved-name-2-target",
				},
			}
		end)
		it("should return the correct paginated reserved names", function()
			local paginatedReservedNames = arns.getPaginatedReservedNames(nil, 1, "name", "desc")
			assert.are.same({
				limit = 1,
				sortBy = "name",
				sortOrder = "desc",
				hasMore = true,
				totalItems = 2,
				nextCursor = "reserved-name-2",
				items = {
					{
						name = "reserved-name-2",
						target = "reserved-name-2-target",
					},
				},
			}, paginatedReservedNames)
		end)
	end)
end)
