local gar = require("gar")
local utils = require("utils")

local startTimestamp = 0
local stubGatewayAddress = "test-this-is-valid-arweave-wallet-address-1"
local stubObserverAddress = "test-this-is-valid-arweave-wallet-address-2"
local stubRandomAddress = "test-this-is-valid-arweave-wallet-address-3"
local stubMessageId = "stub-message-id"
local minDelegatedStake = 10000000 -- 10 ARIO
local minOperatorStake = 10000000000 -- 10,000 ARIO
local operatorLeaveLengthMs = 90 * 24 * 60 * 60 * 1000 -- 90 days
local delegateLeaveLengthMs = 90 * 24 * 60 * 60 * 1000 -- 90 days
local minimumTenureWeightForDiscount = 1
local minimumPerformanceRateForDiscount = 0.90
local testSettings = {
	fqdn = "test.com",
	protocol = "https",
	port = 443,
	allowDelegatedStaking = true,
	minDelegatedStake = minDelegatedStake,
	autoStake = true,
	label = "test",
	note = "",
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
	operatorStake = minOperatorStake,
	totalDelegatedStake = 0,
	vaults = {},
	delegates = {},
	startTimestamp = 0,
	weights = {
		stakeWeight = 0,
		tenureWeight = 0,
		gatewayPerformanceRatio = 0,
		observerPerformanceRatio = 0,
		compositeWeight = 0,
		normalizedCompositeWeight = 0,
	},
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
			[stubGatewayAddress] = minOperatorStake,
		}
		_G.Epochs = {}
		_G.GatewayRegistry = {}
		_G.Redelegations = {}
	end)

	describe("joinNetwork", function()
		it("should fail if the gateway is already in the network", function()
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			local status, error = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				minOperatorStake,
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
				minOperatorStake,
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
				minOperatorStake,
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
				minOperatorStake,
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
				minOperatorStake,
				testSettings,
				servicesWithInvalidBundler,
				stubObserverAddress,
				startTimestamp
			)
			assert.is_false(status)
			assert.match("bundler contains an invalid key", error)
		end)

		it("should fail to join the network if delegateRewardShareRatio is over the maximum", function()
			local settings = utils.deepCopy(testSettings)
			settings.delegateRewardShareRatio = 96
			local status, error = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				minOperatorStake,
				settings,
				nil,
				stubObserverAddress,
				startTimestamp
			)
			assert.is_false(status)
			assert.match("delegateRewardShareRatio must be an integer between 0 and 95", error)
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
				minOperatorStake,
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
				minOperatorStake,
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
				minOperatorStake,
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
				minOperatorStake,
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
				minOperatorStake,
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
				operatorStake = minOperatorStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
				stats = testGateway.stats,
				settings = {
					allowDelegatedStaking = testSettings.allowDelegatedStaking,
					delegateRewardShareRatio = testSettings.delegateRewardShareRatio,
					autoStake = testSettings.autoStake,
					minDelegatedStake = testSettings.minDelegatedStake,
					label = testSettings.label,
					fqdn = testSettings.fqdn,
					protocol = testSettings.protocol,
					port = testSettings.port,
					note = testSettings.note,
					properties = testSettings.properties,
				},
				services = testServices,
				status = "joined",
				observerAddress = stubObserverAddress,
				weights = testGateway.weights,
			}

			local status, result = pcall(
				gar.joinNetwork,
				stubGatewayAddress,
				minOperatorStake,
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
				minOperatorStake,
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
				minOperatorStake,
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
				minOperatorStake,
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
				minOperatorStake,
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
				minOperatorStake,
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
				minOperatorStake,
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
				minOperatorStake,
				testSettings,
				servicesWithInvalidPath,
				stubObserverAddress,
				startTimestamp
			)
			assert.is_false(status)
			assert.match("bundler.path is required and must be a string", error)
		end)
		it("should set defaults for non provided settings", function()
			local minimalSettings = {
				fqdn = "test.com",
				label = "test",
				properties = stubGatewayAddress,
			}

			local result = gar.joinNetwork(
				stubGatewayAddress,
				minOperatorStake,
				minimalSettings,
				nil,
				stubGatewayAddress,
				startTimestamp
			)
			assert.is_not_nil(result)
			assert.are.same({
				allowDelegatedStaking = false,
				delegateRewardShareRatio = 0,
				autoStake = true,
				minDelegatedStake = gar.getSettings().delegates.minStake,
				label = "test",
				fqdn = "test.com",
				protocol = "https",
				note = "",
				port = 443,
				properties = stubGatewayAddress,
			}, _G.GatewayRegistry[stubGatewayAddress].settings)
		end)
	end)

	describe("leaveNetwork", function()
		it("should leave the network", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = (minOperatorStake + 1000),
				totalDelegatedStake = minDelegatedStake,
				vaults = {},
				startTimestamp = startTimestamp,
				stats = testGateway.stats,
				settings = testSettings,
				status = "joined",
				observerAddress = stubObserverAddress,
				delegates = {
					[stubRandomAddress] = {
						delegatedStake = minDelegatedStake,
						startTimestamp = 0,
						vaults = {},
					},
				},
				weights = testGateway.weights,
			}
			local expectedSettings = utils.deepCopy(testSettings)
			expectedSettings.allowedDelegatesLookup = {
				["test-allowlisted-delegator-address-number-1"] = true,
				["test-allowlisted-delegator-address-number-2"] = true,
			}

			local status, result = pcall(gar.leaveNetwork, stubGatewayAddress, startTimestamp, stubMessageId)
			assert.is_true(status)
			assert.are.same(result, {
				operatorStake = 0,
				totalDelegatedStake = 0,
				vaults = {
					[stubGatewayAddress] = {
						balance = minOperatorStake,
						startTimestamp = startTimestamp,
						endTimestamp = operatorLeaveLengthMs,
					},
					[stubMessageId] = {
						balance = 1000,
						startTimestamp = startTimestamp,
						endTimestamp = operatorLeaveLengthMs,
					},
				},
				delegates = {
					[stubRandomAddress] = {
						delegatedStake = 0,
						startTimestamp = 0,
						vaults = {
							[stubMessageId] = {
								balance = minDelegatedStake,
								startTimestamp = startTimestamp,
								endTimestamp = delegateLeaveLengthMs,
							},
						},
					},
				},
				startTimestamp = startTimestamp,
				endTimestamp = operatorLeaveLengthMs,
				stats = testGateway.stats,
				settings = expectedSettings,
				status = "leaving",
				observerAddress = stubObserverAddress,
				weights = testGateway.weights,
			})
		end)
	end)

	describe("increaseOperatorStake", function()
		it("should increase operator stake", function()
			_G.Balances[stubGatewayAddress] = 1000
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = minOperatorStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
				stats = testGateway.stats,
				settings = testSettings,
				status = "joined",
				observerAddress = stubObserverAddress,
				weights = testGateway.weights,
			}
			local result = gar.increaseOperatorStake(stubGatewayAddress, 1000)
			assert.are.equal(_G.Balances[stubGatewayAddress], 0)
			assert.are.same(result, {
				operatorStake = minOperatorStake + 1000,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
				stats = testGateway.stats,
				settings = testSettings,
				status = "joined",
				observerAddress = stubObserverAddress,
				weights = testGateway.weights,
			})
		end)
	end)

	describe("decreaseOperatorStake", function()
		it("should decrease operator stake", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = minOperatorStake + 1000,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
				stats = testGateway.stats,
				settings = testSettings,
				status = "joined",
				observerAddress = stubObserverAddress,
				weights = testGateway.weights,
			}
			local status, result =
				pcall(gar.decreaseOperatorStake, stubGatewayAddress, 1000, startTimestamp, stubMessageId)
			assert.is_true(status)
			assert.are.same(result.gateway, {
				operatorStake = minOperatorStake,
				totalDelegatedStake = 0,
				vaults = {
					[stubMessageId] = {
						balance = 1000,
						startTimestamp = startTimestamp,
						endTimestamp = startTimestamp + (90 * 24 * 60 * 60 * 1000), -- 90 days
					},
				},
				delegates = {},
				startTimestamp = startTimestamp,
				stats = testGateway.stats,
				settings = testSettings,
				status = "joined",
				observerAddress = stubObserverAddress,
				weights = testGateway.weights,
			})
		end)
		it("should instantly withdraw operator stake with expedited withdrawal fee", function()
			_G.Balances[ao.id] = 0 -- Initialize protocol balance to 0
			_G.Balances[stubGatewayAddress] = 0
			local expeditedWithdrawalFee = 1000 * 0.5
			local withdrawalAmount = 1000 - expeditedWithdrawalFee

			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = minOperatorStake + 1000,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
				stats = testGateway.stats,
				settings = testSettings,
				status = "joined",
				observerAddress = stubObserverAddress,
				weights = testGateway.weights,
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
			assert.are.same(result.gateway.operatorStake, minOperatorStake)
			assert.are.same(result.amountWithdrawn, withdrawalAmount)
			assert.are.same(result.expeditedWithdrawalFee, expeditedWithdrawalFee)
			assert.are.equal(_G.Balances[stubGatewayAddress], withdrawalAmount) -- The gateway's balance should increase with withdrawal amount
			assert.are.equal(_G.Balances[ao.id], expeditedWithdrawalFee) -- expedited withdrawal fee amount should be added to protocol balance
		end)

		-- Unhappy path tests

		it("should fail if attempting to withdraw more than max allowed operator stake", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = minOperatorStake + 500,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
				settings = testSettings,
				status = "joined",
				observerAddress = stubObserverAddress,
				weights = testGateway.weights,
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
			assert.matches(
				"Resulting stake of 9999999500 mARIO is not enough to maintain the minimum operator stake",
				result
			)
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
				operatorStake = minOperatorStake + 1000,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
				settings = testSettings,
				status = "leaving",
				observerAddress = stubObserverAddress,
				weights = testGateway.weights,
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
				operatorStake = minOperatorStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
				stats = testGateway.stats,
				settings = testGateway.settings,
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
				weights = testGateway.weights,
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
				minDelegatedStake = minDelegatedStake + 5,
			}
			local expectation = {
				operatorStake = minOperatorStake,
				observerAddress = newObserverWallet,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = testGateway.startTimestamp,
				stats = testGateway.stats,
				settings = updatedSettings,
				status = testGateway.status,
				weights = testGateway.weights,
			}
			local result = gar.updateGatewaySettings(
				stubGatewayAddress,
				updatedSettings,
				nil, -- no additional services on this gateway
				newObserverWallet,
				startTimestamp,
				stubMessageId
			)
			assert.are.same(expectation, result)
			assert.are.same(expectation, _G.GatewayRegistry[stubGatewayAddress])
		end)

		it("should update delegator allow list settings correctly", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = minOperatorStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = startTimestamp,
				stats = testGateway.stats,
				settings = testGateway.settings,
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
				weights = testGateway.weights,
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
				minDelegatedStake = minDelegatedStake + 5,
			}
			local expectedSettings = utils.deepCopy(inputUpdatedSettings)
			expectedSettings.allowedDelegates = nil
			expectedSettings.allowedDelegatesLookup = {
				["test-allowlisted-delegator-address-number-1"] = true,
				["test-allowlisted-delegator-address-number-2"] = true,
			}
			local expectation = {
				operatorStake = minOperatorStake,
				observerAddress = newObserverWallet,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = testGateway.startTimestamp,
				stats = testGateway.stats,
				settings = expectedSettings,
				status = testGateway.status,
				weights = testGateway.weights,
			}
			local result = gar.updateGatewaySettings(
				stubGatewayAddress,
				inputUpdatedSettings,
				nil, -- no additional services on this gateway
				newObserverWallet,
				startTimestamp,
				stubMessageId
			)
			assert.are.same(expectation, result)
			assert.are.same(expectation, _G.GatewayRegistry[stubGatewayAddress])
		end)

		it("should allow updating gateway services", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = minOperatorStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = testGateway.startTimestamp,
				stats = testGateway.stats,
				settings = testGateway.settings,
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
				weights = testGateway.weights,
			}

			local updatedServices = {
				bundlers = {
					{ fqdn = "example.com", port = 80, protocol = "https", path = "/path" },
				},
			}

			local result = gar.updateGatewaySettings(
				stubGatewayAddress,
				testGateway.settings,
				updatedServices,
				stubObserverAddress,
				testGateway.startTimestamp,
				stubMessageId
			)
			assert.are.same({
				operatorStake = minOperatorStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = testGateway.startTimestamp,
				stats = testGateway.stats,
				settings = testGateway.settings,
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
				services = updatedServices,
				weights = testGateway.weights,
			}, result)
		end)

		it("should not allow editing of gateway settings for a gateway that is leaving", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = minOperatorStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = testGateway.startTimestamp,
				stats = testGateway.stats,
				settings = testGateway.settings,
				status = "leaving",
				observerAddress = testGateway.observerAddress,
				weights = testGateway.weights,
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
				minDelegatedStake = minDelegatedStake + 5,
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

		it(
			"should not allow editing gateway settings for a gateway that has a delegate share ratio above the maximum allowed",
			function()
				local settings = utils.deepCopy(testGateway.settings)
				settings.delegateRewardShareRatio = 100

				_G.GatewayRegistry[stubGatewayAddress] = {
					operatorStake = minOperatorStake,
					totalDelegatedStake = 0,
					vaults = {},
					delegates = {},
					startTimestamp = testGateway.startTimestamp,
					stats = testGateway.stats,
					settings = settings,
					status = testGateway.status,
					observerAddress = testGateway.observerAddress,
					weights = testGateway.weights,
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
					delegateRewardShareRatio = 100,
					minDelegatedStake = minDelegatedStake + 5,
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
				assert.matches("delegateRewardShareRatio must be an integer between 0 and 95", err)
			end
		)

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
			local stakeAmount = 10000000
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
						delegatedStake = stakeAmount,
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
				weights = testGateway.weights,
			}, result)
		end)
	end)

	describe("decreaseDelegateStake", function()
		it("should decrease delegated stake if the remaining stake is at least the minimum stake", function()
			local totalDelegatedStake = minDelegatedStake + 100000000
			local decreaseAmount = 100000000
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake = totalDelegatedStake
			_G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress] = {
				delegatedStake = totalDelegatedStake,
				startTimestamp = 0,
				vaults = {},
			}

			local expectedGateway = {
				operatorStake = testGateway.operatorStake,
				totalDelegatedStake = minDelegatedStake,
				vaults = {},
				delegates = {
					[stubRandomAddress] = {
						delegatedStake = minDelegatedStake,
						startTimestamp = 0,
						vaults = {
							[stubMessageId] = {
								balance = decreaseAmount,
								startTimestamp = startTimestamp,
								endTimestamp = 90 * 24 * 60 * 60 * 1000,
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
				weights = testGateway.weights,
			}

			local expectation = {
				amountWithdrawn = 0,
				delegatePruned = false,
				expeditedWithdrawalFee = 0,
				gatewayTotalDelegatedStake = minDelegatedStake,
				penaltyRate = 0,
				updatedDelegate = {
					delegatedStake = minDelegatedStake,
					startTimestamp = 0,
					vaults = {
						[stubMessageId] = {
							balance = decreaseAmount,
							startTimestamp = startTimestamp,
							endTimestamp = startTimestamp + (90 * 24 * 60 * 60 * 1000), -- 90 days
						},
					},
				},
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
			assert.are.same(expectation, result)
			assert.are.same(expectedGateway, _G.GatewayRegistry[stubGatewayAddress])
		end)

		it(
			"should decrease delegated stake with instant withdrawal if the remaining stake is at least the minimum stake",
			function()
				local totalDelegatedStake = minDelegatedStake + 100000000
				local decreaseAmount = 100000000
				local expeditedWithdrawalFee = decreaseAmount * 0.50
				local withdrawalAmount = decreaseAmount - expeditedWithdrawalFee
				_G.GatewayRegistry[stubGatewayAddress] = testGateway
				_G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake = totalDelegatedStake
				_G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress] = {
					delegatedStake = totalDelegatedStake,
					startTimestamp = 0,
					vaults = {},
				}

				local expectedGateway = {
					operatorStake = testGateway.operatorStake,
					totalDelegatedStake = minDelegatedStake,
					vaults = {},
					delegates = {
						[stubRandomAddress] = {
							delegatedStake = minDelegatedStake,
							startTimestamp = 0,
							vaults = {},
						},
					},
					startTimestamp = testGateway.startTimestamp,
					stats = testGateway.stats,
					services = testGateway.services,
					settings = testGateway.settings,
					status = testGateway.status,
					observerAddress = testGateway.observerAddress,
					weights = testGateway.weights,
				}

				local expectation = {
					amountWithdrawn = withdrawalAmount,
					delegatePruned = false,
					expeditedWithdrawalFee = expeditedWithdrawalFee,
					gatewayTotalDelegatedStake = minDelegatedStake,
					penaltyRate = 0.5,
					updatedDelegate = {
						delegatedStake = minDelegatedStake,
						startTimestamp = 0,
						vaults = {},
					},
				}
				local status, result = pcall(
					gar.decreaseDelegateStake,
					stubGatewayAddress,
					stubRandomAddress,
					decreaseAmount,
					startTimestamp,
					stubMessageId,
					true -- Instant withdrawal flag
				)
				assert.is_true(status)
				assert.are.same(expectation, result)
				assert.are.same(expectedGateway, _G.GatewayRegistry[stubGatewayAddress])
				assert.are.equal(withdrawalAmount, _G.Balances[stubRandomAddress])
				assert.are.equal(expeditedWithdrawalFee, _G.Balances[ao.id])
			end
		)

		it("should allow decreasing entire delegated stake", function()
			local totalDelegatedStake = minDelegatedStake
			local decreaseAmount = minDelegatedStake
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake = totalDelegatedStake
			_G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress] = {
				delegatedStake = totalDelegatedStake,
				startTimestamp = 0,
				vaults = {},
			}

			local expectedGateway = {
				operatorStake = testGateway.operatorStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {
					[stubRandomAddress] = {
						delegatedStake = 0,
						startTimestamp = 0,
						vaults = {
							[stubMessageId] = {
								balance = decreaseAmount,
								startTimestamp = startTimestamp,
								endTimestamp = startTimestamp + (90 * 24 * 60 * 60 * 1000), -- 90 days
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
				weights = testGateway.weights,
			}

			local expectation = {
				amountWithdrawn = 0,
				delegatePruned = false,
				expeditedWithdrawalFee = 0,
				gatewayTotalDelegatedStake = 0,
				penaltyRate = 0,
				updatedDelegate = {
					delegatedStake = 0,
					startTimestamp = 0,
					vaults = {
						[stubMessageId] = {
							balance = decreaseAmount,
							startTimestamp = startTimestamp,
							endTimestamp = startTimestamp + (90 * 24 * 60 * 60 * 1000), -- 90 days
						},
					},
				},
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
			assert.are.same(expectation, result)
			assert.are.same(expectedGateway, _G.GatewayRegistry[stubGatewayAddress])
		end)

		it("should allow decreasing entire delegated stake with instant withdrawal and prune the delegate", function()
			local totalDelegatedStake = minDelegatedStake
			local decreaseAmount = minDelegatedStake
			local expeditedWithdrawalFee = decreaseAmount * 0.50
			local withdrawalAmount = decreaseAmount - expeditedWithdrawalFee
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].totalDelegatedStake = totalDelegatedStake
			_G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress] = {
				delegatedStake = totalDelegatedStake,
				startTimestamp = 0,
				vaults = {},
			}

			local expectedGateway = {
				operatorStake = testGateway.operatorStake,
				totalDelegatedStake = 0,
				vaults = {},
				delegates = {},
				startTimestamp = testGateway.startTimestamp,
				stats = testGateway.stats,
				services = testGateway.services,
				settings = utils.deepCopy(testGateway.settings),
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
				weights = testGateway.weights,
			}
			expectedGateway.settings.allowedDelegatesLookup["test-this-is-valid-arweave-wallet-address-3"] = true -- Add pruned delegate back to the allowlist

			local expectation = {
				amountWithdrawn = withdrawalAmount,
				delegatePruned = true,
				expeditedWithdrawalFee = expeditedWithdrawalFee,
				gatewayTotalDelegatedStake = 0,
				penaltyRate = 0.5,
				updatedDelegate = {
					delegatedStake = 0,
					startTimestamp = 0,
					vaults = {},
				},
			}
			local status, result = pcall(
				gar.decreaseDelegateStake,
				stubGatewayAddress,
				stubRandomAddress,
				decreaseAmount,
				startTimestamp,
				stubMessageId,
				true -- Instant withdrawal flag
			)
			assert.is_true(status)
			assert.are.same(expectation, result)
			assert.are.same(expectedGateway, _G.GatewayRegistry[stubGatewayAddress])
			assert.are.equal(withdrawalAmount, _G.Balances[stubRandomAddress])
			assert.are.equal(expeditedWithdrawalFee, _G.Balances[ao.id])
		end)

		it("should error if the remaining delegate stake is less than the minimum stake and greater than 0", function()
			local delegatedStake = minDelegatedStake
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = minOperatorStake,
				totalDelegatedStake = minDelegatedStake,
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
				weights = testGateway.weights,
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
					startTimestamp = testGateway.startTimestamp,
					stats = testGateway.stats,
					services = testGateway.services,
					settings = testGateway.settings,
					status = testGateway.status,
					observerAddress = testGateway.observerAddress,
					weights = testGateway.weights,
					delegates = {},
					totalDelegatedStake = 0,
					operatorStake = 2000,
					vaults = {
						[vaultId] = {
							balance = vaultBalance,
							startTimestamp = currentTimestamp,
							endTimestamp = currentTimestamp + operatorLeaveLengthMs,
						},
					},
				}

				-- Attempt to withdraw instantly
				local withdrawalResult = gar.instantGatewayWithdrawal(from, gatewayAddress, vaultId, currentTimestamp)

				assert.are.same({
					gateway = _G.GatewayRegistry[gatewayAddress],
					elapsedTime = 0,
					remainingTime = operatorLeaveLengthMs, -- the full withdrawal period
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
					local timeElapsed = operatorLeaveLengthMs / 2
					local timeRemaining = operatorLeaveLengthMs / 2
					local currentTimestamp = vaultTimestamp + timeElapsed -- Halfway through the withdrawal period
					local vaultBalance = 1000

					-- Initialize balances
					_G.Balances[ao.id] = 0
					_G.Balances[from] = 0

					_G.GatewayRegistry[gatewayAddress] = {
						startTimestamp = testGateway.startTimestamp,
						stats = testGateway.stats,
						services = testGateway.services,
						settings = testGateway.settings,
						status = testGateway.status,
						observerAddress = testGateway.observerAddress,
						weights = testGateway.weights,
						delegates = {},
						totalDelegatedStake = 0,
						operatorStake = 2000,
						vaults = {
							[vaultId] = {
								balance = vaultBalance,
								startTimestamp = vaultTimestamp,
								endTimestamp = vaultTimestamp + operatorLeaveLengthMs,
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
					startTimestamp = testGateway.startTimestamp,
					stats = testGateway.stats,
					services = testGateway.services,
					settings = testGateway.settings,
					status = testGateway.status,
					observerAddress = testGateway.observerAddress,
					weights = testGateway.weights,
					delegates = {},
					totalDelegatedStake = 0,
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
					startTimestamp = testGateway.startTimestamp,
					stats = testGateway.stats,
					services = testGateway.services,
					settings = testGateway.settings,
					observerAddress = testGateway.observerAddress,
					weights = testGateway.weights,
					delegates = {},
					totalDelegatedStake = 0,
					operatorStake = 2000,
					status = "leaving",
					vaults = {
						[vaultId] = {
							balance = 1000,
							startTimestamp = 1000000,
							endTimestamp = 1000000 + operatorLeaveLengthMs,
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
					startTimestamp = testGateway.startTimestamp,
					stats = testGateway.stats,
					services = testGateway.services,
					settings = testGateway.settings,
					status = testGateway.status,
					observerAddress = testGateway.observerAddress,
					weights = testGateway.weights,
					delegates = {},
					totalDelegatedStake = 0,
					operatorStake = 2000,
					vaults = {
						[vaultId] = {
							balance = 1000,
							startTimestamp = vaultTimestamp,
							endTimestamp = vaultTimestamp + operatorLeaveLengthMs,
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
						operatorStake = minOperatorStake + vaultBalance,
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
										endTimestamp = vaultTimestamp + delegateLeaveLengthMs,
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
						weights = testGateway.weights,
					}

					local withdrawalResult =
						gar.instantGatewayWithdrawal(stubRandomAddress, stubGatewayAddress, vaultId, currentTimestamp)

					assert.are.same({
						gateway = _G.GatewayRegistry[stubGatewayAddress],
						elapsedTime = 0,
						remainingTime = delegateLeaveLengthMs,
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
					local elapsedTime = delegateLeaveLengthMs / 2
					local currentTimestamp = delegateStartTimestamp + elapsedTime
					local vaultBalance = 1000
					local penaltyRate = 0.300
					local expectedExpeditedWithdrawalFee = math.floor(vaultBalance * penaltyRate)
					local expectedWithdrawalAmount = vaultBalance - expectedExpeditedWithdrawalFee
					_G.Balances[ao.id] = 0

					_G.GatewayRegistry[stubGatewayAddress] = {
						operatorStake = minOperatorStake,
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
										endTimestamp = vaultTimestamp + delegateLeaveLengthMs,
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
						weights = testGateway.weights,
					}

					local withdrawalResult =
						gar.instantGatewayWithdrawal(stubRandomAddress, stubGatewayAddress, vaultId, currentTimestamp)

					assert.are.same({
						gateway = _G.GatewayRegistry[stubGatewayAddress],
						elapsedTime = elapsedTime,
						remainingTime = delegateLeaveLengthMs - elapsedTime,
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
					local elapsedTime = delegateLeaveLengthMs - 1 -- 1ms less than 90 days in milliseconds
					local currentTimestamp = delegateStartTimestamp + elapsedTime
					local penaltyRate = 0.5 - ((0.5 - 0.1) * (elapsedTime / delegateLeaveLengthMs))
					local expectedWithdrawalFee = math.floor(vaultBalance * penaltyRate)
					local expectedWithdrawalAmount = vaultBalance - expectedWithdrawalFee
					_G.Balances[ao.id] = 0

					_G.GatewayRegistry[stubGatewayAddress] = {
						operatorStake = minOperatorStake,
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
										endTimestamp = vaultTimestamp + delegateLeaveLengthMs,
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
						weights = testGateway.weights,
					}

					local withdrawalResult =
						gar.instantGatewayWithdrawal(stubRandomAddress, stubGatewayAddress, vaultId, currentTimestamp)

					assert.are.same({
						gateway = _G.GatewayRegistry[stubGatewayAddress],
						elapsedTime = delegateLeaveLengthMs - 1,
						remainingTime = 1,
						penaltyRate = 0.100,
						expeditedWithdrawalFee = 100,
						amountWithdrawn = 900,
					}, withdrawalResult)
					-- Assert the delegate has been removed from the gateway
					assert.are.equal(nil, _G.GatewayRegistry[stubGatewayAddress].delegates[stubRandomAddress])
					assert.are.equal(expectedWithdrawalAmount, _G.Balances[stubRandomAddress])
					assert.are.equal(expectedWithdrawalFee, _G.Balances[ao.id])
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
					operatorStake = minOperatorStake,
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
									endTimestamp = vaultTimestamp + delegateLeaveLengthMs,
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
					weights = testGateway.weights,
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
				operatorStake = minOperatorStake,
				totalDelegatedStake = 123,
				vaults = {},
				delegates = {},
				startTimestamp = 0,
				stats = testGateway.stats,
				settings = testGateway.settings,
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
				weights = testGateway.weights,
			}
			local currentTimestamp = 123456
			local status, err = pcall(gar.slashOperatorStake, stubGatewayAddress, slashAmount, currentTimestamp)
			assert.is_true(status)
			assert.is_nil(err)
			assert.are.same({
				operatorStake = minOperatorStake - slashAmount,
				totalDelegatedStake = 123,
				slashings = {
					["123456"] = slashAmount, -- must be stringified timestamp to avoid encoding issues
				},
				vaults = {},
				delegates = {},
				startTimestamp = 0,
				stats = testGateway.stats,
				settings = testGateway.settings,
				status = testGateway.status,
				observerAddress = testGateway.observerAddress,
				weights = testGateway.weights,
			}, _G.GatewayRegistry[stubGatewayAddress])
			assert.are.equal(slashAmount, _G.Balances[ao.id])
		end)
	end)

	describe("getGatewayWeightsAtTimestamp", function()
		it("should properly compute weights based on gateways for a given timestamp", function()
			_G.GatewayRegistry[stubGatewayAddress] = {
				operatorStake = minOperatorStake,
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
				weights = testGateway.weights,
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
					stake = minOperatorStake,
					startTimestamp = 0,
					stakeWeight = expectedStakeWeight,
					tenureWeight = expectedTenureWeight,
					gatewayPerformanceRatio = expectedGatewayRatioWeight,
					observerPerformanceRatio = expectedObserverRatioWeight,
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
						operatorStake = minOperatorStake,
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
						operatorStake = minOperatorStake,
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
						operatorStake = minOperatorStake + 10000, -- will slash 100% of the min operator stake
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
				local result = gar.pruneGateways(currentTimestamp, msgId)
				local expectedSlashedStake = minOperatorStake -- the full operator stake should be slashed
				local expectedRemainingStake = 10000 -- the remaining stake should be the operator stake minus the slashed stake plus the remaining stake
				assert.are.same({
					prunedGateways = { "address1" },
					slashedGateways = {
						address3 = expectedSlashedStake,
					},
					stakeSlashed = expectedSlashedStake,
					delegateStakeReturned = 0,
					gatewayStakeReturned = 0,
					delegateStakeWithdrawing = 0,
					gatewayStakeWithdrawing = expectedRemainingStake,
					gatewayObjectTallies = {
						numDelegateVaults = 0,
						numDelegatesVaulting = 0,
						numDelegations = 0,
						numDelegates = 0,
						numExitingDelegations = 0,
						numExitingGateways = 1,
						numGatewayVaults = 0,
						numGateways = 1,
						numGatewaysVaulting = 0,
					},
				}, result)

				assert.is_nil(_G.GatewayRegistry["address1"]) -- removed
				assert.is_not_nil(_G.GatewayRegistry["address2"]) -- not removed
				assert.is_not_nil(_G.GatewayRegistry["address3"]) -- not removed
				-- Check that gateway 3's operator stake is slashed by 100% and the remaining stake is vaulted
				assert.are.equal("leaving", _G.GatewayRegistry["address3"].status)
				assert.are.equal(0, _G.GatewayRegistry["address3"].operatorStake)
				assert.are.same({
					balance = expectedRemainingStake,
					startTimestamp = currentTimestamp,
					endTimestamp = currentTimestamp + operatorLeaveLengthMs,
				}, _G.GatewayRegistry["address3"].vaults["address3"])
				assert.are.equal(protocolBalanceBefore + expectedSlashedStake, _G.Balances[ao.id])
			end
		)

		it("should handle empty _G.GatewayRegistry", function()
			local currentTimestamp = 1000000

			-- Set up empty _G.GatewayRegistry
			_G.GatewayRegistry = {}

			-- Call pruneGateways
			gar.pruneGateways(currentTimestamp, "msgId")

			-- Check results
			local gateways = gar.getGateways()
			assert.are.equal(0, utils.lengthOfTable(gateways))
		end)

		it("should skip pruning when there is no known pruning work to do", function()
			local currentTimestamp = 1000000
			_G.NextGatewaysPruneTimestamp = currentTimestamp + 1
			local msgId = "msgId"

			-- Set up test gateways
			_G.GatewayRegistry = {
				["address2"] = {
					startTimestamp = currentTimestamp - 100,
					endTimestamp = currentTimestamp + 100, -- Not expired, failedConsecutiveEpochs is 20
					status = "joined",
					operatorStake = minOperatorStake,
					vaults = {},
					delegates = {},
					stats = {
						failedConsecutiveEpochs = 20,
					},
					totalDelegatedStake = 0,
					-- Other gateway properties...
				},
			}

			-- Call pruneGateways
			_G.Balances[ao.id] = _G.Balances[ao.id] or 0
			local protocolBalanceBefore = _G.Balances[ao.id]
			local result = gar.pruneGateways(currentTimestamp, msgId)
			assert.are.same({
				prunedGateways = {},
				slashedGateways = {},
				stakeSlashed = 0,
				delegateStakeReturned = 0,
				gatewayStakeReturned = 0,
				delegateStakeWithdrawing = 0,
				gatewayStakeWithdrawing = 0,
			}, result)

			assert.is_not_nil(_G.GatewayRegistry["address2"]) -- not changed
			assert.are.equal(protocolBalanceBefore, _G.Balances[ao.id])
		end)
	end)

	describe("cancelGatewayWithdrawal", function()
		it("should cancel a gateway withdrawal", function()
			_G.GatewayRegistry[stubGatewayAddress] = testGateway
			_G.GatewayRegistry[stubGatewayAddress].vaults["some-previous-withdrawal-id"] = {
				balance = 10000000000,
				startTimestamp = 0,
				endTimestamp = 1000,
			}
			local result =
				gar.cancelGatewayWithdrawal(stubGatewayAddress, stubGatewayAddress, "some-previous-withdrawal-id")
			assert.are.same({
				totalDelegatedStake = testGateway.totalDelegatedStake,
				totalOperatorStake = 20000000000,
				previousTotalDelegatedStake = testGateway.totalDelegatedStake,
				previousOperatorStake = 10000000000,
				gateway = _G.GatewayRegistry[stubGatewayAddress],
				vaultBalance = 10000000000,
			}, result)
			assert.are.equal(nil, _G.GatewayRegistry[stubGatewayAddress].vaults["some-previous-withdrawal-id"])
		end)
		it("should not cancel a gateway withdrawal if the gateway is leaving", function()
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
		it("should not cancel a gateway withdrawal if the vault id is not found", function()
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
				startTimestamp = 0,
				vaults = {
					["some-previous-withdrawal-id"] = {
						balance = 1000,
						startTimestamp = 0,
						endTimestamp = 1000,
					},
				},
			}
			local result =
				gar.cancelGatewayWithdrawal(stubRandomAddress, stubGatewayAddress, "some-previous-withdrawal-id")
			assert.are.same({
				totalDelegatedStake = 1000,
				totalOperatorStake = 10000000000,
				previousTotalDelegatedStake = 0,
				previousOperatorStake = 10000000000,
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
				startTimestamp = 0,
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
				startTimestamp = 0,
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

	-- describe("getActiveGatewayAddressesBeforeTimestamp", function()
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
	-- 		local result = gar.getActiveGatewayAddressesBeforeTimestamp(timestamp)
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
			-- remove delegates and vaults to avoid sending unbounded arrays
			local gateway2Copy = utils.deepCopy(gateway2)
			gateway2Copy.delegates = nil
			gateway2Copy.vaults = nil
			assert.are.same({
				limit = 1,
				sortBy = "startTimestamp",
				sortOrder = "asc",
				hasMore = true,
				nextCursor = stubRandomAddress,
				totalItems = 2,
				items = {
					gateway2Copy, -- should be first because it has a lower startTimestamp
				},
			}, gateways)
			-- get the next page
			local nextGateways = gar.getPaginatedGateways(gateways.nextCursor, 1, "startTimestamp", "asc")
			local gateway1Copy = utils.deepCopy(gateway1)
			gateway1Copy.delegates = nil
			gateway1Copy.vaults = nil
			assert.are.same({
				limit = 1,
				sortBy = "startTimestamp",
				sortOrder = "asc",
				hasMore = false,
				nextCursor = nil,
				totalItems = 2,
				items = {
					gateway1Copy,
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
				gatewayPerformanceRatio = 0.85,
				stakeWeight = 0,
				observerPerformanceRatio = 0,
				compositeWeight = 0,
				normalizedCompositeWeight = 0,
			}
			local result = gar.isEligibleForArNSDiscount(stubRandomAddress)
			assert.is_false(result)
		end)

		it("should return false if gatewayPerformanceRatio is less than 0.85", function()
			_G.GatewayRegistry[stubRandomAddress] = testGateway
			_G.GatewayRegistry[stubRandomAddress].weights = {
				tenureWeight = minimumTenureWeightForDiscount,
				gatewayPerformanceRatio = 0.84,
				stakeWeight = 0,
				observerPerformanceRatio = 0,
				compositeWeight = 0,
				normalizedCompositeWeight = 0,
			}
			local result = gar.isEligibleForArNSDiscount(stubRandomAddress)
			assert.is_false(result)
		end)

		it("should return true if gateway is eligible for ArNS discount", function()
			_G.GatewayRegistry[stubRandomAddress] = testGateway
			_G.GatewayRegistry[stubRandomAddress].weights = {
				tenureWeight = minimumTenureWeightForDiscount,
				gatewayPerformanceRatio = minimumPerformanceRateForDiscount,
				stakeWeight = 0,
				observerPerformanceRatio = 0,
				compositeWeight = 0,
				normalizedCompositeWeight = 0,
			}
			_G.GatewayRegistry[stubRandomAddress].status = "joined"
			local result = gar.isEligibleForArNSDiscount(stubRandomAddress)
			assert.is_true(result)
		end)
	end)

	describe("isDelegateEligibleForDistributions", function()
		it("should return false if delegate is not found", function()
			local result = gar.isDelegateEligibleForDistributions(testGateway, stubRandomAddress)
			assert.is_false(result)
		end)

		it("should return false if delegate stake is 0", function()
			local gateway = utils.deepCopy(testGateway)
			gateway.delegates = {
				[stubRandomAddress] = {
					delegatedStake = 0,
				},
			}
			_G.GatewayRegistry = {
				[stubGatewayAddress] = gateway,
			}
			local result = gar.isDelegateEligibleForDistributions(testGateway, stubRandomAddress)
			assert.is_false(result)
		end)
	end)

	describe("getPaginatedDelegates", function()
		it(
			"should return paginated delegates sorted, by default, by startTimestamp in descending order (newest first)",
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
						},
					},
				}, nextDelegates)
			end
		)
	end)

	describe("getPaginatedAllowedDelegates", function()
		it("should return paginated allowed delegates sorted, by default, by address in descending order", function()
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
						endTimestamp = 1000 + delegateLeaveLengthMs,
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
						delegatedStake = 41, -- 40 of this will get drawn down, with the last mARIO forced to a withdraw vault
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
							endTimestamp = 12345 + delegateLeaveLengthMs,
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
								endTimestamp = 12345 + delegateLeaveLengthMs,
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

	local sevenDays = 7 * 24 * 60 * 60 * 1000
	local testRedelegatorAddress = "test-re-delegator-1234567890123456789012345"
	local testSourceAddress = "unique-source-address-123456789012345678901"
	local testTargetAddress = "unique-target-address-123456789012345678901"

	describe("redelegateStake", function()
		local timestamp = 12345
		local testRedelegationGateway = utils.deepCopy({
			operatorStake = minOperatorStake,
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
		})
		testRedelegationGateway.settings.allowedDelegatesLookup = nil
		local stubDelegation = {
			delegatedStake = minDelegatedStake,
			startTimestamp = 0,
			vaults = {},
		}

		it("should redelegate stake from one gateway to another", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			local targetGateway = utils.deepCopy(testRedelegationGateway)
			local qty = minDelegatedStake

			sourceGateway.delegates = {
				[testRedelegatorAddress] = stubDelegation,
			}
			sourceGateway.totalDelegatedStake = minDelegatedStake
			_G.GatewayRegistry = {
				[testSourceAddress] = sourceGateway,
				[testTargetAddress] = targetGateway,
			}
			local result = gar.redelegateStake({
				delegateAddress = testRedelegatorAddress,
				sourceAddress = testSourceAddress,
				targetAddress = testTargetAddress,
				qty = qty,
				currentTimestamp = timestamp,
			})

			assert.are.same({
				sourceAddress = testSourceAddress,
				targetAddress = testTargetAddress,
				redelegationFee = 0,
				feeResetTimestamp = timestamp + sevenDays,
				redelegationsSinceFeeReset = 1,
			}, result)

			assert.are.same({
				timestamp = timestamp,
				redelegations = 1,
			}, _G.Redelegations[testRedelegatorAddress])

			-- setup expectations on gateway tables
			sourceGateway.delegates[testRedelegatorAddress] = nil
			sourceGateway.totalDelegatedStake = 0
			targetGateway.delegates[testRedelegatorAddress] = {
				delegatedStake = qty,
				startTimestamp = timestamp,
				vaults = {},
			}
			targetGateway.totalDelegatedStake = qty

			assert.are.same(sourceGateway, _G.GatewayRegistry[testSourceAddress])
			assert.are.same(targetGateway, _G.GatewayRegistry[testTargetAddress])
		end)

		it("should redelegate stake from its own gateway into another gateway", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			local targetGateway = utils.deepCopy(testRedelegationGateway)
			local qty = minDelegatedStake

			targetGateway.settings.allowedDelegatesLookup = nil
			sourceGateway.operatorStake = minOperatorStake + minDelegatedStake

			_G.GatewayRegistry = {
				-- Set delegator as the source gateway
				[testRedelegatorAddress] = sourceGateway,
				[testTargetAddress] = targetGateway,
			}
			local result = gar.redelegateStake({
				delegateAddress = testRedelegatorAddress,
				sourceAddress = testRedelegatorAddress,
				targetAddress = testTargetAddress,
				qty = qty,
				currentTimestamp = timestamp,
			})

			-- setup expectations on gateway tables
			sourceGateway.delegates[testRedelegatorAddress] = nil
			sourceGateway.operatorStake = minOperatorStake
			targetGateway.delegates[testRedelegatorAddress] = {
				delegatedStake = qty,
				startTimestamp = timestamp,
				vaults = {},
			}
			targetGateway.totalDelegatedStake = qty

			assert.are.same({
				sourceAddress = testRedelegatorAddress,
				targetAddress = testTargetAddress,
				redelegationFee = 0,
				feeResetTimestamp = timestamp + sevenDays,
				redelegationsSinceFeeReset = 1,
			}, result)

			assert.are.same(sourceGateway, _G.GatewayRegistry[testRedelegatorAddress])
			assert.are.same(targetGateway, _G.GatewayRegistry[testTargetAddress])
		end)

		it(
			"should allow operators to redelegate to its own stake when that stake is below the minimum delegated stake value",
			function()
				local sourceGateway = utils.deepCopy(testRedelegationGateway)
				local targetGateway = utils.deepCopy(testRedelegationGateway)

				sourceGateway.totalDelegatedStake = minDelegatedStake

				sourceGateway.delegates = {
					[testRedelegatorAddress] = {
						delegatedStake = minDelegatedStake + 1,
						startTimestamp = 0,
						vaults = {},
					},
				}
				_G.GatewayRegistry = {
					[testRedelegatorAddress] = targetGateway,
					[testSourceAddress] = sourceGateway,
				}

				local result = gar.redelegateStake({
					delegateAddress = testRedelegatorAddress,
					sourceAddress = testSourceAddress,
					targetAddress = testRedelegatorAddress,
					qty = 1, -- Move 1 mARIO to the operator gateway
					currentTimestamp = timestamp,
				})

				assert.are.same({
					sourceAddress = testSourceAddress,
					targetAddress = testRedelegatorAddress,
					redelegationFee = 0,
					feeResetTimestamp = timestamp + sevenDays,
					redelegationsSinceFeeReset = 1,
				}, result)

				assert.are.same({
					timestamp = timestamp,
					redelegations = 1,
				}, _G.Redelegations[testRedelegatorAddress])

				-- setup expectations on gateway tables
				sourceGateway.delegates[testRedelegatorAddress] = {
					delegatedStake = minDelegatedStake,
					startTimestamp = 0,
					vaults = {},
				}
				sourceGateway.totalDelegatedStake = minDelegatedStake - 1
				targetGateway.operatorStake = minOperatorStake + 1
			end
		)

		it(
			"should redelegate stake for a fee if the delegator has already done redelegations in the last seven epochs",
			function()
				local sourceGateway = utils.deepCopy(testRedelegationGateway)
				local targetGateway = utils.deepCopy(testRedelegationGateway)

				-- Use enough stake to account for the 10% fee
				local initialStakeNeeded = math.ceil(minDelegatedStake / (1 - 0.1))
				local redelegationFee = math.ceil(initialStakeNeeded * 0.1)

				sourceGateway.delegates = {
					[testRedelegatorAddress] = {
						delegatedStake = initialStakeNeeded,
						startTimestamp = 0,
						vaults = {},
					},
				}
				sourceGateway.totalDelegatedStake = initialStakeNeeded
				_G.GatewayRegistry = {
					[testSourceAddress] = sourceGateway,
					[testTargetAddress] = targetGateway,
				}
				_G.Redelegations[testRedelegatorAddress] = {
					timestamp = 1, -- earlier timestamp
					redelegations = 1,
				}

				local result = gar.redelegateStake({
					delegateAddress = testRedelegatorAddress,
					sourceAddress = testSourceAddress,
					targetAddress = testTargetAddress,
					qty = initialStakeNeeded,
					currentTimestamp = timestamp,
				})

				assert.are.same({
					sourceAddress = testSourceAddress,
					targetAddress = testTargetAddress,
					redelegationFee = redelegationFee,
					feeResetTimestamp = timestamp + sevenDays,
					redelegationsSinceFeeReset = 2,
				}, result)
				assert.are.same({
					timestamp = timestamp, -- new timestamp
					redelegations = 2,
				}, _G.Redelegations[testRedelegatorAddress])

				-- setup expectations on gateway tables
				sourceGateway.delegates[testRedelegatorAddress] = nil
				sourceGateway.totalDelegatedStake = 0
				targetGateway.delegates[testRedelegatorAddress] = {
					delegatedStake = initialStakeNeeded - redelegationFee,
					startTimestamp = timestamp,
					vaults = {},
				}
				targetGateway.totalDelegatedStake = initialStakeNeeded - redelegationFee

				assert.are.same(sourceGateway, _G.GatewayRegistry[testSourceAddress])
				assert.are.same(targetGateway, _G.GatewayRegistry[testTargetAddress])
			end
		)

		it(
			"should cap the redelegation fee at 0.6 if the delegator has already over 6 redelegations in the last seven epochs",
			function()
				local sourceGateway = utils.deepCopy(testRedelegationGateway)
				local targetGateway = utils.deepCopy(testRedelegationGateway)

				-- Use enough stake to account for the 60% fee
				local initialStakeNeeded = math.ceil(minDelegatedStake / (1 - 0.6))
				local redelegationFee = math.ceil(initialStakeNeeded * 0.6)
				local stakeToBeDelegated = initialStakeNeeded - redelegationFee

				sourceGateway.delegates = {
					[testRedelegatorAddress] = {
						delegatedStake = initialStakeNeeded,
						startTimestamp = 0,
						vaults = {},
					},
				}
				sourceGateway.totalDelegatedStake = initialStakeNeeded
				_G.GatewayRegistry = {
					[testSourceAddress] = sourceGateway,
					[testTargetAddress] = targetGateway,
				}
				_G.Redelegations[testRedelegatorAddress] = {
					timestamp = timestamp,
					redelegations = 7, -- delegator already has 7 redelegations
				}

				local result = gar.redelegateStake({
					delegateAddress = testRedelegatorAddress,
					sourceAddress = testSourceAddress,
					targetAddress = testTargetAddress,
					qty = initialStakeNeeded,
					currentTimestamp = timestamp,
				})

				-- setup expectations on gateway tables
				sourceGateway.delegates[testRedelegatorAddress] = nil
				sourceGateway.totalDelegatedStake = 0

				targetGateway.delegates[testRedelegatorAddress] = {
					delegatedStake = stakeToBeDelegated,
					startTimestamp = timestamp,
					vaults = {},
				}
				targetGateway.totalDelegatedStake = stakeToBeDelegated

				assert.are.same({
					sourceAddress = testSourceAddress,
					targetAddress = testTargetAddress,
					redelegationFee = redelegationFee,
					feeResetTimestamp = timestamp + sevenDays,
					redelegationsSinceFeeReset = 8,
				}, result)
				assert.are.same({
					timestamp = timestamp,
					redelegations = 8,
				}, _G.Redelegations[testRedelegatorAddress])
			end
		)

		it("should redelegate stake to their operator stake if target gateway is the delegator", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			local targetGateway = utils.deepCopy(testRedelegationGateway)

			sourceGateway.delegates = {
				[testRedelegatorAddress] = stubDelegation,
			}
			sourceGateway.totalDelegatedStake = minDelegatedStake
			_G.GatewayRegistry = {
				[testSourceAddress] = sourceGateway,
				[testRedelegatorAddress] = targetGateway,
			}

			local result = gar.redelegateStake({
				delegateAddress = testRedelegatorAddress,
				sourceAddress = testSourceAddress,
				targetAddress = testRedelegatorAddress,
				qty = minDelegatedStake,
				currentTimestamp = timestamp,
			})

			assert.are.same({
				sourceAddress = testSourceAddress,
				targetAddress = testRedelegatorAddress,
				redelegationFee = 0,
				feeResetTimestamp = timestamp + sevenDays,
				redelegationsSinceFeeReset = 1,
			}, result)

			-- setup expectations on gateway tables
			sourceGateway.delegates[testRedelegatorAddress] = nil
			sourceGateway.totalDelegatedStake = 0
			targetGateway.operatorStake = minOperatorStake + minDelegatedStake

			assert.are.same(sourceGateway, _G.GatewayRegistry[testSourceAddress])
			assert.are.same(targetGateway, _G.GatewayRegistry[testRedelegatorAddress])
		end)

		it(
			"should be able to redelegate partial amount of delegated stake from a source gateway as long as the remaining stake meets the minimum ",
			function()
				local sourceGateway = utils.deepCopy(testRedelegationGateway)
				local targetGateway = utils.deepCopy(testRedelegationGateway)

				sourceGateway.delegates = {
					[testRedelegatorAddress] = {
						delegatedStake = minDelegatedStake + minDelegatedStake,
						startTimestamp = 0,
						vaults = {},
					},
				}
				sourceGateway.totalDelegatedStake = minDelegatedStake + minDelegatedStake
				_G.GatewayRegistry = {
					[testSourceAddress] = sourceGateway,
					[testTargetAddress] = targetGateway,
				}

				local result = gar.redelegateStake({
					delegateAddress = testRedelegatorAddress,
					sourceAddress = testSourceAddress,
					targetAddress = testTargetAddress,
					qty = minDelegatedStake,
					currentTimestamp = timestamp,
				})

				assert.are.same({
					sourceAddress = testSourceAddress,
					targetAddress = testTargetAddress,
					redelegationFee = 0,
					feeResetTimestamp = timestamp + sevenDays,
					redelegationsSinceFeeReset = 1,
				}, result)

				-- setup expectations on gateway tables
				sourceGateway.delegates[testRedelegatorAddress] = {
					delegatedStake = minDelegatedStake,
					startTimestamp = 0,
					vaults = {},
				}
				sourceGateway.totalDelegatedStake = minDelegatedStake
				targetGateway.delegates[testRedelegatorAddress] = {
					delegatedStake = minDelegatedStake,
					startTimestamp = timestamp,
					vaults = {},
				}
				targetGateway.totalDelegatedStake = minDelegatedStake

				assert.are.same(sourceGateway, _G.GatewayRegistry[testSourceAddress])
				assert.are.same(targetGateway, _G.GatewayRegistry[testTargetAddress])
			end
		)

		it(
			"should not be able to redelegate stake if the amount to stake after the redelegation fee is zero",
			function()
				local sourceGateway = utils.deepCopy(testRedelegationGateway)
				local targetGateway = utils.deepCopy(testRedelegationGateway)
				_G.Redelegations = {
					[testRedelegatorAddress] = {
						timestamp = timestamp,
						redelegations = 1,
					},
				}
				_G.GatewayRegistry = {
					[testSourceAddress] = sourceGateway,
					[testTargetAddress] = targetGateway,
				}

				local isSuccess, error = pcall(function()
					gar.redelegateStake({
						delegateAddress = testRedelegatorAddress,
						sourceAddress = testSourceAddress,
						targetAddress = testTargetAddress,
						qty = 1,
						currentTimestamp = timestamp,
					})
				end)

				assert(not isSuccess)
				assert(error)
				assert(
					error:find("The redelegation stake amount minus the redelegation fee is too low to redelegate.")
						~= nil
				)
			end
		)

		it("should not redelegate stake if target gateway is not in the allowedDelegatesLookup", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			local targetGateway = utils.deepCopy(testRedelegationGateway)

			targetGateway.settings.allowedDelegatesLookup = {
				[testRedelegatorAddress] = false,
			}
			_G.GatewayRegistry = {
				[testSourceAddress] = sourceGateway,
				[testTargetAddress] = targetGateway,
			}

			local isSuccess, error = pcall(function()
				gar.redelegateStake({
					delegateAddress = testRedelegatorAddress,
					sourceAddress = testSourceAddress,
					targetAddress = testTargetAddress,
					qty = minDelegatedStake,
					currentTimestamp = timestamp,
				})
			end)
			assert(not isSuccess)
			assert(error)
			assert(error:find("This Gateway does not allow this delegate to stake.") ~= nil)
		end)

		it("should not redelegate stake if target gateway is not in the GatewayRegistry", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)

			_G.GatewayRegistry = {
				[testSourceAddress] = sourceGateway,
			}

			local isSuccess, error = pcall(function()
				gar.redelegateStake({
					delegateAddress = testRedelegatorAddress,
					sourceAddress = testSourceAddress,
					targetAddress = testTargetAddress,
					qty = minDelegatedStake,
					currentTimestamp = timestamp,
				})
			end)

			assert(not isSuccess)
			assert(error)
			assert(error:find("Target Gateway not found") ~= nil)
		end)

		it("should not redelegate stake if source gateway is not in the GatewayRegistry", function()
			local isSuccess, error = pcall(function()
				gar.redelegateStake({
					delegateAddress = testRedelegatorAddress,
					sourceAddress = testSourceAddress,
					targetAddress = testTargetAddress,
					qty = minDelegatedStake,
					currentTimestamp = timestamp,
				})
			end)

			assert(not isSuccess)
			assert(error)
			assert(error:find("Source Gateway not found") ~= nil)
		end)

		it("should not redelegate stake if the target gateway is leaving the network", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			local targetGateway = utils.deepCopy(testRedelegationGateway)

			targetGateway.status = "leaving"

			_G.GatewayRegistry = {
				[testSourceAddress] = sourceGateway,
				[testTargetAddress] = targetGateway,
			}

			local isSuccess, error = pcall(function()
				gar.redelegateStake({
					delegateAddress = testRedelegatorAddress,
					sourceAddress = testSourceAddress,
					targetAddress = testTargetAddress,
					qty = minDelegatedStake,
					currentTimestamp = timestamp,
				})
			end)

			assert(not isSuccess)
			assert(error)
			assert(
				error:find("Target Gateway is leaving the network and cannot have more stake delegated to it.") ~= nil
			)
		end)

		it("should be able to redelegate stake if the source gateway is leaving the network", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			local targetGateway = utils.deepCopy(testRedelegationGateway)

			sourceGateway.delegates = {
				[testRedelegatorAddress] = stubDelegation,
			}
			sourceGateway.totalDelegatedStake = minDelegatedStake
			sourceGateway.status = "leaving"
			_G.GatewayRegistry = {
				[testSourceAddress] = sourceGateway,
				[testTargetAddress] = targetGateway,
			}

			local result = gar.redelegateStake({
				delegateAddress = testRedelegatorAddress,
				sourceAddress = testSourceAddress,
				targetAddress = testTargetAddress,
				qty = minDelegatedStake,
				currentTimestamp = timestamp,
			})

			assert.are.same({
				sourceAddress = testSourceAddress,
				targetAddress = testTargetAddress,
				redelegationFee = 0,
				feeResetTimestamp = timestamp + sevenDays,
				redelegationsSinceFeeReset = 1,
			}, result)

			-- setup expectations on gateway tables
			sourceGateway.delegates[testRedelegatorAddress] = nil
			sourceGateway.totalDelegatedStake = 0
			targetGateway.delegates[testRedelegatorAddress] = {
				delegatedStake = minDelegatedStake,
				startTimestamp = timestamp,
				vaults = {},
			}
			targetGateway.totalDelegatedStake = minDelegatedStake

			assert.are.same(sourceGateway, _G.GatewayRegistry[testSourceAddress])
			assert.are.same(targetGateway, _G.GatewayRegistry[testTargetAddress])
		end)

		it("should not redelegate stake if target gateway does not allow delegates", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			local targetGateway = utils.deepCopy(testRedelegationGateway)

			targetGateway.settings.allowDelegatedStaking = false
			_G.GatewayRegistry = {
				[testSourceAddress] = sourceGateway,
				[testTargetAddress] = targetGateway,
			}

			local isSuccess, error = pcall(function()
				gar.redelegateStake({
					delegateAddress = testRedelegatorAddress,
					sourceAddress = testSourceAddress,
					targetAddress = testTargetAddress,
					qty = minDelegatedStake,
					currentTimestamp = timestamp,
				})
			end)

			assert(not isSuccess)
			assert(error)
			assert(error:find("Target Gateway does not allow delegated staking.") ~= nil)
		end)

		it(
			"should not redelegate stake if the remaining stake in its own gateway stake is less than the minimum operator stake",
			function()
				local sourceGateway = utils.deepCopy(testRedelegationGateway)
				local targetGateway = utils.deepCopy(testRedelegationGateway)

				-- Less than the required amount to keep min operator stake and start a new delegate
				sourceGateway.operatorStake = minOperatorStake + minDelegatedStake - 1
				_G.GatewayRegistry = {
					[testRedelegatorAddress] = sourceGateway,
					[testTargetAddress] = targetGateway,
				}

				local isSuccess, error = pcall(function()
					gar.redelegateStake({
						delegateAddress = testRedelegatorAddress,
						sourceAddress = testRedelegatorAddress,
						targetAddress = testTargetAddress,
						qty = minDelegatedStake,
						currentTimestamp = timestamp,
					})
				end)

				assert(not isSuccess)
				assert(error)
				assert.matches(
					"Resulting stake of 9999999999 mARIO is not enough to maintain the minimum operator stake",
					error
				)
			end
		)

		it("should redelegate stake if adding stake to a target gateway where they already have stake", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			local targetGateway = utils.deepCopy(testRedelegationGateway)

			sourceGateway.operatorStake = minOperatorStake + 1
			targetGateway.delegates = {
				[testRedelegatorAddress] = {
					delegatedStake = minDelegatedStake,
					startTimestamp = 1337, -- custom start timestamp
					vaults = {},
				},
			}
			targetGateway.totalDelegatedStake = minDelegatedStake

			_G.GatewayRegistry = {
				[testRedelegatorAddress] = sourceGateway,
				[testTargetAddress] = targetGateway,
			}

			local result = gar.redelegateStake({
				delegateAddress = testRedelegatorAddress,
				sourceAddress = testRedelegatorAddress,
				targetAddress = testTargetAddress,
				qty = 1,
				currentTimestamp = timestamp,
			})

			assert.are.same({
				sourceAddress = testRedelegatorAddress,
				targetAddress = testTargetAddress,
				redelegationFee = 0,
				feeResetTimestamp = timestamp + sevenDays,
				redelegationsSinceFeeReset = 1,
			}, result)

			-- setup expectations on gateway tables
			sourceGateway.operatorStake = minOperatorStake
			targetGateway.delegates[testRedelegatorAddress] = {
				delegatedStake = minDelegatedStake + 1,
				startTimestamp = 1337,
				vaults = {},
			}
			targetGateway.totalDelegatedStake = minDelegatedStake + 1

			assert.are.same(sourceGateway, _G.GatewayRegistry[testRedelegatorAddress])
			assert.are.same(targetGateway, _G.GatewayRegistry[testTargetAddress])
		end)

		it(
			"should not redelegate stake if the remaining stake in the source gateway is less than the minimum delegated stake",
			function()
				local sourceGateway = utils.deepCopy(testRedelegationGateway)
				local targetGateway = utils.deepCopy(testRedelegationGateway)

				sourceGateway.totalDelegatedStake = minDelegatedStake

				sourceGateway.delegates = {
					[testRedelegatorAddress] = {
						delegatedStake = minDelegatedStake,
						startTimestamp = 0,
						vaults = {},
					},
				}
				_G.GatewayRegistry = {
					[testSourceAddress] = sourceGateway,
					[testTargetAddress] = targetGateway,
				}

				local isSuccess, error = pcall(function()
					gar.redelegateStake({
						delegateAddress = testRedelegatorAddress,
						sourceAddress = testSourceAddress,
						targetAddress = testTargetAddress,
						qty = 1,
						currentTimestamp = timestamp,
					})
				end)

				assert(not isSuccess)
				assert(error)
				assert(error:find("Remaining delegated stake must be greater than the minimum delegated stake.") ~= nil)
			end
		)

		it(
			"should not redelegate stake if the resulting stake on the target gateway does not meet the minimum stake amount",
			function()
				local sourceGateway = utils.deepCopy(testRedelegationGateway)
				local targetGateway = utils.deepCopy(testRedelegationGateway)

				sourceGateway.totalDelegatedStake = minDelegatedStake + minDelegatedStake - 1
				sourceGateway.delegates = {
					[testRedelegatorAddress] = {
						delegatedStake = minDelegatedStake + minDelegatedStake - 1,
						startTimestamp = 0,
						vaults = {},
					},
				}
				_G.GatewayRegistry = {
					[testSourceAddress] = sourceGateway,
					[testTargetAddress] = targetGateway,
				}

				local isSuccess, error = pcall(function()
					gar.redelegateStake({
						delegateAddress = testRedelegatorAddress,
						sourceAddress = testSourceAddress,
						targetAddress = testTargetAddress,
						qty = minDelegatedStake - 1,
						currentTimestamp = timestamp,
					})
				end)

				assert(not isSuccess)
				assert(error)
				assert(error:find("Quantity must be greater than the minimum delegated stake amount.") ~= nil)
			end
		)

		it("should not redelegate stake if delegate does not have enough stake to redelegate", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			local targetGateway = utils.deepCopy(testRedelegationGateway)

			sourceGateway.totalDelegatedStake = stubDelegation.delegatedStake

			sourceGateway.delegates = {
				[testRedelegatorAddress] = stubDelegation,
			}
			_G.GatewayRegistry = {
				[testSourceAddress] = sourceGateway,
				[testTargetAddress] = targetGateway,
			}

			local isSuccess, error = pcall(function()
				gar.redelegateStake({
					delegateAddress = testRedelegatorAddress,
					sourceAddress = testSourceAddress,
					targetAddress = testTargetAddress,
					qty = stubDelegation.delegatedStake + 1,
					currentTimestamp = timestamp,
				})
			end)

			assert(not isSuccess)
			assert(error)
			assert(error:find("Quantity must be less than or equal to the delegated stake amount.") ~= nil)
		end)

		it("should not redelegate stake when vault ID cannot be found on the delegate", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			sourceGateway.delegates = {
				[testRedelegatorAddress] = {
					delegatedStake = minDelegatedStake,
					startTimestamp = 0,
					vaults = {},
				},
			}
			_G.GatewayRegistry = {
				[testSourceAddress] = sourceGateway,
				[testTargetAddress] = testRedelegationGateway,
			}

			local isSuccess, error = pcall(function()
				gar.redelegateStake({
					delegateAddress = testRedelegatorAddress,
					sourceAddress = testSourceAddress,
					targetAddress = testTargetAddress,
					qty = minDelegatedStake,
					currentTimestamp = timestamp,
					vaultId = "vault-1",
				})
			end)

			assert(not isSuccess)
			assert(error)
			assert(error:find("Vault not found on the delegate.") ~= nil)
		end)

		it("should not redelegate stake when vault ID cannot be found on the operator", function()
			_G.GatewayRegistry = {
				[testRedelegatorAddress] = testRedelegationGateway,
				[testTargetAddress] = testRedelegationGateway,
			}

			local isSuccess, error = pcall(function()
				gar.redelegateStake({
					delegateAddress = testRedelegatorAddress,
					sourceAddress = testRedelegatorAddress,
					targetAddress = testTargetAddress,
					qty = minDelegatedStake,
					currentTimestamp = timestamp,
					vaultId = "vault-1",
				})
			end)

			assert(not isSuccess)
			assert(error)
			assert(error:find("Vault not found on the operator.") ~= nil)
		end)

		it("should redelegate stake from a valid vault ID on the source delegate", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			local targetGateway = utils.deepCopy(testRedelegationGateway)

			sourceGateway.delegates = {
				[testRedelegatorAddress] = {
					delegatedStake = minDelegatedStake,
					startTimestamp = 0,
					vaults = {
						["vault-1"] = {
							balance = minDelegatedStake,
							startTimestamp = 0,
							endTimestamp = 1000,
						},
					},
				},
			}
			sourceGateway.totalDelegatedStake = minDelegatedStake

			_G.GatewayRegistry = {
				[testSourceAddress] = sourceGateway,
				[testTargetAddress] = testRedelegationGateway,
			}

			local result = gar.redelegateStake({
				delegateAddress = testRedelegatorAddress,
				sourceAddress = testSourceAddress,
				targetAddress = testTargetAddress,
				qty = minDelegatedStake,
				currentTimestamp = timestamp,
				vaultId = "vault-1",
			})

			assert.are.same({
				sourceAddress = testSourceAddress,
				targetAddress = testTargetAddress,
				redelegationFee = 0,
				feeResetTimestamp = timestamp + sevenDays,
				redelegationsSinceFeeReset = 1,
			}, result)

			-- setup redelegation expectations on gateway tables
			sourceGateway.delegates[testRedelegatorAddress] = stubDelegation
			targetGateway.delegates[testRedelegatorAddress] = {
				delegatedStake = minDelegatedStake,
				startTimestamp = timestamp,
				vaults = {},
			}
			targetGateway.totalDelegatedStake = minDelegatedStake

			assert.are.same(sourceGateway, _G.GatewayRegistry[testSourceAddress])
			assert.are.same(targetGateway, _G.GatewayRegistry[testTargetAddress])
		end)

		it("should remove the delegate when the last vault is emptied from a redelegation", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			local targetGateway = utils.deepCopy(testRedelegationGateway)

			sourceGateway.delegates = {
				[testRedelegatorAddress] = {
					delegatedStake = 0,
					startTimestamp = 0,
					vaults = {
						["vault-1"] = {
							balance = minDelegatedStake,
							startTimestamp = 0,
							endTimestamp = 1000,
						},
					},
				},
			}

			_G.GatewayRegistry = {
				[testSourceAddress] = sourceGateway,
				[testTargetAddress] = targetGateway,
			}

			local result = gar.redelegateStake({
				delegateAddress = testRedelegatorAddress,
				sourceAddress = testSourceAddress,
				targetAddress = testTargetAddress,
				qty = minDelegatedStake,
				currentTimestamp = timestamp,
				vaultId = "vault-1",
			})

			assert.are.same({
				sourceAddress = testSourceAddress,
				targetAddress = testTargetAddress,
				redelegationFee = 0,
				feeResetTimestamp = timestamp + sevenDays,
				redelegationsSinceFeeReset = 1,
			}, result)

			-- setup expectations on gateway tables
			sourceGateway.delegates[testRedelegatorAddress] = nil
			targetGateway.delegates[testRedelegatorAddress] = {
				delegatedStake = minDelegatedStake,
				startTimestamp = timestamp,
				vaults = {},
			}
			targetGateway.totalDelegatedStake = minDelegatedStake
			assert.are.same(sourceGateway, _G.GatewayRegistry[testSourceAddress])
			assert.are.same(targetGateway, _G.GatewayRegistry[testTargetAddress])
		end)

		it("should redelegate stake from a valid vault ID on the source operator", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			local targetGateway = utils.deepCopy(testRedelegationGateway)

			sourceGateway.operatorStake = minOperatorStake
			sourceGateway.vaults = {
				["vault-1"] = {
					balance = minDelegatedStake,
					startTimestamp = 0,
					endTimestamp = 1000,
				},
			}
			_G.GatewayRegistry = {
				[testRedelegatorAddress] = sourceGateway,
				[testTargetAddress] = targetGateway,
			}

			local result = gar.redelegateStake({
				delegateAddress = testRedelegatorAddress,
				sourceAddress = testRedelegatorAddress,
				targetAddress = testTargetAddress,
				qty = minDelegatedStake,
				currentTimestamp = timestamp,
				vaultId = "vault-1",
			})

			assert.are.same({
				sourceAddress = testRedelegatorAddress,
				targetAddress = testTargetAddress,
				redelegationFee = 0,
				feeResetTimestamp = timestamp + sevenDays,
				redelegationsSinceFeeReset = 1,
			}, result)

			-- setup expectations on gateway tables
			targetGateway.delegates[testRedelegatorAddress] = {
				delegatedStake = minDelegatedStake,
				startTimestamp = timestamp,
				vaults = {},
			}
			targetGateway.totalDelegatedStake = minDelegatedStake
			sourceGateway.vaults = {}

			assert.are.same(sourceGateway, _G.GatewayRegistry[testRedelegatorAddress])
			assert.are.same(targetGateway, _G.GatewayRegistry[testTargetAddress])
		end)

		it("should not redelegate stake from when the quantity exceeds the balance of the vault", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			local targetGateway = utils.deepCopy(testRedelegationGateway)

			sourceGateway.delegates = {
				[testRedelegatorAddress] = {
					delegatedStake = minDelegatedStake,
					startTimestamp = 0,
					vaults = {
						["vault-1"] = {
							balance = minDelegatedStake,
							startTimestamp = 0,
							endTimestamp = 1000,
						},
					},
				},
			}

			_G.GatewayRegistry = {
				[testSourceAddress] = sourceGateway,
				[testTargetAddress] = targetGateway,
			}

			local isSuccess, error = pcall(function()
				gar.redelegateStake({
					delegateAddress = testRedelegatorAddress,
					sourceAddress = testSourceAddress,
					targetAddress = testTargetAddress,
					qty = minDelegatedStake + 1,
					currentTimestamp = timestamp,
					vaultId = "vault-1",
				})
			end)

			assert(not isSuccess)
			assert(error)
			assert(error:find("Quantity must be less than or equal to the vaulted stake amount.") ~= nil)
		end)

		it("should be able to redelegate partial amount of a vault's balance", function()
			local sourceGateway = utils.deepCopy(testRedelegationGateway)
			local targetGateway = utils.deepCopy(testRedelegationGateway)

			sourceGateway.delegates = {
				[testRedelegatorAddress] = {
					delegatedStake = minDelegatedStake,
					startTimestamp = 0,
					vaults = {
						["vault-1"] = {
							balance = minDelegatedStake + minDelegatedStake,
							startTimestamp = 0,
							endTimestamp = 1000,
						},
					},
				},
			}

			_G.GatewayRegistry = {
				[testSourceAddress] = sourceGateway,
				[testTargetAddress] = targetGateway,
			}

			local result = gar.redelegateStake({
				delegateAddress = testRedelegatorAddress,
				sourceAddress = testSourceAddress,
				targetAddress = testTargetAddress,
				qty = minDelegatedStake,
				currentTimestamp = timestamp,
				vaultId = "vault-1",
			})

			assert.are.same({
				sourceAddress = testSourceAddress,
				targetAddress = testTargetAddress,
				redelegationFee = 0,
				feeResetTimestamp = timestamp + sevenDays,
				redelegationsSinceFeeReset = 1,
			}, result)

			-- setup expectations on gateway tables
			sourceGateway.delegates[testRedelegatorAddress].vaults["vault-1"].balance = minDelegatedStake
			targetGateway.delegates[testRedelegatorAddress] = {
				delegatedStake = minDelegatedStake,
				startTimestamp = timestamp,
				vaults = {},
			}
			targetGateway.totalDelegatedStake = minDelegatedStake

			assert.are.same(sourceGateway, _G.GatewayRegistry[testSourceAddress])
			assert.are.same(targetGateway, _G.GatewayRegistry[testTargetAddress])
		end)
	end)

	describe("getRedelegationFee", function()
		it("should return 0 if the delegator has not redelegated in the last 7 epochs", function()
			local result = gar.getRedelegationFee(testTargetAddress)
			assert.are.same({ redelegationFeeRate = 0 }, result)
		end)

		it("should return 0.1 if the delegator has redelegated once in the last 7 epochs", function()
			_G.Redelegations = {
				[testTargetAddress] = {
					timestamp = 1,
					redelegations = 1,
				},
			}
			local result = gar.getRedelegationFee(testTargetAddress)
			assert.are.same({ redelegationFeeRate = 10, feeResetTimestamp = 1 + sevenDays }, result)
		end)

		it("should return 0.6 if the delegator has redelegated 7 times in the last 7 epochs", function()
			_G.Redelegations = {
				[testTargetAddress] = {
					timestamp = 1,
					redelegations = 7,
				},
			}
			local result = gar.getRedelegationFee(testTargetAddress)
			assert.are.same({ redelegationFeeRate = 60, feeResetTimestamp = 1 + sevenDays }, result)
		end)
	end)

	describe("pruneRedelegationFeeData", function()
		before_each(function()
			_G.Redelegations = {}
			_G.NextRedelegationsPruneTimestamp = 0
		end)

		it("should return an empty array when there are no tracked redelegations", function()
			local prunedRedelegations = gar.pruneRedelegationFeeData(604800001)
			assert.are.same({}, prunedRedelegations)
			assert.are.same({}, _G.Redelegations)
		end)

		it("should prune redelegations that are equal to or older than the pruning threshold", function()
			_G.Redelegations = {
				["recently-delegated"] = {
					timestamp = 100000000,
					redelegations = 1,
				},
				["delegated-two-weeks-ago"] = {
					timestamp = 1,
					redelegations = 2,
				},
				["delegated-over-two-weeks-ago"] = {
					timestamp = 0,
					redelegations = 2,
				},
			}
			local prunedRedelegations = gar.pruneRedelegationFeeData(604800001)
			table.sort(prunedRedelegations)
			assert.are.same({
				"delegated-over-two-weeks-ago",
				"delegated-two-weeks-ago",
			}, prunedRedelegations)
			assert.are.same({
				["recently-delegated"] = {
					timestamp = 100000000,
					redelegations = 1,
				},
			}, _G.Redelegations)
		end)

		it("should skip pruning when possible", function()
			_G.NextRedelegationsPruneTimestamp = 604800002 -- force an invariant state for testing purposes
			local expectedRedelegations = {
				["recently-delegated"] = {
					timestamp = 100000000,
					redelegations = 1,
				},
				["delegated-two-weeks-ago"] = {
					timestamp = 1,
					redelegations = 2,
				},
				["delegated-over-two-weeks-ago"] = {
					timestamp = 0,
					redelegations = 2,
				},
			}
			_G.Redelegations = expectedRedelegations
			local prunedRedelegations = gar.pruneRedelegationFeeData(604800001)
			table.sort(prunedRedelegations)
			assert.are.same({}, prunedRedelegations)
			assert.are.same(expectedRedelegations, _G.Redelegations)
			assert.are.same(604800002, _G.NextRedelegationsPruneTimestamp)
		end)
	end)

	describe("getCompactGateways", function()
		it("returns a operator-wallet-addressed dictionary of gateways without vaults or delegates", function()
			_G.GatewayRegistry = {
				["0x123"] = {
					operator = "0x123",
					vaults = {},
					delegates = {},
					settings = {
						autoStake = true,
						allowedDelegatesLookup = {},
					},
				},
				["0x456"] = {
					operator = "0x456",
					vaults = {},
					delegates = {},
					settings = {
						autoStake = false,
						allowedDelegatesLookup = {},
					},
				},
			}
			local compactGateways = gar.getCompactGateways()
			assert.are.same({
				["0x123"] = { operator = "0x123", settings = { autoStake = true } },
				["0x456"] = { operator = "0x456", settings = { autoStake = false } },
			}, compactGateways)
		end)
	end)

	describe("getPaginatedVaultsForGateway", function()
		before_each(function()
			_G.GatewayRegistry = {}
		end)

		local vault1 = {
			balance = 300,
			startTimestamp = 3,
			endTimestamp = 1000,
		}
		local vault2 = {
			balance = 200,
			startTimestamp = 2,
			endTimestamp = 1000,
		}
		local vault3 = {
			balance = 100,
			startTimestamp = 1,
			endTimestamp = 1000,
		}
		local expectedVault1 = utils.deepCopy(vault1)
		expectedVault1.vaultId = "vault-1"
		expectedVault1.cursorId = "vault-1_3"
		local expectedVault2 = utils.deepCopy(vault2)
		expectedVault2.vaultId = "vault-2"
		expectedVault2.cursorId = "vault-2_2"
		local expectedVault3 = utils.deepCopy(vault3)
		expectedVault3.vaultId = "vault-3"
		expectedVault3.cursorId = "vault-3_1"

		it("should throw an error for a non-existent gateway", function()
			local isSuccess, error = pcall(function()
				gar.getPaginatedVaultsForGateway("non-existent-gateway", nil, 1)
			end)
			assert(not isSuccess)
			assert(error)
			assert(error:find("Gateway not found") ~= nil)
		end)

		it("should handle an empty result set gracefully", function()
			_G.GatewayRegistry = {
				["test-gateway"] = {
					vaults = {},
				},
			}
			local result = gar.getPaginatedVaultsForGateway("test-gateway", nil, 1)
			assert.are.same({
				limit = 1,
				sortBy = "startTimestamp",
				sortOrder = "asc",
				hasMore = false,
				nextCursor = nil,
				totalItems = 0,
				items = {},
			}, result)
		end)

		it("should return paginated gateway vaults sorted by startTimestamp in ascending order by default", function()
			local gateway = {
				vaults = {
					["vault-1"] = vault1,
					["vault-2"] = vault2,
					["vault-3"] = vault3,
				},
			}

			_G.GatewayRegistry = {
				["test-gateway"] = gateway,
			}
			local vaultsPage1 = gar.getPaginatedVaultsForGateway("test-gateway", nil, 1)
			assert.are.same({
				limit = 1,
				sortBy = "startTimestamp",
				sortOrder = "asc",
				hasMore = true,
				nextCursor = "vault-3_1",
				totalItems = 3,
				items = {
					expectedVault3, -- should be first because it has a lower startTimestamp
				},
			}, vaultsPage1)
			-- get the next page
			local nextPage = gar.getPaginatedVaultsForGateway("test-gateway", tostring(vaultsPage1.nextCursor), 2)
			assert.are.same({
				limit = 2,
				sortBy = "startTimestamp",
				sortOrder = "asc",
				hasMore = false,
				nextCursor = nil,
				totalItems = 3,
				items = {
					expectedVault2,
					expectedVault1,
				},
			}, nextPage)
		end)

		it("should allow for descending pagination by other fields, e.g. balance", function()
			local gateway = {
				vaults = {
					["vault-1"] = vault1,
					["vault-2"] = vault2,
					["vault-3"] = vault3,
				},
			}
			_G.GatewayRegistry = {
				["test-gateway"] = gateway,
			}
			local vaultsPage1 = gar.getPaginatedVaultsForGateway("test-gateway", nil, 1, "balance", "desc")
			assert.are.same({
				limit = 1,
				sortBy = "balance",
				sortOrder = "desc",
				hasMore = true,
				nextCursor = "vault-1_3",
				totalItems = 3,
				items = {
					expectedVault1, -- should be first because it has a higher balance
				},
			}, vaultsPage1)
			-- get the next page
			local nextPage =
				gar.getPaginatedVaultsForGateway("test-gateway", tostring(vaultsPage1.nextCursor), 2, "balance", "desc")
			assert.are.same({
				limit = 2,
				sortBy = "balance",
				sortOrder = "desc",
				hasMore = false,
				nextCursor = nil,
				totalItems = 3,
				items = {
					expectedVault2,
					expectedVault3,
				},
			}, nextPage)
		end)
	end)

	describe("allowDelegates", function()
		it("should throw an error if the gateway is nil", function()
			local status, error = pcall(function()
				gar.allowDelegates({ stubRandomAddress }, nil)
			end)
			assert(not status)
			assert(error:find("Gateway not found") ~= nil)
		end)
		it("should throw an error if allowDelegatedStaking is false and allowedDelegatesLookup is nil", function()
			local gateway = {
				settings = { allowDelegatedStaking = false },
			}
			_G.GatewayRegistry = {
				["test-gateway"] = gateway,
			}
			local status, error = pcall(function()
				gar.allowDelegates({ stubRandomAddress }, "test-gateway")
			end)
			assert(not status)
			assert(error:find("allowedDelegatesLookup should not be nil") ~= nil)
		end)

		it(
			"should allow delegates if allowDelegatedStaking is true and the allowedDelegatesLookup is not nil",
			function()
				local gateway = {
					delegates = {},
					settings = { allowDelegatedStaking = true, allowedDelegatesLookup = {} },
				}
				_G.GatewayRegistry = {
					["test-gateway"] = gateway,
				}
				local result = gar.allowDelegates({ stubRandomAddress }, "test-gateway")
				assert.are.same({
					gateway = {
						delegates = {},
						settings = {
							allowDelegatedStaking = true,
							allowedDelegatesLookup = {
								[stubRandomAddress] = true,
							},
						},
					},
					addedDelegates = { stubRandomAddress },
				}, result)
			end
		)

		describe("disallowDelegates", function()
			it("should throw an error if the gateway is nil", function()
				local status, error = pcall(function()
					gar.disallowDelegates({ stubRandomAddress }, nil, "msgId", 1)
				end)
				assert(not status)
				assert(error:find("Gateway not found") ~= nil)
			end)
			it(
				"should not remove any delegates if allowDelegatedStaking is false and the allowedDelegatesLookup is not nil",
				function()
					local gateway = {
						delegates = {},
						settings = { allowDelegatedStaking = false, allowedDelegatesLookup = {} },
					}
					_G.GatewayRegistry = {
						["test-gateway"] = gateway,
					}
					local result = gar.disallowDelegates({ stubRandomAddress }, "test-gateway", "msgId", 1)
					assert.are.same({
						gateway = {
							delegates = {},
							settings = { allowDelegatedStaking = false, allowedDelegatesLookup = {} },
						},
						removedDelegates = {},
					}, result)
				end
			)

			it("should throw an error if the allowedDelegatesLookup is nil", function()
				local gateway = {
					delegates = {},
					settings = { allowDelegatedStaking = true, allowedDelegatesLookup = nil },
				}
				_G.GatewayRegistry = {
					["test-gateway"] = gateway,
				}
				local status, error = pcall(function()
					gar.disallowDelegates({ stubRandomAddress }, "test-gateway", "msgId", 1)
				end)
				assert(not status)
				assert(
					error:find("Allow listing only possible when allowDelegatedStaking is set to 'allowlist'") ~= nil
				)
			end)

			it(
				"should disallow delegates if allowDelegatedStaking is true and the allowedDelegatesLookup is not nil",
				function()
					local gateway = {
						delegates = {},
						settings = {
							allowDelegatedStaking = true,
							allowedDelegatesLookup = { [stubRandomAddress] = true },
						},
					}
					_G.GatewayRegistry = {
						["test-gateway"] = gateway,
					}
					local result = gar.disallowDelegates({ stubRandomAddress }, "test-gateway", "msgId", 1)
					assert.are.same({
						gateway = {
							delegates = {},
							settings = { allowDelegatedStaking = true, allowedDelegatesLookup = {} },
						},
						removedDelegates = { stubRandomAddress },
					}, result)
				end
			)
		end)
	end)

	describe("getPaginatedDelegatesFromAllGateways", function()
		it(
			"should return paginated delegates sorted by delegatedStake in ascending order (most stake first)",
			function()
				local gateway1 = utils.deepCopy(testGateway)
				local gateway2 = utils.deepCopy(testGateway)
				local anotherAddress = "0x123"
				gateway1.delegates = {
					[stubGatewayAddress] = {
						delegatedStake = 100,
						startTimestamp = 0,
						vaults = {},
					},
					[anotherAddress] = {
						delegatedStake = 300,
						startTimestamp = 0,
						vaults = {},
					},
				}
				gateway2.delegates = {
					[stubRandomAddress] = {
						delegatedStake = 200,
						startTimestamp = 0,
						vaults = {
							["vault-1"] = {
								balance = 200,
								startTimestamp = 0,
								endTimestamp = 1000,
							},
						},
					},
					[anotherAddress] = {
						delegatedStake = 500,
						startTimestamp = 0,
						vaults = {
							["vault-1"] = {
								balance = 1000,
								startTimestamp = 0,
								endTimestamp = 1000,
							},
						},
					},
				}
				_G.GatewayRegistry = {
					[stubRandomAddress] = gateway1,
					[stubGatewayAddress] = gateway2,
				}
				local delegates = gar.getPaginatedDelegatesFromAllGateways(nil, 2)

				assert.are.same({
					limit = 2,
					sortBy = "delegatedStake",
					sortOrder = "desc",
					hasMore = true,
					nextCursor = anotherAddress .. "_" .. stubRandomAddress,
					totalItems = 4,
					items = {
						{
							address = anotherAddress,
							cursorId = anotherAddress .. "_" .. stubGatewayAddress,
							gatewayAddress = stubGatewayAddress,
							delegatedStake = 500,
							startTimestamp = 0,
							vaultedStake = 1000,
						},
						{
							address = anotherAddress,
							cursorId = anotherAddress .. "_" .. stubRandomAddress,
							gatewayAddress = stubRandomAddress,
							delegatedStake = 300,
							startTimestamp = 0,
							vaultedStake = 0,
						},
					},
				}, delegates)

				-- get the next page
				local nextPage = gar.getPaginatedDelegatesFromAllGateways(tostring(delegates.nextCursor), 2)
				assert.are.same({
					limit = 2,
					sortBy = "delegatedStake",
					sortOrder = "desc",
					hasMore = false,
					nextCursor = nil,
					totalItems = 4,
					items = {
						{
							address = stubRandomAddress,
							cursorId = stubRandomAddress .. "_" .. stubGatewayAddress,
							gatewayAddress = stubGatewayAddress,
							delegatedStake = 200,
							startTimestamp = 0,
							vaultedStake = 200,
						},
						{
							address = stubGatewayAddress,
							cursorId = stubGatewayAddress .. "_" .. stubRandomAddress,
							gatewayAddress = stubRandomAddress,
							delegatedStake = 100,
							startTimestamp = 0,
							vaultedStake = 0,
						},
					},
				}, nextPage)
			end
		)
	end)

	describe("getPaginatedVaultsFromAllGateways", function()
		it("should return paginated vaults sorted by delegatedStake in ascending order (most stake first)", function()
			local gateway1 = utils.deepCopy(testGateway)
			local gateway2 = utils.deepCopy(testGateway)
			gateway1.vaults = {
				["vault-1"] = {
					balance = 100,
					startTimestamp = 0,
					endTimestamp = 1000,
				},
				["vault-2"] = {
					balance = 300,
					startTimestamp = 0,
					endTimestamp = 1000,
				},
				["vault-3"] = {
					balance = 500,
					startTimestamp = 0,
					endTimestamp = 1000,
				},
			}
			gateway2.vaults = {
				["vault-4"] = {
					balance = 600,
					startTimestamp = 0,
					endTimestamp = 1000,
				},
				["vault-5"] = {
					balance = 200,
					startTimestamp = 0,
					endTimestamp = 1000,
				},
				["vault-6"] = {
					balance = 400,
					startTimestamp = 0,
					endTimestamp = 1000,
				},
			}
			_G.GatewayRegistry = {
				[stubRandomAddress] = gateway1,
				[stubGatewayAddress] = gateway2,
			}
			local delegates = gar.getPaginatedVaultsFromAllGateways(nil, 3, "balance", "desc")

			assert.are.same({
				limit = 3,
				sortBy = "balance",
				sortOrder = "desc",
				hasMore = true,
				nextCursor = stubGatewayAddress .. "_vault-6",
				totalItems = 6,
				items = {
					{
						vaultId = "vault-4",
						cursorId = stubGatewayAddress .. "_vault-4",
						gatewayAddress = stubGatewayAddress,
						balance = 600,
						startTimestamp = 0,
						endTimestamp = 1000,
					},
					{
						vaultId = "vault-3",
						cursorId = stubRandomAddress .. "_vault-3",
						gatewayAddress = stubRandomAddress,
						balance = 500,
						startTimestamp = 0,
						endTimestamp = 1000,
					},
					{
						vaultId = "vault-6",
						cursorId = stubGatewayAddress .. "_vault-6",
						gatewayAddress = stubGatewayAddress,
						balance = 400,
						startTimestamp = 0,
						endTimestamp = 1000,
					},
				},
			}, delegates)

			-- get the next page
			local nextPage = gar.getPaginatedVaultsFromAllGateways(tostring(delegates.nextCursor), 3, "balance", "desc")
			assert.are.same({
				limit = 3,
				sortBy = "balance",
				sortOrder = "desc",
				hasMore = false,
				nextCursor = nil,
				totalItems = 6,
				items = {
					{
						vaultId = "vault-2",
						cursorId = stubRandomAddress .. "_vault-2",
						gatewayAddress = stubRandomAddress,
						balance = 300,
						startTimestamp = 0,
						endTimestamp = 1000,
					},
					{
						vaultId = "vault-5",
						cursorId = stubGatewayAddress .. "_vault-5",
						gatewayAddress = stubGatewayAddress,
						balance = 200,
						startTimestamp = 0,
						endTimestamp = 1000,
					},
					{
						vaultId = "vault-1",
						cursorId = stubRandomAddress .. "_vault-1",
						gatewayAddress = stubRandomAddress,
						balance = 100,
						startTimestamp = 0,
						endTimestamp = 1000,
					},
				},
			}, nextPage)
		end)
	end)
end)
