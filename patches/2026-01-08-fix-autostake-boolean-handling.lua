--[[
	Fixes autoStake boolean handling in joinNetwork function.

	The previous logic `autoStake = settings.autoStake or true` would incorrectly
	default to true even when autoStake was explicitly set to false, because
	`false or true` evaluates to true in Lua.

	This patch ensures that when autoStake is explicitly set to false, it remains false,
	while still defaulting to true when not provided (nil).

	Reviewers: Dylan
]]
--
local gar = require(".src.gar")
local balances = require(".src.balances")
local utils = require(".src.utils")

--- Joins the network with the given parameters
--- @param from WalletAddress The address from which the request is made
--- @param stake mARIO: The amount of stake to be used
--- @param settings JoinGatewaySettings The settings for joining the network
--- @param services GatewayServices|nil The services to be used in the network
--- @param observerAddress WalletAddress The address of the observer
--- @param timeStamp Timestamp The timestamp of the request
--- @return Gateway # Returns the newly joined gateway
function gar.joinNetwork(from, stake, settings, services, observerAddress, timeStamp)
	gar.assertValidGatewayParameters(from, stake, settings, services, observerAddress)

	assert(not gar.getGateway(from), "Gateway already exists")
	assert(balances.walletHasSufficientBalance(from, stake), "Insufficient balance")

	local newGateway = {
		operatorStake = stake,
		totalDelegatedStake = 0,
		vaults = {},
		delegates = {},
		startTimestamp = timeStamp,
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
			allowDelegatedStaking = settings.allowDelegatedStaking or false,
			allowedDelegatesLookup = settings.allowedDelegates and utils.createLookupTable(settings.allowedDelegates)
				or nil,
			delegateRewardShareRatio = settings.delegateRewardShareRatio or 0,
			autoStake = settings.autoStake == nil and true or settings.autoStake,
			minDelegatedStake = settings.minDelegatedStake or gar.getSettings().delegates.minStake,
			label = settings.label,
			fqdn = settings.fqdn,
			protocol = settings.protocol or "https",
			port = settings.port or 443,
			properties = settings.properties,
			note = settings.note or "",
		},
		services = services or nil,
		status = "joined",
		observerAddress = observerAddress or from,
		weights = {
			stakeWeight = 0,
			tenureWeight = 0,
			gatewayPerformanceRatio = 0,
			observerPerformanceRatio = 0,
			compositeWeight = 0,
			normalizedCompositeWeight = 0,
		},
	}

	local gateway = gar.addGateway(from, newGateway)
	balances.reduceBalance(from, stake)
	return gateway
end
