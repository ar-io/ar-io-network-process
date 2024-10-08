local testProcessId = "NdZ3YRwMB2AMwwFYjKn1g88Y9nRybTo0qhS1ORq_E7g"
local constants = require("constants")
local arns = require("arns")
local balances = require("balances")
local demand = require("demand")
local utils = require("utils")
local json = require("json")

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

	describe("auctions", function()
		it("should create an auction", function()
			local auction = arns.createAuction("test-name", "permabuy", 1000000, "test-initiator")
			local twoWeeksMs = 1000 * 60 * 60 * 24 * 14
			assert.are.equal(auction.name, "test-name")
			assert.are.equal(auction.type, "permabuy")
			assert.are.equal(auction.startTimestamp, 1000000)
			assert.are.equal(auction.endTimestamp, twoWeeksMs + 1000000) -- 14 days late
			assert.are.equal(auction.startPrice, 125000000000)
			assert.are.equal(auction.floorPrice, 2500000000)
			assert.are.equal(auction.initiator, "test-initiator")
		end)

		it("should throw an error if the name is already in the auction map", function()
			local auction = arns.createAuction("test-name", "permabuy", 1000000, "test-initiator")
			local status, error = pcall(arns.createAuction, "test-name", "permabuy", 1000000, "test-initiator")
			assert.is_false(status)
			assert.match("Auction already exists", error)
		end)

		describe("getAuction", function()
			it("should return the auction", function()
				local auction = arns.createAuction("test-name", "permabuy", 1000000, "test-initiator")
				local retrievedAuction = arns.getAuction("test-name")
				assert.are.equal(auction, retrievedAuction)
			end)
		end)

		it("should return the correct price for an auction at a given timestamp", function()
			local startTimestamp = 1000000
			local auction = arns.createAuction("test-name", "permabuy", startTimestamp, "test-initiator")
			assert.are.equal(auction.startPrice, auction.prices[startTimestamp])
		end)

		it("should return the correct price for an auction at a given timestamp", function()
			local startTimestamp = 1000000
			local auction = arns.createAuction("test-name", "permabuy", startTimestamp, "test-initiator")
			local auctionIntervalMs = 1000 * 60 * 2 -- ~2 min per price interval
			local intervalsSinceStart = 1
			local totalDecaySinceStart = math.min(1, 0.000002 * intervalsSinceStart)
			local secondIntervalPrice = math.floor(auction.startPrice * ((1 - totalDecaySinceStart) ^ 190))
			assert.are.equal(secondIntervalPrice, auction.prices[startTimestamp + auctionIntervalMs])
		end)

		it(
			"should accept bid on an existing auction and transfer tokens to the auction initiator and protocol balance, and create the record",
			function()
				local auction = arns.createAuction("test-name", "permabuy", 1000000, "test-initiator")
				local bid = arns.submitAuctionBid(
					"test-name",
					auction.startPrice,
					testAddressArweave,
					1000000,
					"test-process-id"
				)
				local balances = balances.getBalances()
				-- no time passed between creation and bid
				local expectedPrice = auction.startPrice
				assert.are.equal(balances["test-initiator"], expectedPrice * 0.5)
				assert.are.equal(balances[_G.ao.id], expectedPrice * 0.5)
				assert.are.equal(NameRegistry.auctions["test-name"], nil)
				assert.same({
					endTimestamp = nil,
					processId = "test-process-id",
					purchasePrice = expectedPrice,
					startTimestamp = 1000000,
					type = "permabuy",
					undernameLimit = 10,
				}, NameRegistry.records["test-name"])
			end
		)

		it("should throw an error if the auction is not found", function()
			local status, error =
				pcall(arns.submitAuctionBid, "test-name-2", 1000000000, "test-bidder", 1000000, "test-process-id")
			assert.is_false(status)
			assert.match("Auction does not exist", error)
		end)
	end)

	-- describe("getPricesForAuction", function()
	-- 	it("should return the correct prices for an auction", function()
	-- 		local auction = {
	-- 			startTimestamp = 1000000,
	-- 			endTimestamp = 10000000,
	-- 			startPrice = 1000000000,
	-- 		}
	-- 		local prices = arns.getPricesForAuction(auction)
	-- 		assert.are.equal(utils.lengthOfTable(prices), 151)
	-- 		assert.are.equal(prices[1000000], 1000000000)
	-- 		assert.are.equal(prices[10000000], 1000000000)
	-- 	end)
	-- end)

	-- describe("getPriceForAuctionAtTimestamp", function()
	-- 	it("should return the correct price for an auction at a given timestamp", function()
	-- 		local auction = {
	-- 			startTimestamp = 1000000,
	-- 			endTimestamp = 10000000,
	-- 			startPrice = 5000000000,
	-- 			floorPrice = 100000000,
	-- 		}
	-- 		local price = arns.getPriceForAuctionAtTimestamp(auction, 1000000)
	-- 		assert.are.equal(price, 1000000000)
	-- 	end)
	-- end)

	-- describe("createAuction", function()
	-- 	it("should create an auction", function()
	-- 		local auction = arns.createAuction("test-name", "permabuy", 1000000, "test-initiator")
	-- 		assert.are.equal(auction.name, "test-name")
	-- 		assert.are.equal(auction.type, "permabuy")
	-- 		assert.are.equal(auction.startTimestamp, 1000000)
	-- 		assert.are.equal(auction.endTimestamp, 10000000)
	-- 		assert.are.equal(auction.startPrice, 1000000000)
	-- 	end)
	-- end)

	-- describe("submitAuctionBid", function()
	-- 	it("should submit a bid", function()
	-- 		local auction = arns.createAuction("test-name", "permabuy", 1000000, "test-initiator")
	-- 		local bid = arns.submitAuctionBid(auction, 1000000000, "test-bidder", 1000000)
	-- 		assert.are.equal(bid.name, "test-name")
	-- 		assert.are.equal(bid.type, "permabuy")
	-- 		assert.are.equal(bid.startTimestamp, 1000000)
	-- 		assert.are.equal(bid.endTimestamp, 10000000)
	-- 		assert.are.equal(bid.startPrice, 1000000000)
	-- 	end)

	-- 	it("should throw an error if the bid is less than the required bid", function()
	-- 		local auction = arns.createAuction("test-name", "permabuy", 1000000, "test-initiator")
	-- 		local status, error = pcall(arns.submitAuctionBid, auction, 1000000, "test-bidder", 1000000)
	-- 		assert.is_false(status)
	-- 		assert.match("Bid amount is less than the required bid", error)
	-- 	end)

	-- 	it("should throw an error if the auction is not found", function()
	-- 		local status, error = pcall(arns.submitAuctionBid, "test-name", 1000000000, "test-bidder", 1000000)
	-- 		assert.is_false(status)
	-- 		assert.match("Auction does not exist", error)
	-- 	end)

	-- 	it("should throw an error if the bidder has insufficient balance", function()
	-- 		local auction = arns.createAuction("test-name", "permabuy", 1000000, testAddressEth)
	-- 		local status, error = pcall(arns.submitAuctionBid, auction, 1000000000, testAddressArweave, 1000000)
	-- 		assert.is_false(status)
	-- 		assert.match("Insufficient balance", error)
	-- 	end)
	-- end)
end)
