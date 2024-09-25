local gar = require("gar")
local utils = require("utils")
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

	describe("slashOperatorStake", function()
		it("should slash operator stake by the provided slash amount and return it to the protocol balance", function()
			local slashAmount = 10000
			Balances[ao.id] = 0
			GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
			}
			local status, err =
				pcall(gar.slashOperatorStake, "test-this-is-valid-arweave-wallet-address-1", slashAmount)
			assert.is_true(status)
			assert.is_nil(err)
			assert.are.equal(
				gar.getSettings().operators.minStake - slashAmount,
				GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].operatorStake
			)
			assert.are.equal(slashAmount, Balances[ao.id])
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

	describe("pruneGateways", function()
		it(
			"should remove gateways with endTimestamp < currentTimestamp, slash gateways with failedConsecutiveEpochs > 30 and mark them for leaving",
			function()
				local currentTimestamp = 1000000
				local msgId = "msgId"

				-- Set up test gateways
				_G.GatewayRegistry = {
					["address1"] = {
						startTimestamp = currentTimestamp - 1000,
						endTimestamp = currentTimestamp - 100, -- Expired
						status = "leaving",
						operatorStake = gar.getSettings().operators.minStake,
						vaults = {},
						delegates = {},
						stats = {
							failedConsecutiveEpochs = 30,
						},
						-- Other gateway properties...
					},
					["address2"] = {
						startTimestamp = currentTimestamp - 100,
						endTimestamp = currentTimestamp + 100, -- Not expired, failedConsecutiveEpochs is 20
						status = "joined",
						operatorStake = gar.getSettings().operators.minStake,
						vaults = {},
						delegates = {},
						stats = {
							failedConsecutiveEpochs = 20,
						},
						-- Other gateway properties...
					},
					["address3"] = {
						startTimestamp = currentTimestamp - 100,
						endTimestamp = 0, -- Not expired, but failedConsecutiveEpochs is 30
						status = "joined",
						operatorStake = gar.getSettings().operators.minStake + 10000, -- will slash 20% of the min operator stake
						vaults = {},
						delegates = {},
						stats = {
							failedConsecutiveEpochs = 30,
						},
						-- Other gateway properties...
					},
				}

				-- Call pruneGateways
				local protocolBalanceBefore = _G.Balances[ao.id] or 0
				local status, err = pcall(gar.pruneGateways, currentTimestamp, msgId)
				assert.is_true(status)
				assert.is_nil(err)

				local expectedSlashedStake = math.floor(gar.getSettings().operators.minStake * 0.2)
				local expectedRemainingStake = math.floor(gar.getSettings().operators.minStake * 0.8) + 10000
				assert.is_nil(GatewayRegistry["address1"]) -- removed
				assert.is_not_nil(GatewayRegistry["address2"]) -- not removed
				assert.is_not_nil(GatewayRegistry["address3"]) -- not removed
				-- Check that gateway 3's operator stake is slashed by 20% and the remaining stake is vaulted
				assert.are.equal("leaving", GatewayRegistry["address3"].status)
				assert.are.equal(0, GatewayRegistry["address3"].operatorStake)
				assert.are.same({
					balance = expectedRemainingStake,
					startTimestamp = currentTimestamp,
					endTimestamp = currentTimestamp + gar.getSettings().operators.leaveLengthMs,
				}, GatewayRegistry["address3"].vaults["address3"])
				assert.are.equal(protocolBalanceBefore + expectedSlashedStake, Balances[ao.id])
			end
		)

		it("should handle empty GatewayRegistry", function()
			local currentTimestamp = 1000000

			-- Set up empty GatewayRegistry
			_G.GatewayRegistry = {}

			-- Call pruneGateways
			gar.pruneGateways(currentTimestamp)

			-- Check results
			local gateways = gar.getGateways()
			assert.equals(0, utils.lengthOfTable(gateways))
		end)
	end)

	describe("cancelDelegateWithdrawal", function()
		it("should cancel a withdrawal", function()
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = testGateway
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].delegates["test-this-is-valid-arweave-wallet-address-2"] =
				{
					delegatedStake = 0,
					vaults = {
						["some-previous-withdrawal-id"] = {
							balance = 1000,
							startTimestamp = 0,
							endTimestamp = 1000,
						},
					},
				}
			local status, result = pcall(
				gar.cancelDelegateWithdrawal,
				"test-this-is-valid-arweave-wallet-address-2",
				"test-this-is-valid-arweave-wallet-address-1",
				"some-previous-withdrawal-id"
			)
			assert.is_true(status)
			assert.are.same(
			result,
			{
				totalDelegatedStake = 1000,
				delegate = {
					delegatedStake = 1000,
					vaults = {},
				},
			})
			-- assert the vault is removed and the delegated stake is added back to the delegate
			assert.are.equal(
				1000, -- added back to the delegate
				GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].delegates["test-this-is-valid-arweave-wallet-address-2"].delegatedStake
			)
			assert.are.equal(
				nil,
				GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].delegates["test-this-is-valid-arweave-wallet-address-2"].vaults["some-previous-withdrawal-id"]
			)
			assert.are.equal(1000, GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].totalDelegatedStake)
		end)
		it("should not cancel a withdrawal if the gateway does not allow staking", function()
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = testGateway
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].settings.allowDelegatedStaking = false
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].delegates["test-this-is-valid-arweave-wallet-address-2"] =
				{
					delegatedStake = 0,
					vaults = {
						["some-previous-withdrawal-id"] = {
							balance = 1000,
							startTimestamp = 0,
							endTimestamp = 1000,
						},
					},
				}
			local status, err = pcall(
				gar.cancelDelegateWithdrawal,
				"test-this-is-valid-arweave-wallet-address-2",
				"test-this-is-valid-arweave-wallet-address-1",
				"some-previous-withdrawal-id"
			)
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches("Gateway does not allow staking", err)
			assert.are.same(
				{
					delegatedStake = 0,
					vaults = {
						["some-previous-withdrawal-id"] = {
							balance = 1000,
							startTimestamp = 0,
							endTimestamp = 1000,
						},
					},
				},
				_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].delegates["test-this-is-valid-arweave-wallet-address-2"]
			)
		end)
		it("should not cancel a withdrawal if the delegate does not exist", function()
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = testGateway
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].delegates["test-this-is-valid-arweave-wallet-address-2"] =
				nil
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].settings.allowDelegatedStaking = true
			local status, err = pcall(
				gar.cancelDelegateWithdrawal,
				"test-this-is-valid-arweave-wallet-address-2",
				"test-this-is-valid-arweave-wallet-address-1",
				"some-previous-withdrawal-id"
			)
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches("Delegate does not exist", err)
		end)
		it("should not cancel a withdrawal if the withdrawal does not exist", function()
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = testGateway
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].delegates["test-this-is-valid-arweave-wallet-address-2"] =
				{
					delegatedStake = 0,
					vaults = {},
					startTimestamp = 0,
				}
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].settings.allowDelegatedStaking = true
			local status, err = pcall(
				gar.cancelDelegateWithdrawal,
				"test-this-is-valid-arweave-wallet-address-2",
				"test-this-is-valid-arweave-wallet-address-1",
				"some-previous-withdrawal-id"
			)
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches("Vault does not exist", err)
		end)
		it("should not cancel a withdrawal if the gateway is leaving", function()
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"] = testGateway
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].settings.allowDelegatedStaking = true
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].delegates["test-this-is-valid-arweave-wallet-address-2"] =
				{
					delegatedStake = 0,
					vaults = {
						["some-previous-withdrawal-id"] = {
							balance = 1000,
							startTimestamp = 0,
							endTimestamp = 1000,
						},
					},
					startTimestamp = 0,
				}
			_G.GatewayRegistry["test-this-is-valid-arweave-wallet-address-1"].status = "leaving"
			local status, err = pcall(
				gar.cancelDelegateWithdrawal,
				"test-this-is-valid-arweave-wallet-address-2",
				"test-this-is-valid-arweave-wallet-address-1",
				"some-previous-withdrawal-id"
			)
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches("Gateway is leaving the network and cannot cancel withdrawals.", err)
		end)
	end)

	describe("getActiveGatewaysBeforeTimestamp", function()
		it("should return all active gateways before the timestamp", function()
			local timestamp = 1704092400100
			_G.GatewayRegistry = {
				["test-this-is-valid-arweave-wallet-address-1"] = {
					startTimestamp = timestamp - 10, -- joined before the timestamp
					status = "joined",
				},
				["test-this-is-valid-arweave-wallet-address-2"] = {
					startTimestamp = timestamp + 10, -- joined after the timestamp
					status = "joined",
				},
				["test-this-is-valid-arweave-wallet-address-3"] = {
					startTimestamp = timestamp - 10, -- joined before the timestamp, but leaving
					endTimestamp = timestamp + 100,
					status = "leaving",
				},
			}
			local result = gar.getActiveGatewaysBeforeTimestamp(timestamp)
			assert.are.same({ "test-this-is-valid-arweave-wallet-address-1" }, result)
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
