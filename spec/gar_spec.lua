local constants = require("constants")
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
	allowedDelegatesLookup = {
		["test-allowlisted-delegator-address-number-1"] = true,
		["test-allowlisted-delegator-address-number-2"] = true,
	},
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
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
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
			local expectation = testGateway
			local inputSettings = utils.deepCopy(testSettings)
			inputSettings.allowedDelegatesLookup = nil
			inputSettings.allowedDelegates = {
				"test-allowlisted-delegator-address-number-1",
				"test-allowlisted-delegator-address-number-2",
			}
			local status, result = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				gar.getSettings().operators.minStake,
				inputSettings,
				nil, -- no additional services on this gateway
				stubObserverAddress,
				startTimestamp
			)
			assert.is_true(status)
			assert.are.equal(_G.Balances[stubGatewayAddress], 0)
			assert.are.same(expectation, result)
			assert.are.same(expectation, _G.GatewayRegistry[stubGatewayAddress])
		end)
		it("should join the network with services and bundlers", function()
			local expectation = testGateway
			expectation.services = testServices
			local inputSettings = utils.deepCopy(testSettings)
			inputSettings.allowedDelegatesLookup = nil
			inputSettings.allowedDelegates = {
				"test-allowlisted-delegator-address-number-1",
				"test-allowlisted-delegator-address-number-2",
			}
			local status, result = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				gar.getSettings().operators.minStake,
				inputSettings,
				testServices,
				stubObserverAddress,
				startTimestamp
			)
			assert.is_true(status)
			assert.are.equal(_G.Balances[stubGatewayAddress], 0)
			assert.are.same(expectation, result)
			assert.are.same(expectation, _G.GatewayRegistry[stubGatewayAddress])
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
				stubObserverAddress,
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
				stubObserverAddress,
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
				stubObserverAddress,
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
				stubObserverAddress,
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
				stubObserverAddress,
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
				stubObserverAddress,
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
				stubObserverAddress,
				startTimestamp
			)
			assert.is_false(status)
			assert.match("bundler.path is required and must be a string", error)
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
				observerAddress = stubObserverAddress,
			}

			local status, result = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				gar.getSettings().operators.minStake,
				testSettings,
				testServices,
				stubObserverAddress,
				startTimestamp
			)
			assert.is_true(status)
			assert.are.equal(0, _G.Balances[stubGatewayAddress])
			assert.are.same(expectation, result)
			assert.are.same(expectation, _G.GatewayRegistry[stubGatewayAddress])
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
				stubObserverAddress,
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
				stubObserverAddress,
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
				stubObserverAddress,
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
				stubObserverAddress,
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
				stubObserverAddress,
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
				stubObserverAddress,
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
				stubObserverAddress,
				startTimestamp
			)
			assert.is_false(status)
			assert.match("bundler.path is required and must be a string", error)
		end)
	end)

	describe("leaveNetwork", function()
		it("should leave the network", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
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
			local expectedSettings = utils.deepCopy(testSettings)
			expectedSettings.allowedDelegatesLookup = {
				["test-allowlisted-delegator-address-number-1"] = true,
				["test-allowlisted-delegator-address-number-2"] = true,
				[stubRandomAddress] = true,
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
				settings = expectedSettings,
				status = "leaving",
				observerAddress = stubObserverAddress,
			})
		end)
	end)

	describe("increaseOperatorStake", function()
		it("should increase operator stake", function()
			_G.Balances[stubGatewayAddress] = 1000
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
				observerAddress = stubObserverAddress,
			}
			local result = gar.increaseOperatorStake(stubGatewayAddress, 1000)
			assert.are.equal(_G.Balances[stubGatewayAddress], 0)
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
			assert.are.same(result.gateway, {
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
		it("should instantly withdraw operator stake with expedited withdrawal fee", function()
			_G.Balances[ao.id] = 0 -- Initialize protocol balance to 0
			_G.Balances[stubGatewayAddress] = 0
			local expeditedWithdrawalFee = 1000 * constants.MAX_EXPEDITED_WITHDRAWAL_PENALTY_RATE
			local withdrawalAmount = 1000 - expeditedWithdrawalFee

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
			assert.are.same(result.gateway.operatorStake, gar.getSettings().operators.minStake)
			assert.are.same(result.amountWithdrawn, withdrawalAmount)
			assert.are.same(result.expeditedWithdrawalFee, expeditedWithdrawalFee)
			assert.are.equal(_G.Balances[stubGatewayAddress], withdrawalAmount) -- The gateway's balance should increase with withdrawal amount
			assert.are.equal(_G.Balances[ao.id], expeditedWithdrawalFee) -- expedited withdrawal fee amount should be added to protocol balance
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
			assert.matches("Resulting stake is not enough to maintain the minimum operator stake", result)
		end)

		it("should fail if Gateway not found", function()
			local nonexistentGatewayAddress = "nonexistent_gateway"

			local status, result =
				pcall(gar.decreaseOperatorStake, nonexistentGatewayAddress, 1000, startTimestamp, stubMessageId, true)

			assert.is_false(status)
			assert.matches("Gateway not found", result)
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

	describe("updateGatewaySettings", function()
		it("should update gateway settings", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
				stats = testGateway.stats,
				settings = testGateway.settings,
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
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
				startTimestamp = testGateway.startTimestamp,
				stats = testGateway.stats,
				settings = updatedSettings,
				status = testGateway.status,
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
			assert.are.same(expectation, _G.GatewayRegistry[stubGatewayAddress])
		end)

		it("should update delegator allow list settings correctly", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
				stats = testGateway.stats,
				settings = testGateway.settings,
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
			}
			local newObserverWallet = stubGatewayAddress
			local inputUpdatedSettings = {
				fqdn = "example.com",
				port = 80,
				protocol = "https",
				properties = "NdZ3YRwMB2AMwwFYjKn1g88Y9nRybTo0qhS1ORq_E7g",
				note = "This is a test update.",
				label = "Test Label Update",
				autoStake = true,
				allowDelegatedStaking = true,
				allowedDelegates = {
					"test-allowlisted-delegator-address-number-1",
					"test-allowlisted-delegator-address-number-2",
				},
				delegateRewardShareRatio = 15,
				minDelegatedStake = gar.getSettings().delegates.minStake + 5,
			}
			local expectedSettings = utils.deepCopy(inputUpdatedSettings)
			expectedSettings.allowedDelegates = nil
			expectedSettings.allowedDelegatesLookup = {
				["test-allowlisted-delegator-address-number-1"] = true,
				["test-allowlisted-delegator-address-number-2"] = true,
			}
			local expectation = {
				operatorStake = gar.getSettings().operators.minStake,
				observerAddress = newObserverWallet,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = testGateway.startTimestamp,
				stats = testGateway.stats,
				settings = expectedSettings,
				status = testGateway.status,
			}
			local status, result = pcall(
				gar.updateGatewaySettings,
				stubGatewayAddress,
				inputUpdatedSettings,
				nil, -- no additional services on this gateway
				newObserverWallet,
				startTimestamp,
				stubMessageId
			)
			assert.is_true(status)
			assert.are.same(expectation, result)
			assert.are.same(expectation, _G.GatewayRegistry[stubGatewayAddress])
		end)

		it("should allow updating gateway services", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = testGateway.startTimestamp,
				stats = testGateway.stats,
				settings = testGateway.settings,
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
			}

			local updatedServices = {
				bundlers = {
					{ fqdn = "example.com", port = 80, protocol = "https", path = "/path" },
				},
			}

			local status, result = pcall(
				gar.updateGatewaySettings,
				stubGatewayAddress,
				testGateway.settings,
				updatedServices,
				stubObserverAddress,
				testGateway.startTimestamp,
				stubMessageId
			)
			assert.is_true(status)
			assert.are.same({
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = testGateway.startTimestamp,
				stats = testGateway.stats,
				settings = testGateway.settings,
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
				services = updatedServices,
			}, result)
		end)

		it("should not allow editing of gateway settings for a gateway that is leaving", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = testGateway.startTimestamp,
				stats = testGateway.stats,
				settings = testGateway.settings,
				status = "leaving",
				observerAddress = testGateway.observerAddress,
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

		it("should not update gateway settings if the Gateway not found", function()
			local updatedSettings = {
				fqdn = "example.com",
				port = 80,
				protocol = "https",
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
			assert.matches("Gateway not found", err)
		end)
	end)

	describe("delegateStake", function()
		it("should delegate stake to a gateway", function()
			local stakeAmount = 500000000
			_G.Balances[stubRandomAddress] = stakeAmount
			_G.GatewayRegistry[stubGatewayAddress] = utils.deepCopy(testGateway)
			_G.GatewayRegistry[stubGatewayAddress].settings.allowedDelegatesLookup = {
				[stubRandomAddress] = true,
			}
			local result = gar.delegateStake(stubRandomAddress, stubGatewayAddress, stakeAmount, startTimestamp)
			local expectedSettings = utils.deepCopy(testGateway.settings)
			expectedSettings.allowedDelegatesLookup = {}
			assert.are.equal(0, _G.Balances[stubRandomAddress])
			assert.are.same({
				operatorStake = testGateway.operatorStake,
				totalDelegatedStake = stakeAmount,
				vaults = {},
				delegates = {
					[stubRandomAddress] = {
						delegatedStake = gar.getSettings().delegates.minStake,
						startTimestamp = startTimestamp,
						vaults = {},
					},
				},
				startTimestamp = startTimestamp,
				stats = testGateway.stats,
				services = testGateway.services,
				settings = expectedSettings,
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
			}, result)
		end)

		it("should decrease delegated stake if the remaining stake is greater than the minimum stake", function()
			local totalDelegatedStake = 750000000
			local decreaseAmount = 100000000
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake = totalDelegatedStake
			_G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress] = {
				delegatedStake = totalDelegatedStake,
				startTimestamp = 0,
				vaults = {},
			}

			local expectation = {
				operatorStake = testGateway.operatorStake,
				totalDelegatedStake = totalDelegatedStake - decreaseAmount,
				vaults = {},
				delegates = {
					[stubRandomAddress] = {
						delegatedStake = totalDelegatedStake - decreaseAmount,
						startTimestamp = 0,
						vaults = {
							[stubMessageId] = {
								balance = decreaseAmount,
								startTimestamp = startTimestamp,
								endTimestamp = gar.getSettings().delegates.withdrawLengthMs,
							},
						},
					},
				},
				startTimestamp = testGateway.startTimestamp,
				stats = testGateway.stats,
				services = testGateway.services,
				settings = testGateway.settings,
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
			}
			local status, result = pcall(
				gar.decreaseDelegateStake,
				stubGatewayAddress,
				stubRandomAddress,
				decreaseAmount,
				startTimestamp,
				stubMessageId
			)
			assert.is_true(status)
			assert.are.same(expectation, result.gateway)
			assert.are.same(expectation, _G.GatewayRegistry[stubGatewayAddress])
		end)

		it("should decrease delegated stake with instant withdrawal and apply penalty and remove delegate", function()
			_G.Balances[ao.id] = 0
			local expeditedWithdrawalFee = 1000 * 0.50
			local withdrawalAmount = 1000 - expeditedWithdrawalFee
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = gar.getSettings().delegates.minStake + 1000,
				vaults = {},
				startTimestamp = startTimestamp,
				stats = testGateway.stats,
				services = testGateway.services,
				settings = testGateway.settings,
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
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
			assert.are.same(
				result.gateway.delegates[stubRandomAddress].delegatedStake,
				gar.getSettings().delegates.minStake
			)
			assert.are.equal(result.gateway.totalDelegatedStake, gar.getSettings().delegates.minStake)
			assert.are.equal(withdrawalAmount, result.amountWithdrawn)
			assert.are.equal(withdrawalAmount, _G.Balances[stubRandomAddress])
			assert.are.equal(expeditedWithdrawalFee, result.expeditedWithdrawalFee)
			assert.are.equal(expeditedWithdrawalFee, _G.Balances[ao.id])
			assert.are.equal(constants.MAX_EXPEDITED_WITHDRAWAL_PENALTY_RATE, result.penaltyRate)
			assert.are.equal(
				gar.getSettings().delegates.minStake,
				_G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake
			)
		end)

		it("should error if the remaining delegate stake is less than the minimum stake", function()
			local delegatedStake = gar.getSettings().delegates.minStake
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = gar.getSettings().delegates.minStake - 1,
				vaults = {},
				delegates = {
					[stubRandomAddress] = {
						delegatedStake = delegatedStake,
						startTimestamp = startTimestamp,
						vaults = {},
					},
				},
				startTimestamp = testGateway.startTimestamp,
				stats = testGateway.stats,
				services = testGateway.services,
				settings = testGateway.settings,
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
			}

			local status, err = pcall(
				gar.decreaseDelegateStake,
				stubGatewayAddress,
				stubRandomAddress,
				1,
				startTimestamp,
				stubMessageId
			)
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches(
				"Remaining delegated stake must be greater than the minimum delegated stake. Adjust the amount or withdraw all stake.",
				err
			)
		end)
	end)

	describe("instantGatewayWithdrawal", function()
		describe("gateways", function()
			-- gateways
			it("should successfully withdraw instantly with maximum expedited withdrawal fee", function()
				-- Setup a valid gateway with a vault to withdraw from
				local from = "gateway_address"
				local gatewayAddress = from
				local vaultId = "vault_1"
				local currentTimestamp = 1000000
				local vaultBalance = 1000

				-- Initialize balances
				_G.Balances[ao.id] = 0
				_G.Balances[from] = 0

				_G.GatewayRegistry[gatewayAddress] = {
					operatorStake = 2000,
					vaults = {
						[vaultId] = {
							balance = vaultBalance,
							startTimestamp = currentTimestamp,
							endTimestamp = currentTimestamp + gar.getSettings().operators.withdrawLengthMs,
						},
					},
				}

				-- Attempt to withdraw instantly
				local withdrawalResult = gar.instantGatewayWithdrawal(from, gatewayAddress, vaultId, currentTimestamp)

				assert.are.same({
					gateway = _G.GatewayRegistry[gatewayAddress],
					elapsedTime = 0,
					remainingTime = gar.getSettings().operators.withdrawLengthMs, -- the full withdrawal period
					penaltyRate = 0.500, -- 50% penalty rate - the maximum given no time passed
					expeditedWithdrawalFee = 500, -- 50% of 1000
					amountWithdrawn = 500, -- 50% of 1000
				}, withdrawalResult)
				assert.are.same(nil, withdrawalResult.gateway.vaults[vaultId]) -- Vault should be removed after withdrawal
				assert.are.equal(500, _G.Balances[from]) -- 50% of the vault balance
				assert.are.equal(500, _G.Balances[ao.id]) -- 50% of the vault balance
			end)

			-- Happy path test: Successful instant withdrawal with reduced expedited withdrawal fee
			it(
				"should successfully withdraw instantly with reduced expedited withdrawal fee after partial time elapsed",
				function()
					-- Setup a valid gateway with a vault to withdraw from
					local from = "gateway_address"
					local gatewayAddress = from
					local vaultId = "vault_1"
					local vaultTimestamp = 1000000
					local timeElapsed = gar.getSettings().operators.withdrawLengthMs / 2
					local timeRemaining = gar.getSettings().operators.withdrawLengthMs / 2
					local currentTimestamp = vaultTimestamp + timeElapsed -- Halfway through the withdrawal period
					local vaultBalance = 1000

					-- Initialize balances
					_G.Balances[ao.id] = 0
					_G.Balances[from] = 0

					_G.GatewayRegistry[gatewayAddress] = {
						operatorStake = 2000,
						vaults = {
							[vaultId] = {
								balance = vaultBalance,
								startTimestamp = vaultTimestamp,
								endTimestamp = vaultTimestamp + gar.getSettings().operators.withdrawLengthMs,
							},
						},
					}

					-- Attempt to withdraw instantly
					local withdrawalResult =
						gar.instantGatewayWithdrawal(from, gatewayAddress, vaultId, currentTimestamp)

					assert.are.same({
						gateway = _G.GatewayRegistry[gatewayAddress],
						elapsedTime = timeElapsed,
						remainingTime = timeRemaining,
						penaltyRate = 0.300, -- 30% penalty rate due to 50% elapsed time
						expeditedWithdrawalFee = 300, -- 30% of 1000
						amountWithdrawn = 700, -- 70% of 1000
					}, withdrawalResult)
					assert.are.same(nil, withdrawalResult.gateway.vaults[vaultId]) -- Vault should be removed after withdrawal
					assert.are.equal(700, _G.Balances[from]) -- 70% of the vault balance
					assert.are.equal(300, _G.Balances[ao.id]) -- 30% of the vault balance
				end
			)

			-- Unhappy path test: Gateway does not exist
			it("should fail if the Gateway not found", function()
				local from = "nonexistent_gateway"
				local gatewayAddress = from
				local vaultId = "vault_1"
				local currentTimestamp = 1000000

				local status, result =
					pcall(gar.instantGatewayWithdrawal, from, gatewayAddress, vaultId, currentTimestamp)

				assert.is_false(status)
				assert.matches("Gateway not found", result)
			end)

			-- Unhappy path test: vault not found
			it("should fail if the vault does not exist", function()
				local from = "gateway_address"
				local gatewayAddress = from
				local nonexistentVaultId = "nonexistent_vault"
				local currentTimestamp = 1000000

				_G.GatewayRegistry[from] = {
					operatorStake = 2000,
					vaults = {},
				}

				local status, result =
					pcall(gar.instantGatewayWithdrawal, from, gatewayAddress, nonexistentVaultId, currentTimestamp)

				assert.is_false(status)
				assert.matches("Vault not found", result)
			end)

			-- Unhappy path test: Withdrawal from leaving gateway
			it("should fail if trying to withdraw from a vault while gateway is leaving", function()
				local from = "gateway_address"
				local gatewayAddress = from
				local vaultId = from -- Special vault ID representing the leaving status
				local currentTimestamp = 1000000

				_G.GatewayRegistry[from] = {
					operatorStake = 2000,
					status = "leaving",
					vaults = {
						[vaultId] = {
							balance = 1000,
							startTimestamp = 1000000,
							endTimestamp = 1000000 + gar.getSettings().operators.withdrawLengthMs,
						},
					},
				}

				local status, result =
					pcall(gar.instantGatewayWithdrawal, from, gatewayAddress, vaultId, currentTimestamp)

				assert.is_false(status)
				assert.matches("This gateway is leaving and this vault cannot be instantly withdrawn.", result)
			end)

			-- Unhappy path test: Invalid elapsed time
			it("should fail if elapsed time is negative", function()
				local from = "gateway_address"
				local gatewayAddress = from
				local vaultId = "vault_1"
				local vaultTimestamp = 1000000
				local currentTimestamp = vaultTimestamp - 1 -- Negative elapsed time

				_G.GatewayRegistry[from] = {
					operatorStake = 2000,
					vaults = {
						[vaultId] = {
							balance = 1000,
							startTimestamp = vaultTimestamp,
							endTimestamp = vaultTimestamp + gar.getSettings().operators.withdrawLengthMs,
						},
					},
				}

				local status, result =
					pcall(gar.instantGatewayWithdrawal, from, gatewayAddress, vaultId, currentTimestamp)

				assert.is_false(status)
				assert.matches("Invalid elapsed time", result)
			end)
		end)

		describe("delegates", function()
			it(
				"should successfully convert a standard delegate withdraw to instant with maximum expedited withdrawal fee and remove delegate",
				function()
					-- Setup a valid gateway with a delegate vault
					local vaultId = "vault_id_1"
					local currentTimestamp = 1000000
					local delegateStartTimestamp = 1000000
					local vaultTimestamp = delegateStartTimestamp
					local vaultBalance = 1000
					local expectedPenaltyRate = 0.50
					local expectedexpeditedWithdrawalFee = vaultBalance * expectedPenaltyRate
					local expectedWithdrawalAmount = vaultBalance - expectedexpeditedWithdrawalFee

					_G.Balances[ao.id] = 0

					_G.GatewayRegistry[stubGatewayAddress] = {
						operatorStake = gar.getSettings().operators.minStake + vaultBalance,
						totalDelegatedStake = 0,
						vaults = {},
						delegates = {
							[stubRandomAddress] = {
								delegatedStake = 0,
								startTimestamp = delegateStartTimestamp,
								vaults = {
									[vaultId] = {
										balance = vaultBalance,
										startTimestamp = vaultTimestamp,
										endTimestamp = vaultTimestamp + gar.getSettings().delegates.withdrawLengthMs,
									},
								},
							},
						},
						startTimestamp = testGateway.startTimestamp,
						stats = testGateway.stats,
						services = testGateway.services,
						settings = testGateway.settings,
						status = testGateway.status,
						observerAddress = testGateway.observerAddress,
					}

					local withdrawalResult =
						gar.instantGatewayWithdrawal(stubRandomAddress, stubGatewayAddress, vaultId, currentTimestamp)

					assert.are.same({
						gateway = _G.GatewayRegistry[stubGatewayAddress],
						elapsedTime = 0,
						remainingTime = gar.getSettings().delegates.withdrawLengthMs,
						penaltyRate = 0.50,
						expeditedWithdrawalFee = 500,
						amountWithdrawn = 500,
					}, withdrawalResult)
					-- assert the delegate has been removed from the gateway
					assert.are.equal(nil, _G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress])
					assert.are.equal(expectedWithdrawalAmount, _G.Balances[stubRandomAddress])
					assert.are.equal(expectedexpeditedWithdrawalFee, _G.Balances[ao.id])
					assert.are.equal(0, _G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake)
				end
			)

			it(
				"should withdraw delegate stake and apply reduced expedited withdrawal fee based on elapsed time with remaining vault",
				function()
					-- Setup a valid gateway with a delegate vault
					local vaultId = "vault_id_1"
					local remainingDelegateStakeBalance = 1000
					local delegateStartTimestamp = 500000
					local vaultTimestamp = delegateStartTimestamp
					local elapsedTime = 15 * 24 * 60 * 60 * 1000 -- Half of 30 days in milliseconds
					local currentTimestamp = delegateStartTimestamp + elapsedTime
					local vaultBalance = 1000
					local penaltyRate = 0.300
					local expectedExpeditedWithdrawalFee = math.floor(vaultBalance * penaltyRate)
					local expectedWithdrawalAmount = vaultBalance - expectedExpeditedWithdrawalFee
					_G.Balances[ao.id] = 0

					_G.GatewayRegistry[stubGatewayAddress] = {
						operatorStake = gar.getSettings().operators.minStake,
						totalDelegatedStake = remainingDelegateStakeBalance,
						vaults = {},
						delegates = {
							[stubRandomAddress] = {
								delegatedStake = remainingDelegateStakeBalance,
								startTimestamp = delegateStartTimestamp,
								vaults = {
									[vaultId] = {
										balance = vaultBalance,
										startTimestamp = vaultTimestamp,
										endTimestamp = vaultTimestamp + gar.getSettings().delegates.withdrawLengthMs,
									},
								},
							},
						},
						startTimestamp = testGateway.startTimestamp,
						stats = testGateway.stats,
						services = testGateway.services,
						settings = testGateway.settings,
						status = testGateway.status,
						observerAddress = testGateway.observerAddress,
					}

					local withdrawalResult =
						gar.instantGatewayWithdrawal(stubRandomAddress, stubGatewayAddress, vaultId, currentTimestamp)

					assert.are.same({
						gateway = _G.GatewayRegistry[stubGatewayAddress],
						elapsedTime = 1296000000,
						remainingTime = 1296000000,
						penaltyRate = 0.300,
						expeditedWithdrawalFee = 300,
						amountWithdrawn = 700,
					}, withdrawalResult)
					assert.are.equal(expectedWithdrawalAmount, _G.Balances[stubRandomAddress])
					assert.are.equal(expectedExpeditedWithdrawalFee, _G.Balances[ao.id])
					assert.are.equal(
						remainingDelegateStakeBalance,
						_G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake
					)
				end
			)

			it(
				"should withdraw delegate stake and apply near minimum penalty based nearly all required elapsed time and remove delegate",
				function()
					-- Setup a valid gateway with a delegate vault
					local vaultId = "vault_id_1"
					local vaultBalance = 1000
					local delegateStartTimestamp = 500000
					local vaultTimestamp = delegateStartTimestamp
					local elapsedTime = 30 * 24 * 60 * 60 * 1000 - 1 -- 1ms less than 30 days in milliseconds
					local currentTimestamp = delegateStartTimestamp + elapsedTime
					local penaltyRate = constants.MAX_EXPEDITED_WITHDRAWAL_PENALTY_RATE
						- (
							(
								constants.MAX_EXPEDITED_WITHDRAWAL_PENALTY_RATE
								- constants.MIN_EXPEDITED_WITHDRAWAL_PENALTY_RATE
							) * (elapsedTime / gar.getSettings().delegates.withdrawLengthMs)
						)
					local expectedexpeditedWithdrawalFee = math.floor(vaultBalance * penaltyRate)
					local expectedWithdrawalAmount = vaultBalance - expectedexpeditedWithdrawalFee
					_G.Balances[ao.id] = 0

					_G.GatewayRegistry[stubGatewayAddress] = {
						operatorStake = gar.getSettings().operators.minStake,
						totalDelegatedStake = 0,
						vaults = {},
						delegates = {
							[stubRandomAddress] = {
								delegatedStake = 0,
								startTimestamp = delegateStartTimestamp,
								vaults = {
									[vaultId] = {
										balance = vaultBalance,
										startTimestamp = vaultTimestamp,
										endTimestamp = vaultTimestamp + gar.getSettings().delegates.withdrawLengthMs,
									},
								},
							},
						},
						startTimestamp = testGateway.startTimestamp,
						stats = testGateway.stats,
						services = testGateway.services,
						settings = testGateway.settings,
						status = testGateway.status,
						observerAddress = testGateway.observerAddress,
					}

					local withdrawalResult =
						gar.instantGatewayWithdrawal(stubRandomAddress, stubGatewayAddress, vaultId, currentTimestamp)

					assert.are.same({
						gateway = _G.GatewayRegistry[stubGatewayAddress],
						elapsedTime = 2591999999,
						remainingTime = 1,
						penaltyRate = 0.100,
						expeditedWithdrawalFee = 100,
						amountWithdrawn = 900,
					}, withdrawalResult)
					-- Assert the delegate has been removed from the gateway
					assert.are.equal(nil, _G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress])
					assert.are.equal(expectedWithdrawalAmount, _G.Balances[stubRandomAddress])
					assert.are.equal(expectedexpeditedWithdrawalFee, _G.Balances[ao.id])
					assert.are.equal(0, _G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake)
				end
			)

			it("should error if the vault is not found", function()
				local vaultId = "vault_id_1"
				local vaultBalance = 1000
				local delegateStartTimestamp = 500000
				local vaultTimestamp = delegateStartTimestamp
				local currentTimestamp = delegateStartTimestamp + 1000

				_G.GatewayRegistry[stubGatewayAddress] = {
					operatorStake = gar.getSettings().operators.minStake,
					totalDelegatedStake = 0,
					vaults = {},
					delegates = {
						[stubRandomAddress] = {
							delegatedStake = 0,
							startTimestamp = delegateStartTimestamp,
							vaults = {
								[vaultId] = {
									balance = vaultBalance,
									startTimestamp = vaultTimestamp,
									endTimestamp = vaultTimestamp + gar.getSettings().delegates.withdrawLengthMs,
								},
							},
						},
					},
					startTimestamp = testGateway.startTimestamp,
					stats = testGateway.stats,
					services = testGateway.services,
					settings = testGateway.settings,
					status = testGateway.status,
					observerAddress = testGateway.observerAddress,
				}

				local status, err = pcall(
					gar.instantGatewayWithdrawal,
					stubRandomAddress,
					stubGatewayAddress,
					"non-existent-vault-id",
					currentTimestamp
				)
				assert.is_false(status)
				assert.is_not_nil(err)
				assert.matches("Vault not found", err)
			end)

			it("should error if the Gateway not found", function()
				local vaultId = "vault_id_1"
				local currentTimestamp = 1000

				local status, err = pcall(
					gar.instantGatewayWithdrawal,
					stubRandomAddress,
					"non-existent-gateway-address",
					vaultId,
					currentTimestamp
				)
				assert.is_false(status)
				assert.is_not_nil(err)
				assert.matches("Gateway not found", err)
			end)
		end)
	end)

	describe("slashOperatorStake", function()
		it("should slash operator stake by the provided slash amount and return it to the protocol balance", function()
			local slashAmount = 10000
			_G.Balances[ao.id] = 0
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = gar.getSettings().operators.minStake,
				totalDelegatedStake = 123,
				vaults = {},
				delegates = {},
			}
			local currentTimestamp = 123456
			local status, err = pcall(gar.slashOperatorStake, stubGatewayAddress, slashAmount, currentTimestamp)
			assert.is_true(status)
			assert.is_nil(err)
			assert.are.same({
				operatorStake = gar.getSettings().operators.minStake - slashAmount,
				totalDelegatedStake = 123,
				slashings = {
					["123456"] = slashAmount, -- must be stringified timestamp to avoid encoding issues
				},
				vaults = {},
				delegates = {},
			}, _G.GatewayRegistry[stubGatewayAddress])
			assert.are.equal(slashAmount, _G.Balances[ao.id])
		end)
	end)

	describe("getGatewayWeightsAtTimestamp", function()
		it("shoulud properly compute weights based on gateways for a given timestamp", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
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
						totalDelegatedStake = 0,
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
						totalDelegatedStake = 0,
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
						totalDelegatedStake = 0,
						-- Other gateway properties...
					},
				}

				-- Call pruneGateways
				local protocolBalanceBefore = _G.Balances[ao.id] or 0
				local status, result = pcall(gar.pruneGateways, currentTimestamp, msgId)
				assert.is_true(status)
				local expectedSlashedStake = math.floor(gar.getSettings().operators.minStake * 0.2)
				assert.are.same({
					prunedGateways = { "address1" },
					slashedGateways = {
						address3 = expectedSlashedStake,
					},
					stakeSlashed = expectedSlashedStake,
					delegateStakeReturned = 0,
					gatewayStakeReturned = 0,
					delegateStakeWithdrawing = 0,
					gatewayStakeWithdrawing = 40000010000,
				}, result)

				local expectedRemainingStake = math.floor(gar.getSettings().operators.minStake * 0.8) + 10000
				assert.is_nil(_G.GatewayRegistry["address1"]) -- removed
				assert.is_not_nil(_G.GatewayRegistry["address2"]) -- not removed
				assert.is_not_nil(_G.GatewayRegistry["address3"]) -- not removed
				-- Check that gateway 3's operator stake is slashed by 20% and the remaining stake is vaulted
				assert.are.equal("leaving", _G.GatewayRegistry["address3"].status)
				assert.are.equal(0, _G.GatewayRegistry["address3"].operatorStake)
				assert.are.same({
					balance = expectedRemainingStake,
					startTimestamp = currentTimestamp,
					endTimestamp = currentTimestamp + gar.getSettings().operators.leaveLengthMs,
				}, _G.GatewayRegistry["address3"].vaults["address3"])
				assert.are.equal(protocolBalanceBefore + expectedSlashedStake, _G.Balances[ao.id])
			end
		)

		it("should handle empty _G.GatewayRegistry", function()
			local currentTimestamp = 1000000

			-- Set up empty _G.GatewayRegistry
			_G.GatewayRegistry = {}

			-- Call pruneGateways
			gar.pruneGateways(currentTimestamp)

			-- Check results
			local gateways = gar.getGateways()
			assert.equals(0, utils.lengthOfTable(gateways))
		end)
	end)

	describe("cancelGatewayWithdrawal", function()
		it("should cancel a gateway withdrawal", function()
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].vaults["some-previous-withdrawal-id"] = {
				balance = 25000000000,
				startTimestamp = 0,
				endTimestamp = 1000,
			}
			local result =
				gar.cancelGatewayWithdrawal(stubGatewayAddress, stubGatewayAddress, "some-previous-withdrawal-id")
			assert.are.same({
				totalDelegatedStake = testGateway.totalDelegatedStake,
				totalOperatorStake = 75000000000,
				previousTotalDelegatedStake = testGateway.totalDelegatedStake,
				previousOperatorStake = 50000000000,
				gateway = _G.GatewayRegistry[stubGatewayAddress],
				vaultBalance = 25000000000,
			}, result)
			assert.are.equal(nil, _G.GatewayRegistry[stubGatewayAddress].vaults["some-previous-withdrawal-id"])
		end)
		it("should not cancel a gateway withdrawl if the gateway is leaving", function()
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].status = "leaving"
			local status, err = pcall(
				gar.cancelGatewayWithdrawal,
				stubGatewayAddress,
				stubGatewayAddress,
				"some-previous-withdrawal-id"
			)
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches("Gateway is leaving the network and cannot cancel withdrawals.", err)
		end)
		it("should not cancel a gateway withdrawl if the vault id is not found", function()
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].status = "joined"
			local status, err = pcall(
				gar.cancelGatewayWithdrawal,
				stubGatewayAddress,
				stubGatewayAddress,
				"some-non-existent-withdrawal-id"
			)
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches("Vault not found", err)
		end)
		it("should cancel a delegate withdrawal", function()
			_G.GatewayRegistry[stubGatewayAddress] = utils.deepCopy(testGateway)
			_G.GatewayRegistry[stubGatewayAddress].settings.allowedDelegatesLookup = { [stubRandomAddress] = true }
			_G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake = 0
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
			-- do not use pcall so test throws error if it fails
			local result =
				gar.cancelGatewayWithdrawal(stubRandomAddress, stubGatewayAddress, "some-previous-withdrawal-id")
			assert.are.same({
				totalDelegatedStake = 1000,
				totalOperatorStake = 50000000000,
				previousTotalDelegatedStake = 0,
				previousOperatorStake = 50000000000,
				gateway = _G.GatewayRegistry[stubGatewayAddress],
				vaultBalance = 1000,
			}, result)
			-- assert the vault is removed and the delegated stake is added back to the delegate
			assert.are.equal(
				1000, -- added back to the delegate
				_G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress].delegatedStake
			)
			assert.are.equal(
				nil,
				_G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress].vaults["some-previous-withdrawal-id"]
			)
			assert.are.equal(1000, _G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake)
		end)
		it("should not cancel a delegate withdrawal if the gateway does not allow staking", function()
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
			local status, err =
				pcall(gar.cancelGatewayWithdrawal, stubRandomAddress, stubGatewayAddress, "some-previous-withdrawal-id")
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
		it("should not cancel a delegate withdrawal if the delegate is not found", function()
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress] = nil
			_G.GatewayRegistry[stubGatewayAddress].settings.allowDelegatedStaking = true
			local status, err =
				pcall(gar.cancelGatewayWithdrawal, stubRandomAddress, stubGatewayAddress, "some-previous-withdrawal-id")
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches("Delegate not found", err)
		end)
		it("should not cancel a delegate withdrawal if the withdrawal is not found", function()
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress] = {
				delegatedStake = 0,
				vaults = {},
				startTimestamp = 0,
			}
			_G.GatewayRegistry[stubGatewayAddress].settings.allowDelegatedStaking = true
			local status, err =
				pcall(gar.cancelGatewayWithdrawal, stubRandomAddress, stubGatewayAddress, "some-previous-withdrawal-id")
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches("Vault not found", err)
		end)
		it("should not cancel a delegate withdrawal if the gateway is leaving", function()
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
			local status, err =
				pcall(gar.cancelGatewayWithdrawal, stubRandomAddress, stubGatewayAddress, "some-previous-withdrawal-id")
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches("Gateway is leaving the network and cannot cancel withdrawals.", err)
		end)
		it("should not cancel a delegate withdrawal if the gateway is not found", function()
			_G.GatewayRegistry[stubGatewayAddress] = nil
			local status, err =
				pcall(gar.cancelGatewayWithdrawal, stubRandomAddress, stubGatewayAddress, "some-previous-withdrawal-id")
			assert.is_false(status)
			assert.is_not_nil(err)
			assert.matches("Gateway not found", err)
		end)
	end)

	-- describe("getActiveGatewaysBeforeTimestamp", function()
	-- 	it("should return all active gateways before the timestamp", function()
	-- 		local timestamp = 1704092400100
	-- 		_G.GatewayRegistry = {
	-- 			[stubGatewayAddress] = {
	-- 				startTimestamp = timestamp - 1, -- joined before the timestamp
	-- 				status = "joined",
	-- 			},
	-- 			[stubRandomAddress] = {
	-- 				startTimestamp = timestamp, -- joined on the timestamp
	-- 				status = "joined",
	-- 			},
	-- 			["test-this-is-valid-arweave-wallet-address-4"] = {
	-- 				startTimestamp = timestamp + 1,
	-- 				status = "joined",
	-- 			},
	-- 			["test-this-is-valid-arweave-wallet-address-5"] = {
	-- 				startTimestamp = timestamp - 1, -- joined before the timestamp, but leaving
	-- 				endTimestamp = timestamp + 100,
	-- 				status = "leaving",
	-- 			},
	-- 		}
	-- 		local result = gar.getActiveGatewaysBeforeTimestamp(timestamp)
	-- 		-- assert both gateways are returned, in no particular ordering
	-- 		assert.is_true(utils.isSubset(result, {
	-- 			[stubGatewayAddress] = testGateway,
	-- 			[stubRandomAddress] = testGateway,
	-- 		}))
	-- 	end)
	-- end)

	describe("getters", function()
		-- TODO: other tests for error conditions when joining/leaving network
		it("should get single gateway", function()
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			local result = _G.GatewayRegistry[stubGatewayAddress]
			assert.are.same(result, testGateway)
		end)

		it("should get multiple gateways", function()
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubRandomAddress] = testGateway
			local result = gar.getGateways()
			assert.are.same(result, {
				[stubGatewayAddress] = testGateway,
				[stubRandomAddress] = testGateway,
			})
		end)
	end)

	describe("getPaginatedGateways", function()
		it("should return paginated gateways sorted by startTimestamp in ascending order (oldest first)", function()
			local gateway1 = utils.deepCopy(testGateway)
			local gateway2 = utils.deepCopy(testGateway)
			gateway1.startTimestamp = 1000
			gateway2.startTimestamp = 0
			_G.GatewayRegistry = {
				[stubGatewayAddress] = gateway1,
				[stubRandomAddress] = gateway2,
			}
			local gateways = gar.getPaginatedGateways(nil, 1, "startTimestamp", "asc")
			gateway1.gatewayAddress = stubGatewayAddress
			gateway2.gatewayAddress = stubRandomAddress
			assert.are.same({
				limit = 1,
				sortBy = "startTimestamp",
				sortOrder = "asc",
				hasMore = true,
				nextCursor = stubRandomAddress,
				totalItems = 2,
				items = {
					gateway2, -- should be first because it has a lower startTimestamp
				},
			}, gateways)
			-- get the next page
			local nextGateways = gar.getPaginatedGateways(gateways.nextCursor, 1, "startTimestamp", "asc")
			assert.are.same({
				limit = 1,
				sortBy = "startTimestamp",
				sortOrder = "asc",
				hasMore = false,
				nextCursor = nil,
				totalItems = 2,
				items = {
					gateway1,
				},
			}, nextGateways)
		end)
	end)

	describe("isEligibleForArNSDiscount", function()
		it("should return false if gateway is not found", function()
			local result = gar.isEligibleForArNSDiscount(stubRandomAddress)
			assert.is_false(result)
		end)

		it("should return false if gateway weights are not found", function()
			_G.GatewayRegistry[stubRandomAddress] = testGateway
			local result = gar.isEligibleForArNSDiscount(stubRandomAddress)
			assert.is_false(result)
		end)

		it("should return false if tenureWeight is less than 1", function()
			_G.GatewayRegistry[stubRandomAddress] = testGateway
			_G.GatewayRegistry[stubRandomAddress].weights = {
				tenureWeight = 0.5,
				gatewayRewardRatioWeight = 0.85,
			}
			local result = gar.isEligibleForArNSDiscount(stubRandomAddress)
			assert.is_false(result)
		end)

		it("should return false if gatewayPerformanceRatio is less than 0.85", function()
			_G.GatewayRegistry[stubRandomAddress] = testGateway
			_G.GatewayRegistry[stubRandomAddress].weights = {
				tenureWeight = 1,
				gatewayRewardRatioWeight = 0.84,
			}
			local result = gar.isEligibleForArNSDiscount(stubRandomAddress)
			assert.is_false(result)
		end)

		it("should return true if gateway is eligible for ArNS discount", function()
			_G.GatewayRegistry[stubRandomAddress] = testGateway
			_G.GatewayRegistry[stubRandomAddress].weights = {
				tenureWeight = 1,
				gatewayRewardRatioWeight = 0.85,
			}
			_G.GatewayRegistry[stubRandomAddress].status = "joined"
			local result = gar.isEligibleForArNSDiscount(stubRandomAddress)
			assert.is_true(result)
		end)
	end)

	describe("getPaginatedDelegates", function()
		it(
			"should return paginated delegates sorted, by defualt, by startTimestamp in descending order (newest first)",
			function()
				local gateway = utils.deepCopy(testGateway)
				local stubDelegate2Address = stubGatewayAddress
				local delegate1 = {
					delegatedStake = 1,
					startTimestamp = 1000,
					vaults = {},
				}
				local delegate2 = {
					delegatedStake = 2,
					startTimestamp = 2000,
					vaults = {},
				}
				gateway.delegates = {
					[stubRandomAddress] = delegate1,
					[stubDelegate2Address] = delegate2,
				}
				_G.GatewayRegistry = {
					[stubGatewayAddress] = gateway,
				}
				local delegates = gar.getPaginatedDelegates(stubGatewayAddress, nil, 1, "startTimestamp", "desc")
				assert.are.same({
					limit = 1,
					sortBy = "startTimestamp",
					sortOrder = "desc",
					hasMore = true,
					nextCursor = stubDelegate2Address,
					totalItems = 2,
					items = {
						{
							address = stubDelegate2Address,
							delegatedStake = 2,
							startTimestamp = 2000,
							vaults = {},
						}, -- should be first because it has a higher startTimestamp
					},
				}, delegates)
				-- get the next page
				local nextDelegates =
					gar.getPaginatedDelegates(stubGatewayAddress, delegates.nextCursor, 1, "startTimestamp", "desc")
				assert.are.same({
					limit = 1,
					sortBy = "startTimestamp",
					sortOrder = "desc",
					hasMore = false,
					nextCursor = nil,
					totalItems = 2,
					items = {
						{
							address = stubRandomAddress,
							delegatedStake = 1,
							startTimestamp = 1000,
							vaults = {},
						},
					},
				}, nextDelegates)
			end
		)
	end)

	describe("getPaginatedAllowedDelegates", function()
		it("should return paginated allowed delegates sorted, by defualt, by address in descending order", function()
			local gateway = utils.deepCopy(testGateway)
			local delegateAAddress = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
			local delegateBAddress = "BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB"
			local delegateCAddress = "CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC"
			local delegateA = {
				delegatedStake = 1,
				startTimestamp = 1000,
				vaults = {},
			}
			local delegateB = {
				delegatedStake = 0,
				startTimestamp = 1000,
				vaults = {
					["vault_id"] = {
						balance = 1000,
						startTimestamp = 1000,
						endTimestamp = 1000 + gar.getSettings().delegates.withdrawLengthMs,
					},
				},
			}
			gateway.delegates = {
				[delegateAAddress] = delegateA,
				[delegateBAddress] = delegateB, -- Will be excluded since exiting and not in allow list
			}
			gateway.settings.allowedDelegatesLookup = {
				[delegateCAddress] = true,
			}
			_G.GatewayRegistry = {
				[stubGatewayAddress] = gateway,
			}
			local delegates = gar.getPaginatedAllowedDelegates(stubGatewayAddress, nil, 1, "desc")
			assert.are.same({
				limit = 1,
				sortOrder = "desc",
				hasMore = true,
				nextCursor = delegateCAddress,
				totalItems = 2,
				items = {
					[1] = delegateCAddress,
				},
			}, delegates)
			-- get the next page
			local nextDelegates = gar.getPaginatedAllowedDelegates(stubGatewayAddress, delegates.nextCursor, 1, "desc")
			assert.are.same({
				limit = 1,
				sortOrder = "desc",
				hasMore = false,
				nextCursor = nil,
				totalItems = 2,
				items = {
					[1] = delegateAAddress,
				},
			}, nextDelegates)
		end)
	end)

	describe("getFundingPlan", function()
		before_each(function()
			_G.Balances = {}
			_G.GatewayRegistry = {}
		end)

		after_each(function()
			_G.Balances = {}
			_G.GatewayRegistry = {}
		end)

		it("should identify a shortfall when the user has no spending power of any kind", function()
			local fundingPlan = gar.getFundingPlan(stubRandomAddress, 1000, "any")
			assert.are.same({
				address = stubRandomAddress,
				balance = 0,
				stakes = {},
				shortfall = 1000,
			}, fundingPlan)
		end)

		it(
			"should use balance when the user has just enough and preferred source is either 'balance' or 'any'",
			function()
				local expectedBalances = {
					[stubRandomAddress] = 1000,
				}
				local expectedGatewaysRegistry = {
					[stubGatewayAddress] = {
						totalDelegatedStake = 1500,
						vaults = {},
						delegates = {
							[stubRandomAddress] = {
								delegatedStake = 1500, -- none of this should be touched
								vaults = {
									["vault_id_1"] = {
										balance = 1000, -- none of this should be touched
										startTimestamp = 0,
										endTimestamp = 1001,
									},
								},
							},
						},
						settings = {
							minDelegatedStake = 500,
						},
						stats = {
							passedEpochCount = 0,
							totalEpochCount = 0,
						},
					},
				}
				_G.Balances = expectedBalances
				_G.GatewayRegistry = expectedGatewaysRegistry
				assert.are.same({
					address = stubRandomAddress,
					balance = 1000,
					stakes = {},
					shortfall = 0,
				}, gar.getFundingPlan(stubRandomAddress, 1000, "any"))
				assert.are.same({
					address = stubRandomAddress,
					balance = 1000,
					stakes = {},
					shortfall = 0,
				}, gar.getFundingPlan(stubRandomAddress, 1000, "balance"))
				assert.are.same(expectedBalances, _G.Balances)
				assert.are.same(expectedGatewaysRegistry, _G.GatewayRegistry)
			end
		)

		it("should have a shortfall when holding balance but no stakes and funding source is 'stakes'", function()
			local expectedBalances = {
				[stubRandomAddress] = 1000,
			}
			local expectedGatewaysRegistry = {}
			_G.Balances[stubRandomAddress] = 1000
			assert.are.same({
				address = stubRandomAddress,
				balance = 0,
				stakes = {},
				shortfall = 1000,
			}, gar.getFundingPlan(stubRandomAddress, 1000, "stakes"))
			assert.are.same(expectedBalances, _G.Balances)
			assert.are.same(expectedGatewaysRegistry, _G.GatewayRegistry)
		end)

		it(
			"should use vaulted stake withdrawals from multiple gateways when no excess stake is available and whether or not holding balance and funding source is 'stakes'",
			function()
				-- TO TEST:
				-- Withdraw balances are used after balances, ordered from nearest-to-liquid to furthest from liquid.
				-- tie broken here by smallest to largest to help the contract save memory when pruning expended vaults
				local expectedGatewaysRegistry = {
					[stubGatewayAddress] = {
						totalDelegatedStake = 1000, -- irrelevant in this case
						vaults = {},
						delegates = {
							[stubRandomAddress] = {
								delegatedStake = 50, -- at the minimum so won't be used
								vaults = {
									["vault_id_1"] = {
										balance = 1000, -- enough to satisfy the whole purchase but ordered lower for drawdown
										startTimestamp = 0,
										endTimestamp = 1001, -- later end timestamp
									},
								},
							},
						},
						settings = {
							minDelegatedStake = 50,
						},
						stats = {
							passedEpochCount = 0,
							totalEpochCount = 0,
						},
					},
					[stubObserverAddress] = {
						totalDelegatedStake = 1000, -- irrelevant in this case
						vaults = {},
						delegates = {
							[stubRandomAddress] = {
								delegatedStake = 700, -- also minimum but otherwise irrelevant
								vaults = {
									["vault_id_2"] = {
										balance = 250, -- should draw down first
										startTimestamp = 0,
										endTimestamp = 1000, -- earlier end timestamp
									},
								},
							},
						},
						settings = {
							minDelegatedStake = 700,
						},
						stats = {
							passedEpochCount = 0,
							totalEpochCount = 0,
						},
					},
				}
				_G.GatewayRegistry = expectedGatewaysRegistry

				for _, balance in pairs({ 0, 1000 }) do
					local expectedBalances = {
						[stubRandomAddress] = balance,
					}
					_G.Balances = expectedBalances
					assert.are.same({
						address = stubRandomAddress,
						balance = 0,
						stakes = {
							[stubGatewayAddress] = {
								delegatedStake = 0,
								vaults = {
									["vault_id_1"] = 750, -- partial drawdown (750 of 1000)
								},
							},
							[stubObserverAddress] = {
								delegatedStake = 0,
								vaults = {
									["vault_id_2"] = 250, -- whole vault
								},
							},
						},
						shortfall = 0,
					}, gar.getFundingPlan(stubRandomAddress, 1000, "stakes"))
					assert.are.same(expectedBalances, _G.Balances)
					assert.are.same(expectedGatewaysRegistry, _G.GatewayRegistry)
				end
			end
		)

		it(
			"should use excess stake from a single gateway after withdraw vaults and whether or not holding balance when funding source is 'stakes'",
			function()
				local expectedGatewaysRegistry = {
					[stubGatewayAddress] = {
						totalDelegatedStake = 1500,
						vaults = {},
						delegates = {
							[stubRandomAddress] = {
								delegatedStake = 1500,
								vaults = {
									vault_1 = {
										balance = 100,
										startTimestamp = 0,
										endTimestamp = 1001,
									},
								},
							},
						},
						settings = {
							minDelegatedStake = 500,
						},
						stats = {
							passedEpochCount = 0,
							totalEpochCount = 0,
						},
					},
				}
				_G.GatewayRegistry = expectedGatewaysRegistry

				for _, balance in pairs({ 0, 10000 }) do
					local expectedBalances = {
						[stubRandomAddress] = balance,
					}
					_G.Balances = expectedBalances
					assert.are.same({
						address = stubRandomAddress,
						balance = 0,
						stakes = {
							[stubGatewayAddress] = {
								delegatedStake = 900,
								vaults = {
									vault_1 = 100,
								},
							},
						},
						shortfall = 0,
					}, gar.getFundingPlan(stubRandomAddress, 1000, "stakes"))
					assert.are.same(expectedBalances, _G.Balances)
					assert.are.same(expectedGatewaysRegistry, _G.GatewayRegistry)
				end
			end
		)

		it(
			"should use excess stake from multiple gateways after withdraw vaults and whether or not holding balance when funding source is 'stakes'",
			function()
				-- TO TEST:
				-- Excess stakes above the minimum are used after withdraw vaults, ordered from largest excess over each gateways’ proposed minimum to smallest.
				-- Tie broken here by ordering from worst performing gateway to best
				-- Next tie breaker is highest total gateway stake to lowest (hurst the biggest and baddest gateway first)
				-- Final tie breaker is gateway tenure
				local expectedGatewaysRegistry = {
					[stubGatewayAddress] = {
						totalDelegatedStake = 1000,
						vaults = {},
						delegates = {
							[stubRandomAddress] = {
								delegatedStake = 800, -- 750 over minimum, but lower total delegated stake
								vaults = {},
							},
						},
						settings = {
							minDelegatedStake = 50,
						},
						stats = {
							passedEpochCount = 0,
							totalEpochCount = 0,
						},
					},
					[stubObserverAddress] = {
						totalDelegatedStake = 1000,
						vaults = {},
						delegates = {
							[stubRandomAddress] = {
								delegatedStake = 1000, -- 300 over minimum, but higher total delegated stake
								vaults = {
									vault_1 = {
										balance = 100, -- This will be drawn down before any excess stakes
										startTimestamp = 0,
										endTimestamp = 1000,
									},
								},
							},
						},
						settings = {
							minDelegatedStake = 700,
						},
						stats = {
							passedEpochCount = 0,
							totalEpochCount = 0,
						},
					},
				}
				_G.GatewayRegistry = expectedGatewaysRegistry
				for _, balance in pairs({ 0, 10000 }) do
					local expectedBalances = {
						[stubRandomAddress] = balance,
					}
					_G.Balances = expectedBalances

					assert.are.same({
						address = stubRandomAddress,
						balance = 0,
						stakes = {
							[stubGatewayAddress] = {
								delegatedStake = 750,
								vaults = {},
							},
							[stubObserverAddress] = {
								delegatedStake = 150, -- not using all available excess stake because ranked lower in ordering
								vaults = {
									vault_1 = 100,
								},
							},
						},
						shortfall = 0,
					}, gar.getFundingPlan(stubRandomAddress, 1000, "stakes"))
					assert.are.same(expectedBalances, _G.Balances)
					assert.are.same(expectedGatewaysRegistry, _G.GatewayRegistry)
				end
			end
		)

		it(
			"should use minimum stakes from multiple gateways if needed and funding source is 'any' or 'stakes'",
			function()
				-- TO TEST:
				-- Minimum stakes are used next ordered from:
				-- worst performing gateway to best performing gateway
				-- Next tie breaker is highest total gateway stake to lowest (hurst the biggest and baddest gateway first)
				-- Final tie breaker is gateway tenure
				local expectedGatewaysRegistry = {
					[stubGatewayAddress] = {
						totalDelegatedStake = 2,
						vaults = {},
						delegates = {
							[stubRandomAddress] = {
								delegatedStake = 2,
								vaults = {
									["vault_id_1"] = {
										balance = 1,
										startTimestamp = 0,
										endTimestamp = 1001, -- later end timestamp
									},
								},
							},
						},
						settings = {
							minDelegatedStake = 1,
						},
						stats = {
							passedEpochCount = 1,
							totalEpochCount = 5,
						},
					},
					[stubObserverAddress] = {
						totalDelegatedStake = 3,
						vaults = {},
						delegates = {
							[stubRandomAddress] = {
								delegatedStake = 3,
								vaults = {
									["vault_id_2"] = {
										balance = 1,
										startTimestamp = 0,
										endTimestamp = 1000, -- earlier end timestamp
									},
								},
							},
						},
						settings = {
							minDelegatedStake = 1,
						},
						stats = {
							passedEpochCount = 1,
							totalEpochCount = 3,
						},
					},
				}
				_G.GatewayRegistry = expectedGatewaysRegistry

				for _, fundingPreference in pairs({ "any", "stakes" }) do
					for _, balance in pairs({ 0, 10 }) do
						local expectedBalances = {
							[stubRandomAddress] = balance,
						}
						_G.Balances = expectedBalances
						assert.are.same({
							address = stubRandomAddress,
							balance = fundingPreference == "any" and balance or 0,
							stakes = {
								[stubGatewayAddress] = {
									delegatedStake = 2,
									vaults = {
										["vault_id_1"] = 1,
									},
								},
								[stubObserverAddress] = {
									delegatedStake = 3,
									vaults = {
										["vault_id_2"] = 1,
									},
								},
							},
							shortfall = 993 - (fundingPreference == "any" and balance or 0),
						}, gar.getFundingPlan(stubRandomAddress, 1000, fundingPreference))
						assert.are.same(expectedBalances, _G.Balances)
						assert.are.same(expectedGatewaysRegistry, _G.GatewayRegistry)
					end
				end
			end
		)
	end)

	describe("applyFundingPlan", function()
		it("should apply the funding plan and return the applied plan and total spent", function()
			_G.Balances = {
				["test-address-1"] = 100, -- all of this will get drawn down
			}
			_G.GatewayRegistry["gateway-1"] = {
				totalDelegatedStake = 51, -- 50 of this will get drawn down
				vaults = {},
				delegates = {
					["test-address-1"] = {
						delegatedStake = 51, -- 50 of this will get drawn down
						vaults = {
							["vault-1"] = {
								balance = 20, -- 10 of this will get drawn down
								startTimestamp = 0,
								endTimestamp = 1000,
							},
							["vault-2"] = {
								balance = 10, -- all of this will get drawn down
								startTimestamp = 0,
								endTimestamp = 998,
							},
						},
					},
				},
				settings = {
					minDelegatedStake = 1,
				},
				stats = {
					passedEpochCount = 1,
					totalEpochCount = 3,
				},
			}
			_G.GatewayRegistry["gateway-2"] = {
				totalDelegatedStake = 41, -- 40 of this will get drawn down
				vaults = {},
				delegates = {
					["test-address-1"] = {
						delegatedStake = 41, -- 40 of this will get drawn down, with the last mIO forced to a withdraw vault
						vaults = {
							["vault-3"] = {
								balance = 10, -- this will not be drawn down
								startTimestamp = 0,
								endTimestamp = 999,
							},
						},
					},
				},
				settings = {
					minDelegatedStake = 2,
				},
				stats = {
					passedEpochCount = 1,
					totalEpochCount = 3,
				},
			}
			local fundingPlan = {
				address = "test-address-1",
				balance = 100,
				stakes = {
					["gateway-1"] = {
						delegatedStake = 50,
						vaults = {
							["vault-1"] = 10,
							["vault-2"] = 10,
						},
					},
					["gateway-2"] = {
						delegatedStake = 40,
						vaults = {},
					},
				},
			}
			local result = gar.applyFundingPlan(fundingPlan, "stub-msg-id", 12345)
			assert.are.same({
				totalFunded = 210,
				newWithdrawVaults = {
					["gateway-2"] = {
						["stub-msg-id"] = {
							balance = 1,
							startTimestamp = 12345,
							endTimestamp = 12345 + gar.getSettings().delegates.withdrawLengthMs,
						},
					},
				},
			}, result)
			assert.equals(0, _G.Balances["test-address-1"])
			assert.are.same({
				totalDelegatedStake = 1,
				vaults = {},
				delegates = {
					["test-address-1"] = {
						delegatedStake = 1,
						vaults = {
							-- drawn down
							["vault-1"] = {
								balance = 10,
								startTimestamp = 0,
								endTimestamp = 1000,
							},
						},
					},
				},
				settings = {
					minDelegatedStake = 1,
				},
				stats = {
					passedEpochCount = 1,
					totalEpochCount = 3,
				},
			}, _G.GatewayRegistry["gateway-1"])
			assert.are.same({
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {
					["test-address-1"] = {
						delegatedStake = 0,
						vaults = {
							-- untouched
							["vault-3"] = {
								balance = 10,
								startTimestamp = 0,
								endTimestamp = 999,
							},
							["stub-msg-id"] = {
								balance = 1,
								startTimestamp = 12345,
								endTimestamp = 12345 + gar.getSettings().delegates.withdrawLengthMs,
							},
						},
					},
				},
				settings = {
					minDelegatedStake = 2,
				},
				stats = {
					passedEpochCount = 1,
					totalEpochCount = 3,
				},
			}, _G.GatewayRegistry["gateway-2"])
		end)
	end)

	describe("getPaginatedDelegations", function()
		local gateway1 = utils.deepCopy(testGateway)
		local gateway2 = utils.deepCopy(testGateway)
		gateway1.delegates = {
			["test-user"] = {
				delegatedStake = 1,
				startTimestamp = 2,
				vaults = {
					["vault_id_1"] = {
						balance = 1000,
						startTimestamp = 4,
						endTimestamp = 1000,
					},
				},
			},
			["other-address"] = {
				delegatedStake = 2,
				startTimestamp = 100,
				vaults = {
					["vault_id_2"] = {
						balance = 2000,
						startTimestamp = 103,
						endTimestamp = 1001,
					},
				},
			},
		}
		gateway2.delegates = {
			["test-user"] = {
				delegatedStake = 3,
				startTimestamp = 0,
				vaults = {
					["vault_id_3"] = {
						balance = 3000,
						startTimestamp = 1,
						endTimestamp = 1002,
					},
				},
			},
		}
		local expectedStakeA = {
			type = "stake",
			gatewayAddress = stubRandomAddress,
			balance = 3,
			startTimestamp = 0,
			delegationId = stubRandomAddress .. "_0",
		}
		local expectedStakeB = {
			type = "vault",
			vaultId = "vault_id_3",
			gatewayAddress = stubRandomAddress,
			balance = 3000,
			startTimestamp = 1,
			endTimestamp = 1002,
			delegationId = stubRandomAddress .. "_1",
		}
		local expectedStakeC = {
			type = "stake",
			gatewayAddress = stubGatewayAddress,
			balance = 1,
			startTimestamp = 2,
			delegationId = stubGatewayAddress .. "_2",
		}
		local expectedStakeD = {
			type = "vault",
			vaultId = "vault_id_1",
			gatewayAddress = stubGatewayAddress,
			balance = 1000,
			startTimestamp = 4,
			endTimestamp = 1000,
			delegationId = stubGatewayAddress .. "_4",
		}

		before_each(function()
			_G.GatewayRegistry = {
				[stubGatewayAddress] = gateway1,
				[stubRandomAddress] = gateway2,
			}
		end)

		it(
			"should return paginated delegatations of stakes and vaults sorted by startTimestamp in ascending order (oldest first)",
			function()
				local delegations = gar.getPaginatedDelegations("test-user", nil, 3, "startTimestamp", "asc")
				assert.are.same({
					limit = 3,
					sortBy = "startTimestamp",
					sortOrder = "asc",
					hasMore = true,
					nextCursor = stubGatewayAddress .. "_2",
					totalItems = 4,
					items = {
						[1] = expectedStakeA,
						[2] = expectedStakeB,
						[3] = expectedStakeC,
					},
				}, delegations)
				-- get the next page
				local nextDelegations =
					gar.getPaginatedDelegations("test-user", delegations.nextCursor, 3, "startTimestamp", "asc")
				assert.are.same({
					limit = 3,
					sortBy = "startTimestamp",
					sortOrder = "asc",
					hasMore = false,
					nextCursor = nil,
					totalItems = 4,
					items = {
						[1] = expectedStakeD,
					},
				}, nextDelegations)
				--
			end
		)

		it(
			"should return paginated delegatations of stakes and vaults sorted by balance in descending order",
			function()
				local delegations = gar.getPaginatedDelegations("test-user", nil, 3, "balance", "desc")
				assert.are.same({
					limit = 3,
					sortBy = "balance",
					sortOrder = "desc",
					hasMore = true,
					nextCursor = stubRandomAddress .. "_0",
					totalItems = 4,
					items = {
						[1] = expectedStakeB,
						[2] = expectedStakeD,
						[3] = expectedStakeA,
					},
				}, delegations)
				-- get the next page
				local nextDelegations =
					gar.getPaginatedDelegations("test-user", delegations.nextCursor, 3, "balance", "desc")
				assert.are.same({
					limit = 3,
					sortBy = "balance",
					sortOrder = "desc",
					hasMore = false,
					nextCursor = nil,
					totalItems = 4,
					items = {
						[1] = expectedStakeC,
					},
				}, nextDelegations)
				--
			end
		)
	end)
end)
