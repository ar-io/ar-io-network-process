local gar = require("gar")
local testSettings = {
	fqdn = "test.com",
	protocol = "https",
	port = 443,
	allowDelegatedStaking = true,
	minDelegatedStake = gar.getSettings().delegates.minStake,
	autoStake = true,
	label = "test",
	delegateRewardShareRatio = 0,
	properties = "test-this-is-valid-arweave-wallet-address-1",
}

local startTimestamp = 0
local testGateway = {
	operatorStake = gar.getSettings().operators.minStake,
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
}

describe("gar", function()
	before_each(function()
		_G.Balances = {
			["test-this-is-valid-arweave-wallet-address-1"] = gar.getSettings().operators.minStake,
		}
		_G.Epochs = {
			[0] = {
				startTimestamp = 0,
				endTimestamp = 100,
				prescribedObservers = {},
				observations = {},
			},
		}
		_G.GatewayRegistry = {}
	end)

	describe("joinNetwork", function()
		it("should fail if the gateway is already in the network", function()
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
				observerAddress = "test-this-is-valid-arweave-wallet-address-1",
			}
			local status, error = pcall(
				gar.joinNetwork,
				"test-this-is-valid-arweave-wallet-address-1",
				gar.getSettings().operators.minStake,
				testSettings,
				"test-this-is-valid-arweave-wallet-address-1",
				startTimestamp
			)
			assert.is_false(status)
			assert.match("Gateway already exists", error)
		end)
		it("should join the network", function()
			local expectation = {
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
				settings = {
					allowDelegatedStaking = testSettings.allowDelegatedStaking,
					delegateRewardShareRatio = 0,
					autoStake = testSettings.autoStake,
					propteris = testSettings.propteries,
					minDelegatedStake = testSettings.minDelegatedStake,
					label = testSettings.label,
					fqdn = testSettings.fqdn,
					protocol = testSettings.protocol,
					port = testSettings.port,
					properties = testSettings.properties,
				},
				status = "joined",
				observerAddress = "test-this-is-valid-arweave-wallet-address-1",
			}
			local status, result = pcall(
				gar.joinNetwork,
				"test-this-is-valid-arweave-wallet-address-1",
				gar.getSettings().operators.minStake,
				testSettings,
				"test-this-is-valid-arweave-wallet-address-1",
				startTimestamp
			)
			assert.is_true(status)
			assert.are.equal(Balances["test-this-is-valid-arweave-wallet-address-1"], 0)
			assert.are.same(expectation, result)
			assert.are.same(expectation, gar.getGateway("test-this-is-valid-arweave-wallet-address-1"))
		end)
	end)

	describe("leaveNetwork", function()
		it("should leave the network", function()
			GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = {
				operatorStake = (gar.getSettings().operators.minStake + 1000),
				totalDelegatedStake = gar.getSettings().delegates.minStake,
				vaults = {},
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
				delegates = {
					["test-this-is-valid-arweave-wallet-address-2"] = {
						delegatedStake = gar.getSettings().delegates.minStake,
						startTimestamp = 0,
						vaults = {},
					},
				},
			}

			local status, result =
				pcall(gar.leaveNetwork, "test-this-is-valid-arweave-wallet-address-1", startTimestamp, "msgId")
			assert.is_true(status)
			assert.are.same(result, {
				operatorStake = 0,
				totalDelegatedStake = 0,
				vaults = {
					["test-this-is-valid-arweave-wallet-address-1"] = {
						balance = gar.getSettings().operators.minStake,
						startTimestamp = startTimestamp,
						endTimestamp = gar.getSettings().operators.leaveLengthMs,
					},
					msgId = {
						balance = 1000,
						startTimestamp = startTimestamp,
						endTimestamp = gar.getSettings().operators.withdrawLengthMs,
					},
				},
				delegates = {
					["test-this-is-valid-arweave-wallet-address-2"] = {
						delegatedStake = 0,
						startTimestamp = 0,
						vaults = {
							msgId = {
								balance = gar.getSettings().delegates.minStake,
								startTimestamp = startTimestamp,
								endTimestamp = gar.getSettings().delegates.withdrawLengthMs,
							},
						},
					},
				},
				startTimestamp = startTimestamp,
				endTimestamp = gar.getSettings().operators.leaveLengthMs,
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
				observerAddress = "observerAddress",
			})
		end)
	end)

	describe("increaseOperatorStake", function()
		it("should increase operator stake", function()
			Balances["test-this-is-valid-arweave-wallet-address-1"] = 1000
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
			local result, err = gar.increaseOperatorStake("test-this-is-valid-arweave-wallet-address-1", 1000)
			assert.are.equal(Balances["test-this-is-valid-arweave-wallet-address-1"], 0)
			assert.are.same(result, {
				operatorStake = gar.getSettings().operators.minStake + 1000,
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
			})
		end)
	end)

	describe("decreaseOperatorStake", function()
		it("should decrease operator stake", function()
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = {
				operatorStake = gar.getSettings().operators.minStake + 1000,
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
			local status, result = pcall(
				gar.decreaseOperatorStake,
				"test-this-is-valid-arweave-wallet-address-1",
				1000,
				startTimestamp,
				"msgId"
			)
			assert.is_true(status)
			assert.are.same(result, {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = 0,
				vaults = {
					msgId = {
						balance = 1000,
						startTimestamp = startTimestamp,
						endTimestamp = startTimestamp + gar.getSettings().operators.withdrawLengthMs,
					},
				},
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
			})
		end)
	end)

	describe("updateGatewaySettings", function()
		it("should update gateway settings", function()
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
				observerAddress = "test-this-is-valid-arweave-wallet-address-0",
			}
			local newObserverWallet = "test-this-is-valid-arweave-wallet-address-1"
			local updatedSettings = {
				fqdn = "example.com",
				port = 80,
				protocol = "https",
				properties = "NdZ3YRwMB2AMwwFYjKn1g88Y9nRybTo0qhS1ORq_E7g",
				note = "This is a test update.",
				label = "Test Label Update",
				autoStake = true,
				allowDelegatedStaking = false,
				delegateRewardShareRatio = 15,
				minDelegatedStake = gar.getSettings().delegates.minStake + 5,
			}
			local expectation = {
				operatorStake = gar.getSettings().operators.minStake,
				observerAddress = newObserverWallet,
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
				settings = updatedSettings,
				status = "joined",
			}
			local status, result = pcall(
				gar.updateGatewaySettings,
				"test-this-is-valid-arweave-wallet-address-1",
				updatedSettings,
				newObserverWallet,
				startTimestamp,
				"msgId"
			)
			assert.is_true(status)
			assert.are.same(expectation, result)
			assert.are.same(expectation, gar.getGateway("test-this-is-valid-arweave-wallet-address-1"))
		end)
	end)

	describe("delegateStake", function()
		it("should delegate stake to a gateway", function()
			Balances["test-this-is-valid-arweave-wallet-address-2"] = gar.getSettings().delegates.minStake
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
			local result, err = gar.delegateStake(
				"test-this-is-valid-arweave-wallet-address-2",
				"test-this-is-valid-arweave-wallet-address-1",
				gar.getSettings().delegates.minStake,
				startTimestamp
			)
			assert.are.equal(Balances["test-this-is-valid-arweave-wallet-address-2"], 0)
			assert.are.same(result, {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = gar.getSettings().delegates.minStake,
				vaults = {},
				delegates = {
					["test-this-is-valid-arweave-wallet-address-2"] = {
						delegatedStake = gar.getSettings().delegates.minStake,
						startTimestamp = startTimestamp,
						vaults = {},
					},
				},
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
			})
		end)

		it("should decrease delegated stake", function()
			GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = gar.getSettings().delegates.minStake + 1000,
				vaults = {},
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
				delegates = {
					["test-this-is-valid-arweave-wallet-address-2"] = {
						delegatedStake = gar.getSettings().delegates.minStake + 1000,
						startTimestamp = 0,
						vaults = {},
					},
				},
			}

			local expectation = {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = gar.getSettings().delegates.minStake,
				vaults = {},
				delegates = {
					["test-this-is-valid-arweave-wallet-address-2"] = {
						delegatedStake = gar.getSettings().delegates.minStake,
						startTimestamp = 0,
						vaults = {
							msgId = {
								balance = 1000,
								startTimestamp = startTimestamp,
								endTimestamp = gar.getSettings().delegates.withdrawLengthMs,
							},
						},
					},
				},
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
			local status, result = pcall(
				gar.decreaseDelegateStake,
				"test-this-is-valid-arweave-wallet-address-1",
				"test-this-is-valid-arweave-wallet-address-2",
				1000,
				startTimestamp,
				"msgId"
			)
			assert.is_true(status)
			assert.are.same(expectation, result)
			assert.are.same(expectation, gar.getGateway("test-this-is-valid-arweave-wallet-address-1"))
		end)
	end)

	describe("getGatewayWeightsAtTimestamp", function()
		it("shoulud properly compute weights based on gateways for a given timestamp", function()
			GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = 0,
				stats = {
					prescribedEpochCount = 3,
					observedEpochCount = 1,
					totalEpochCount = 10,
					passedEpochCount = 3,
					failedEpochCount = 7,
					failedConsecutiveEpochs = 5,
					passedConsecutiveEpochs = 0,
				},
				settings = testSettings,
				status = "joined",
				observerAddress = "observerAddress",
			}
			local timestamp = 100
			local expectedTenureWeight = timestamp / gar.getSettings().observers.tenureWeightPeriod
			local expectedStakeWeight = 1
			-- NOTE: we increment by one to avoid division by zero
			local expectedObserverRatioWeight = 2 / 4 -- (the stats are 1/3)
			local expectedGatewayRatioWeight = 4 / 11 -- (the tats are 3/10)
			local expectedCompositeWeight = expectedStakeWeight
				* expectedTenureWeight
				* expectedGatewayRatioWeight
				* expectedObserverRatioWeight
			local expectation = {
				{
					gatewayAddress = "test-this-is-valid-arweave-wallet-address-1",
					observerAddress = "observerAddress",
					stake = gar.getSettings().operators.minStake,
					startTimestamp = 0,
					stakeWeight = expectedStakeWeight,
					tenureWeight = expectedTenureWeight,
					gatewayRewardRatioWeight = expectedGatewayRatioWeight,
					observerRewardRatioWeight = expectedObserverRatioWeight,
					compositeWeight = expectedCompositeWeight,
					normalizedCompositeWeight = 1, -- there is only one gateway
				},
			}
			local status, result =
				pcall(gar.getGatewayWeightsAtTimestamp, { "test-this-is-valid-arweave-wallet-address-1" }, timestamp)
			assert.is_true(status)
			assert.are.same(expectation, result)
		end)
	end)

	describe("getters", function()
		-- TODO: other tests for error conditions when joining/leaving network
		it("should get single gateway", function()
			GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = testGateway
			local result = gar.getGateway("test-this-is-valid-arweave-wallet-address-1")
			assert.are.same(result, testGateway)
		end)

		it("should get multiple gateways", function()
			GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = testGateway
			GatewayRegistry["test-this-is-valid-arweave-wallet-address-2"] = testGateway
			local result = gar.getGateways()
			assert.are.same(result, {
				["test-this-is-valid-arweave-wallet-address-1"] = testGateway,
				["test-this-is-valid-arweave-wallet-address-2"] = testGateway,
			})
		end)
	end)
end)
