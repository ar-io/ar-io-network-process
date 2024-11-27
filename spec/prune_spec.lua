local tick = require("prune")

describe("prune", function()
	before_each(function()
		_G.NameRegistry = {
			records = {
				["test-record"] = {
					endTimestamp = 1000000,
					purchaseType = "lease",
				},
			},
			reserved = {
				["test-reserved"] = {
					endTimestamp = 1000000,
				},
			},
			auctions = {
				["test-auction"] = {
					endTimestamp = 1000000,
				},
			},
		}
		_G.PrimaryNames = {
			owners = {
				["test-primary-name-owner"] = {
					name = "test-record",
					baseName = "test-record",
					startTimestamp = 1000000,
				},
			},
			names = {
				["test-record"] = "test-primary-name-owner",
			},
			requests = {
				["test-primary-name-request"] = {
					endTimestamp = 1000000,
					name = "test-record",
				},
			},
		}
	end)

	it(
		"should prune records and related primary names, and create auctions when endtimestamp is past the grace period",
		function()
			local pruneTimestamp = 1000000 + 14 * 24 * 60 * 60 * 1000 + 1
			local result = tick.pruneState(pruneTimestamp, "msgId", 0)
			assert.are.same({
				["test-record"] = {
					endTimestamp = 1000000,
					purchaseType = "lease",
				},
			}, result.prunedRecords)
			assert.are.same({
				["test-record"] = {
					startTimestamp = pruneTimestamp,
					endTimestamp = pruneTimestamp + 14 * 24 * 60 * 60 * 1000,
					baseFee = 500000000,
					demandFactor = 1,
					initiator = "test",
					name = "test-record",
					registrationFeeCalculator = require("arns").calculateRegistrationFee,
					settings = {
						decayRate = 1.6847809193121693337e-11,
						durationMs = 1209600000,
						scalingExponent = 190,
						startPriceMultiplier = 50,
					},
				},
			}, _G.NameRegistry.auctions)
			--- check that the primary names and owners were also pruned
			assert.are.same({
				["test-record"] = {
					{
						name = "test-record",
						owner = "test-primary-name-owner",
					},
				},
			}, result.prunedPrimaryNamesAndOwners)
			assert.are.same({}, _G.PrimaryNames.owners)
			assert.are.same({}, _G.PrimaryNames.names)
		end
	)

	it("should prune auctions at the time they expire", function()
		_G.NextAuctionsPruneTimestamp = 0
		local pruneTimestamp = 1000000
		local result = tick.pruneState(pruneTimestamp, "msgId", 0)
		assert.are.same({
			["test-auction"] = {
				endTimestamp = pruneTimestamp,
			},
		}, result.prunedAuctions)
		assert.are.same({}, _G.NameRegistry.auctions)
	end)

	it("should prune reserved names, vaults, and gateways when endtimestamp is in the past", function()
		local pruneTimestamp = 1000000
		local result = tick.pruneState(pruneTimestamp, "msgId", 0)
		assert.are.same({
			["test-reserved"] = {
				endTimestamp = pruneTimestamp,
			},
		}, result.prunedReserved)
	end)

	it("should prune primary names claims when they expire", function()
		_G.NextPrimaryNamesPruneTimestamp = 0
		local pruneTimestamp = 1000000
		local result = tick.pruneState(pruneTimestamp, "msgId", 0)
		assert.are.same({
			["test-primary-name-request"] = {
				endTimestamp = pruneTimestamp,
				name = "test-record",
			},
		}, result.prunedPrimaryNameRequests)
		assert.are.same({}, _G.PrimaryNames.requests)
	end)
end)
