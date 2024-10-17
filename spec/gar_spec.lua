local gar = require("gar")
local utils = require("utils")

local startTimestamp = 0
local stubGatewayAddress = "test-this-is-valid-arweave-wallet-address-1"
local stubObserverAddress = "test-this-is-valid-arweave-wallet-address-2"
local stubRandomAddress = "test-this-is-valid-arweave-wallet-address-3"
local stubMessageId = "stub-message-id"
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
}
local testServices = {
	bundlers = {
		{
			fqdn = "bundler1.example.com",
			port = 443,
			protocol = "https",
			path = "/bundler1",
		},
		{
			fqdn = "bundler2.example.com",
			port = 443,
			protocol = "https",
			path = "/bundler2",
		},
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

describe("gar", function()
	before_each(function()
		_G.Balances = {
			[stubGatewayAddress] = gar.getSettings().operators.minStake,
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
			_G.GatewayRegistry[stubGatewayAddress] = {
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
				observerAddress = stubGatewayAddress,
			}
			local status, error = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				gar.getSettings().operators.minStake,
				testSettings,
				nil, -- no additional services on this gateway
				stubGatewayAddress,
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
				observerAddress = stubGatewayAddress,
			}
			local status, result = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				gar.getSettings().operators.minStake,
				testSettings,
				nil, -- no additional services on this gateway
				stubGatewayAddress,
				startTimestamp
			)
			assert.is_true(status)
			assert.are.equal(Balances[stubGatewayAddress], 0)
			assert.are.same(expectation, result)
			assert.are.same(expectation, gar.getGateway(stubGatewayAddress))
		end)
		it("should join the network with services and bundlers", function()
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
					delegateRewardShareRatio = testSettings.delegateRewardShareRatio,
					autoStake = testSettings.autoStake,
					minDelegatedStake = testSettings.minDelegatedStake,
					label = testSettings.label,
					fqdn = testSettings.fqdn,
					protocol = testSettings.protocol,
					port = testSettings.port,
					properties = testSettings.properties,
				},
				services = testServices,
				status = "joined",
				observerAddress = stubGatewayAddress,
			}

			local status, result = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				gar.getSettings().operators.minStake,
				testSettings,
				testServices,
				stubGatewayAddress,
				startTimestamp
			)
			assert.is_true(status)
			assert.are.equal(Balances[stubGatewayAddress], 0)
			assert.are.same(expectation, result)
			assert.are.same(expectation, gar.getGateway(stubGatewayAddress))
		end)
		it("should fail to join the network with invalid services key", function()
			local invalidServices = {
				invalidKey = {}, -- Invalid key not allowed
			}
			local status, error = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				gar.getSettings().operators.minStake,
				testSettings,
				invalidServices,
				stubGatewayAddress,
				startTimestamp
			)
			assert.is_false(status)
			assert.match("services contains an invalid key", error)
		end)
		it("should fail to join the network with invalid bundler keys", function()
			local servicesWithInvalidBundler = {
				bundlers = {
					{
						fqdn = "bundler1.example.com",
						port = 443,
						protocol = "https",
						path = "/bundler1",
						invalidKey = "invalid", -- Invalid key in bundler
					},
				},
			}
			local status, error = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				gar.getSettings().operators.minStake,
				testSettings,
				servicesWithInvalidBundler,
				stubGatewayAddress,
				startTimestamp
			)
			assert.is_false(status)
			assert.match("bundler contains an invalid key", error)
		end)
		it("should fail to join the network with too many bundlers", function()
			local servicesWithTooManyBundlers = {
				bundlers = {},
			}
			for i = 1, 21 do -- Exceeding the maximum of 20 bundlers
				table.insert(servicesWithTooManyBundlers.bundlers, {
					fqdn = "bundler" .. i .. ".example.com",
					port = 443,
					protocol = "https",
					path = "/bundler" .. i,
				})
			end

			local status, error = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				gar.getSettings().operators.minStake,
				testSettings,
				servicesWithTooManyBundlers,
				stubGatewayAddress,
				startTimestamp
			)
			assert.is_false(status)
			assert.match("No more than 20 bundlers allowed", error)
		end)
		it("should fail to join the network with invalid bundler fqdn", function()
			local servicesWithInvalidFqdn = {
				bundlers = {
					{
						fqdn = 20, -- Invalid fqdn (a number)
						port = 443,
						protocol = "https",
						path = "/bundler",
					},
				},
			}

			local status, error = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				gar.getSettings().operators.minStake,
				testSettings,
				servicesWithInvalidFqdn,
				stubGatewayAddress,
				startTimestamp
			)
			assert.is_false(status)
			assert.match("bundler.fqdn is required and must be a string", error)
		end)
		it("should fail to join the network with invalid bundler port", function()
			local servicesWithInvalidPort = {
				bundlers = {
					{
						fqdn = "bundler.example.com",
						port = -1, -- Invalid port (negative number)
						protocol = "https",
						path = "/bundler",
					},
				},
			}

			local status, error = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				gar.getSettings().operators.minStake,
				testSettings,
				servicesWithInvalidPort,
				stubGatewayAddress,
				startTimestamp
			)
			assert.is_false(status)
			assert.match("bundler.port must be an integer between 0 and 65535", error)
		end)
		it("should fail to join the network with invalid bundler protocol", function()
			local servicesWithInvalidProtocol = {
				bundlers = {
					{
						fqdn = "bundler.example.com",
						port = 443,
						protocol = "ftp", -- Invalid protocol (should be 'https')
						path = "/bundler",
					},
				},
			}

			local status, error = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				gar.getSettings().operators.minStake,
				testSettings,
				servicesWithInvalidProtocol,
				stubGatewayAddress,
				startTimestamp
			)
			assert.is_false(status)
			assert.match("bundler.protocol is required and must be 'https'", error)
		end)
		it("should fail to join the network with invalid bundler path", function()
			local servicesWithInvalidPath = {
				bundlers = {
					{
						fqdn = "bundler.example.com",
						port = 443,
						protocol = "https",
						path = nil, -- Invalid path (nil value)
					},
				},
			}

			local status, error = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				gar.getSettings().operators.minStake,
				testSettings,
				servicesWithInvalidPath,
				stubGatewayAddress,
				startTimestamp
			)
			assert.is_false(status)
			assert.match("bundler.path is required and must be a string", error)
		end)
	end)

	describe("leaveNetwork", function()
		it("should leave the network", function()
			GatewayRegistry[stubGatewayAddress] = {
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
				observerAddress = stubObserverAddress,
				delegates = {
					[stubRandomAddress] = {
						delegatedStake = gar.getSettings().delegates.minStake,
						startTimestamp = 0,
						vaults = {},
					},
				},
			}

			local status, result = pcall(gar.leaveNetwork, stubGatewayAddress, startTimestamp, stubMessageId)
			assert.is_true(status)
			assert.are.same(result, {
				operatorStake = 0,
				totalDelegatedStake = 0,
				vaults = {
					[stubGatewayAddress] = {
						balance = gar.getSettings().operators.minStake,
						startTimestamp = startTimestamp,
						endTimestamp = gar.getSettings().operators.leaveLengthMs,
					},
					[stubMessageId] = {
						balance = 1000,
						startTimestamp = startTimestamp,
						endTimestamp = gar.getSettings().operators.withdrawLengthMs,
					},
				},
				delegates = {
					[stubRandomAddress] = {
						delegatedStake = 0,
						startTimestamp = 0,
						vaults = {
							[stubMessageId] = {
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
				observerAddress = stubObserverAddress,
			})
		end)
	end)

	describe("increaseOperatorStake", function()
		it("should increase operator stake", function()
			Balances[stubGatewayAddress] = 1000
			GatewayRegistry[stubGatewayAddress] = {
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
				observerAddress = stubObserverAddress,
			}
			local result, err = gar.increaseOperatorStake(stubGatewayAddress, 1000)
			assert.are.equal(Balances[stubGatewayAddress], 0)
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
				observerAddress = stubObserverAddress,
			})
		end)
	end)

	describe("decreaseOperatorStake", function()
		it("should decrease operator stake", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
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
				observerAddress = stubObserverAddress,
			}
			local status, result =
				pcall(gar.decreaseOperatorStake, stubGatewayAddress, 1000, startTimestamp, stubMessageId)
			assert.is_true(status)
			assert.are.same(result, {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = 0,
				vaults = {
					[stubMessageId] = {
						balance = 1000,
						startTimestamp = startTimestamp,
						endTimestamp = startTimestamp + (30 * 24 * 60 * 60 * 1000), -- 30 days
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
				observerAddress = stubObserverAddress,
			})
		end)
		it("should instantly withdraw operator stake with penalty", function()
			Balances[ao.id] = 0 -- Initialize protocol balance to 0
			Balances[stubGatewayAddress] = 0
			local penaltyRate = 0.80
			local penaltyAmount = 1000 * penaltyRate
			local withdrawalAmount = 1000 - penaltyAmount

			_G.GatewayRegistry[stubGatewayAddress] = {
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
				observerAddress = stubObserverAddress,
			}

			local status, result = pcall(
				gar.decreaseOperatorStake,
				stubGatewayAddress,
				1000,
				startTimestamp,
				stubMessageId,
				true -- Instant withdrawal flag
			)

			assert.is_true(status)
			assert.are.same(result.operatorStake, gar.getSettings().operators.minStake)
			assert.are.equal(Balances[stubGatewayAddress], withdrawalAmount) -- The gateway's balance should increase with withdrawal amount
			assert.are.equal(Balances[ao.id], penaltyAmount) -- Penalty amount should be added to protocol balance
		end)

		-- Unhappy path tests

		it("should fail if attempting to withdraw more than max allowed operator stake", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = gar.getSettings().operators.minStake + 500,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
				settings = testSettings,
				status = "joined",
				observerAddress = stubObserverAddress,
			}

			local status, result = pcall(
				gar.decreaseOperatorStake,
				stubGatewayAddress,
				1000, -- Attempting to withdraw more than allowed
				startTimestamp,
				stubMessageId,
				true
			)

			assert.is_false(status)
			assert.matches("Resulting stake is not enough maintain the minimum operator stake", result)
		end)

		it("should fail if gateway does not exist", function()
			local nonexistentGatewayAddress = "nonexistent_gateway"

			local status, result =
				pcall(gar.decreaseOperatorStake, nonexistentGatewayAddress, 1000, startTimestamp, stubMessageId, true)

			assert.is_false(status)
			assert.matches("Gateway does not exist", result)
		end)

		it("should fail if gateway is in 'leaving' status", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = gar.getSettings().operators.minStake + 1000,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
				settings = testSettings,
				status = "leaving",
				observerAddress = stubObserverAddress,
			}

			local status, result =
				pcall(gar.decreaseOperatorStake, stubGatewayAddress, 1000, startTimestamp, stubMessageId, true)

			assert.is_false(status)
			assert.matches("Gateway is leaving the network", result)
		end)
	end)

	describe("instantGatewayWithdrawal", function()
		-- Happy path test: Successful instant withdrawal with maximum penalty
		it("should successfully withdraw instantly with maximum penalty", function()
			-- Setup a valid gateway with a vault to withdraw from
			local from = "gateway_address"
			local vaultId = "vault_1"
			local currentTimestamp = 1000000
			local startTimestamp = 1000000
			local vaultBalance = 1000
			local expectedPenaltyRate = 0.80
			local expectedPenaltyAmount = math.floor(vaultBalance * expectedPenaltyRate)
			local expectedWithdrawalAmount = vaultBalance - expectedPenaltyAmount

			-- Initialize balances
			Balances[ao.id] = 0
			Balances[from] = 0

			_G.GatewayRegistry[from] = {
				operatorStake = 2000,
				vaults = {
					[vaultId] = {
						balance = vaultBalance,
						startTimestamp = startTimestamp,
					},
				},
			}

			-- Attempt to withdraw instantly
			local status, result = pcall(gar.instantGatewayWithdrawal, from, vaultId, currentTimestamp)

			-- Assertions
			assert.is_true(status)
			assert.are.same(result.gateway.vaults[vaultId], nil) -- Vault should be removed after withdrawal
			assert.are.equal(Balances[from], expectedWithdrawalAmount) -- Withdrawal amount should be added to gateway balance
			assert.are.equal(Balances[ao.id], expectedPenaltyAmount) -- Penalty should be added to protocol balance
		end)

		-- Happy path test: Successful instant withdrawal with reduced penalty
		it("should successfully withdraw instantly with reduced penalty after partial time elapsed", function()
			-- Setup a valid gateway with a vault to withdraw from
			local from = "gateway_address"
			local vaultId = "vault_1"
			local startTimestamp = 1000000
			local currentTimestamp = startTimestamp + (gar.getSettings().operators.withdrawLengthMs / 2) -- Halfway through the withdrawal period
			local vaultBalance = 1000
			local maxPenalty = 0.80
			local minPenalty = 0.05
			local expectedPenaltyRate = maxPenalty - ((maxPenalty - minPenalty) * 0.5) -- 50% elapsed time
			local expectedPenaltyAmount = math.floor(vaultBalance * expectedPenaltyRate)
			local expectedWithdrawalAmount = vaultBalance - expectedPenaltyAmount

			-- Initialize balances
			Balances[ao.id] = 0
			Balances[from] = 0

			_G.GatewayRegistry[from] = {
				operatorStake = 2000,
				vaults = {
					[vaultId] = {
						balance = vaultBalance,
						startTimestamp = startTimestamp,
					},
				},
			}

			-- Attempt to withdraw instantly
			local status, result = pcall(gar.instantGatewayWithdrawal, from, vaultId, currentTimestamp)

			-- Assertions
			assert.is_true(status)
			assert.are.same(result.gateway.vaults[vaultId], nil) -- Vault should be removed after withdrawal
			assert.are.equal(Balances[from], expectedWithdrawalAmount) -- Withdrawal amount should be added to gateway balance
			assert.are.equal(Balances[ao.id], expectedPenaltyAmount) -- Penalty should be added to protocol balance
		end)

		-- Unhappy path test: Gateway does not exist
		it("should fail if the gateway does not exist", function()
			local nonexistentGateway = "nonexistent_gateway"
			local vaultId = "vault_1"
			local currentTimestamp = 1000000

			local status, result = pcall(gar.instantGatewayWithdrawal, nonexistentGateway, vaultId, currentTimestamp)

			assert.is_false(status)
			assert.matches("Gateway does not exist", result)
		end)

		-- Unhappy path test: Vault does not exist
		it("should fail if the vault does not exist", function()
			local from = "gateway_address"
			local nonexistentVaultId = "nonexistent_vault"
			local currentTimestamp = 1000000

			_G.GatewayRegistry[from] = {
				operatorStake = 2000,
				vaults = {},
			}

			local status, result = pcall(gar.instantGatewayWithdrawal, from, nonexistentVaultId, currentTimestamp)

			assert.is_false(status)
			assert.matches("Vault does not exist", result)
		end)

		-- Unhappy path test: Withdrawal from leaving gateway
		it("should fail if trying to withdraw from a vault while gateway is leaving", function()
			local from = "gateway_address"
			local vaultId = from -- Special vault ID representing the leaving status
			local currentTimestamp = 1000000

			_G.GatewayRegistry[from] = {
				operatorStake = 2000,
				vaults = {
					[vaultId] = {
						balance = 1000,
						startTimestamp = 1000000,
					},
				},
			}

			local status, result = pcall(gar.instantGatewayWithdrawal, from, vaultId, currentTimestamp)

			assert.is_false(status)
			assert.matches("This gateway is leaving and this vault cannot be instantly withdrawn.", result)
		end)

		-- Unhappy path test: Invalid elapsed time
		it("should fail if elapsed time is negative", function()
			local from = "gateway_address"
			local vaultId = "vault_1"
			local startTimestamp = 1000000
			local currentTimestamp = startTimestamp - 1 -- Negative elapsed time

			_G.GatewayRegistry[from] = {
				operatorStake = 2000,
				vaults = {
					[vaultId] = {
						balance = 1000,
						startTimestamp = startTimestamp,
					},
				},
			}

			local status, result = pcall(gar.instantGatewayWithdrawal, from, vaultId, currentTimestamp)

			assert.is_false(status)
			assert.matches("Invalid elapsed time", result)
		end)
	end)

	describe("updateGatewaySettings", function()
		it("should update gateway settings", function()
			GatewayRegistry[stubGatewayAddress] = {
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
			local newObserverWallet = stubGatewayAddress
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
				stubGatewayAddress,
				updatedSettings,
				nil, -- no additional services on this gateway
				newObserverWallet,
				startTimestamp,
				stubMessageId
			)
			assert.is_true(status)
			assert.are.same(expectation, result)
			assert.are.same(expectation, gar.getGateway(stubGatewayAddress))
		end)

		it("should allow updating gateway services", function()
			GatewayRegistry[stubGatewayAddress] = {
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
				observerAddress = stubObserverAddress,
			}

			local updatedServices = {
				bundlers = {
					{ fqdn = "example.com", port = 80, protocol = "https", path = "/path" },
				},
			}

			local status, result = pcall(
				gar.updateGatewaySettings,
				stubGatewayAddress,
				testSettings,
				updatedServices,
				stubObserverAddress,
				startTimestamp,
				stubMessageId
			)
			assert.is_true(status)
			assert.are.same({
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
				observerAddress = stubObserverAddress,
				services = updatedServices,
			}, result)
		end)

		it("should not allow editing of gateway settings for a gateway that is leaving", function()
			GatewayRegistry[stubGatewayAddress] = {
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
				status = "leaving",
				observerAddress = stubObserverAddress,
			}

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
			local status, err = pcall(
				gar.updateGatewaySettings,
				stubGatewayAddress,
				updatedSettings,
				nil,
				stubObserverAddress,
				startTimestamp,
				stubMessageId
			)
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches("Gateway is leaving the network and cannot be updated", err)
		end)
	end)

	describe("delegateStake", function()
		it("should delegate stake to a gateway", function()
			Balances[stubRandomAddress] = gar.getSettings().delegates.minStake
			GatewayRegistry[stubGatewayAddress] = {
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
				observerAddress = stubObserverAddress,
			}
			local status, result = pcall(
				gar.delegateStake,
				stubRandomAddress,
				stubGatewayAddress,
				gar.getSettings().delegates.minStake,
				startTimestamp
			)
			assert.is_true(status)
			assert.are.equal(Balances[stubRandomAddress], 0)
			assert.are.same(result, {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = gar.getSettings().delegates.minStake,
				vaults = {},
				delegates = {
					[stubRandomAddress] = {
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
				observerAddress = stubObserverAddress,
			})
		end)

		it("should decrease delegated stake", function()
			GatewayRegistry[stubGatewayAddress] = {
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
				observerAddress = stubObserverAddress,
				delegates = {
					[stubRandomAddress] = {
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
					[stubRandomAddress] = {
						delegatedStake = gar.getSettings().delegates.minStake,
						startTimestamp = 0,
						vaults = {
							[stubMessageId] = {
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
				observerAddress = stubObserverAddress,
			}
			local status, result = pcall(
				gar.decreaseDelegateStake,
				stubGatewayAddress,
				stubRandomAddress,
				1000,
				startTimestamp,
				stubMessageId
			)
			assert.is_true(status)
			assert.are.same(expectation, result)
			assert.are.same(expectation, gar.getGateway(stubGatewayAddress))
		end)

		it("should decrease delegated stake with instant withdrawal and apply penalty and remove delegate", function()
			Balances[ao.id] = 0
			local penaltyAmount = 1000 * 0.80
			local withdrawalAmount = 1000 - penaltyAmount
			GatewayRegistry[stubGatewayAddress] = {
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
				observerAddress = stubObserverAddress,
				delegates = {
					[stubRandomAddress] = {
						delegatedStake = gar.getSettings().delegates.minStake + 1000,
						startTimestamp = 0,
						vaults = {},
					},
				},
			}

			local status, result = pcall(
				gar.decreaseDelegateStake,
				stubGatewayAddress,
				stubRandomAddress,
				1000,
				startTimestamp,
				stubMessageId,
				true -- instant withdrawal
			)

			assert.is_true(status)
			assert.are.same(result.delegates[stubRandomAddress].delegatedStake, gar.getSettings().delegates.minStake)
			assert.are.equal(result.totalDelegatedStake, gar.getSettings().delegates.minStake)
			assert.are.equal(withdrawalAmount, Balances[stubRandomAddress])
			assert.are.equal(penaltyAmount, Balances[ao.id])
			assert.are.equal(
				gar.getSettings().delegates.minStake,
				_G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake
			)
		end)

		it(
			"should successfully convert a standard delegate withdraw to instant with maximum penalty and remove delegate",
			function()
				-- Setup a valid gateway with a delegate vault
				local vaultId = "vault_id_1"
				local currentTimestamp = 1000000
				local startTimestamp = 1000000
				local vaultBalance = 1000
				local expectedPenaltyRate = 0.80
				local expectedPenaltyAmount = vaultBalance * expectedPenaltyRate
				local expectedWithdrawalAmount = vaultBalance - expectedPenaltyAmount

				Balances[ao.id] = 0

				_G.GatewayRegistry[stubGatewayAddress] = {
					operatorStake = gar.getSettings().operators.minStake + vaultBalance,
					totalDelegatedStake = 0,
					vaults = {},
					delegates = {
						[stubRandomAddress] = {
							delegatedStake = 0,
							startTimestamp = startTimestamp,
							vaults = {
								[vaultId] = {
									balance = vaultBalance,
									startTimestamp = startTimestamp,
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
					observerAddress = stubObserverAddress,
				}

				local status, result = pcall(
					gar.instantDelegateWithdrawal,
					stubRandomAddress,
					stubGatewayAddress,
					vaultId,
					currentTimestamp
				)

				assert.is_true(status)
				assert.are.equal(nil, result.delegate) -- Delegate should be removed after full withdrawal
				assert.are.equal(0, result.totalDelegatedStake)
				assert.are.equal(expectedWithdrawalAmount, Balances[stubRandomAddress])
				assert.are.equal(expectedPenaltyAmount, Balances[ao.id])
				assert.are.equal(0, _G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake)
			end
		)

		it(
			"should withdraw delegate stake and apply reduced penalty based on elapsed time with remaining vault",
			function()
				-- Setup a valid gateway with a delegate vault
				local vaultId = "vault_id_1"
				local remainingDelegateStakeBalance = 1000
				local startTimestamp = 500000
				local elapsedTime = 15 * 24 * 60 * 60 * 1000 -- Half of 30 days in milliseconds
				local currentTimestamp = startTimestamp + elapsedTime
				local vaultBalance = 1000
				local maxPenalty = 0.80
				local minPenalty = 0.05
				local penaltyRate = maxPenalty
					- ((maxPenalty - minPenalty) * (elapsedTime / gar.getSettings().delegates.withdrawLengthMs))
				local expectedPenaltyAmount = math.floor(vaultBalance * penaltyRate)
				local expectedWithdrawalAmount = vaultBalance - expectedPenaltyAmount
				Balances[ao.id] = 0

				_G.GatewayRegistry[stubGatewayAddress] = {
					operatorStake = gar.getSettings().operators.minStake,
					totalDelegatedStake = remainingDelegateStakeBalance,
					vaults = {},
					delegates = {
						[stubRandomAddress] = {
							delegatedStake = remainingDelegateStakeBalance,
							startTimestamp = startTimestamp,
							vaults = {
								[vaultId] = {
									balance = vaultBalance,
									startTimestamp = startTimestamp,
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
					observerAddress = stubObserverAddress,
				}

				local status, result = pcall(
					gar.instantDelegateWithdrawal,
					stubRandomAddress,
					stubGatewayAddress,
					vaultId,
					currentTimestamp
				)

				assert.is_true(status)
				assert.are.equal(nil, next(result.delegate.vaults)) -- Delegate should have no vaults remaining
				assert.are.equal(remainingDelegateStakeBalance, result.totalDelegatedStake)
				assert.are.equal(expectedWithdrawalAmount, Balances[stubRandomAddress])
				assert.are.equal(expectedPenaltyAmount, Balances[ao.id])
				assert.are.equal(
					remainingDelegateStakeBalance,
					_G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake
				)
			end
		)

		it(
			"should withdraw delegate stake and apply reduced penalty based on more elapsed time and remove delegate",
			function()
				-- Setup a valid gateway with a delegate vault
				local vaultId = "vault_id_1"
				local vaultBalance = 1000
				local startTimestamp = 500000
				local elapsedTime = 29 * 24 * 60 * 60 * 1000 -- Half of 30 days in milliseconds
				local currentTimestamp = startTimestamp + elapsedTime
				local maxPenalty = 0.80
				local minPenalty = 0.05
				local penaltyRate = maxPenalty
					- ((maxPenalty - minPenalty) * (elapsedTime / gar.getSettings().delegates.withdrawLengthMs))
				local expectedPenaltyAmount = math.floor(vaultBalance * penaltyRate)
				local expectedWithdrawalAmount = vaultBalance - expectedPenaltyAmount
				Balances[ao.id] = 0

				_G.GatewayRegistry[stubGatewayAddress] = {
					operatorStake = gar.getSettings().operators.minStake,
					totalDelegatedStake = 0,
					vaults = {},
					delegates = {
						[stubRandomAddress] = {
							delegatedStake = 0,
							startTimestamp = startTimestamp,
							vaults = {
								[vaultId] = {
									balance = vaultBalance,
									startTimestamp = startTimestamp,
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
					observerAddress = stubObserverAddress,
				}

				local status, result = pcall(
					gar.instantDelegateWithdrawal,
					stubRandomAddress,
					stubGatewayAddress,
					vaultId,
					currentTimestamp
				)

				assert.is_true(status)
				assert.are.equal(nil, result.delegate) -- Delegate should be removed after full withdrawal
				assert.are.equal(0, result.totalDelegatedStake)
				assert.are.equal(expectedWithdrawalAmount, Balances[stubRandomAddress])
				assert.are.equal(expectedPenaltyAmount, Balances[ao.id])
				assert.are.equal(0, _G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake)
			end
		)
	end)

	describe("slashOperatorStake", function()
		it("should slash operator stake by the provided slash amount and return it to the protocol balance", function()
			local slashAmount = 10000
			Balances[ao.id] = 0
			GatewayRegistry[stubGatewayAddress] = {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
			}
			local status, err = pcall(gar.slashOperatorStake, stubGatewayAddress, slashAmount)
			assert.is_true(status)
			assert.is_nil(err)
			assert.are.equal(
				gar.getSettings().operators.minStake - slashAmount,
				GatewayRegistry[stubGatewayAddress].operatorStake
			)
			assert.are.equal(slashAmount, Balances[ao.id])
		end)
	end)

	describe("getGatewayWeightsAtTimestamp", function()
		it("shoulud properly compute weights based on gateways for a given timestamp", function()
			GatewayRegistry[stubGatewayAddress] = {
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
				observerAddress = stubObserverAddress,
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
					gatewayAddress = stubGatewayAddress,
					observerAddress = stubObserverAddress,
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
			local status, result = pcall(gar.getGatewayWeightsAtTimestamp, { stubGatewayAddress }, timestamp)
			assert.is_true(status)
			assert.are.same(expectation, result)
		end)
	end)

	describe("pruneGateways", function()
		it(
			"should remove gateways with endTimestamp < currentTimestamp, slash gateways with failedConsecutiveEpochs > 30 and mark them for leaving",
			function()
				local currentTimestamp = 1000000

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
				local status, result = pcall(gar.pruneGateways, currentTimestamp, msgId)
				assert.is_true(status)
				assert.are.same({
					prunedGateways = { "address1" },
					slashedGateways = { "address3" },
				}, result)

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
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress] = {
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
				stubRandomAddress,
				stubGatewayAddress,
				"some-previous-withdrawal-id"
			)
			assert.is_true(status)
			assert.are.same(result, {
				totalDelegatedStake = 1000,
				delegate = {
					delegatedStake = 1000,
					vaults = {},
				},
			})
			-- assert the vault is removed and the delegated stake is added back to the delegate
			assert.are.equal(
				1000, -- added back to the delegate
				GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress].delegatedStake
			)
			assert.are.equal(
				nil,
				GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress].vaults["some-previous-withdrawal-id"]
			)
			assert.are.equal(1000, GatewayRegistry[stubGatewayAddress].totalDelegatedStake)
		end)
		it("should not cancel a withdrawal if the gateway does not allow staking", function()
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].settings.allowDelegatedStaking = false
			_G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress] = {
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
				stubRandomAddress,
				stubGatewayAddress,
				"some-previous-withdrawal-id"
			)
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches("Gateway does not allow staking", err)
			assert.are.same({
				delegatedStake = 0,
				vaults = {
					["some-previous-withdrawal-id"] = {
						balance = 1000,
						startTimestamp = 0,
						endTimestamp = 1000,
					},
				},
			}, _G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress])
		end)
		it("should not cancel a withdrawal if the delegate does not exist", function()
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress] = nil
			_G.GatewayRegistry[stubGatewayAddress].settings.allowDelegatedStaking = true
			local status, err = pcall(
				gar.cancelDelegateWithdrawal,
				stubRandomAddress,
				stubGatewayAddress,
				"some-previous-withdrawal-id"
			)
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches("Delegate does not exist", err)
		end)
		it("should not cancel a withdrawal if the withdrawal does not exist", function()
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress] = {
				delegatedStake = 0,
				vaults = {},
				startTimestamp = 0,
			}
			_G.GatewayRegistry[stubGatewayAddress].settings.allowDelegatedStaking = true
			local status, err = pcall(
				gar.cancelDelegateWithdrawal,
				stubRandomAddress,
				stubGatewayAddress,
				"some-previous-withdrawal-id"
			)
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches("Vault does not exist", err)
		end)
		it("should not cancel a withdrawal if the gateway is leaving", function()
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].settings.allowDelegatedStaking = true
			_G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress] = {
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
			_G.GatewayRegistry[stubGatewayAddress].status = "leaving"
			local status, err = pcall(
				gar.cancelDelegateWithdrawal,
				stubRandomAddress,
				stubGatewayAddress,
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
				[stubGatewayAddress] = {
					startTimestamp = timestamp - 10, -- joined before the timestamp
					status = "joined",
				},
				[stubRandomAddress] = {
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
			assert.are.same({ stubGatewayAddress }, result)
		end)
	end)

	describe("getters", function()
		-- TODO: other tests for error conditions when joining/leaving network
		it("should get single gateway", function()
			GatewayRegistry[stubGatewayAddress] = testGateway
			local result = gar.getGateway(stubGatewayAddress)
			assert.are.same(result, testGateway)
		end)

		it("should get multiple gateways", function()
			GatewayRegistry[stubGatewayAddress] = testGateway
			GatewayRegistry[stubRandomAddress] = testGateway
			local result = gar.getGateways()
			assert.are.same(result, {
				[stubGatewayAddress] = testGateway,
				[stubRandomAddress] = testGateway,
			})
		end)
	end)
end)
