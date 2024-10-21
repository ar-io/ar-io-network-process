local testProcessId = "NdZ3YRwMB2AMwwFYjKn1g88Y9nRybTo0qhS1ORq_E7g"
local constants = require("constants")
local arns = require("arns")
local balances = require("balances")
local demand = require("demand")
local utils = require("utils")
local Auction = require("auctions")

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
			auctions = {},
		}
		_G.Balances = {
			[testAddressArweave] = startBalance,
			[testAddressEth] = startBalance,
		}
		_G.DemandFactor.currentDemandFactor = 1.0
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

	describe("getTokenCost", function()
		it("should return the correct token cost for a lease", function()
			local baseFee = 500000000
			local years = 2
			local demandFactor = 0.974
			local expectedCost = math.floor((years * baseFee * 0.20) + baseFee) * demandFactor
			local intendedAction = {
				intent = "Buy-Record",
				purchaseType = "lease",
				years = 2,
				name = "test-name",
			}
			_G.DemandFactor.currentDemandFactor = demandFactor
			assert.are.equal(expectedCost, arns.getTokenCost(intendedAction))
		end)
		it("should return the correct token cost for a permabuy", function()
			local baseFee = 500000000
			local demandFactor = 1.052
			local expectedCost = math.floor((baseFee * 0.2 * 20) + baseFee) * demandFactor
			local intendedAction = {
				intent = "Buy-Record",
				purchaseType = "permabuy",
				name = "test-name",
			}
			_G.DemandFactor.currentDemandFactor = demandFactor
			assert.are.equal(expectedCost, arns.getTokenCost(intendedAction))
		end)
		it("should return the correct token cost for an undername", function()
			_G.NameRegistry.records["test-name"] = {
				endTimestamp = constants.oneYearMs,
				processId = testProcessId,
				purchasePrice = 600000000,
				startTimestamp = 0,
				type = "lease",
				undernameLimit = 10,
			}
			local baseFee = 500000000
			local undernamePercentageFee = 0.001
			local increaseQty = 5
			local demandFactor = 0.60137
			local yearsRemaining = 0.5
			local expectedCost =
				math.floor(baseFee * increaseQty * undernamePercentageFee * yearsRemaining * demandFactor)
			local intendedAction = {
				intent = "Increase-Undername-Limit",
				quantity = 5,
				name = "test-name",
				currentTimestamp = constants.oneYearMs / 2,
			}
			_G.DemandFactor.currentDemandFactor = demandFactor
			assert.are.equal(expectedCost, arns.getTokenCost(intendedAction))
		end)
		it("should return the token cost for extending a name", function()
			_G.NameRegistry.records["test-name"] = {
				endTimestamp = timestamp + constants.oneYearMs,
				processId = testProcessId,
				purchasePrice = 600000000,
				startTimestamp = 0,
				type = "lease",
				undernameLimit = 10,
			}
			local baseFee = 500000000
			local years = 2
			local demandFactor = 1.2405
			local expectedCost = math.floor((years * baseFee * 0.20) * demandFactor)
			local intendedAction = {
				intent = "Extend-Lease",
				years = 2,
				name = "test-name",
			}
			_G.DemandFactor.currentDemandFactor = demandFactor
			assert.are.equal(expectedCost, arns.getTokenCost(intendedAction))
		end)
	end)

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

	describe("pruneAuctions", function()
		it("should remove expired auctions", function()
			local currentTimestamp = 1000000
			local existingAuction = Auction:new(
				"active-auction",
				currentTimestamp,
				1000 * 60 * 60 * 24 * 14,
				0.020379 / (1000 * 60 * 60 * 24 * 14),
				190,
				1,
				1000000000,
				"test-initiator"
			)
			local expiredAuction = Auction:new(
				"expired-auction",
				currentTimestamp - 1,
				0, -- ended after 0 ms
				0.020379 / (1000 * 60 * 60 * 24 * 14),
				190,
				1,
				1000000000,
				"test-initiator"
			)
			_G.NameRegistry.auctions = {
				["active-auction"] = existingAuction,
				["expired-auction"] = expiredAuction,
			}
			local prunedAuctions = arns.pruneAuctions(currentTimestamp)
			assert.are.same({
				["expired-auction"] = expiredAuction,
			}, prunedAuctions)
			assert.are.same({
				["active-auction"] = existingAuction,
			}, _G.NameRegistry.auctions)
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

	describe("auctions", function()
		before_each(function()
			_G.NameRegistry.records["test-name"] = {
				endTimestamp = nil,
				processId = "test-process-id",
				purchasePrice = 600000000,
				startTimestamp = 0,
				type = "permabuy",
				undernameLimit = 10,
			}
		end)

		describe("createAuction", function()
			it("should create an auction and remove any existing record", function()
				local auction = arns.createAuction("test-name", 1000000, "test-initiator"):decode()
				local twoWeeksMs = 1000 * 60 * 60 * 24 * 14
				assert.are.equal(auction.name, "test-name")
				assert.are.equal(auction.startTimestamp, 1000000)
				assert.are.equal(auction.endTimestamp, twoWeeksMs + 1000000) -- 14 days late
				assert.are.equal(auction.baseFee, 500000000)
				assert.are.equal(auction.demandFactor, 1)
				assert.are.equal(auction.decayRate, 0.020379 / (1000 * 60 * 60 * 24 * 14))
				assert.are.equal(auction.scalingExponent, 190)
				assert.are.equal(auction.initiator, "test-initiator")
				assert.are.equal(NameRegistry.records["test-name"], nil)
			end)

			it("should throw an error if the name is already in the auction map", function()
				local existingAuction = Auction:new(
					"test-name",
					1000000,
					1000 * 60 * 60 * 24 * 14,
					0.020379 / (1000 * 60 * 60 * 24 * 14),
					190,
					1,
					500000000,
					"test-initiator"
				)
				_G.NameRegistry.auctions = {
					["test-name"] = existingAuction,
				}
				local status, error = pcall(arns.createAuction, "test-name", 1000000, "test-initiator")
				assert.is_false(status)
				assert.match("Auction already exists", error)
			end)

			it("should throw an error if the name is not registered", function()
				_G.NameRegistry.records["test-name"] = nil
				local status, error = pcall(arns.createAuction, "test-name", 1000000, "test-initiator")
				assert.is_false(status)
				assert.match("Name is not registered", error)
			end)
		end)

		describe("getAuction", function()
			it("should return the auction", function()
				local auction = arns.createAuction("test-name", 1000000, "test-initiator")
				local retrievedAuction = arns.getAuction("test-name")
				assert.are.same(retrievedAuction, auction)
			end)
		end)

		describe("getCurrentBidPriceForAuction", function()
			it("should return the correct price for an auction at a given timestamp for a permabuy", function()
				local startTimestamp = 1000000
				local auction = arns.createAuction("test-name", startTimestamp, "test-initiator")
				local currentTimestamp = startTimestamp + 1000 * 60 * 60 * 24 * 7 -- 1 week into the auction
				local decayRate = 0.020379 / (1000 * 60 * 60 * 24 * 14)
				local scalingExponent = 190
				local expectedStartPrice = arns.calculateRegistrationFee(
					"permabuy",
					auction.baseFee,
					nil,
					auction.demandFactor
				) * 50
				local timeSinceStart = currentTimestamp - auctionDecoded.startTimestamp
				local totalDecaySinceStart = decayRate * timeSinceStart
				local expectedPriceAtTimestamp =
					math.floor(expectedStartPrice * ((1 - totalDecaySinceStart) ^ scalingExponent))
				local priceAtTimestamp = auction:getPriceForAuctionAtTimestamp(currentTimestamp, "permabuy", nil)
				assert.are.equal(expectedPriceAtTimestamp, priceAtTimestamp)
			end)
		end)

		describe("computePricesForAuction", function()
			it("should return the correct prices for an auction", function()
				local startTimestamp = 1729524023521
				local auction = arns.createAuction("test-name", startTimestamp, "test-initiator")
				local auctionDecoded = auction:decode()
				local startPriceForLease = arns.calculateRegistrationFee(
					"lease",
					auctionDecoded.baseFee,
					1,
					auctionDecoded.demandFactor
				) * 50
				local intervalMs = 1000 * 60 * 15 -- 15 min (how granular we want to compute the prices)
				local prices = auction:computePricesForAuction(1, "lease", intervalMs)
				-- create the curve of prices
				local decayRate = auctionDecoded.decayRate
				local scalingExponent = auctionDecoded.scalingExponent
				for i = startTimestamp, auctionDecoded.endTimestamp, intervalMs do
					local timeSinceStart = i - auctionDecoded.startTimestamp
					local totalDecaySinceStart = decayRate * timeSinceStart
					local expectedPriceAtTimestamp =
						math.floor(startPriceForLease * ((1 - totalDecaySinceStart) ^ scalingExponent))
					assert.are.equal(
						prices[i],
						expectedPriceAtTimestamp,
						"Price at timestamp" .. i .. " should be " .. expectedPriceAtTimestamp
					)
				end
				-- make sure the last price at the end of the auction is the floor price
				local lastPrice = prices[auctionDecoded.endTimestamp]
				local listPricePercentDifference = (lastPrice - auctionDecoded.floorPrice) / auctionDecoded.floorPrice
				assert.is_true(
					listPricePercentDifference <= 0.0001,
					"Last price should be within 0.01% of the floor price. Last price: "
						.. lastPrice
						.. " Floor price: "
						.. auctionDecoded.floorPrice
				)
			end)
		end)

		describe("submitAuctionBid", function()
			it(
				"should accept bid on an existing auction and transfer tokens to the auction initiator and protocol balance, and create the record",
				function()
					local startTimestamp = 1000000
					local bidTimestamp = startTimestamp + 1000 * 60 * 2 -- 2 min into the auction
					local demandBefore = demand.getCurrentPeriodPurchases()
					local revenueBefore = demand.getCurrentPeriodRevenue()
					local auction = arns.createAuction("test-name", startTimestamp, "test-initiator")
					local auctionDecoded = auction and auction:decode()
					local result = arns.submitAuctionBid(
						"test-name",
						auctionDecoded.startPrice,
						testAddressArweave,
						bidTimestamp,
						"test-process-id"
					)
					local balances = balances.getBalances()
					local expectedPrice = math.floor(
						auctionDecoded.startPrice
							* (
								(1 - (auctionDecoded.decayRate * (bidTimestamp - startTimestamp)))
								^ auctionDecoded.scalingExponent
							)
					)
					local expectedRecord = {
						endTimestamp = nil,
						processId = "test-process-id",
						purchasePrice = expectedPrice,
						startTimestamp = bidTimestamp,
						type = "permabuy",
						undernameLimit = 10,
					}
					local expectedInitiatorReward = math.floor(expectedPrice * 0.5)
					local expectedProtocolReward = expectedPrice - expectedInitiatorReward
					assert.are.equal(expectedInitiatorReward, balances["test-initiator"])
					assert.are.equal(expectedProtocolReward, balances[_G.ao.id])
					assert.are.equal(nil, NameRegistry.auctions["test-name"])
					assert.are.same(expectedRecord, NameRegistry.records["test-name"])
					assert.are.same(expectedRecord, result.record)
					assert.are.equal(
						demandBefore + 1,
						demand.getCurrentPeriodPurchases(),
						"Purchases should increase by 1"
					)
					assert.are.equal(
						revenueBefore + expectedPrice,
						demand.getCurrentPeriodRevenue(),
						"Revenue should increase by the bid amount"
					)
				end
			)

			it("should throw an error if the auction is not found", function()
				local status, error =
					pcall(arns.submitAuctionBid, "test-name-2", 1000000000, "test-bidder", 1000000, "test-process-id")
				assert.is_false(status)
				assert.match("Auction does not exist", error)
			end)

			it("should throw an error if the bid is not high enough", function()
				local startTimestamp = 1000000
				local auction = arns.createAuction("test-name", startTimestamp, "test-initiator"):decode()
				local status, error = pcall(
					arns.submitAuctionBid,
					"test-name",
					auction.startPrice - 1,
					testAddressArweave,
					startTimestamp,
					"test-process-id"
				)
				assert.is_false(status)
				assert.match("Bid amount is less than the required bid of " .. auction.startPrice, error)
			end)

			it("should throw an error if the bidder does not have enough balance", function()
				local startTimestamp = 1000000
				local auction = arns.createAuction("test-name", startTimestamp, "test-initiator")
				local requiredBid = arns.getCurrentBidPriceForAuction(auction, startTimestamp)
				_G.Balances[testAddressArweave] = requiredBid - 1
				local status, error = pcall(
					arns.submitAuctionBid,
					"test-name",
					requiredBid,
					testAddressArweave,
					startTimestamp,
					"test-process-id"
				)
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
						purchasePrice = 600000000,
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
						purchasePrice = 600000000,
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
						purchasePrice = 600000000,
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
						purchasePrice = 600000000,
						startTimestamp = 0,
						type = "permabuy",
						undernameLimit = 10,
					},
				},
			}, paginatedRecords4)
		end)
	end)
end)
