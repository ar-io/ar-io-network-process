local epochs = require("epochs")
local gar = require("gar")
local balances = require("balances")
local utils = require("utils")
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
local protocolBalance = 500000000 * 1000000
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
		epochs.updateEpochSettings({
			prescribedNameCount = 5,
			maxObservers = 5,
			epochZeroStartTimestamp = 1704092400000, -- 2024-01-01T00:00:00.000Z
			durationMs = 100,
			distributionDelayMs = 15,
			rewardPercentage = 0.0025, -- 0.25%
			pruneEpochsCount = 14,
		})
	end)

	describe("computePrescribedObserversForEpoch", function()
		it("should return all eligible gateways if fewer than the maximum in network", function()
			GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = {
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
			}
			local expectation = {
				{
					gatewayAddress = "test-this-is-valid-arweave-wallet-address-1",
					observerAddress = "observerAddress",
					stake = gar.getSettings().operators.minStake,
					startTimestamp = startTimestamp,
					stakeWeight = 1,
					tenureWeight = 1 / gar.getSettings().observers.tenureWeightPeriod,
					gatewayRewardRatioWeight = 1,
					observerRewardRatioWeight = 1,
					compositeWeight = 1 / gar.getSettings().observers.tenureWeightPeriod,
					normalizedCompositeWeight = 1,
				},
			}
			local status, result = pcall(epochs.computePrescribedObserversForEpoch, 0, hashchain)
			assert.is_true(status)
			assert.are.equal(1, #result)
			assert.are.same(expectation, result)
		end)

		it("should return the maximum number of gateways if more are enrolled in network", function()
			local hashchain = "c29tZSBzYW1wbGUgaGFzaA==" -- base64 of "some sample hash"
			epochs.updateEpochSettings({
				maxObservers = 2, -- limit to 2 observers
				epochZeroStartTimestamp = startTimestamp,
				durationMs = 60 * 1000 * 60 * 24, -- 24 hours
				distributionDelayMs = 60 * 1000 * 2 * 15, -- 15 blocks
			})
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
					observerAddress = "observerAddress",
				}
				-- note - ordering of keys is not guaranteed when insert into maps
				GatewayRegistry["observer" .. i] = gateway
			end

			local expectation = {
				{
					gatewayAddress = "observer2",
					observerAddress = "observerAddress",
					stake = gar.getSettings().operators.minStake,
					startTimestamp = startTimestamp,
					stakeWeight = 1,
					tenureWeight = 1 / gar.getSettings().observers.tenureWeightPeriod,
					gatewayRewardRatioWeight = 1,
					observerRewardRatioWeight = 1,
					compositeWeight = 1 / gar.getSettings().observers.tenureWeightPeriod,
					normalizedCompositeWeight = 1 / 3,
				},
				{
					gatewayAddress = "observer1",
					observerAddress = "observerAddress",
					stake = gar.getSettings().operators.minStake,
					startTimestamp = startTimestamp,
					stakeWeight = 1,
					tenureWeight = 1 / gar.getSettings().observers.tenureWeightPeriod,
					gatewayRewardRatioWeight = 1,
					observerRewardRatioWeight = 1,
					compositeWeight = 1 / gar.getSettings().observers.tenureWeightPeriod,
					normalizedCompositeWeight = 1 / 3,
				},
			}
			local status, result = pcall(epochs.computePrescribedObserversForEpoch, 0, hashchain)
			assert.is_true(status)
			assert.are.equal(2, #result)
			assert.are.same(expectation, result)
		end)
	end)

	describe("computePrescrbiedNamesForEpoch", function()
		it("should return all eligible names if fewer than the maximum in name registry", function()
			_G.NameRegistry.records = {
				["arns-name-1"] = {
					startTimestamp = startTimestamp,
					endTimestamp = startTimestamp + 60 * 1000 * 60 * 24 * 365, -- add a year
					type = "lease",
					purchasePrice = 0,
					undernameLimit = 10,
				},
				["arns-name-2"] = {
					startTimestamp = startTimestamp,
					type = "permabuy",
					purchasePrice = 0,
					undernameLimit = 10,
				},
			}
			local expectation = { "arns-name-1", "arns-name-2" }
			local status, result = pcall(epochs.computePrescribedNamesForEpoch, 0, hashchain)
			assert.is_true(status)
			assert.are.equal(2, #result)
			assert.are.same(expectation, result)
		end)

		it("should return a subset of eligible names if more than the maximum in the name registry", function()
			_G.NameRegistry.records = {
				["arns-name-1"] = {
					startTimestamp = startTimestamp,
					endTimestamp = startTimestamp + 60 * 1000 * 60 * 24 * 365, -- add a year
					type = "lease",
					purchasePrice = 0,
					undernameLimit = 10,
				},
				["arns-name-2"] = {
					startTimestamp = startTimestamp,
					type = "permabuy",
					purchasePrice = 0,
					undernameLimit = 10,
				},
				["arns-name-3"] = {
					startTimestamp = startTimestamp,
					endTimestamp = startTimestamp + 60 * 1000 * 60 * 24 * 365, -- add a year
					type = "lease",
					purchasePrice = 0,
					undernameLimit = 10,
				},
				["arns-name-4"] = {
					startTimestamp = startTimestamp,
					type = "permabuy",
					purchasePrice = 0,
					undernameLimit = 10,
				},
				["arns-name-5"] = {
					startTimestamp = startTimestamp,
					type = "permabuy",
					purchasePrice = 0,
					undernameLimit = 10,
				},
				["arns-name-6"] = {
					startTimestamp = startTimestamp,
					endTimestamp = startTimestamp + 60 * 1000 * 60 * 24 * 365, -- add a year
					type = "lease",
					purchasePrice = 0,
					undernameLimit = 10,
				},
			}
			local expectation = { "arns-name-1", "arns-name-2", "arns-name-4", "arns-name-5", "arns-name-6" }
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
			local observer = "test-this-is-valid-arweave-wallet-address-2"
			local reportTxId = "test-this-very-valid-observations-report-tx"
			local settings = epochs.getSettings()
			local timestamp = settings.epochZeroStartTimestamp + settings.distributionDelayMs + 1
			local failedGateways = {
				"test-this-is-valid-arweave-wallet-address-1",
			}
			Epochs[0].prescribedObservers = {
				{
					gatewayAddress = "test-this-is-valid-arweave-wallet-address-1",
					observerAddress = "test-this-is-valid-arweave-wallet-address-1",
					stake = gar.getSettings().operators.minStake,
					startTimestamp = startTimestamp,
					stakeWeight = 1,
					tenureWeight = 1 / gar.getSettings().observers.tenureWeightPeriod,
					gatewayRewardRatioWeight = 1,
					observerRewardRatioWeight = 1,
					compositeWeight = 1 / gar.getSettings().observers.tenureWeightPeriod,
					normalizedCompositeWeight = 1,
				},
			}
			local status, error = pcall(epochs.saveObservations, observer, reportTxId, failedGateways, timestamp)
			assert.is_false(status)
			assert.match("Caller is not a prescribed observer for the current epoch.", error)
		end)
		it(
			"should save observation when the timestamp is after the distribution delay and only mark gateways around during the full epoch as failed",
			function()
				local observer = "test-this-is-valid-arweave-wallet-address-2"
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
						observerAddress = "test-this-is-valid-arweave-wallet-address-1",
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
						observerAddress = "test-this-is-valid-arweave-wallet-address-2",
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
						observerAddress = "test-this-is-valid-arweave-wallet-address-3",
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
						observerAddress = "test-this-is-valid-arweave-wallet-address-4",
					},
				}
				_G.Epochs[0].prescribedObservers = {
					{
						gatewayAddress = "test-this-is-valid-arweave-wallet-address-2",
						observerAddress = "test-this-is-valid-arweave-wallet-address-2",
						stake = gar.getSettings().operators.minStake,
						startTimestamp = startTimestamp,
						stakeWeight = 1,
						tenureWeight = 1 / gar.getSettings().observers.tenureWeightPeriod,
						gatewayRewardRatioWeight = 1,
						observerRewardRatioWeight = 1,
						compositeWeight = 1 / gar.getSettings().observers.tenureWeightPeriod,
						normalizedCompositeWeight = 1,
					},
				}
				local failedGateways = {
					"test-this-is-valid-arweave-wallet-address-1",
					"test-this-is-valid-arweave-wallet-address-3",
				}
				local status, result = pcall(epochs.saveObservations, observer, reportTxId, failedGateways, timestamp)
				assert.is_true(status)
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
		it(
			"should create a new epoch for the given timestamp once distributions for the last epoch have occurred",
			function()
				_G.Epochs[0].distributions = {
					totalEligibleRewards = 0,
					totalDistributedRewards = 0,
					distributedTimestamp = 0, -- it has a distribution timestamp
					rewards = {
						eligible = {},
						distributed = {},
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
							gatewayRewardRatioWeight = 0,
							observerRewardRatioWeight = 0,
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
							gatewayRewardRatioWeight = 0,
							observerRewardRatioWeight = 0,
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
				local expectedElibibleRewards = math.floor(protocolBalance * settings.rewardPercentage)
				local expectedTotalGatewayReward = math.floor(expectedElibibleRewards * 0.90)
				local expectedTotalObserverReward = math.floor(expectedElibibleRewards * 0.10)
				local expectedPerGatewayReward = math.floor(expectedTotalGatewayReward / 1) -- only one gateway in the registry
				local expectedPerObserverReward = math.floor(expectedTotalObserverReward / 1) -- only one prescribed obserever
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
						{
							compositeWeight = 4.0,
							gatewayAddress = "test-this-is-valid-arweave-wallet-address-1",
							gatewayRewardRatioWeight = 1.0,
							normalizedCompositeWeight = 1.0,
							observerAddress = "test-this-is-valid-arweave-wallet-address-1",
							observerRewardRatioWeight = 1.0,
							stake = gar.getSettings().operators.minStake,
							stakeWeight = 1.0,
							startTimestamp = 0,
							tenureWeight = 4,
						},
					},
					prescribedNames = {},
					distributions = {
						totalEligibleGateways = 1,
						totalEligibleRewards = expectedElibibleRewards,
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
				local status, result = pcall(epochs.createEpoch, timestamp, epochStartBlockHeight, hashchain)
				assert.is_true(status)
				assert.are.same(expectation, result)
				assert.are.same(expectation, epochs.getEpoch(epochIndex))
				-- confirm the gateway weights were updated
				assert.are.same({
					stakeWeight = 1,
					tenureWeight = 4,
					gatewayRewardRatioWeight = 1,
					observerRewardRatioWeight = 1,
					compositeWeight = 4,
					normalizedCompositeWeight = 1,
				}, gar.getGateway("test-this-is-valid-arweave-wallet-address-1").weights)
				-- confirm the leaving gateway weights were not updated
				assert.are.same({
					stakeWeight = 0,
					tenureWeight = 0,
					gatewayRewardRatioWeight = 0,
					observerRewardRatioWeight = 0,
					compositeWeight = 0,
					normalizedCompositeWeight = 0,
				}, gar.getGateway("test-this-is-valid-arweave-wallet-address-2").weights)
			end
		)
	end)

	describe("distributeRewardsForEpoch", function()
		it("should distribute rewards for the epoch, auto staking for delegates", function()
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
							["test-this-is-valid-arweave-wallet-address-2"] = {
								operatorReward = 225000000000,
								delegateRewards = { ["this-is-a-delegate"] = 25000000000 },
							},
							["test-this-is-valid-arweave-wallet-address-1"] = {
								operatorReward = 225000000000,
								delegateRewards = { ["this-is-a-delegate"] = 25000000000 },
							},
							["test-this-is-valid-arweave-wallet-address-4"] = {
								operatorReward = 225000000000,
								delegateRewards = { ["this-is-a-delegate"] = 25000000000 },
							},
							["test-this-is-valid-arweave-wallet-address-5"] = {
								operatorReward = 225000000000,
								delegateRewards = { ["this-is-a-delegate"] = 25000000000 },
							},
							["test-this-is-valid-arweave-wallet-address-3"] = {
								operatorReward = 225000000000,
								delegateRewards = { ["this-is-a-delegate"] = 25000000000 },
							},
						},
					},
				},
				prescribedNames = {},
				prescribedObservers = {
					{
						tenureWeight = 4,
						observerRewardRatioWeight = 0.5,
						observerAddress = "test-this-very-valid-observer-wallet-addr-1",
						stakeWeight = 1.002,
						startTimestamp = 0,
						normalizedCompositeWeight = 0.3448275862069,
						compositeWeight = 2.004,
						gatewayAddress = "test-this-is-valid-arweave-wallet-address-1",
						gatewayRewardRatioWeight = 1,
						stake = 50100000000,
					},
					{
						tenureWeight = 4,
						observerRewardRatioWeight = 0.33333333333333,
						observerAddress = "test-this-very-valid-observer-wallet-addr-2",
						stakeWeight = 1.002,
						startTimestamp = 0,
						normalizedCompositeWeight = 0.22988505747126,
						compositeWeight = 1.336,
						gatewayAddress = "test-this-is-valid-arweave-wallet-address-2",
						gatewayRewardRatioWeight = 1,
						stake = 50100000000,
					},
					{
						tenureWeight = 4,
						observerRewardRatioWeight = 0.25,
						observerAddress = "test-this-very-valid-observer-wallet-addr-3",
						stakeWeight = 1.002,
						startTimestamp = 0,
						normalizedCompositeWeight = 0.17241379310345,
						compositeWeight = 1.002,
						gatewayAddress = "test-this-is-valid-arweave-wallet-address-3",
						gatewayRewardRatioWeight = 1,
						stake = 50100000000,
					},
					{
						tenureWeight = 4,
						observerRewardRatioWeight = 0.2,
						observerAddress = "test-this-very-valid-observer-wallet-addr-4",
						stakeWeight = 1.002,
						startTimestamp = 0,
						normalizedCompositeWeight = 0.13793103448276,
						compositeWeight = 0.8016,
						gatewayAddress = "test-this-is-valid-arweave-wallet-address-4",
						gatewayRewardRatioWeight = 1,
						stake = 50100000000,
					},
					{
						tenureWeight = 4,
						observerRewardRatioWeight = 0.16666666666667,
						observerAddress = "test-this-very-valid-observer-wallet-addr-5",
						stakeWeight = 1.002,
						startTimestamp = 0,
						normalizedCompositeWeight = 0.11494252873563,
						compositeWeight = 0.668,
						gatewayAddress = "test-this-is-valid-arweave-wallet-address-5",
						gatewayRewardRatioWeight = 1,
						stake = 50100000000,
					},
				},
			}

			local epochIndex = 0
			local originalDelegatedStake = 100000000
			for i = 1, 5 do
				local gateway = {
					operatorStake = gar.getSettings().operators.minStake,
					totalDelegatedStake = originalDelegatedStake,
					vaults = {},
					delegates = {
						["this-is-a-delegate"] = {
							delegatedStake = originalDelegatedStake,
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
						autoStake = i == 2, -- set autostake on for the second gateway
						label = "test",
						properties = "",
						delegateRewardShareRatio = 10,
					},
					status = "joined",
					observerAddress = "test-this-very-valid-observer-wallet-addr-" .. i,
				}
				gar.addGateway("test-this-is-valid-arweave-wallet-address-" .. i, gateway)
			end
			-- clear the balances for the gateways
			Balances["test-this-is-valid-arweave-wallet-address-1"] = 0
			local epoch = epochs.getEpoch(epochIndex)
			local expectedGatewayReward = epoch.distributions.totalEligibleGatewayReward
			local expectedObserverReward = epoch.distributions.totalEligibleObserverReward

			-- distribute rewards for the epoch
			local status, result = pcall(epochs.distributeRewardsForEpoch, epoch.distributionTimestamp)
			assert.is_true(status)
			-- gateway 1 should not get any rewards - failed observation and did not observe, should not get any rewards
			assert.are.same({
				prescribedEpochCount = 2, -- increment by one
				observedEpochCount = 0,
				passedEpochCount = 0,
				failedEpochCount = 1,
				failedConsecutiveEpochs = 1,
				passedConsecutiveEpochs = 0,
				totalEpochCount = 1,
			}, gar.getGateway("test-this-is-valid-arweave-wallet-address-1").stats)
			assert.are.equal(
				gar.getSettings().operators.minStake,
				gar.getGateway("test-this-is-valid-arweave-wallet-address-1").operatorStake
			)

			-- passed observation, did not observe
			assert.are.same({
				prescribedEpochCount = 3, -- increment by one
				observedEpochCount = 0,
				passedEpochCount = 1,
				failedEpochCount = 0,
				failedConsecutiveEpochs = 0,
				passedConsecutiveEpochs = 1,
				totalEpochCount = 1,
			}, gar.getGateway("test-this-is-valid-arweave-wallet-address-2").stats)
			local gateway1 = gar.getGateway("test-this-is-valid-arweave-wallet-address-2")
			local balance1 = balances.getBalance("test-this-is-valid-arweave-wallet-address-2")
			assert.are.equal(
				-- it passed, but did not observe, so it gets 75% of the gateway reward and then 90% of that bc of the delegate reward share
				gar.getSettings().operators.minStake + math.floor((expectedGatewayReward * 0.75) * 0.90),
				gateway1.operatorStake
			)
			assert.are.equal(0, balance1)
			-- failed observation, did observe
			assert.are.same({
				prescribedEpochCount = 4, -- increment by one
				observedEpochCount = 1,
				passedEpochCount = 0,
				failedEpochCount = 1,
				failedConsecutiveEpochs = 1,
				passedConsecutiveEpochs = 0,
				totalEpochCount = 1,
			}, gar.getGateway("test-this-is-valid-arweave-wallet-address-3").stats)
			assert.are.equal(
				math.floor(expectedObserverReward * 0.90), -- 10% is given to delegates
				balances.getBalance("test-this-is-valid-arweave-wallet-address-3")
			)
			assert.are.equal(
				gar.getSettings().operators.minStake,
				gar.getGateway("test-this-is-valid-arweave-wallet-address-3").operatorStake
			)
			-- passed observation, did observe
			assert.are.same({
				prescribedEpochCount = 5, -- increment by one
				observedEpochCount = 1,
				passedEpochCount = 1,
				failedEpochCount = 0,
				failedConsecutiveEpochs = 0,
				passedConsecutiveEpochs = 1,
				totalEpochCount = 1,
			}, gar.getGateway("test-this-is-valid-arweave-wallet-address-4").stats)
			assert.are.equal(
				math.floor((expectedGatewayReward + expectedObserverReward) * 0.90), -- 10% is given to delegates
				balances.getBalance("test-this-is-valid-arweave-wallet-address-4")
			)
			assert.are.equal(
				gar.getSettings().operators.minStake,
				gar.getGateway("test-this-is-valid-arweave-wallet-address-4").operatorStake
			)
			-- passed observation, did observe
			assert.are.same({
				prescribedEpochCount = 6, -- increment by one
				observedEpochCount = 1,
				passedEpochCount = 1,
				failedEpochCount = 0,
				failedConsecutiveEpochs = 0,
				passedConsecutiveEpochs = 1,
				totalEpochCount = 1,
			}, gar.getGateway("test-this-is-valid-arweave-wallet-address-5").stats)
			assert.are.equal(
				(expectedGatewayReward + expectedObserverReward) * 0.90, -- 10% is given to delegates
				balances.getBalance("test-this-is-valid-arweave-wallet-address-5")
			)
			assert.are.equal(
				gar.getSettings().operators.minStake,
				gar.getGateway("test-this-is-valid-arweave-wallet-address-5").operatorStake
			)

			local expectedGateway1TotalRewards = 0
			local expectedGateway2TotalRewards = math.floor(expectedGatewayReward * 0.75) -- penalized for not observing
			local expectedGateway3TotalRewards = expectedObserverReward
			local expectedGateway4TotalRewards = (expectedGatewayReward + expectedObserverReward)
			local expectedGateway5TotalRewards = (expectedGatewayReward + expectedObserverReward)

			-- check the epoch was updated
			local distributions = epochs.getEpoch(epochIndex).distributions
			local expectedTotalDistribution = math.floor(expectedGateway1TotalRewards + expectedGateway2TotalRewards + expectedGateway3TotalRewards + expectedGateway4TotalRewards + expectedGateway5TotalRewards)

			-- confirm the updated epoch values
			assert.are.equal(expectedTotalDistribution, distributions.totalDistributedRewards)
			assert.are.equal(epoch.distributionTimestamp, distributions.distributedTimestamp)

			assert.are.same({
				["test-this-is-valid-arweave-wallet-address-1"] = expectedGateway1TotalRewards * 0.90,
				["test-this-is-valid-arweave-wallet-address-2"] = expectedGateway2TotalRewards * 0.90,
				["test-this-is-valid-arweave-wallet-address-3"] = expectedGateway3TotalRewards * 0.90,
				["test-this-is-valid-arweave-wallet-address-4"] = expectedGateway4TotalRewards * 0.90,
				["test-this-is-valid-arweave-wallet-address-5"] = expectedGateway5TotalRewards * 0.90,
				["this-is-a-delegate"] = expectedTotalDistribution * 0.10,
			}, distributions.rewards.distributed)
			-- gateway 1 did not get any rewards, so the delegate stake should be the original amount
			assert.are.equal(
				originalDelegatedStake,
				gar.getGateway("test-this-is-valid-arweave-wallet-address-1").delegates["this-is-a-delegate"].delegatedStake
			)
			-- delegate on gateway 2 gets 10% of the total rewards received by the gateway
			assert.are.equal(
				originalDelegatedStake + math.floor(expectedGateway2TotalRewards * 0.10),
				gar.getGateway("test-this-is-valid-arweave-wallet-address-2").delegates["this-is-a-delegate"].delegatedStake
			)
			-- delegate on gateway 3 gets 10% of the total rewards received by the gateway
			assert.are.equal(
				originalDelegatedStake + math.floor(expectedGateway3TotalRewards * 0.10),
				gar.getGateway("test-this-is-valid-arweave-wallet-address-3").delegates["this-is-a-delegate"].delegatedStake
			)
			-- delegate on gateway 4 gets 10% of the total rewards received by the gateway
			assert.are.equal(
				originalDelegatedStake + math.floor(expectedGateway4TotalRewards * 0.10),
				gar.getGateway("test-this-is-valid-arweave-wallet-address-4").delegates["this-is-a-delegate"].delegatedStake
			)
			-- assert that the balance withdrawn from the protocol balance matches the total distributed rewards
			assert.are.equal(protocolBalance - expectedTotalDistribution, balances.getBalance(ao.id))
		end)
	end)

	-- prune epochs
	describe("pruneEpochs", function()
		it("should prune epochs older than 14 days", function()
			-- add 20 epochs
			for i = 0, 20 do
				_G.Epochs[i] = {
					epochIndex = i,
					startTimestamp = 1704092400000,
					endTimestamp = 1704092400100,
					distributionTimestamp = 1704092400115,
				}
			end
			local currentTimestamp = epochs.getSettings().epochZeroStartTimestamp
				+ epochs.getSettings().durationMs * 20
				+ 1
			-- prune epochs
			epochs.pruneEpochs(currentTimestamp)
			-- confirm the lenght of epochs is only 14 and the last 14 days are left
			assert.are.equal(14, utils.lengthOfTable(_G.Epochs))
			assert.are.same({
				[7] = _G.Epochs[7],
				[8] = _G.Epochs[8],
				[9] = _G.Epochs[9],
				[10] = _G.Epochs[10],
				[11] = _G.Epochs[11],
				[12] = _G.Epochs[12],
				[13] = _G.Epochs[13],
				[14] = _G.Epochs[14],
				[15] = _G.Epochs[15],
				[16] = _G.Epochs[16],
				[17] = _G.Epochs[17],
				[18] = _G.Epochs[18],
				[19] = _G.Epochs[19],
				[20] = _G.Epochs[20],
			}, _G.Epochs)
		end)
	end)
end)
