local epochs = require("epochs")
local gar = require("gar")
local constants = require("constants")
local testSettings = {
	fqdn = "test.com",
	protocol = "https",
	port = 443,
	allowDelegatedStaking = true,
	minDelegatedStake = 100,
	autoStake = true,
	label = "test",
	delegateRewardShareRatio = 0,
}
local startTimestamp = 1704092400000
local protocolBalance = constants.ARIOToMARIO(500000000)
local hashchain = "NGU1fq_ssL9m6kRbRU1bqiIDBht79ckvAwRMGElkSOg" -- base64 of "some sample hash"

describe("epochs", function()
	before_each(function()
		_G.Balances = {
			[ao.id] = protocolBalance,
			["test-this-is-valid-arweave-wallet-address-1"] = 500000000,
		}
		_G.Epochs = {}
		_G.GatewayRegistry = {}
		_G.NameRegistry = {
			records = {},
			reserved = {},
		}
		_G.EpochSettings = {
			prescribedNameCount = 5,
			maxObservers = 5,
			epochZeroStartTimestamp = 1704092400000, -- 2024-01-01T00:00:00.000Z
			durationMs = 100,
			rewardPercentage = 0.0025, -- 0.25%
		}
	end)

	describe("getPrescribedObserversWithWeightsForEpoch", function()
		it("should return the prescribed observers with weights for the epoch", function()
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
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
				observerAddress = "observerAddress",
				weights = {
					normalizedCompositeWeight = 1,
					stakeWeight = 1,
					tenureWeight = 1,
					gatewayPerformanceRatio = 1,
					observerPerformanceRatio = 1,
					compositeWeight = 1,
				},
			}
			_G.Epochs[0] = {
				prescribedObservers = {
					["observerAddress"] = "test-this-is-valid-arweave-wallet-address-1",
				},
			}
			local epochIndex = 0
			local expectation = {
				{
					observerAddress = "observerAddress",
					gatewayAddress = "test-this-is-valid-arweave-wallet-address-1",
					normalizedCompositeWeight = 1,
					stakeWeight = 1,
					tenureWeight = 1,
					gatewayPerformanceRatio = 1,
					observerPerformanceRatio = 1,
					compositeWeight = 1,
					stake = gar.getSettings().operators.minStake,
					startTimestamp = startTimestamp,
				},
			}
			local result = epochs.getPrescribedObserversWithWeightsForEpoch(epochIndex)
			assert.are.same(expectation, result)
		end)
	end)

	describe("computePrescribedObserversForEpoch", function()
		it("should return all eligible gateways if fewer than the maximum in network", function()
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
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
				observerAddress = "observerAddress",
				weights = {
					normalizedCompositeWeight = 1,
					stakeWeight = 1,
					tenureWeight = 1,
					gatewayPerformanceRatio = 1,
					observerPerformanceRatio = 1,
					compositeWeight = 1,
				},
			}
			local expectation = {
				["observerAddress"] = "test-this-is-valid-arweave-wallet-address-1",
			}
			local prescribedObserverMap = epochs.computePrescribedObserversForEpoch(1, hashchain)
			assert.are.same(expectation, prescribedObserverMap)
		end)

		it("should return the maximum number of gateways if more are enrolled in network", function()
			local testHashchain = "c29tZSBzYW1wbGUgaGFzaA==" -- base64 of "some sample hash"
			_G.EpochSettings = {
				maxObservers = 2, -- limit to 2 observers
				epochZeroStartTimestamp = startTimestamp,
				durationMs = 60 * 1000 * 60 * 24, -- 24 hours
			}
			for i = 1, 3 do
				local gateway = {
					operatorStake = gar.getSettings().operators.minStake,
					totalDelegatedStake = 0,
					vaults = {},
					delegates = {},
					startTimestamp = startTimestamp,
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
					observerAddress = "observer-address-" .. i,
					weights = {
						normalizedCompositeWeight = 1,
						stakeWeight = 1,
						tenureWeight = 1,
						gatewayPerformanceRatio = 1,
						observerPerformanceRatio = 1,
						compositeWeight = 1,
					},
				}
				-- note - ordering of keys is not guaranteed when insert into maps
				_G.GatewayRegistry["observer" .. i] = gateway
			end

			local prescribedObserverMap = epochs.computePrescribedObserversForEpoch(1, testHashchain)
			-- Should select exactly maxObservers (2) from the 3 available gateways
			local count = 0
			for _ in pairs(prescribedObserverMap) do
				count = count + 1
			end
			assert.are.equal(2, count)
		end)
	end)

	describe("computePrescribedNamesForEpoch", function()
		-- NOTE: Record names in the tests below use spelled out numbers because without that
		-- there's insufficient base64url information encoded in the final encoded block to
		-- disambiguate the decoded values.
		it("should return all eligible names if fewer than the maximum in name registry", function()
			_G.NameRegistry.records = {
				["arns-name-one"] = {
					startTimestamp = startTimestamp,
					endTimestamp = startTimestamp + 60 * 1000 * 60 * 24 * 365, -- add a year
					type = "lease",
					purchasePrice = 0,
					undernameLimit = 10,
				},
				["arns-name-two"] = {
					startTimestamp = startTimestamp,
					type = "permabuy",
					purchasePrice = 0,
					undernameLimit = 10,
				},
			}
			local expectation = { "arns-name-two", "arns-name-one" }
			local status, result = pcall(epochs.computePrescribedNamesForEpoch, 1, hashchain)
			assert.is_true(status)
			assert.are.equal(2, #result)
			assert.are.same(expectation, result)
		end)

		it("should return a subset of eligible names if more than the maximum in the name registry", function()
			_G.NameRegistry.records = {
				["arns-name-one"] = {
					startTimestamp = startTimestamp,
					endTimestamp = startTimestamp + 60 * 1000 * 60 * 24 * 365, -- add a year
					type = "lease",
					purchasePrice = 0,
					undernameLimit = 10,
				},
				["arns-name-two"] = {
					startTimestamp = startTimestamp,
					type = "permabuy",
					purchasePrice = 0,
					undernameLimit = 10,
				},
				["arns-name-three"] = {
					startTimestamp = startTimestamp,
					endTimestamp = startTimestamp + 60 * 1000 * 60 * 24 * 365, -- add a year
					type = "lease",
					purchasePrice = 0,
					undernameLimit = 10,
				},
				["arns-name-four"] = {
					startTimestamp = startTimestamp,
					type = "permabuy",
					purchasePrice = 0,
					undernameLimit = 10,
				},
				["arns-name-five"] = {
					startTimestamp = startTimestamp,
					type = "permabuy",
					purchasePrice = 0,
					undernameLimit = 10,
				},
				["arns-name-six"] = {
					startTimestamp = startTimestamp,
					endTimestamp = startTimestamp + 60 * 1000 * 60 * 24 * 365, -- add a year
					type = "lease",
					purchasePrice = 0,
					undernameLimit = 10,
				},
			}
			local expectation =
				{ "arns-name-five", "arns-name-four", "arns-name-one", "arns-name-three", "arns-name-two" }
			local status, result = pcall(epochs.computePrescribedNamesForEpoch, 1, hashchain)
			assert.is_true(status)
			assert.are.equal(5, #result)
			assert.are.same(expectation, result)
		end)
	end)

	describe("saveObservations", function()
		it("should throw an error when saving observation too early in the epoch", function()
			local observer = "test-this-is-valid-arweave-wallet-address-2"
			local reportTxId = "test-this-very-valid-observations-report-tx"
			local timestamp = _G.EpochSettings.epochZeroStartTimestamp - 1
			local failedGateways = {
				"test-this-is-valid-arweave-wallet-address-1",
			}
			local status, error = pcall(epochs.saveObservations, observer, reportTxId, failedGateways, 0, timestamp)
			assert.is_false(status)
			assert.match(
				"Observations for epoch 0 must be submitted after " .. _G.EpochSettings.epochZeroStartTimestamp,
				error
			)
		end)
		it("should throw an error if the caller is not prescribed", function()
			local observer = "test-this-is-valid-arweave-observer-address-2"
			local reportTxId = "test-this-very-valid-observations-report-tx"
			local timestamp = _G.EpochSettings.epochZeroStartTimestamp + 1
			local failedGateways = {
				"test-this-is-valid-arweave-wallet-address-1",
			}
			_G.Epochs[0] = {
				prescribedObservers = {
					["test-this-is-valid-arweave-observer-address-1"] = "test-this-is-valid-arweave-gateway-address-1",
				},
			}
			local status, error = pcall(epochs.saveObservations, observer, reportTxId, failedGateways, 0, timestamp)
			assert.is_false(status)
			assert.match("Caller is not a prescribed observer for the current epoch.", error)
		end)
		it(
			"should save observation when the timestamp is after the distribution delay and only mark gateways around during the full epoch as failed",
			function()
				local observer = "test-this-is-valid-arweave-observer-address-2"
				local reportTxId = "test-this-very-valid-observations-report-tx"
				local timestamp = _G.EpochSettings.epochZeroStartTimestamp + 1
				_G.GatewayRegistry = {
					["test-this-is-valid-arweave-wallet-address-1"] = {
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
						observerAddress = "test-this-is-valid-arweave-observer-address-1",
						weights = {
							normalizedCompositeWeight = 1,
							stakeWeight = 1,
							tenureWeight = 1,
							gatewayPerformanceRatio = 1,
							observerPerformanceRatio = 1,
							compositeWeight = 1,
						},
					},
					["test-this-is-valid-arweave-wallet-address-2"] = {
						operatorStake = gar.getSettings().operators.minStake,
						totalDelegatedStake = 0,
						vaults = {},
						delegates = {},
						startTimestamp = startTimestamp,
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
						observerAddress = "test-this-is-valid-arweave-observer-address-2",
						weights = {
							normalizedCompositeWeight = 1,
							stakeWeight = 1,
							tenureWeight = 1,
							gatewayPerformanceRatio = 1,
							observerPerformanceRatio = 1,
							compositeWeight = 1,
						},
					},
					["test-this-is-valid-arweave-wallet-address-3"] = {
						operatorStake = gar.getSettings().operators.minStake,
						totalDelegatedStake = 0,
						vaults = {},
						delegates = {},
						startTimestamp = startTimestamp + 10, -- joined after the epoch started
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
						observerAddress = "test-this-is-valid-arweave-observer-address-3",
						weights = {
							normalizedCompositeWeight = 1,
							stakeWeight = 1,
							tenureWeight = 1,
							gatewayPerformanceRatio = 1,
							observerPerformanceRatio = 1,
							compositeWeight = 1,
						},
					},
					["test-this-is-valid-arweave-wallet-address-4"] = {
						operatorStake = gar.getSettings().operators.minStake,
						totalDelegatedStake = 0,
						vaults = {},
						delegates = {},
						endTimestamp = startTimestamp + 10, -- left before the epoch ended
						startTimestamp = startTimestamp - 10,
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
						status = "leaving", -- leaving, so it is not eligible to receive stats from this epoch
						observerAddress = "test-this-is-valid-arweave-observer-address-4",
						weights = {
							normalizedCompositeWeight = 1,
							stakeWeight = 1,
							tenureWeight = 1,
							gatewayPerformanceRatio = 1,
							observerPerformanceRatio = 1,
							compositeWeight = 1,
						},
					},
				}
				_G.Epochs[0] = {
					prescribedObservers = {
						["test-this-is-valid-arweave-observer-address-2"] = "test-this-is-valid-arweave-wallet-address-2",
					},
				}
				local failedGateways = {
					"test-this-is-valid-arweave-wallet-address-1",
					"test-this-is-valid-arweave-wallet-address-3",
				}
				local result = epochs.saveObservations(observer, reportTxId, failedGateways, 0, timestamp)
				assert.are.same(result, {
					reports = {
						[observer] = reportTxId,
					},
					failureSummaries = {
						["test-this-is-valid-arweave-wallet-address-1"] = { observer },
					},
				})
			end
		)
	end)

	describe("getPrescribedObserversForEpoch", function()
		it("should return the prescribed observers for the epoch", function()
			local epochIndex = 0
			local expectation = {}
			local result = epochs.getPrescribedObserversForEpoch(epochIndex)
			assert.are.same(result, expectation)
		end)
	end)

	describe("getEpochIndexForTimestamp", function()
		it("should return the epoch index for the given timestamp", function()
			local timestamp = epochs.getSettings().epochZeroStartTimestamp + epochs.getSettings().durationMs + 1
			local result = epochs.getEpochIndexForTimestamp(timestamp)
			assert.are.equal(result, 1)
		end)
	end)

	describe("getEpochTimestampsForIndex", function()
		it("should return the epoch timestamps for the given epoch index", function()
			local epochIndex = 0
			local expectation = { 1704092400000, 1704092400100 }
			local result = { epochs.getEpochTimestampsForIndex(epochIndex) }
			assert.are.same(result, expectation)
		end)
	end)

	describe("createAndPrescribeNewEpoch", function()
		local epochIndex = 0
		local epochStartTimestamp = _G.EpochSettings.epochZeroStartTimestamp
		local epochEndTimestamp = epochStartTimestamp + _G.EpochSettings.durationMs
		local epochStartBlockHeight = 0
		local oneYearMs = 60 * 1000 * 60 * 24 * 365
		local recordTimestamp = epochStartTimestamp
		local endTimestamp = epochStartTimestamp + oneYearMs

		before_each(function()
			_G.Epochs = {}
			_G.NameRegistry.records = {
				["test-record-1"] = {
					startTimestamp = recordTimestamp,
					type = "permabuy",
					purchasePrice = 0,
					undernameLimit = 10,
				},
				["test-record-2"] = {
					startTimestamp = recordTimestamp,
					endTimestamp = endTimestamp,
					type = "lease",
					purchasePrice = 0,
					undernameLimit = 10,
				},
				-- active at the beginning of the epoch, but will go into grace period during the epoch, so next epoch will be count it in grace period
				["this-is-a-record-in-grace-period"] = {
					startTimestamp = recordTimestamp,
					endTimestamp = epochEndTimestamp - 1,
					type = "lease",
					purchasePrice = 0,
					undernameLimit = 10,
				},
			}
			_G.NameRegistry.returned = {
				["this-is-a-record-in-returned"] = {
					name = "this-is-a-record-in-returned",
					initiator = "test-this-is-valid-arweave-wallet-address-1",
					startTimestamp = recordTimestamp,
				},
			}
			_G.NameRegistry.reserved = {
				["this-is-a-record-in-reserved"] = {
					name = "this-is-a-record-in-reserved",
					target = "test-this-is-valid-arweave-wallet-address-1",
					endTimestamp = endTimestamp,
				},
				["this-is-another-record-in-reserved"] = {
					name = "this-is-another-record-in-returned",
					target = "test-this-is-valid-arweave-wallet-address-1",
					endTimestamp = endTimestamp,
				},
			}
			_G.GatewayRegistry = {
				["test-this-is-valid-arweave-wallet-address-1"] = {
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
					observerAddress = "test-this-is-valid-arweave-wallet-address-1",
					weights = {
						stakeWeight = 0,
						tenureWeight = 0,
						gatewayPerformanceRatio = 0,
						observerPerformanceRatio = 0,
						compositeWeight = 0,
						normalizedCompositeWeight = 0,
					},
				},
				-- not eligible to be prescribed as it is leaving, so it should not be included in the eligible gateways count either
				["test-this-is-valid-arweave-wallet-address-2"] = {
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
					status = "leaving",
					observerAddress = "test-this-is-valid-arweave-wallet-address-1",
					weights = {
						stakeWeight = 0,
						tenureWeight = 0,
						gatewayPerformanceRatio = 0,
						observerPerformanceRatio = 0,
						compositeWeight = 0,
						normalizedCompositeWeight = 0,
					},
				},
			}
		end)

		it("should create and prescribe the new epoch, and update gateway weights with computed weights", function()
			local expectedEligibleGateways = 1
			local expectedEligibleRewards = math.floor(protocolBalance * 0.001) -- it's 0.1% for the first year
			local expectedTotalGatewayReward = math.floor(expectedEligibleRewards * 0.90)
			local expectedTotalObserverReward = math.floor(expectedEligibleRewards * 0.10)
			local expectedPerGatewayReward = math.floor(expectedTotalGatewayReward / 1) -- only one gateway in the registry
			local expectedPerObserverReward = math.floor(expectedTotalObserverReward / 1) -- only one prescribed observer
			local expectation = {
				hashchain = hashchain,
				startTimestamp = epochStartTimestamp,
				endTimestamp = epochEndTimestamp,
				epochIndex = epochIndex,
				startHeight = epochStartBlockHeight,
				observations = {
					failureSummaries = {},
					reports = {},
				},
				arnsStats = {
					totalActiveNames = 3,
					totalGracePeriodNames = 0,
					totalReturnedNames = 1,
					totalReservedNames = 2,
				},
				prescribedObservers = {
					["test-this-is-valid-arweave-wallet-address-1"] = "test-this-is-valid-arweave-wallet-address-1",
				},
				prescribedNames = {
					"test-record-1",
					"test-record-2",
				},
				distributions = {
					totalEligibleGateways = expectedEligibleGateways,
					totalEligibleRewards = expectedEligibleRewards,
					totalEligibleGatewayReward = expectedTotalGatewayReward,
					totalEligibleObserverReward = expectedTotalObserverReward,
					rewards = {
						eligible = {
							["test-this-is-valid-arweave-wallet-address-1"] = {
								operatorReward = expectedPerGatewayReward + expectedPerObserverReward,
								delegateRewards = {}, -- no delegates
							},
						},
					},
				},
			}
			local result = epochs.createAndPrescribeNewEpoch(epochStartTimestamp, epochStartBlockHeight, hashchain)
			assert(result, "Expected epoch to be created")
			-- sort the prescribed names to avoid lua array comparison issues
			table.sort(expectation.prescribedNames)
			table.sort(result.prescribedNames)
			assert.are.same(expectation, result)
			assert.are.same(expectation, epochs.getEpoch(epochIndex))
			-- confirm the gateway weights were updated
			assert.are.same({
				stakeWeight = 1,
				tenureWeight = 4,
				gatewayPerformanceRatio = 1,
				observerPerformanceRatio = 1,
				compositeWeight = 4,
				normalizedCompositeWeight = 1,
			}, _G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].weights)
			-- confirm the leaving gateway weights were not updated
			assert.are.same({
				stakeWeight = 0,
				tenureWeight = 0,
				gatewayPerformanceRatio = 0,
				observerPerformanceRatio = 0,
				compositeWeight = 0,
				normalizedCompositeWeight = 0,
			}, _G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-2"].weights)
		end)

		it("should count arns stat totals for the given epoch", function()
			local result = epochs.createAndPrescribeNewEpoch(epochStartTimestamp, epochStartBlockHeight, hashchain)

			-- Check arnsStats are counted as expected
			assert.are.same({
				totalActiveNames = 3,
				totalGracePeriodNames = 0,
				totalReservedNames = 2,
				totalReturnedNames = 1,
			}, result.arnsStats)
		end)
	end)

	describe("distributeEpoch", function()
		before_each(function()
			-- adds a fully prescribed epoch to the epoch registry, with 5 gateways and 5 observers and observations
			_G.Epochs[0] = {
				epochIndex = 0,
				observations = {
					failureSummaries = {
						["test-this-is-valid-arweave-wallet-address-1"] = {
							"test-this-very-valid-observer-wallet-addr-3",
							"test-this-very-valid-observer-wallet-addr-4",
							"test-this-very-valid-observer-wallet-addr-5",
						},
						["test-this-is-valid-arweave-wallet-address-3"] = {
							"test-this-very-valid-observer-wallet-addr-3",
							"test-this-very-valid-observer-wallet-addr-4",
						},
					},
					reports = {
						["test-this-very-valid-observer-wallet-addr-3"] = "test-this-very-valid-observations-report-03",
						["test-this-very-valid-observer-wallet-addr-4"] = "test-this-very-valid-observations-report-04",
						["test-this-very-valid-observer-wallet-addr-5"] = "test-this-very-valid-observations-report-05",
					},
				},
				endTimestamp = 1704092400100,
				startTimestamp = 1704092400000,
				startHeight = 0,
				distributionTimestamp = 1704092400115,
				distributions = {
					totalEligibleGateways = 5,
					totalEligibleGatewayReward = 225000000000,
					totalEligibleObserverReward = 25000000000,
					totalEligibleRewards = 1250000000000,
					rewards = {
						eligible = {
							["test-this-is-valid-arweave-wallet-address-1"] = {
								operatorReward = 225000000000,
								delegateRewards = { ["this-is-a-delegate"] = 25000000000 },
							},
							["test-this-is-valid-arweave-wallet-address-2"] = {
								operatorReward = 225000000000,
								delegateRewards = { ["this-is-a-delegate"] = 25000000000 },
							},
							["test-this-is-valid-arweave-wallet-address-3"] = {
								operatorReward = 225000000000,
								delegateRewards = { ["this-is-a-delegate"] = 25000000000 },
							},
							["test-this-is-valid-arweave-wallet-address-4"] = {
								operatorReward = 225000000000,
								delegateRewards = { ["this-is-a-delegate"] = 25000000000 },
							},
							["test-this-is-valid-arweave-wallet-address-5"] = {
								operatorReward = 225000000000,
								delegateRewards = {
									["this-is-a-delegate"] = 12500000000,
									--- these rewards will stay in the protocol balance as the delegate no longer exists on the gateway
									["this-delegate-left-the-gateway"] = 12500000000,
								},
							},
							--- this gateway will be marked as leaving during the epoch, rewards should not be distributed
							["test-this-is-valid-arweave-wallet-address-6"] = {
								operatorReward = 225000000000,
								delegateRewards = { ["this-is-a-delegate"] = 25000000000 },
							},
						},
					},
				},
				prescribedNames = {},
				prescribedObservers = {
					["test-this-very-valid-observer-wallet-addr-1"] = "test-this-very-valid-arweave-wallet-addr-1",
					["test-this-very-valid-observer-wallet-addr-2"] = "test-this-very-valid-arweave-wallet-addr-2",
					["test-this-very-valid-observer-wallet-addr-3"] = "test-this-very-valid-arweave-wallet-addr-3",
					["test-this-very-valid-observer-wallet-addr-4"] = "test-this-very-valid-arweave-wallet-addr-4",
					["test-this-very-valid-observer-wallet-addr-5"] = "test-this-very-valid-arweave-wallet-addr-5",
				},
			}
		end)

		it("should distribute rewards for the epoch, auto staking for delegates", function()
			local originalOperatorStake = gar.getSettings().operators.minStake
			local originalDelegateStake = 100000000
			local epochIndex = 0
			for i = 1, 6 do
				local gateway = {
					operatorStake = originalOperatorStake,
					totalDelegatedStake = originalDelegateStake,
					vaults = {},
					delegates = {
						["this-is-a-delegate"] = {
							delegatedStake = originalDelegateStake,
							startTimestamp = 0,
							vaults = {},
						},
					},
					startTimestamp = 0,
					endTimestamp = 0,
					stats = {
						prescribedEpochCount = i,
						observedEpochCount = 0,
						totalEpochCount = 0,
						passedEpochCount = 0,
						failedEpochCount = 0,
						failedConsecutiveEpochs = 0,
						passedConsecutiveEpochs = 0,
					},
					settings = {
						fqdn = "test.com",
						protocol = "https",
						port = 443,
						allowDelegatedStaking = true,
						minDelegatedStake = 100,
						autoStake = i ~= 5, -- set autostake on for all gateways except the last one
						label = "test",
						properties = "",
						delegateRewardShareRatio = 10,
					},
					status = "joined",
					observerAddress = "test-this-very-valid-observer-wallet-addr-" .. i,
				}
				gar.addGateway("test-this-is-valid-arweave-wallet-address-" .. i, gateway)
			end
			--- set the last gateway to leaving, rewards should not be distributed to it
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-6"].status = "leaving"
			-- clear the balances for the gateways
			_G.Balances["test-this-is-valid-arweave-wallet-address-1"] = 0
			local epoch = epochs.getEpoch(epochIndex)
			assert(epoch, "Epoch not found")
			local expectedGatewayReward = epoch.distributions.totalEligibleGatewayReward
			local expectedObserverReward = epoch.distributions.totalEligibleObserverReward

			-- validate the distribution of rewards for the epoch
			local distributedEpoch = epochs.distributeEpoch(epoch.epochIndex, epoch.endTimestamp)
			assert(distributedEpoch)

			-- validate the epoch is removed from the epoch table after distribution
			assert.is_nil(_G.Epochs[epochIndex])

			-- gateway 1 should not get any rewards - failed observation and did not observe, should not get any rewards
			assert.are.same({
				prescribedEpochCount = 2, -- increment by one
				observedEpochCount = 0,
				passedEpochCount = 0,
				failedEpochCount = 1,
				failedConsecutiveEpochs = 1,
				passedConsecutiveEpochs = 0,
				totalEpochCount = 1,
			}, _G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].stats)

			-- passed observation, did not observe
			assert.are.same({
				prescribedEpochCount = 3, -- increment by one
				observedEpochCount = 0,
				passedEpochCount = 1,
				failedEpochCount = 0,
				failedConsecutiveEpochs = 0,
				passedConsecutiveEpochs = 1,
				totalEpochCount = 1,
			}, _G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-2"].stats)
			-- failed observation, did observe
			assert.are.same({
				prescribedEpochCount = 4, -- increment by one
				observedEpochCount = 1,
				passedEpochCount = 0,
				failedEpochCount = 1,
				failedConsecutiveEpochs = 1,
				passedConsecutiveEpochs = 0,
				totalEpochCount = 1,
			}, _G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-3"].stats)
			-- passed observation, did observe
			assert.are.same({
				prescribedEpochCount = 5, -- increment by one
				observedEpochCount = 1,
				passedEpochCount = 1,
				failedEpochCount = 0,
				failedConsecutiveEpochs = 0,
				passedConsecutiveEpochs = 1,
				totalEpochCount = 1,
			}, _G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-4"].stats)
			-- passed observation, did observe
			assert.are.same({
				prescribedEpochCount = 6, -- increment by one
				observedEpochCount = 1,
				passedEpochCount = 1,
				failedEpochCount = 0,
				failedConsecutiveEpochs = 0,
				passedConsecutiveEpochs = 1,
				totalEpochCount = 1,
			}, _G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-5"].stats)

			local expectedGateway1TotalRewards = 0
			local expectedGateway2TotalRewards = math.floor(expectedGatewayReward * 0.75) -- penalized for not observing
			local expectedGateway3TotalRewards = expectedObserverReward
			local expectedGateway4TotalRewards = (expectedGatewayReward + expectedObserverReward)
			local expectedGateway5TotalRewards = (expectedGatewayReward + expectedObserverReward)

			local expectedDelegateRewardForGateway1 = 0 -- no rewards
			local expectedDelegateRewardForGateway2 = math.floor(expectedGateway2TotalRewards * 0.10)
			local expectedDelegateRewardForGateway3 = math.floor(expectedGateway3TotalRewards * 0.10)
			local expectedDelegateRewardForGateway4 = math.floor(expectedGateway4TotalRewards * 0.10)
			local expectedDelegateRewardForGateway5 = math.floor(expectedGateway5TotalRewards * 0.05) -- it splits with the gateway that left

			local totalRewardForDelegateOfAllGateways = expectedDelegateRewardForGateway1
				+ expectedDelegateRewardForGateway2
				+ expectedDelegateRewardForGateway3
				+ expectedDelegateRewardForGateway4
				+ expectedDelegateRewardForGateway5

			local rewardsForDelegatesThatLeft = 12500000000

			-- check the epoch was properly distributed
			if not distributedEpoch then
				error("Distributed epoch is nil")
			end
			local distributions = distributedEpoch.distributions
			local expectedTotalDistribution = math.floor(
				expectedGateway1TotalRewards
					+ expectedGateway2TotalRewards
					+ expectedGateway3TotalRewards
					+ expectedGateway4TotalRewards
					+ expectedGateway5TotalRewards -- reward for leaving delegate is not distributed
			) - rewardsForDelegatesThatLeft

			-- the updated operator stakes after rewards are distributed and restaked for the delegate
			local gateway1OperatorStakeAfterRewards = originalOperatorStake -- no rewards
			local gateway2OperatorStakeAfterRewards = originalOperatorStake
				+ math.floor(expectedGateway2TotalRewards * 0.90)
			local gateway3OperatorStakeAfterRewards = originalOperatorStake
				+ math.floor(expectedGateway3TotalRewards * 0.90)
			local gateway4OperatorStakeAfterRewards = originalOperatorStake
				+ math.floor(expectedGateway4TotalRewards * 0.90)
			local gateway5OperatorStakeAfterRewards = originalOperatorStake

			-- the total delegations after rewards are distributed and restaked for the delegate
			local gateway1DelegateStakeAfterRewards = originalDelegateStake + expectedDelegateRewardForGateway1
			local gateway2DelegateStakeAfterRewards = originalDelegateStake + expectedDelegateRewardForGateway2
			local gateway3DelegateStakeAfterRewards = originalDelegateStake + expectedDelegateRewardForGateway3
			local gateway4DelegateStakeAfterRewards = originalDelegateStake + expectedDelegateRewardForGateway4
			local gateway5DelegateStakeAfterRewards = originalDelegateStake + expectedDelegateRewardForGateway5

			-- balances after rewards are distributed and restaked for the delegate
			local expectedGateway1Balance = 0 -- autostaking enabled
			local expectedGateway2Balance = 0 -- autostaking enabled
			local expectedGateway3Balance = 0 -- autostaking enabled
			local expectedGateway4Balance = 0 -- autostaking enabled
			local expectedGateway5Balance = math.floor(expectedGateway5TotalRewards * 0.90) -- autostaking disabled

			-- confirm the updated epoch values
			assert.are.equal(expectedTotalDistribution, distributions.totalDistributedRewards)
			assert.are.equal(epoch.endTimestamp, distributions.distributedTimestamp)

			assert.are.same({
				--- gateway 1 did not earn any rewards, so it should not be in the distributed table
				["test-this-is-valid-arweave-wallet-address-2"] = expectedGateway2TotalRewards * 0.90,
				["test-this-is-valid-arweave-wallet-address-3"] = expectedGateway3TotalRewards * 0.90,
				["test-this-is-valid-arweave-wallet-address-4"] = expectedGateway4TotalRewards * 0.90,
				["test-this-is-valid-arweave-wallet-address-5"] = expectedGateway5TotalRewards * 0.90,
				["this-is-a-delegate"] = totalRewardForDelegateOfAllGateways,
				--- the delegate that left the gateway should not have any rewards and not be in the distributed table
			}, distributions.rewards.distributed)
			-- assert the gateway operator stakes are updated
			assert.are.equal(
				gateway1OperatorStakeAfterRewards,
				_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].operatorStake
			) -- no rewards
			assert.are.equal(
				gateway2OperatorStakeAfterRewards,
				_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-2"].operatorStake
			) -- autostake enabled
			assert.are.equal(
				gateway3OperatorStakeAfterRewards,
				_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-3"].operatorStake
			) -- autostake enabled
			assert.are.equal(
				gateway4OperatorStakeAfterRewards,
				_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-4"].operatorStake
			) -- autostake enabled
			assert.are.equal(
				gateway5OperatorStakeAfterRewards,
				_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-5"].operatorStake
			) -- autostake DISABLED - return directly to owner

			-- assert that gateway 5 balance increased by the expected amount as it is the only one that is autostaking disabled and returns directly to owner, all other balances should be 0
			assert.are.equal(expectedGateway1Balance, _G.Balances["test-this-is-valid-arweave-wallet-address-1"])
			assert.are.equal(expectedGateway2Balance, _G.Balances["test-this-is-valid-arweave-wallet-address-2"])
			assert.are.equal(expectedGateway3Balance, _G.Balances["test-this-is-valid-arweave-wallet-address-3"])
			assert.are.equal(expectedGateway4Balance, _G.Balances["test-this-is-valid-arweave-wallet-address-4"])
			assert.are.equal(expectedGateway5Balance, _G.Balances["test-this-is-valid-arweave-wallet-address-5"])

			-- gateway 1 did not get any rewards, so the delegate stake should be the original amount
			assert.are.equal(
				gateway1DelegateStakeAfterRewards,
				_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].delegates["this-is-a-delegate"].delegatedStake
			)
			-- delegate on gateway 2 gets 10% of the total rewards received by the gateway
			assert.are.equal(
				gateway2DelegateStakeAfterRewards,
				_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-2"].delegates["this-is-a-delegate"].delegatedStake
			)
			-- delegate on gateway 3 gets 10% of the total rewards received by the gateway
			assert.are.equal(
				gateway3DelegateStakeAfterRewards,
				_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-3"].delegates["this-is-a-delegate"].delegatedStake
			)
			-- delegate on gateway 4 gets 10% of the total rewards received by the gateway
			assert.are.equal(
				gateway4DelegateStakeAfterRewards,
				_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-4"].delegates["this-is-a-delegate"].delegatedStake
			)
			-- delegate on gateway 5 gets 10% of the total rewards received by the gateway
			assert.are.equal(
				gateway5DelegateStakeAfterRewards,
				_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-5"].delegates["this-is-a-delegate"].delegatedStake
			)
			-- assert that the balance withdrawn from the protocol balance matches the total distributed rewards
			assert.are.equal(protocolBalance - expectedTotalDistribution, _G.Balances[ao.id])
		end)
		it(
			"should return nil if the epoch has already been distributed and remove it from the epoch registry",
			function()
				local epochIndex = 0
				-- marks the epoch as distributed
				_G.Epochs[epochIndex] = {
					epochIndex = epochIndex,
					distributions = {
						distributedTimestamp = 1704092400115,
					},
				}
				local epoch = epochs.getEpoch(epochIndex)
				assert(epoch, "Epoch not found")
				local distributedEpoch = epochs.distributeEpoch(epoch.epochIndex, epoch.endTimestamp)
				assert.is_nil(distributedEpoch)
				assert.is_nil(_G.Epochs[epochIndex])
			end
		)

		it("should return nil if the epoch does not exist in the epoch registry", function()
			local epochIndex = 0
			local epoch = epochs.getEpoch(epochIndex)
			assert(epoch, "Epoch not found")
			-- remove the epoch from the epoch registry
			_G.Epochs[epochIndex] = nil
			assert.is_nil(epochs.distributeEpoch(epoch.epochIndex, epoch.endTimestamp))
		end)
	end)

	describe("getRewardRateForEpoch", function()
		it("returns 0.1% for the first 365 epochs (approximately one year)", function()
			for i = 1, 365 do
				assert.are.equal(0.001, epochs.getRewardRateForEpoch(i))
			end
		end)

		it("returns a linearly decreasing rate starting from 0.1% after 365 epochs, up to 5 decimal places", function()
			assert.are.equal(0.001, epochs.getRewardRateForEpoch(366))
			assert.are.equal(0.00075, epochs.getRewardRateForEpoch(366 + 91))
			assert.are.equal(0.0005, epochs.getRewardRateForEpoch(366 + 182))
		end)

		it("returns 0.05% after 547 epochs (approximately 1.5 years)", function()
			assert.are.equal(0.0005, epochs.getRewardRateForEpoch(548))
			assert.are.equal(0.0005, epochs.getRewardRateForEpoch(730))
			assert.are.equal(0.0005, epochs.getRewardRateForEpoch(12053))
		end)
	end)

	describe("computePrescribedObserversForEpoch weighted selection", function()
		it("should select observers proportionally to their normalized weights across full [0,1] range", function()
			-- Setup: Create 10 gateways with varying weights to test the full distribution
			-- Gateway 1-5 have low cumulative weights (0-0.5 range)
			-- Gateway 6-10 have high cumulative weights (0.5-1.0 range)
			-- With the bug (0xffffffff), only gateways in the 0-0.5 range would be selected
			-- With the fix (0x7fffffff), all gateways should be selectable

			_G.EpochSettings = {
				maxObservers = 3, -- select 3 observers
				epochZeroStartTimestamp = startTimestamp,
				durationMs = 60 * 1000 * 60 * 24, -- 24 hours
			}

			-- Create 10 gateways with equal weights (each 0.1 normalized weight)
			for i = 1, 10 do
				local gateway = {
					operatorStake = gar.getSettings().operators.minStake,
					totalDelegatedStake = 0,
					vaults = {},
					delegates = {},
					startTimestamp = startTimestamp,
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
					observerAddress = "observer-address-" .. i,
					weights = {
						normalizedCompositeWeight = 0.1, -- each gateway has 10% weight
						stakeWeight = 1,
						tenureWeight = 1,
						gatewayPerformanceRatio = 1,
						observerPerformanceRatio = 1,
						compositeWeight = 1,
					},
				}
				_G.GatewayRegistry["gateway-address-" .. i] = gateway
			end

			-- Run multiple epochs with different hashchains to get statistical distribution
			local selectionCounts = {}
			for i = 1, 10 do
				selectionCounts["observer-address-" .. i] = 0
			end

			-- Use different hashchains to simulate multiple epochs
			local testHashchains = {
				"YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY=", -- base64 strings
				"MTIzNDU2Nzg5MGFiY2RlZmdoaWprbG1ub3BxcnN0dXY=",
				"cXdlcnR5dWlvcGFzZGZnaGprbHp4Y3Zibm0xMjM0NTY=",
				"YXNkZmdoamtsenhjdmJubTEyMzQ1Njc4OTBxd2VydHk=",
				"enhjdmJubTEyMzQ1Njc4OTBhc2RmZ2hqa2xxd2VydHl1",
				"cG9pdXl0cmV3cWFzZGZnaGprbHp4Y3Zibm0xMjM0NTY=",
				"bW5iY3h6bGtqaGdmZHNhcG9pdXl0cmV3cTEyMzQ1Njc=",
				"OTg3NjU0MzIxMHF3ZXJ0eXVpb3Bhc2RmZ2hqa2x6eGM=",
				"dGVzdGluZzEyMzQ1Njc4OTBhYmNkZWZnaGlqa2xtbm9w",
				"Zmluam1zZGlvYXNkZmhzdWRmaHNkaWZoc2lkZmhzZGY=",
			}

			for _, testHashchain in ipairs(testHashchains) do
				local prescribedObserverMap = epochs.computePrescribedObserversForEpoch(1, testHashchain)
				for observerAddr, _ in pairs(prescribedObserverMap) do
					selectionCounts[observerAddr] = selectionCounts[observerAddr] + 1
				end
			end

			-- With 10 hashchains selecting 3 observers each = 30 total selections
			-- With equal 10% weights, each gateway should be selected ~3 times on average
			-- The key test: gateways in the upper half of the distribution (6-10) should also be selected
			local upperHalfSelections = 0
			for i = 6, 10 do
				upperHalfSelections = upperHalfSelections + selectionCounts["observer-address-" .. i]
			end

			-- With the bug (random max ~0.5), upperHalfSelections would be 0 or very low
			-- With the fix, upperHalfSelections should be roughly 15 (half of 30)
			-- We use a loose bound to account for randomness: at least 5 selections in upper half
			assert(
				upperHalfSelections >= 5,
				"Expected at least 5 selections from upper half of weight distribution, got "
					.. upperHalfSelections
					.. ". This suggests random values are not reaching the full [0,1] range."
			)
		end)

		it("should select high-weight gateways more frequently than low-weight gateways", function()
			_G.EpochSettings = {
				maxObservers = 1, -- select only 1 observer to make weight differences more pronounced
				epochZeroStartTimestamp = startTimestamp,
				durationMs = 60 * 1000 * 60 * 24, -- 24 hours
			}

			-- Create 2 gateways with very different weights:
			-- Gateway 1: 90% weight (should be selected most often)
			-- Gateway 2: 10% weight (should be selected rarely)
			local weights = { 0.9, 0.1 }
			for i = 1, 2 do
				local gateway = {
					operatorStake = gar.getSettings().operators.minStake,
					totalDelegatedStake = 0,
					vaults = {},
					delegates = {},
					startTimestamp = startTimestamp,
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
					observerAddress = "observer-" .. i,
					weights = {
						normalizedCompositeWeight = weights[i],
						stakeWeight = 1,
						tenureWeight = 1,
						gatewayPerformanceRatio = 1,
						observerPerformanceRatio = 1,
						compositeWeight = 1,
					},
				}
				_G.GatewayRegistry["gateway-" .. i] = gateway
			end

			local selectionCounts = { 0, 0 }

			-- Use many different hashchains to get statistically significant results
			-- With 90/10 split over 50 trials, gateway 1 should win ~45 times
			for i = 1, 50 do
				-- Generate unique hashchains by using different base strings
				local testHashchain = "dGVzdGhhc2g=" .. string.format("%02d", i)
				local prescribedObserverMap = epochs.computePrescribedObserversForEpoch(1, testHashchain)
				for observerAddr, _ in pairs(prescribedObserverMap) do
					local idx = tonumber(observerAddr:match("observer%-(%d+)"))
					selectionCounts[idx] = selectionCounts[idx] + 1
				end
			end

			-- Gateway 1 (90% weight) should be selected significantly more than Gateway 2 (10% weight)
			-- With 50 trials and 90/10 split, expect ~45 vs ~5. Use loose bound of 2x to avoid flakiness.
			assert(
				selectionCounts[1] > selectionCounts[2] * 2,
				"Expected gateway with 90% weight to be selected at least 2x more often than gateway with 10% weight. "
					.. "Gateway 1: "
					.. selectionCounts[1]
					.. ", Gateway 2: "
					.. selectionCounts[2]
			)
		end)
	end)

	describe("getEligibleRewardsForEpoch", function()
		it("should return paginated eligible rewards for the current epoch", function()
			_G.Epochs[0] = {
				distributions = {
					rewards = {
						eligible = {
							["test-this-is-valid-arweave-wallet-address-1"] = {
								operatorReward = 300,
								delegateRewards = {
									["this-is-a-delegate-2"] = 2550,
									["this-is-a-delegate"] = 25,
								},
							},
							["test-this-is-valid-arweave-wallet-address-2"] = {
								operatorReward = 255,
								delegateRewards = { ["this-is-a-delegate"] = 50 },
							},
							["test-this-is-valid-arweave-wallet-address-3"] = {
								operatorReward = 125,
								delegateRewards = { ["this-is-a-delegate"] = 20 },
							},
							["test-this-is-valid-arweave-wallet-address-4"] = {
								operatorReward = 40,
								delegateRewards = { ["this-is-a-delegate"] = 30 },
							},
							["test-this-is-valid-arweave-wallet-address-5"] = {
								operatorReward = 5,
								delegateRewards = { ["this-is-a-delegate"] = 10 },
							},
						},
					},
				},
			}

			local result = epochs.getEligibleRewardsForEpoch(
				_G.EpochSettings.epochZeroStartTimestamp,
				nil,
				3,
				"eligibleReward",
				"desc"
			)

			assert.are.same({
				limit = 3,
				sortBy = "eligibleReward",
				sortOrder = "desc",
				hasMore = true,
				totalItems = 11,
				nextCursor = "test-this-is-valid-arweave-wallet-address-2_test-this-is-valid-arweave-wallet-address-2",
				items = {
					{
						cursorId = "test-this-is-valid-arweave-wallet-address-1_this-is-a-delegate-2",
						eligibleReward = 2550,
						gatewayAddress = "test-this-is-valid-arweave-wallet-address-1",
						recipient = "this-is-a-delegate-2",
						type = "delegateReward",
					},
					{
						cursorId = "test-this-is-valid-arweave-wallet-address-1_test-this-is-valid-arweave-wallet-address-1",
						eligibleReward = 300,
						gatewayAddress = "test-this-is-valid-arweave-wallet-address-1",
						recipient = "test-this-is-valid-arweave-wallet-address-1",
						type = "operatorReward",
					},
					{
						cursorId = "test-this-is-valid-arweave-wallet-address-2_test-this-is-valid-arweave-wallet-address-2",
						eligibleReward = 255,
						gatewayAddress = "test-this-is-valid-arweave-wallet-address-2",
						recipient = "test-this-is-valid-arweave-wallet-address-2",
						type = "operatorReward",
					},
				},
			}, result)

			-- Test with a different cursor
			result = epochs.getEligibleRewardsForEpoch(
				_G.EpochSettings.epochZeroStartTimestamp,
				"test-this-is-valid-arweave-wallet-address-2_test-this-is-valid-arweave-wallet-address-2",
				3,
				"eligibleReward",
				"desc"
			)

			assert.are.same({
				limit = 3,
				sortBy = "eligibleReward",
				sortOrder = "desc",
				hasMore = true,
				nextCursor = "test-this-is-valid-arweave-wallet-address-4_test-this-is-valid-arweave-wallet-address-4",
				totalItems = 11,
				items = {
					{
						cursorId = "test-this-is-valid-arweave-wallet-address-3_test-this-is-valid-arweave-wallet-address-3",
						eligibleReward = 125,
						gatewayAddress = "test-this-is-valid-arweave-wallet-address-3",
						recipient = "test-this-is-valid-arweave-wallet-address-3",
						type = "operatorReward",
					},
					{
						cursorId = "test-this-is-valid-arweave-wallet-address-2_this-is-a-delegate",
						eligibleReward = 50,
						gatewayAddress = "test-this-is-valid-arweave-wallet-address-2",
						recipient = "this-is-a-delegate",
						type = "delegateReward",
					},

					{
						cursorId = "test-this-is-valid-arweave-wallet-address-4_test-this-is-valid-arweave-wallet-address-4",
						eligibleReward = 40,
						gatewayAddress = "test-this-is-valid-arweave-wallet-address-4",
						recipient = "test-this-is-valid-arweave-wallet-address-4",
						type = "operatorReward",
					},
				},
			}, result)
		end)
	end)
end)
