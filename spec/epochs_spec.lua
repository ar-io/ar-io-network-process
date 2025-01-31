local epochs = require("epochs")
local gar = require("gar")
local utils = require("utils")
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
		_G.Epochs = {
			[0] = {
				startTimestamp = 1704092400000,
				endTimestamp = 1704092400100,
				distributionTimestamp = 1704092400115,
				prescribedObservers = {},
				distributions = {},
				observations = {
					failureSummaries = {},
					reports = {},
				},
			},
		}
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
			distributionDelayMs = 15,
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
			_G.Epochs[0].prescribedObservers = {
				["observerAddress"] = "test-this-is-valid-arweave-wallet-address-1",
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
			local prescribedObserverMap = epochs.computePrescribedObserversForEpoch(0, hashchain)
			assert.are.same(expectation, prescribedObserverMap)
		end)

		it("should return the maximum number of gateways if more are enrolled in network", function()
			local testHashchain = "c29tZSBzYW1wbGUgaGFzaA==" -- base64 of "some sample hash"
			_G.EpochSettings = {
				maxObservers = 2, -- limit to 2 observers
				epochZeroStartTimestamp = startTimestamp,
				durationMs = 60 * 1000 * 60 * 24, -- 24 hours
				distributionDelayMs = 60 * 1000 * 2 * 15, -- 15 blocks
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

			local expectation = {
				["observer-address-1"] = "observer1",
				["observer-address-3"] = "observer3",
			}
			local prescribedObserverMap = epochs.computePrescribedObserversForEpoch(0, testHashchain)
			assert.are.same(expectation, prescribedObserverMap)
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
			local status, result = pcall(epochs.computePrescribedNamesForEpoch, 0, hashchain)
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
			local status, result = pcall(epochs.computePrescribedNamesForEpoch, 0, hashchain)
			assert.is_true(status)
			assert.are.equal(5, #result)
			assert.are.same(expectation, result)
		end)
	end)

	describe("saveObservations", function()
		it("should throw an error when saving observation too early in the epoch", function()
			local observer = "test-this-is-valid-arweave-wallet-address-2"
			local reportTxId = "test-this-very-valid-observations-report-tx"
			local settings = epochs.getSettings()
			local timestamp = settings.epochZeroStartTimestamp + settings.distributionDelayMs - 1
			local failedGateways = {
				"test-this-is-valid-arweave-wallet-address-1",
			}
			local status, error = pcall(epochs.saveObservations, observer, reportTxId, failedGateways, timestamp)
			assert.is_false(status)
			assert.match("Observations for the current epoch cannot be submitted before", error)
		end)
		it("should throw an error if the caller is not prescribed", function()
			local observer = "test-this-is-valid-arweave-observer-address-2"
			local reportTxId = "test-this-very-valid-observations-report-tx"
			local settings = epochs.getSettings()
			local timestamp = settings.epochZeroStartTimestamp + settings.distributionDelayMs + 1
			local failedGateways = {
				"test-this-is-valid-arweave-wallet-address-1",
			}
			_G.Epochs[0].prescribedObservers = {
				["test-this-is-valid-arweave-observer-address-1"] = "test-this-is-valid-arweave-gateway-address-1",
			}
			local status, error = pcall(epochs.saveObservations, observer, reportTxId, failedGateways, timestamp)
			assert.is_false(status)
			assert.match("Caller is not a prescribed observer for the current epoch.", error)
		end)
		it(
			"should save observation when the timestamp is after the distribution delay and only mark gateways around during the full epoch as failed",
			function()
				local observer = "test-this-is-valid-arweave-observer-address-2"
				local reportTxId = "test-this-very-valid-observations-report-tx"
				local settings = epochs.getSettings()
				local timestamp = settings.epochZeroStartTimestamp + settings.distributionDelayMs + 1
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
				_G.Epochs[0].prescribedObservers = {
					["test-this-is-valid-arweave-observer-address-2"] = "test-this-is-valid-arweave-wallet-address-2",
				}
				local failedGateways = {
					"test-this-is-valid-arweave-wallet-address-1",
					"test-this-is-valid-arweave-wallet-address-3",
				}
				local result = epochs.saveObservations(observer, reportTxId, failedGateways, timestamp)
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
			local expectation = { 1704092400000, 1704092400100, 1704092400115 }
			local result = { epochs.getEpochTimestampsForIndex(epochIndex) }
			assert.are.same(result, expectation)
		end)
	end)

	describe("createEpoch", function()
		it("should create a new epoch for the given timestamp if all previous epochs have been distributed", function()
			_G.Epochs = {}
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
				-- not eligible for rewards as it is leaving, so it should not be included in the eligible gateways count
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
			local settings = epochs.getSettings()
			local epochIndex = 1
			local epochStartTimestamp = settings.epochZeroStartTimestamp + settings.durationMs
			local timestamp = epochStartTimestamp
			local epochEndTimestamp = epochStartTimestamp + settings.durationMs
			local epochDistributionTimestamp = epochEndTimestamp + settings.distributionDelayMs
			local epochStartBlockHeight = 0
			local expectedEligibleRewards = math.floor(protocolBalance * constants.minimumRewardRate)
			local expectedTotalGatewayReward = math.floor(expectedEligibleRewards * 0.90)
			local expectedTotalObserverReward = math.floor(expectedEligibleRewards * 0.10)
			local expectedPerGatewayReward = math.floor(expectedTotalGatewayReward / 1) -- only one gateway in the registry
			local expectedPerObserverReward = math.floor(expectedTotalObserverReward / 1) -- only one prescribed observer
			local expectation = {
				startTimestamp = epochStartTimestamp,
				endTimestamp = epochEndTimestamp,
				epochIndex = epochIndex,
				startHeight = 0,
				distributionTimestamp = epochDistributionTimestamp,
				observations = {
					failureSummaries = {},
					reports = {},
				},
				prescribedObservers = {
					["test-this-is-valid-arweave-wallet-address-1"] = "test-this-is-valid-arweave-wallet-address-1",
				},
				prescribedNames = {},
				distributions = {
					totalEligibleGateways = 1,
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
				arnsStats = {
					totalActiveNames = 0,
					totalReservedNames = 0,
					totalReturnedNames = 0,
				},
			}
			local result = epochs.createEpoch(timestamp, epochStartBlockHeight, hashchain)
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
	end)

	describe("distributeRewardsForEpoch", function()
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
			local expectedGatewayReward = epoch.distributions.totalEligibleGatewayReward
			local expectedObserverReward = epoch.distributions.totalEligibleObserverReward

			-- validate the distribution of rewards for the epoch
			local distributedEpoch = epochs.distributeRewardsForEpoch(epoch.distributionTimestamp)
			assert.is_not_nil(distributedEpoch)

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
			assert.are.equal(epoch.distributionTimestamp, distributions.distributedTimestamp)

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
				_G.Epochs[epochIndex].distributions.distributedTimestamp = 1704092400115
				local epoch = epochs.getEpoch(epochIndex)
				local distributedEpoch = epochs.distributeRewardsForEpoch(epoch.distributionTimestamp)
				assert.is_nil(distributedEpoch)
				assert.is_nil(_G.Epochs[epochIndex])
			end
		)

		it("should return nil if the epoch does not exist in the epoch registry", function()
			local epochIndex = 0
			local epoch = epochs.getEpoch(epochIndex)
			-- remove the epoch from the epoch registry
			_G.Epochs[epochIndex] = nil
			assert.is_nil(epochs.distributeRewardsForEpoch(epoch.distributionTimestamp))
		end)
	end)

	-- prune epochs
	describe("pruneEpochs", function()
		local startingEpochs
		before_each(function()
			_G.Epochs = {}
			-- add 20 epochs
			for i = 0, 20 do
				_G.Epochs[i] = {
					epochIndex = i,
					startTimestamp = 1704092400000,
					endTimestamp = 1704092400100,
					distributionTimestamp = 1704092400115,
				}
			end
			startingEpochs = utils.deepCopy(_G.Epochs)
		end)

		it(
			"should prune any epochs older than the current epoch and previous epoch, until distribution occurs",
			function()
				local currentTimestamp = epochs.getSettings().epochZeroStartTimestamp
					+ epochs.getSettings().durationMs * 20
					+ 1
				-- prune epochs, keeping on the current epoch and the previous one
				epochs.pruneEpochs(currentTimestamp)
				assert.are.equal(2, utils.lengthOfTable(_G.Epochs))
				assert.are.same({
					[19] = _G.Epochs[19],
					[20] = _G.Epochs[20],
				}, _G.Epochs)
			end
		)

		it("should skip pruning when unnecessary", function()
			local currentTimestamp = epochs.getSettings().epochZeroStartTimestamp
				+ epochs.getSettings().durationMs * 20
				+ 1
			_G.NextEpochsPruneTimestamp = currentTimestamp + 1
			-- prune epochs
			local result = epochs.pruneEpochs(currentTimestamp)
			assert.are.same({}, result)
			assert.are.same(startingEpochs, _G.Epochs)
			assert.are.equal(currentTimestamp + 1, _G.NextEpochsPruneTimestamp)
		end)
	end)

	describe("getRewardRateForEpoch", function()
		it("returns 0.05% for the first 365 epochs (approximately one year)", function()
			assert.are.equal(0.0005, epochs.getRewardRateForEpoch(1))
			assert.are.equal(0.0005, epochs.getRewardRateForEpoch(2))
			assert.are.equal(0.0005, epochs.getRewardRateForEpoch(364))
			assert.are.equal(0.0005, epochs.getRewardRateForEpoch(365))
		end)

		it("returns a linearly decreasing rate starting from 0.1% after 365 epochs", function()
			assert.are.equal(0.00099726775956284147498, epochs.getRewardRateForEpoch(366))
			assert.are.equal(0.00099453551912568314598, epochs.getRewardRateForEpoch(367))
			assert.are.equal(0.00099180327868852460015, epochs.getRewardRateForEpoch(368))

			assert.are.equal(0.0005109289617486338685, epochs.getRewardRateForEpoch(544))
			assert.are.equal(0.00050819672131147543108, epochs.getRewardRateForEpoch(545))
			assert.are.equal(0.00050546448087431699366, epochs.getRewardRateForEpoch(546))
			assert.are.equal(0.00050273224043715844783, epochs.getRewardRateForEpoch(547))
		end)

		it("returns 0.05% after 547 epochs (approximately 1.5 years)", function()
			assert.are.equal(0.0005, epochs.getRewardRateForEpoch(548))
			assert.are.equal(0.0005, epochs.getRewardRateForEpoch(730))
			assert.are.equal(0.0005, epochs.getRewardRateForEpoch(12053))
		end)
	end)
end)
