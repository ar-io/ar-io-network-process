-- gar.lua
local balances = require("balances")
local constants = require("constants")
local utils = require("utils")
local gar = {}

GatewayRegistry = GatewayRegistry or {}
GatewayRegistrySettings = GatewayRegistrySettings
	or {
		observers = {
			maxPerEpoch = 50,
			tenureWeightDays = 180,
			tenureWeightPeriod = 180 * 24 * 60 * 60 * 1000, -- aproximately 180 days
			maxTenureWeight = 4,
		},
		operators = {
			minStake = 50000 * 1000000, -- 50,000 IO
			withdrawLengthMs = 30 * 24 * 60 * 60 * 1000, -- 30 days to lower operator stake
			leaveLengthMs = 90 * 24 * 60 * 60 * 1000, -- 90 days that balance will be vaulted
			failedEpochCountMax = 30, -- number of epochs failed before marked as leaving
			failedEpochSlashPercentage = 0.2, -- 20% of stake is returned to protocol balance
		},
		delegates = {
			minStake = 500 * 1000000, -- 500 IO
			withdrawLengthMs = 30 * 24 * 60 * 60 * 1000, -- 30 days
		},
	}

function gar.joinNetwork(from, stake, settings, services, observerAddress, timeStamp)
	gar.assertValidGatewayParameters(from, stake, settings, services, observerAddress)

	if gar.getGateway(from) then
		error("Gateway already exists")
	end

	if balances.getBalance(from) < stake then
		error("Insufficient balance")
	end

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
			autoStake = settings.autoStake or false,
			minDelegatedStake = settings.minDelegatedStake,
			label = settings.label,
			fqdn = settings.fqdn,
			protocol = settings.protocol,
			port = settings.port,
			properties = settings.properties,
			note = settings.note,
		},
		services = services or nil,
		status = "joined",
		observerAddress = observerAddress or from,
	}

	local gateway = gar.addGateway(from, newGateway)
	balances.reduceBalance(from, stake)
	return gateway
end

function gar.leaveNetwork(from, currentTimestamp, msgId)
	local gateway = gar.getGateway(from)

	if not gateway then
		error("Gateway not found")
	end

	if not gar.isGatewayEligibleToLeave(gateway, currentTimestamp) then
		error("The gateway is not eligible to leave the network.")
	end

	local gatewayEndTimestamp = currentTimestamp + gar.getSettings().operators.leaveLengthMs
	local gatewayStakeWithdrawTimestamp = currentTimestamp + gar.getSettings().operators.withdrawLengthMs

	local minimumStakedTokens = math.min(gar.getSettings().operators.minStake, gateway.operatorStake)

	-- if the slash happens to be 100% we do not need to vault anything
	if minimumStakedTokens > 0 then
		gateway.vaults[from] = {
			balance = minimumStakedTokens,
			startTimestamp = currentTimestamp,
			endTimestamp = gatewayEndTimestamp,
		}

		-- if there is more than the minimum staked tokens, we need to vault the rest but on shorter term
		local remainingStake = gateway.operatorStake - gar.getSettings().operators.minStake

		if remainingStake > 0 then
			gateway.vaults[msgId] = {
				balance = remainingStake,
				startTimestamp = currentTimestamp,
				endTimestamp = gatewayStakeWithdrawTimestamp,
			}
		end
	end

	gateway.status = "leaving"
	gateway.endTimestamp = gatewayEndTimestamp
	gateway.operatorStake = 0

	-- Add tokens from each delegate to a vault that unlocks after the delegate withdrawal period ends
	for address, _ in pairs(gateway.delegates) do
		gar.kickDelegateFromGateway(address, gateway, msgId, currentTimestamp)
	end

	-- update global state
	GatewayRegistry[from] = gateway
	return gateway
end

--- Increases the operator stake for a gateway
---@param from string # The address of the gateway to increase stake for
---@param qty number # The amount of stake to increase by - must be positive integer
---@return table # The updated gateway object
function gar.increaseOperatorStake(from, qty)
	assert(type(qty) == "number", "Quantity is required and must be a number")
	assert(qty > 0 and utils.isInteger(qty), "Quantity must be an integer greater than 0")

	local gateway = gar.getGateway(from)

	if not gateway then
		error("Gateway not found")
	end

	if gateway.status == "leaving" then
		error("Gateway is leaving the network and cannot accept additional stake.")
	end

	if balances.getBalance(from) < qty then
		error("Insufficient balance")
	end

	balances.reduceBalance(from, qty)
	gateway.operatorStake = gateway.operatorStake + qty
	-- update the gateway
	GatewayRegistry[from] = gateway
	return gateway
end

-- Utility function to calculate withdrawal details and handle balance adjustments
---@param stake number # The amount of stake to withdraw in mIO
---@param elapsedTimeMs number # The amount of time that has elapsed since the withdrawal started
---@param totalWithdrawalTimeMs number # The total amount of time the withdrawal will take
---@param from string # The address of the operator or delegate
---@return number # The penalty rate as a percentage
---@return number # The expedited withdrawal fee in mIO, given to the protocol balance
---@return number # The final amount withdrawn, after the penalty fee is subtracted and moved to the from balance
local function processInstantWithdrawal(stake, elapsedTimeMs, totalWithdrawalTimeMs, from)
	-- Calculate the withdrawal fee and the amount to withdraw
	local penaltyRate = constants.MAX_EXPEDITED_WITHDRAWAL_PENALTY_RATE
		- (
			(constants.MAX_EXPEDITED_WITHDRAWAL_PENALTY_RATE - constants.MIN_EXPEDITED_WITHDRAWAL_PENALTY_RATE)
			* (elapsedTimeMs / totalWithdrawalTimeMs)
		)
	penaltyRate = math.max(
		constants.MIN_EXPEDITED_WITHDRAWAL_PENALTY_RATE,
		math.min(constants.MAX_EXPEDITED_WITHDRAWAL_PENALTY_RATE, penaltyRate)
	)

	-- round to three decimal places to avoid floating point precision loss with small numbers
	penaltyRate = utils.roundToPrecision(penaltyRate, 3)

	local expeditedWithdrawalFee = math.floor(stake * penaltyRate)
	local amountToWithdraw = stake - expeditedWithdrawalFee

	-- Withdraw the tokens to the delegate and the protocol balance
	balances.increaseBalance(ao.id, expeditedWithdrawalFee)
	balances.increaseBalance(from, amountToWithdraw)

	return expeditedWithdrawalFee, amountToWithdraw, penaltyRate
end

function gar.decreaseOperatorStake(from, qty, currentTimestamp, msgId, instantWithdraw)
	assert(type(qty) == "number", "Quantity is required and must be a number")
	assert(qty > 0, "Quantity must be greater than 0")

	local gateway = gar.getGateway(from)

	if not gateway then
		error("Gateway not found")
	end

	if gateway.status == "leaving" then
		error("Gateway is leaving the network and cannot withdraw more stake.")
	end

	local maxWithdraw = gateway.operatorStake - gar.getSettings().operators.minStake

	if qty > maxWithdraw then
		return error(
			"Resulting stake is not enough to maintain the minimum operator stake of "
				.. gar.getSettings().operators.minStake
				.. " IO"
		)
	end
	gateway.operatorStake = gateway.operatorStake - qty

	local expeditedWithdrawalFee = 0
	local amountToWithdraw = 0
	local penaltyRate = 0
	if instantWithdraw == true then
		-- Calculate the penalty and withdraw using the utility function
		expeditedWithdrawalFee, amountToWithdraw, penaltyRate = processInstantWithdrawal(qty, 0, 0, from)
	else
		gateway.vaults[msgId] = {
			balance = qty,
			startTimestamp = currentTimestamp,
			endTimestamp = currentTimestamp + gar.getSettings().operators.withdrawLengthMs,
		}
	end

	-- Update the gateway
	GatewayRegistry[from] = gateway

	return {
		gateway = gateway,
		penaltyRate = penaltyRate,
		expeditedWithdrawalFee = expeditedWithdrawalFee,
		amountWithdrawn = amountToWithdraw,
	}
end

function gar.updateGatewaySettings(from, updatedSettings, updatedServices, observerAddress, currentTimestamp, msgId)
	local gateway = gar.getGateway(from)

	if not gateway then
		error("Gateway not found")
	end

	if gateway.status == "leaving" then
		error("Gateway is leaving the network and cannot be updated")
	end

	gar.assertValidGatewayParameters(from, gateway.operatorStake, updatedSettings, updatedServices, observerAddress)

	if
		updatedSettings.minDelegatedStake
		and updatedSettings.minDelegatedStake < gar.getSettings().delegates.minStake
	then
		error("The minimum delegated stake must be at least " .. gar.getSettings().operators.minStake .. " IO")
	end

	for gatewayAddress, existingGateway in pairs(gar.getGatewaysUnsafe()) do
		if existingGateway.observerAddress == observerAddress and gatewayAddress ~= from then
			error("Invalid observer wallet. The provided observer wallet is correlated with another gateway.")
		end
	end

	-- update the allow list first if necessary since we may need it for accounting in any subsequent delegate kicks
	if updatedSettings.allowDelegatedStaking and updatedSettings.allowedDelegates then
		-- Replace the existing lookup table
		updatedSettings.allowedDelegatesLookup = utils.createLookupTable(updatedSettings.allowedDelegates)
		updatedSettings.allowedDelegates = nil -- no longer need the list now that lookup is built

		-- remove any delegates that are not in the allowlist
		for delegateAddress, delegate in pairs(gateway.delegates) do
			if updatedSettings.allowedDelegatesLookup[delegateAddress] then
				if delegate.delegatedStake > 0 then
					-- remove the delegate from the lookup since it's adequately tracked as a delegate already
					updatedSettings.allowedDelegatesLookup[delegateAddress] = nil
				end
			elseif delegate.delegatedStake > 0 then
				gar.kickDelegateFromGateway(delegateAddress, gateway, msgId, currentTimestamp)
			end
			-- else: the delegate was exiting already with 0-balance and will no longer be on the allowlist
		end
	end

	if not updatedSettings.allowDelegatedStaking then
		-- Add tokens from each delegate to a vault that unlocks after the delegate withdrawal period ends
		if next(gateway.delegates) ~= nil then -- staking disabled and delegates must go
			for address, _ in pairs(gateway.delegates) do
				gar.kickDelegateFromGateway(address, gateway, msgId, currentTimestamp)
			end
		end

		-- clear the allowedDelegatesLookup since we no longer need it
		updatedSettings.allowedDelegatesLookup = nil
	end

	-- if allowDelegateStaking is currently false, and you want to set it to true - you have to wait until all the vaults have been returned
	if
		updatedSettings.allowDelegatedStaking == true
		and gateway.settings.allowDelegatedStaking == false
		and next(gateway.delegates) ~= nil
	then -- checks if the delegates table is not empty
		error("You cannot enable delegated staking until all delegated stakes have been withdrawn.")
	end

	gateway.settings = updatedSettings
	if updatedServices then
		gateway.services = updatedServices
	end
	if observerAddress then
		gateway.observerAddress = observerAddress
	end
	-- update the gateway on the global state
	GatewayRegistry[from] = gateway
	return gateway
end

--- Gets a gateway by address
---@param address string The address to get the gateway for
---@return table|nil The gateway object or nil if not found
function gar.getGateway(address)
	return utils.deepCopy(GatewayRegistry[address])
end

function gar.getGatewayUnsafe(address)
	return GatewayRegistry[address]
end

-- TODO: Add a getGatewaysProps function that omits lots of heavy data like vaults and delegates
--- Gets all gateways
---@return table All gateway objects
function gar.getGateways()
	local gateways = utils.deepCopy(GatewayRegistry)
	return gateways or {}
end

function gar.getGatewaysUnsafe()
	return GatewayRegistry or {}
end

function gar.delegateStake(from, target, qty, currentTimestamp)
	assert(type(qty) == "number", "Quantity is required and must be a number")
	assert(qty > 0, "Quantity must be greater than 0")
	assert(type(target) == "string", "Target is required and must be a string")
	assert(type(from) == "string", "From is required and must be a string")

	local gateway = gar.getGateway(target)
	if not gateway then
		error("Gateway not found")
	end

	-- don't allow delegating to yourself
	if from == target then
		error("Cannot delegate to your own gateway, use increaseOperatorStake instead.")
	end

	if not balances.walletHasSufficientBalance(from, qty) then
		error("Insufficient balance")
	end

	if gateway.status == "leaving" then
		error("This Gateway is in the process of leaving the network and cannot have more stake delegated to it.")
	end

	if not gateway.settings.allowDelegatedStaking then
		error(
			"This Gateway does not allow delegated staking. Only allowed delegates can delegate stake to this Gateway."
		)
	end

	if not gar.delegateAllowedToStake(from, gateway) then
		error("This Gateway does not allow this delegate to stake.")
	end

	-- Assuming `gateway` is a table and `fromAddress` is defined
	local existingDelegate = gateway.delegates[from]
	local minimumStakeForGatewayAndDelegate
	-- if it is not an auto stake provided by the protocol, then we need to validate the stake amount meets the gateway's minDelegatedStake
	if existingDelegate and existingDelegate.delegatedStake ~= 0 then
		-- It already has a stake that is not zero
		minimumStakeForGatewayAndDelegate = 1 -- Delegate must provide at least one additional IO
	else
		-- Consider if the operator increases the minimum amount after you've already staked
		minimumStakeForGatewayAndDelegate = gateway.settings.minDelegatedStake
	end
	if qty < minimumStakeForGatewayAndDelegate then
		error("Quantity must be greater than the minimum delegated stake amount.")
	end

	-- If this delegate has staked before, update its amount, if not, create a new delegated staker
	if existingDelegate == nil then
		-- create the new delegate stake
		gateway.delegates[from] = {
			delegatedStake = qty,
			startTimestamp = currentTimestamp,
			vaults = {},
		}
	else
		-- increment the existing delegate's stake
		gateway.delegates[from].delegatedStake = gateway.delegates[from].delegatedStake + qty
	end
	-- Decrement the user's balance
	balances.reduceBalance(from, qty)
	gateway.totalDelegatedStake = gateway.totalDelegatedStake + qty

	-- prune user from allow list, if necessary, to save memory
	if gateway.settings.allowedDelegatesLookup then
		gateway.settings.allowedDelegatesLookup[from] = nil
	end

	-- update the gateway
	GatewayRegistry[target] = gateway
	return gateway
end

--- Internal function to increase the stake of an existing delegate. This should only be called from epochs.lua
---@param gatewayAddress string # The gateway address to increase stake for (required)
---@param gateway table # The gateway object to increase stake for (required)
---@param delegateAddress string # The address of the delegate to increase stake for (required)
---@param qty number # The amount of stake to increase by - must be positive integer (required)
function gar.increaseExistingDelegateStake(gatewayAddress, gateway, delegateAddress, qty)
	if not gateway then
		error("Gateway not found")
	end

	if not delegateAddress then
		error("Delegate address is required")
	end

	if not qty or not utils.isInteger(qty) or qty <= 0 then
		error("Quantity is required and must be an integer greater than 0: " .. qty)
	end

	local delegate = gateway.delegates[delegateAddress]
	if not delegate then
		error("Delegate not found")
	end

	-- consider case where delegate has been kicked from the gateway and has vaulted stake
	if not gar.delegateAllowedToStake(delegateAddress, gateway) then
		error("This Gateway does not allow this delegate to stake.")
	end

	gateway.delegates[delegateAddress].delegatedStake = delegate.delegatedStake + qty
	gateway.totalDelegatedStake = gateway.totalDelegatedStake + qty
	GatewayRegistry[gatewayAddress] = gateway
	return gateway
end

function gar.getSettings()
	return utils.deepCopy(GatewayRegistrySettings)
end

function gar.decreaseDelegateStake(gatewayAddress, delegator, qty, currentTimestamp, messageId, instantWithdraw)
	assert(type(qty) == "number", "Quantity is required and must be a number")
	assert(qty > 0, "Quantity must be greater than 0")

	local gateway = gar.getGateway(gatewayAddress)

	if not gateway then
		error("Gateway not found")
	end
	if gateway.status == "leaving" then
		error("Gateway is leaving the network and cannot withdraw more stake.")
	end

	if gateway.delegates[delegator] == nil then
		error("This delegate is not staked at this gateway.")
	end

	local existingStake = gateway.delegates[delegator].delegatedStake
	local requiredMinimumStake = gateway.settings.minDelegatedStake
	local maxAllowedToWithdraw = existingStake - requiredMinimumStake
	if maxAllowedToWithdraw < qty and qty ~= existingStake then
		error(
			"Remaining delegated stake must be greater than the minimum delegated stake. Adjust the amount or withdraw all stake."
		)
	end

	-- Instant withdrawal logic with penalty
	local expeditedWithdrawalFee = 0
	local amountToWithdraw = 0
	local penaltyRate = 0
	if instantWithdraw == true then
		-- Unlock the tokens from the gateway and delegate
		gateway.delegates[delegator].delegatedStake = gateway.delegates[delegator].delegatedStake - qty
		gateway.totalDelegatedStake = gateway.totalDelegatedStake - qty

		-- Calculate the penalty and withdraw using the utility function and move the balances
		expeditedWithdrawalFee, amountToWithdraw, penaltyRate = processInstantWithdrawal(qty, 0, 0, delegator)

		-- Remove the delegate if no stake is left in its balance or vaults
		if gateway.delegates[delegator].delegatedStake == 0 and next(gateway.delegates[delegator].vaults) == nil then
			gar.pruneDelegateFromGateway(delegator, gateway)
		end
	else
		-- Withdraw the delegate's stake
		local newDelegateVault = {
			balance = qty,
			startTimestamp = currentTimestamp,
			endTimestamp = currentTimestamp + gar.getSettings().delegates.withdrawLengthMs,
		}

		-- Lock the qty in a vault to be unlocked after withdrawal period and decrease the gateway's total delegated stake
		gateway.delegates[delegator].vaults[messageId] = newDelegateVault
		gateway.delegates[delegator].delegatedStake = gateway.delegates[delegator].delegatedStake - qty
		gateway.totalDelegatedStake = gateway.totalDelegatedStake - qty
	end

	-- update the gateway
	GatewayRegistry[gatewayAddress] = gateway
	return {
		gateway = gateway,
		penaltyRate = penaltyRate,
		expeditedWithdrawalFee = expeditedWithdrawalFee,
		amountWithdrawn = amountToWithdraw,
	}
end

function gar.isGatewayLeaving(gateway)
	return gateway.status == "leaving"
end

function gar.isGatewayEligibleToLeave(gateway, timestamp)
	if not gateway then
		error("Gateway not found")
	end
	local isJoined = gar.isGatewayJoined(gateway, timestamp)
	return isJoined
end

function gar.isGatewayActiveBeforeTimestamp(startTimestamp, gateway)
	local didStartBeforeEpoch = gateway.startTimestamp <= startTimestamp
	local isNotLeaving = not gar.isGatewayLeaving(gateway)
	return didStartBeforeEpoch and isNotLeaving
end

function gar.getActiveGatewaysBeforeTimestamp(startTimestamp)
	local activeGatewayAddresses = {}
	-- use pairs as gateways is a map
	for address, gateway in pairs(gar.getGatewaysUnsafe()) do
		if gar.isGatewayActiveBeforeTimestamp(startTimestamp, gateway) then
			table.insert(activeGatewayAddresses, address)
		end
	end
	return activeGatewayAddresses
end

function gar.getGatewayWeightsAtTimestamp(gatewayAddresses, timestamp)
	local weightedObservers = {}
	local totalCompositeWeight = 0

	-- Iterate over gateways to calculate weights
	for _, address in pairs(gatewayAddresses) do
		local gateway = gar.getGateway(address)
		if gateway then
			local totalStake = gateway.operatorStake + gateway.totalDelegatedStake -- 100 - no cap to this
			local stakeWeightRatio = totalStake / gar.getSettings().operators.minStake -- this is always greater than 1 as the minOperatorStake is always less than the stake
			-- the percentage of the epoch the gateway was joined for before this epoch, if the gateway starts in the future this will be 0
			local gatewayStartTimestamp = gateway.startTimestamp
			local totalTimeForGateway = timestamp >= gatewayStartTimestamp and (timestamp - gatewayStartTimestamp) or -1
			-- TODO: should we increment by one here or are observers that join at the epoch start not eligible to be selected as an observer

			local calculatedTenureWeightForGateway = totalTimeForGateway < 0 and 0
				or (
					totalTimeForGateway > 0 and totalTimeForGateway / gar.getSettings().observers.tenureWeightPeriod
					or 1 / gar.getSettings().observers.tenureWeightPeriod
				)
			local gatewayTenureWeight =
				math.min(calculatedTenureWeightForGateway, gar.getSettings().observers.maxTenureWeight)

			local totalEpochsGatewayPassed = gateway.stats.passedEpochCount or 0
			local totalEpochsParticipatedIn = gateway.stats.totalEpochCount or 0
			local gatewayRewardRatioWeight = (1 + totalEpochsGatewayPassed) / (1 + totalEpochsParticipatedIn)
			local totalEpochsPrescribed = gateway.stats.prescribedEpochCount or 0
			local totalEpochsSubmitted = gateway.stats.observedEpochCount or 0
			local observerRewardRatioWeight = (1 + totalEpochsSubmitted) / (1 + totalEpochsPrescribed)

			local compositeWeight = stakeWeightRatio
				* gatewayTenureWeight
				* gatewayRewardRatioWeight
				* observerRewardRatioWeight

			table.insert(weightedObservers, {
				gatewayAddress = address,
				observerAddress = gateway.observerAddress,
				stake = totalStake,
				startTimestamp = gateway.startTimestamp,
				stakeWeight = stakeWeightRatio,
				tenureWeight = gatewayTenureWeight,
				gatewayRewardRatioWeight = gatewayRewardRatioWeight,
				observerRewardRatioWeight = observerRewardRatioWeight,
				compositeWeight = compositeWeight,
				normalizedCompositeWeight = nil, -- set later once we have the total composite weight
			})

			totalCompositeWeight = totalCompositeWeight + compositeWeight
		end
	end

	-- Calculate the normalized composite weight for each observer
	for _, weightedObserver in pairs(weightedObservers) do
		if totalCompositeWeight > 0 then
			weightedObserver.normalizedCompositeWeight = weightedObserver.compositeWeight / totalCompositeWeight
		else
			weightedObserver.normalizedCompositeWeight = 0
		end
	end
	return weightedObservers
end

function gar.isGatewayJoined(gateway, currentTimestamp)
	return gateway.status == "joined" and gateway.startTimestamp <= currentTimestamp
end

function gar.assertValidGatewayParameters(from, stake, settings, services, observerAddress)
	assert(type(from) == "string", "from is required and must be a string")
	assert(type(stake) == "number", "stake is required and must be a number")
	assert(type(settings) == "table", "settings is required and must be a table")
	assert(
		type(observerAddress) == "string" and utils.isValidAOAddress(observerAddress),
		"Observer-Address is required and must be a a valid arweave address"
	)
	assert(type(settings.allowDelegatedStaking) == "boolean", "allowDelegatedStaking must be a boolean")
	if type(settings.allowedDelegates) == "table" then
		for _, delegate in ipairs(settings.allowedDelegates) do
			assert(utils.isValidAOAddress(delegate), "delegates in allowedDelegates must be valid AO addresses")
		end
	else
		assert(
			settings.allowedDelegates == nil,
			"allowedDelegates must be a table parsed from a comma-separated string or nil"
		)
	end

	assert(type(settings.label) == "string", "label is required and must be a string")
	assert(type(settings.fqdn) == "string", "fqdn is required and must be a string")
	assert(
		type(settings.protocol) == "string" and settings.protocol == "https",
		"protocol is required and must be https"
	)
	assert(
		type(settings.port) == "number"
			and utils.isInteger(settings.port)
			and settings.port >= 0
			and settings.port <= 65535,
		"port is required and must be an integer between 0 and 65535"
	)
	assert(
		type(settings.properties) == "string" and utils.isValidArweaveAddress(settings.properties),
		"properties is required and must be a string"
	)
	assert(
		stake >= gar.getSettings().operators.minStake,
		"Operator stake must be greater than the minimum stake to join the network"
	)
	if settings.delegateRewardShareRatio ~= nil then
		assert(
			type(settings.delegateRewardShareRatio) == "number"
				and utils.isInteger(settings.delegateRewardShareRatio)
				and settings.delegateRewardShareRatio >= 0
				and settings.delegateRewardShareRatio <= 100,
			"delegateRewardShareRatio must be an integer between 0 and 100"
		)
	end
	if settings.autoStake ~= nil then
		assert(type(settings.autoStake) == "boolean", "autoStake must be a boolean")
	end
	if settings.properties ~= nil then
		assert(type(settings.properties) == "string", "properties must be a table")
	end
	if settings.minDelegatedStake ~= nil then
		assert(
			type(settings.minDelegatedStake) == "number"
				and utils.isInteger(settings.minDelegatedStake)
				and settings.minDelegatedStake >= gar.getSettings().delegates.minStake,
			"minDelegatedStake must be an integer greater than or equal to the minimum delegated stake"
		)
	end

	if services ~= nil then
		assert(type(services) == "table", "services must be a table")

		local allowedServiceKeys = { bundlers = true }
		for key, _ in pairs(services) do
			assert(allowedServiceKeys[key], "services contains an invalid key: " .. tostring(key))
		end

		if services.bundlers ~= nil then
			assert(type(services.bundlers) == "table", "services.bundlers must be a table")

			assert(utils.lengthOfTable(services.bundlers) <= 20, "No more than 20 bundlers allowed")

			for _, bundler in ipairs(services.bundlers) do
				local allowedBundlerKeys = { fqdn = true, port = true, protocol = true, path = true }
				for key, _ in pairs(bundler) do
					assert(allowedBundlerKeys[key], "bundler contains an invalid key: " .. tostring(key))
				end
				assert(type(bundler.fqdn) == "string", "bundler.fqdn is required and must be a string")
				assert(
					type(bundler.port) == "number"
						and utils.isInteger(bundler.port)
						and bundler.port >= 0
						and bundler.port <= 65535,
					"bundler.port must be an integer between 0 and 65535"
				)
				assert(
					type(bundler.protocol) == "string" and bundler.protocol == "https",
					"bundler.protocol is required and must be 'https'"
				)
				assert(type(bundler.path) == "string", "bundler.path is required and must be a string")
			end
		end
	end
end

--- Updates the stats for a gateway
---@param address string # The address of the gateway to update stats for
---@param gateway table # The gateway object to update stats for
---@param stats table # The stats to update the gateway with
function gar.updateGatewayStats(address, gateway, stats)
	if gateway == nil then
		error("Gateway not found")
	end

	assert(stats.prescribedEpochCount, "prescribedEpochCount is required")
	assert(stats.observedEpochCount, "observedEpochCount is required")
	assert(stats.totalEpochCount, "totalEpochCount is required")
	assert(stats.passedEpochCount, "passedEpochCount is required")
	assert(stats.failedEpochCount, "failedEpochCount is required")
	assert(stats.failedConsecutiveEpochs, "failedConsecutiveEpochs is required")
	assert(stats.passedConsecutiveEpochs, "passedConsecutiveEpochs is required")

	gateway.stats = stats
	GatewayRegistry[address] = gateway
	return gateway
end

function gar.updateGatewayWeights(weightedGateway)
	local address = weightedGateway.gatewayAddress
	local gateway = gar.getGateway(address)
	if gateway == nil then
		error("Gateway not found")
	end

	assert(weightedGateway.stakeWeight, "stakeWeight is required")
	assert(weightedGateway.tenureWeight, "tenureWeight is required")
	assert(weightedGateway.gatewayRewardRatioWeight, "gatewayRewardRatioWeight is required")
	assert(weightedGateway.observerRewardRatioWeight, "observerRewardRatioWeight is required")
	assert(weightedGateway.compositeWeight, "compositeWeight is required")
	assert(weightedGateway.normalizedCompositeWeight, "normalizedCompositeWeight is required")

	gateway.weights = {
		stakeWeight = weightedGateway.stakeWeight,
		tenureWeight = weightedGateway.tenureWeight,
		gatewayRewardRatioWeight = weightedGateway.gatewayRewardRatioWeight,
		observerRewardRatioWeight = weightedGateway.observerRewardRatioWeight,
		compositeWeight = weightedGateway.compositeWeight,
		normalizedCompositeWeight = weightedGateway.normalizedCompositeWeight,
	}
	GatewayRegistry[address] = gateway
end

function gar.addGateway(address, gateway)
	GatewayRegistry[address] = gateway
	return gateway
end

-- for test purposes
function gar.updateSettings(newSettings)
	GatewayRegistrySettings = newSettings
end

function gar.pruneGateways(currentTimestamp, msgId)
	local gateways = gar.getGateways()
	local garSettings = gar.getSettings()
	local result = {
		prunedGateways = {},
		slashedGateways = {},
		gatewayStakeReturned = 0,
		delegateStakeReturned = 0,
		gatewayStakeWithdrawing = 0,
		delegateStakeWithdrawing = 0,
		stakeSlashed = 0,
	}

	if next(gateways) == nil then
		return result
	end

	-- we take a deep copy so we can operate directly on the gateway object
	for address, gateway in pairs(gateways) do
		if gateway then
			-- first, return any expired vaults regardless of the gateway status
			for vaultId, vault in pairs(gateway.vaults) do
				if vault.endTimestamp <= currentTimestamp then
					balances.increaseBalance(address, vault.balance)
					result.gatewayStakeReturned = result.gatewayStakeReturned + vault.balance
					gateway.vaults[vaultId] = nil
				end
			end
			-- return any delegated vaults and return the stake to the delegate
			for delegateAddress, delegate in pairs(gateway.delegates) do
				for vaultId, vault in pairs(delegate.vaults) do
					if vault.endTimestamp <= currentTimestamp then
						balances.increaseBalance(delegateAddress, vault.balance)
						result.delegateStakeReturned = result.delegateStakeReturned + vault.balance
						delegate.vaults[vaultId] = nil
					end
				end
			end
			-- remove the delegate if all vaults are empty and the delegated stake is 0
			for delegateAddress, delegate in pairs(gateway.delegates) do
				if delegate.delegatedStake == 0 and next(delegate.vaults) == nil then
					-- any allowlist reassignment would have already taken place by now
					gateway.delegates[delegateAddress] = nil
				end
			end
			-- update the gateway before we do anything else
			GatewayRegistry[address] = gateway

			-- if gateway is joined but failed more than 30 consecutive epochs, mark it as leaving and put operator stake and delegate stakes in vaults
			if
				gateway.status == "joined"
				and garSettings ~= nil
				and gateway.stats.failedConsecutiveEpochs >= garSettings.operators.failedEpochCountMax
			then
				-- slash 20% of the minimum operator stake and return the rest to the protocol balance, then mark the gateway as leaving
				local slashableOperatorStake = math.min(gateway.operatorStake, garSettings.operators.minStake)
				local slashAmount =
					math.floor(slashableOperatorStake * garSettings.operators.failedEpochSlashPercentage)
				result.delegateStakeWithdrawing = result.delegateStakeWithdrawing + gateway.totalDelegatedStake
				result.gatewayStakeWithdrawing = result.gatewayStakeWithdrawing + (gateway.operatorStake - slashAmount)
				gar.slashOperatorStake(address, slashAmount, currentTimestamp)
				gar.leaveNetwork(address, currentTimestamp, msgId)
				result.slashedGateways[address] = slashAmount
				result.stakeSlashed = result.stakeSlashed + slashAmount
			else
				if gateway.status == "leaving" and gateway.endTimestamp <= currentTimestamp then
					-- if the timestamp is after gateway end timestamp, mark the gateway as nil
					GatewayRegistry[address] = nil
					table.insert(result.prunedGateways, address)
				end
			end
		end
	end
	return result
end

function gar.slashOperatorStake(address, slashAmount, currentTimestamp)
	assert(utils.isInteger(slashAmount), "Slash amount must be an integer")
	assert(slashAmount > 0, "Slash amount must be greater than 0")

	local gateway = gar.getGateway(address)
	if gateway == nil then
		error("Gateway not found")
	end
	local garSettings = gar.getSettings()
	if garSettings == nil then
		error("Gateway Registry settings do not exist")
	end

	gateway.operatorStake = gateway.operatorStake - slashAmount
	gateway.slashings = gateway.slashings or {}
	gateway.slashings[tostring(currentTimestamp)] = slashAmount
	balances.increaseBalance(ao.id, slashAmount)
	GatewayRegistry[address] = gateway
	-- TODO: send slash notice to gateway address
end

---@param cursor string|nil # The cursor gateway address after which to fetch more gateways (optional)
---@param limit number # The max number of gateways to fetch
---@param sortBy string # The gateway field to sort by. Default is "gatewayAddress" (which is added each time)
---@param sortOrder string # The order to sort by, either "asc" or "desc"
---@return table # A table containing the paginated gateways and pagination metadata
function gar.getPaginatedGateways(cursor, limit, sortBy, sortOrder)
	local gateways = gar.getGateways()
	local gatewaysArray = {}
	local cursorField = "gatewayAddress" -- the cursor will be the gateway address
	for address, record in pairs(gateways) do
		record.gatewayAddress = address
		-- TODO: remove delegates here to avoid sending an unbounded array; to fetch delegates, use getPaginatedDelegates
		table.insert(gatewaysArray, record)
	end

	return utils.paginateTableWithCursor(gatewaysArray, cursor, cursorField, limit, sortBy, sortOrder)
end

---@param address string # The address of the gateway
---@param cursor string|nil # The cursor delegate address after which to fetch more delegates (optional)
---@param limit number # The max number of delegates to fetch
---@param sortBy string # The delegate field to sort by. Default is "address" (which is added each)
---@param sortOrder string # The order to sort by, either "asc" or "desc"
---@return table # A table containing the paginated delegates and pagination metadata
function gar.getPaginatedDelegates(address, cursor, limit, sortBy, sortOrder)
	local gateway = gar.getGateway(address)
	if not gateway then
		error("Gateway not found")
	end
	local delegatesArray = {}
	local cursorField = "address"
	for delegateAddress, delegate in pairs(gateway.delegates) do
		delegate.address = delegateAddress
		table.insert(delegatesArray, delegate)
	end

	return utils.paginateTableWithCursor(delegatesArray, cursor, cursorField, limit, sortBy, sortOrder)
end

--- Returns all allowed delegates if allowlisting is in use. Empty table otherwise.
---@param address string # The address of the gateway
---@param cursor string|nil # The cursor delegate address after which to fetch more delegates (optional)
---@param limit number # The max number of delegates to fetch
---@param sortOrder string # The order to sort by, either "asc" or "desc"
---@return table # A table containing the paginated allowed delegates and pagination metadata
function gar.getPaginatedAllowedDelegates(address, cursor, limit, sortOrder)
	local gateway = gar.getGateway(address)
	if not gateway then
		error("Gateway not found")
	end
	local allowedDelegatesArray = {}

	if gateway.settings.allowedDelegatesLookup then
		for delegateAddress, _ in pairs(gateway.settings.allowedDelegatesLookup) do
			table.insert(allowedDelegatesArray, delegateAddress)
		end
		for delegateAddress, delegate in pairs(gateway.delegates) do
			if delegate.delegatedStake > 0 then
				table.insert(allowedDelegatesArray, delegateAddress)
			end
		end
	end

	local cursorField = nil
	local sortBy = nil
	return utils.paginateTableWithCursor(allowedDelegatesArray, cursor, cursorField, limit, sortBy, sortOrder)
end

function gar.cancelGatewayWithdrawal(from, gatewayAddress, vaultId)
	local gateway = gar.getGateway(gatewayAddress)
	if gateway == nil then
		error("Gateway not found")
	end

	if gateway.status == "leaving" then
		error("Gateway is leaving the network and cannot cancel withdrawals.")
	end

	local existingVault, delegate
	local isGatewayWithdrawal = from == gatewayAddress
	-- if the from matches the gateway address, we are cancelling the operator withdrawal
	if isGatewayWithdrawal then
		existingVault = gateway.vaults[vaultId]
	else
		delegate = gateway.delegates[from]
		if delegate == nil then
			error("Delegate not found")
		end
		existingVault = delegate.vaults[vaultId]
	end

	if existingVault == nil then
		error("Vault not found for " .. from .. " on " .. gatewayAddress)
	end

	-- confirm the gateway still allow staking
	if not isGatewayWithdrawal and not gateway.settings.allowDelegatedStaking then
		error("Gateway does not allow staking")
	end

	local previousOperatorStake = gateway.operatorStake
	local previousTotalDelegatedStake = gateway.totalDelegatedStake
	local vaultBalance = existingVault.balance
	if isGatewayWithdrawal then
		gateway.vaults[vaultId] = nil
		gateway.operatorStake = gateway.operatorStake + vaultBalance
	else
		if not gar.delegateAllowedToStake(from, gateway) then
			error("This Gateway does not allow this delegate to stake.")
		end
		delegate.vaults[vaultId] = nil
		delegate.delegatedStake = delegate.delegatedStake + vaultBalance
		gateway.totalDelegatedStake = gateway.totalDelegatedStake + vaultBalance
	end
	GatewayRegistry[gatewayAddress] = gateway
	return {
		previousOperatorStake = previousOperatorStake,
		previousTotalDelegatedStake = previousTotalDelegatedStake,
		totalOperatorStake = gateway.operatorStake,
		totalDelegatedStake = gateway.totalDelegatedStake,
		vaultBalance = vaultBalance,
		gateway = gateway,
	}
end

---@param from string # The address of the operator or delegate
---@param gatewayAddress string # The address of the gateway
---@param vaultId string # The id of the vault
---@param currentTimestamp number # The current timestamp
---@return table # A table containing the gateway, elapsed time, remaining time, penalty rate, expedited withdrawal fee, and amount withdrawn
function gar.instantGatewayWithdrawal(from, gatewayAddress, vaultId, currentTimestamp)
	local gateway = gar.getGateway(gatewayAddress)
	if gateway == nil then
		error("Gateway not found")
	end

	local isGatewayWithdrawal = from == gatewayAddress

	if isGatewayWithdrawal and gateway.status == "leaving" then
		error("This gateway is leaving and this vault cannot be instantly withdrawn.")
	end

	local vault
	local delegate
	if isGatewayWithdrawal then
		vault = gateway.vaults[vaultId]
	else
		delegate = gateway.delegates[from]
		if delegate == nil then
			error("Delegate not found")
		end
		vault = delegate.vaults[vaultId]
	end
	if vault == nil then
		error("Vault not found")
	end

	---@type number
	local elapsedTime = currentTimestamp - vault.startTimestamp
	---@type number
	local totalWithdrawalTime = vault.endTimestamp - vault.startTimestamp

	-- Ensure the elapsed time is not negative
	if elapsedTime < 0 then
		error("Invalid elapsed time")
	end

	-- Process the instant withdrawal
	local expeditedWithdrawalFee, amountToWithdraw, penaltyRate =
		processInstantWithdrawal(vault.balance, elapsedTime, totalWithdrawalTime, from)

	-- Remove the vault after withdrawal
	if isGatewayWithdrawal then
		gateway.vaults[vaultId] = nil
	else
		if delegate == nil then
			error("Delegate not found")
		end
		delegate.vaults[vaultId] = nil
		-- Remove the delegate if no stake is left
		if delegate.delegatedStake == 0 and next(delegate.vaults) == nil then
			gar.pruneDelegateFromGateway(from, gateway)
		end
	end

	-- Update the gateway
	GatewayRegistry[gatewayAddress] = gateway
	return {
		gateway = gateway,
		elapsedTime = elapsedTime,
		remainingTime = totalWithdrawalTime - elapsedTime,
		penaltyRate = penaltyRate,
		expeditedWithdrawalFee = expeditedWithdrawalFee,
		amountWithdrawn = amountToWithdraw,
	}
end

--- Preserves delegate's position in allow list upon removal from gateway
--- @param delegateAddress string The address of the delegator
--- @param gateway table The gateway from which the delegate is being removed
function gar.pruneDelegateFromGateway(delegateAddress, gateway)
	gateway.delegates[delegateAddress] = nil

	-- replace the delegate in the allowedDelegatesLookup table if necessary
	if gateway.settings.allowedDelegatesLookup then
		gateway.settings.allowedDelegatesLookup[delegateAddress] = true
	end
end

--- Add delegate addresses to the allowedDelegatesLookup table in the gateway's settings
--- @param delegates table The list of delegate addresses to add
--- @param gatewayAddress string The address of the gateway
--- @return table result Result table containing updated gateway object and the delegates that were actually added
function gar.allowDelegates(delegates, gatewayAddress)
	local gateway = gar.getGateway(gatewayAddress)
	if gateway == nil then
		error("Gateway not found")
	end

	-- Only allow modification of the allow list when allowDelegatedStaking is set to false or a current allow list is in place
	if gateway.settings.allowDelegatedStaking == true and not gateway.settings.allowedDelegatesLookup then
		error("Allow listing only possible when allowDelegatedStaking is set to 'allowlist'")
	end

	assert(gateway.settings.allowedDelegatesLookup, "allowedDelegatesLookup should not be nil")

	local addedDelegates = {}
	for _, delegateAddress in ipairs(delegates) do
		if not utils.isValidAOAddress(delegateAddress) then
			error("Invalid delegate address: " .. delegateAddress)
		end

		-- Skip over delegates that are already in the allow list or that have a stake balance
		if not gar.delegateAllowedToStake(delegateAddress, gateway) then
			gateway.settings.allowedDelegatesLookup[delegateAddress] = true
			table.insert(addedDelegates, delegateAddress)
		end
	end

	GatewayRegistry[gatewayAddress] = gateway
	return {
		gateway = gateway,
		addedDelegates = addedDelegates,
	}
end

function gar.isEligibleForArNSDiscount(from)
	local gateway = gar.getGatewayUnsafe(from)
	if gateway == nil or gateway.weights == nil or gar.isGatewayLeaving(gateway) then
		return false
	end

	local tenureWeight = gateway.weights.tenureWeight or 0
	local gatewayPerformanceRatio = gateway.weights.gatewayRewardRatioWeight or 0

	return tenureWeight >= constants.ARNS_DISCOUNT_TENURE_WEIGHT_ELIGIBILITY_THRESHOLD
		and gatewayPerformanceRatio >= constants.ARNS_DISCOUNT_GATEWAY_PERFORMANCE_RATIO_ELIGIBILITY_THRESHOLD
end

--- Remove delegate addresses from the allowedDelegatesLookup table in the gateway's settings
--- @param delegates table The list of delegate addresses to remove
--- @param gatewayAddress string The address of the gateway
--- @param msgId string The associated message ID
--- @param currentTimestamp number The current timestamp
--- @return table result Result table containing updated gateway object and the delegates that were actually removed
function gar.disallowDelegates(delegates, gatewayAddress, msgId, currentTimestamp)
	local gateway = gar.getGateway(gatewayAddress)
	if gateway == nil then
		error("Gateway not found")
	end

	-- Only allow modification of the allow list when allowDelegatedStaking is set to false or a current allow list is in place
	if gateway.settings.allowDelegatedStaking == true or not gateway.settings.allowedDelegatesLookup then
		error("Allow listing only possible when allowDelegatedStaking is set to 'allowlist'")
	end

	assert(gateway.settings.allowedDelegatesLookup, "allowedDelegatesLookup should not be nil")

	local removedDelegates = {}
	for _, delegateToDisallow in ipairs(delegates) do
		if not utils.isValidAOAddress(delegateToDisallow) then
			error("Invalid delegate address: " .. delegateToDisallow)
		end

		-- Skip over delegates that are not in the allow list
		if gateway.settings.allowedDelegatesLookup[delegateToDisallow] then
			gateway.settings.allowedDelegatesLookup[delegateToDisallow] = nil
			table.insert(removedDelegates, delegateToDisallow)
		end
		-- Kick the delegate off the gateway if necessary
		local ban = true
		gar.kickDelegateFromGateway(delegateToDisallow, gateway, msgId, currentTimestamp, ban)
	end

	GatewayRegistry[gatewayAddress] = gateway
	return {
		gateway = gateway,
		removedDelegates = removedDelegates,
	}
end

--- Vaults delegate's tokens and updates delegate and gateway staking balances
function gar.kickDelegateFromGateway(delegateAddress, gateway, msgId, currentTimestamp, ban)
	local delegate = gateway.delegates[delegateAddress]
	if not delegate then
		return
	end

	if not delegate.vaults then
		delegate.vaults = {}
	end

	if delegate.delegatedStake > 0 then
		delegate.vaults[msgId] = {
			balance = delegate.delegatedStake,
			startTimestamp = currentTimestamp,
			endTimestamp = currentTimestamp + gar.getSettings().delegates.withdrawLengthMs,
		}
		-- reduce gateway stake and set this delegate stake to 0
		gateway.totalDelegatedStake = gateway.totalDelegatedStake - delegate.delegatedStake
		delegate.delegatedStake = 0
	end

	if not ban and gar.delegationAllowlistedOnGateway(gateway) then
		gateway.settings.allowedDelegatesLookup[delegateAddress] = true
	end
end

function gar.delegationAllowlistedOnGateway(gateway)
	return gateway.settings.allowedDelegatesLookup ~= nil
end

function gar.delegateAllowedToStake(delegateAddress, gateway)
	if not gar.delegationAllowlistedOnGateway(gateway) then
		return true
	end
	-- Delegate must either be in the allow list or have a balance greater than 0
	return gateway.settings.allowedDelegatesLookup[delegateAddress]
		or (gateway.delegates[delegateAddress] and gateway.delegates[delegateAddress].delegatedStake or 0) > 0
end

function gar.getFundingPlan(address, quantity, sourcesPreference)
	sourcesPreference = sourcesPreference or "balance"
	local fundingPlan = {
		address = address,
		balance = 0,
		stakes = {},
		shortfall = quantity,
	}

	planBalanceDrawdown(fundingPlan, sourcesPreference)

	-- if the remaining quantity is 0 or there are no more sources, return early
	if fundingPlan.shortfall == 0 or sourcesPreference == "balance" then
		return fundingPlan
	end

	local gatewaysInfo = planExcessStakesDrawdown(fundingPlan)

	-- early return if possible. Otherwise we'll move on to use delegation vaults
	if fundingPlan.shortfall == 0 then
		return fundingPlan
	end

	planVaultsDrawdown(fundingPlan, gatewaysInfo)

	-- early return if possible. Otherwise we'll move on to using minimum stakes
	if fundingPlan.shortfall == 0 then
		return fundingPlan
	end

	planMinimumStakesDrawdown(fundingPlan, gatewaysInfo)

	return fundingPlan
end

function planBalanceDrawdown(fundingPlan, sourcesPreference)
	local availableBalance = balances.getBalance(fundingPlan.address)
	if sourcesPreference == "balance" or sourcesPreference == "any" then
		fundingPlan.balance = math.min(availableBalance, fundingPlan.shortfall)
		fundingPlan.shortfall = fundingPlan.shortfall - fundingPlan.balance
	end
end

function planExcessStakesDrawdown(fundingPlan)
	-- find all the address's delegations across the gateways
	local gatewaysInfo = utils.sortTableByFields(
		utils.reduce(
			-- only consider gateways that have the address as a delegate
			utils.filterDictionary(gar.getGatewaysUnsafe(), function(_, gateway)
				return gateway.delegates[fundingPlan.address] ~= nil
			end),
			-- extract only the essential gateway fields, copying tables so we don't mutate references
			function(acc, gatewayAddress, gateway)
				local totalEpochsGatewayPassed = gateway.stats.passedEpochCount or 0
				local totalEpochsParticipatedIn = gateway.stats.totalEpochCount or 0
				local gatewayRewardRatioWeight = (1 + totalEpochsGatewayPassed) / (1 + totalEpochsParticipatedIn)
				local delegate = utils.deepCopy(gateway.delegates[fundingPlan.address])
				delegate.excessStake = math.max(0, delegate.delegatedStake - gateway.settings.minDelegatedStake)
				delegate.gatewayAddress = gatewayAddress
				table.insert(acc, {
					totalDelegatedStake = gateway.totalDelegatedStake, -- for comparing gw total stake
					gatewayRewardRatioWeight = gatewayRewardRatioWeight, -- for comparing gw performance
					delegate = delegate,
					startTimestamp = gateway.startTimestamp, -- for comparing gw tenure
				})
				return acc
			end,
			{}
		),
		{
			{
				order = "desc",
				field = "delegate.excessStake",
			},
			{
				order = "asc",
				field = "gatewayRewardRatioWeight",
			},
			{
				order = "desc",
				field = "totalDelegatedStake",
			},
			{
				order = "desc",
				field = "startTimestamp",
			},
		}
	)

	-- simulate drawing down excess stakes until the remaining balance is satisfied OR excess stakes are exhausted
	for _, gatewayInfo in pairs(gatewaysInfo) do
		if fundingPlan.shortfall == 0 then
			break
		end
		local excessStake = gatewayInfo.delegate.excessStake
		local stakeToDraw = math.min(excessStake, fundingPlan.shortfall)
		fundingPlan["stakes"][gatewayInfo.delegate.gatewayAddress] = {
			delegatedStake = stakeToDraw,
			vaults = {}, -- set up vault spend tracking now while we're passing through
		}
		fundingPlan.shortfall = fundingPlan.shortfall - stakeToDraw
		gatewayInfo.delegate.delegatedStake = gatewayInfo.delegate.delegatedStake - stakeToDraw
		-- maintain consistency for future re-sorting of the gatewayInfos based on theoretical updated state
		gatewayInfo.delegate.excessStake = excessStake - stakeToDraw
		gatewayInfo.totalDelegatedStake = gatewayInfo.totalDelegatedStake - stakeToDraw
	end
	return gatewaysInfo
end

function planVaultsDrawdown(fundingPlan, gatewaysInfo)
	-- simulate drawing down vaults until the remaining balance is satisfied OR vaults are exhausted
	local vaults = utils.sortTableByFields(
		-- flatten the vaults across all gateways so we can sort them together
		utils.reduce(gatewaysInfo, function(acc, _, gatewayInfo)
			for vaultId, vault in pairs(gatewayInfo.delegate.vaults) do
				table.insert(acc, {
					vaultId = vaultId,
					gatewayAddress = gatewayInfo.delegate.gatewayAddress,
					endTimestamp = vault.endTimestamp,
					balance = vault.balance,
				})
			end
			return acc
		end, {}),
		{
			{
				order = "asc",
				field = "endTimestamp",
			},
		}
	)

	for _, vault in pairs(vaults) do
		if fundingPlan.shortfall == 0 then
			break
		end
		local balance = vault.balance
		local balanceToDraw = math.min(balance, fundingPlan.shortfall)
		local gatewayAddress = vault.gatewayAddress
		if not fundingPlan["stakes"][gatewayAddress] then
			fundingPlan["stakes"][gatewayAddress] = {
				delegatedStake = 0,
				vaults = {},
			}
		end
		fundingPlan["stakes"][gatewayAddress].vaults[vault.vaultId] = balanceToDraw
		fundingPlan.shortfall = fundingPlan.shortfall - balanceToDraw
		vault.balance = balance - balanceToDraw
	end
end

function planMinimumStakesDrawdown(fundingPlan, gatewaysInfo)
	-- re-sort the gateways since their totalDelegatedStakes may have changed
	gatewaysInfo = utils.sortTableByFields(gatewaysInfo, {
		{
			order = "asc",
			field = "gatewayRewardRatioWeight",
		},
		{
			order = "desc",
			field = "totalDelegatedStake",
		},
		{
			order = "desc",
			field = "startTimestamp",
		},
	})

	for _, gatewayInfo in pairs(gatewaysInfo) do
		if fundingPlan.shortfall == 0 then
			break
		end
		local stakeToDraw = math.min(gatewayInfo.delegate.delegatedStake, fundingPlan.shortfall)
		fundingPlan["stakes"][gatewayInfo.delegate.gatewayAddress].delegatedStake = fundingPlan["stakes"][gatewayInfo.delegate.gatewayAddress].delegatedStake
			+ stakeToDraw
		fundingPlan.shortfall = fundingPlan.shortfall - stakeToDraw
		-- not needed after this, but keep track
		gatewayInfo.delegate.delegatedStake = gatewayInfo.delegate.delegatedStake - stakeToDraw
		gatewayInfo.totalDelegatedStake = gatewayInfo.totalDelegatedStake - stakeToDraw
	end
end

-- TODO: return event-worthy data
--- Reduces all balances and creates withdraw stakes as prescribed by the funding plan
--- @param fundingPlan table The funding plan to apply
--- @param msgId string The current message ID
--- @param currentTimestamp number The current timestamp
function gar.applyFundingPlan(fundingPlan, msgId, currentTimestamp)
	local appliedPlan = {
		totalFunded = 0,
		newWithdrawVaults = {},
	}

	-- draw down balance first
	balances.reduceBalance(fundingPlan.address, fundingPlan.balance)
	appliedPlan.totalFunded = appliedPlan.totalFunded + fundingPlan.balance

	--draw down stakes and vaults, creating withdraw vaults if necessary
	for gatewayAddress, delegationPlan in pairs(fundingPlan.stakes) do
		local gateway = gar.getGateway(gatewayAddress)
		if not gateway then
			error("Gateway not found")
		end
		local delegate = gateway.delegates[fundingPlan.address]
		if not delegate then
			error("Delegate not found")
		end

		-- draw down the delegated stake balance
		delegate.delegatedStake = delegate.delegatedStake - delegationPlan.delegatedStake
		assert(delegate.delegatedStake >= 0, "Delegated stake cannot be negative")
		gateway.totalDelegatedStake = gateway.totalDelegatedStake - delegationPlan.delegatedStake
		assert(gateway.totalDelegatedStake >= 0, "Total delegated stake cannot be negative")
		appliedPlan.totalFunded = appliedPlan.totalFunded + delegationPlan.delegatedStake

		-- draw down the vaults
		delegate.vaults = utils.reduce(delegate.vaults, function(acc, vaultId, vault)
			if delegationPlan.vaults[vaultId] then
				-- if the whole vault is used, "prune" it by moving on
				if vault.balance ~= delegationPlan.vaults[vaultId] then
					acc[vaultId] = {
						balance = vault.balance - delegationPlan.vaults[vaultId],
						startTimestamp = vault.startTimestamp,
						endTimestamp = vault.endTimestamp,
					}
					assert(acc[vaultId].balance > 0, "Vault balance should be greater than 0")
				end
				appliedPlan.totalFunded = appliedPlan.totalFunded + delegationPlan.vaults[vaultId]
			else
				-- nothing to change
				acc[vaultId] = vault
			end
			return acc
		end, {})

		-- create an exit vault for the remaining stake if less than the gateway's minimum
		if delegate.delegatedStake > 0 and delegate.delegatedStake < gateway.settings.minDelegatedStake then
			-- create a vault for the remaining stake
			delegate.vaults[msgId] = {
				balance = delegate.delegatedStake,
				startTimestamp = currentTimestamp,
				endTimestamp = currentTimestamp + gar.getSettings().delegates.withdrawLengthMs,
			}
			gateway.totalDelegatedStake = gateway.totalDelegatedStake - delegate.delegatedStake
			delegate.delegatedStake = 0
			appliedPlan.newWithdrawVaults[gatewayAddress] = {
				[msgId] = utils.deepCopy(delegate.vaults[msgId]),
			}
		end

		-- TODO: ensure delegates with 0 stake and no vaults are pruned

		-- update the gateway
		GatewayRegistry[gatewayAddress] = gateway
	end

	return appliedPlan
end

--- Fetch copies of all the delegations present across all gateways for the given address
--- @param address string The address of the delegator
--- @return table # a table, indexed by gateway address, of all the address's delegations, including nested vaults
function gar.getDelegations(address)
	return utils.reduce(gar.getGatewaysUnsafe(), function(acc, gatewayAddress, gateway)
		if gateway.delegates[address] then
			acc[gatewayAddress] = utils.deepCopy(gateway.delegates[address])
		end
		return acc
	end, {})
end

---@class Delegation
---@field type string # The type of the object. Either "stake" or "vault"
---@field gatewayAddress string # The address of the gateway the delegation is associated with
---@field delegateStake number|nil # The amount of stake delegated to the gateway if type is "stake"
---@field startTimestamp number # The start timestamp of the delegation's initial stake or the vault's creation
---@field messageId string|nil # The message ID associated with the vault's creation if type is "vault"
---@field balance number|nil # The balance of the vault if type is "vault"
---@field endTimestamp number|nil # The end timestamp of the vault if type is "vault"
---@field delegationId string # The unique ID of the delegation

--- Fetch a flattened array of all the delegations (stakes and vaults) present across all gateways for the given address
--- @param address string The address of the delegator
--- @return Delegation[] # A table of all the address's staked and vaulted delegations
function gar.getFlattenedDelegations(address)
	return utils.reduce(gar.getDelegations(address), function(acc, gatewayAddress, delegation)
		table.insert(acc, {
			type = "stake",
			gatewayAddress = gatewayAddress,
			balance = delegation.delegatedStake,
			startTimestamp = delegation.startTimestamp,
			delegationId = gatewayAddress .. "_" .. delegation.startTimestamp,
		})
		for vaultId, vault in pairs(delegation.vaults) do
			table.insert(acc, {
				type = "vault",
				gatewayAddress = gatewayAddress,
				startTimestamp = vault.startTimestamp,
				vaultId = vaultId,
				balance = vault.balance,
				endTimestamp = vault.endTimestamp,
				delegationId = gatewayAddress .. "_" .. vault.startTimestamp,
			})
		end
		return acc
	end, {})
end

--- Fetch a heterogenous array of all active and vaulted delegated stakes, cursored on startTimestamp
--- @param address string The address of the delegator
--- @param cursor number|nil The cursor startTimestamp after which to fetch more stakes (optional)
--- @param limit number The max number of stakes to fetch
--- @param sortBy string The field to sort by. Default is "startTimestamp"
--- @param sortOrder string The order to sort by, either "asc" or "desc". Default is "asc"
--- @return PaginatedTable # A table containing the paginated stakes and pagination metadata as Delegation objects
function gar.getPaginatedDelegations(address, cursor, limit, sortBy, sortOrder)
	local delegationsArray = gar.getFlattenedDelegations(address)
	return utils.paginateTableWithCursor(
		delegationsArray,
		cursor,
		"delegationId",
		limit,
		sortBy or "startTimestamp",
		sortOrder or "asc"
	)
end

-- TODO: Prune on ticks -- integrate with primary name branch
--- @type { [string]: { timestamp: number, redelegations: number } }
ReDelegations = ReDelegations or {}

function gar.getReDelgations()
	return utils.deepCopy(ReDelegations)
end

function gar.getReDelgationsUnsafe()
	return ReDelegations
end

function gar.getReDelegation(delegateAddress)
	return gar.getReDelgations()[delegateAddress]
end

function gar.getReDelegationUnsafe(delegateAddress)
	return gar.getReDelgationsUnsafe()[delegateAddress]
end

--- Take stake from a delegate and stake it to a new delegate.
--- This function will be called by the delegate to redelegate their stake to a new gateway.
--- The delegated stake will be moved from the old gateway to the new gateway.
--- It will fail if there is no or not enough delegated stake to move from the gateway.
--- It will fail if the old gateway does not meet the minimum staking requirements after the stake is moved.
--- It can move stake from the vaulted stake
--- It can move stake from its own stake as long as it meets the minimum staking requirements after the stake is moved.
---
--- @class ReDelegateStakeParams
--- @field delegateAddress string # The address of the delegate to redelegate stake from (required)
--- @field sourceAddress string # The address of the gateway to redelegate stake from (required)
--- @field targetAddress string # The address of the gateway to redelegate stake to (required)
--- @field qty number # The amount of stake to redelegate - must be positive integer (required)
--- @field currentTimestamp number # The current timestamp (required)
--- @field vaultId string | nil # The vault id to redelegate from (optional)

--- @class ReDelegateStakeResult
--- @field sourceGateway table # The updated gateway object that the stake was moved from
--- @field targetGateway table # The updated gateway object that the stake was moved to
--- @field reDelegationFee number # The fee charged for the redelegation
--- @field feeResetTimestamp number # The timestamp when the reldelegation fee will be reset
--- @field reDelegationsSinceFeeReset number # The number of redelegations the user has made since the last fee reset

--- @param params ReDelegateStakeParams
--- @return ReDelegateStakeResult
function gar.reDelegateStake(params)
	local delegateAddress = params.delegateAddress
	local targetAddress = params.targetAddress
	local sourceAddress = params.sourceAddress
	local stakeToTakeFromSource = params.qty
	local currentTimestamp = params.currentTimestamp
	local vaultId = params.vaultId

	assert(type(stakeToTakeFromSource) == "number", "Quantity is required and must be a number")
	assert(stakeToTakeFromSource > 0, "Quantity must be greater than 0")
	assert(type(targetAddress) == "string", "Target address is required and must be a string")
	assert(type(sourceAddress) == "string", "Source address is required and must be a string")
	assert(type(delegateAddress) == "string", "Delegate address is required and must be a string")
	assert(type(currentTimestamp) == "number", "Current timestamp is required and must be a number")

	if sourceAddress == targetAddress then
		error("Source and target gateway addresses must be different.")
	end

	local sourceGateway = gar.getGateway(sourceAddress)
	local targetGateway = gar.getGateway(targetAddress)

	if not sourceGateway then
		error("Source Gateway not found")
	end
	if not targetGateway then
		error("Target Gateway not found")
	end
	if targetGateway.status == "leaving" then
		error("Target Gateway is leaving the network and cannot have more stake delegated to it.")
	end

	if not targetGateway.settings.allowDelegatedStaking then
		error("Target Gateway does not allow delegated staking.")
	end

	if not gar.delegateAllowedToStake(delegateAddress, targetGateway) then
		error("This Gateway does not allow this delegate to stake.")
	end

	local previousReDelegations = gar.getReDelegation(delegateAddress)

	local reDelegationFeePct = math.min(
		previousReDelegations and previousReDelegations.redelegations >= 1 and 0.1 * previousReDelegations.redelegations
			or 0,
		0.6
	)

	local redelegationFee = math.ceil(stakeToTakeFromSource * reDelegationFeePct)
	local stakeToDelegate = stakeToTakeFromSource - redelegationFee

	if stakeToDelegate == 0 then
		error("The redelegation stake amount minus the redelegation fee is too low to redelegate.")
	end

	-- Assert source has enough stake to redelegate and remove the stake from the source
	if delegateAddress == sourceAddress then
		-- check if he gateway can afford to redelegate from itself

		if vaultId then
			-- Get the redelegation amount from the operator vault

			local existingVault = sourceGateway.vaults[vaultId]
			if not existingVault then
				error("Vault not found on the operator.")
			end

			if existingVault.balance < stakeToTakeFromSource then
				error("Quantity must be less than or equal to the vaulted stake amount.")
			end

			if existingVault.balance == stakeToTakeFromSource then
				-- The operator vault has been emptied
				sourceGateway.vaults[vaultId] = nil
			else
				-- The operator vault has been partially emptied
				sourceGateway.vaults[delegateAddress][vaultId].balance = sourceGateway.vaults[delegateAddress][vaultId].balance
					- stakeToTakeFromSource
			end
		else
			-- Get the redelegation amount from the operator stakes
			local maxWithdraw = sourceGateway.operatorStake - gar.getSettings().operators.minStake

			if stakeToTakeFromSource > maxWithdraw then
				error(
					"Resulting stake is not enough to maintain the minimum operator stake of "
						.. gar.getSettings().operators.minStake
						.. " IO"
				)
			end

			sourceGateway.operatorStake = sourceGateway.operatorStake - stakeToTakeFromSource
		end
	else
		local existingDelegate = sourceGateway.delegates[delegateAddress]
		if not existingDelegate then
			error("This delegate has no stake to redelegate.")
		end

		if vaultId then
			local existingVault = existingDelegate.vaults[vaultId]
			if not existingVault then
				error("Vault not found on the delegate.")
			end

			if existingVault.balance < stakeToTakeFromSource then
				error("Quantity must be less than or equal to the vaulted stake amount.")
			end

			if existingVault.balance == stakeToTakeFromSource then
				-- The vault has been emptied
				sourceGateway.delegates[delegateAddress].vaults[vaultId] = nil

				if
					-- If all vaults and stake are emptied, remove the delegate
					sourceGateway.delegates[delegateAddress].delegatedStake == 0
					and next(sourceGateway.delegates[delegateAddress].vaults) == nil
				then
					gar.pruneDelegateFromGateway(delegateAddress, sourceGateway)
				end
			else
				-- The vault has been partially emptied
				sourceGateway.delegates[delegateAddress].vaults[vaultId].balance = sourceGateway.delegates[delegateAddress].vaults[vaultId].balance
					- stakeToTakeFromSource
			end
		else
			-- Check if the delegate has enough stake to redelegate
			if existingDelegate.delegatedStake < stakeToTakeFromSource then
				error("Quantity must be less than or equal to the delegated stake amount.")
			end

			-- Check if the delegate will have enough stake left after re-delegating
			local existingStake = existingDelegate.delegatedStake
			local requiredMinimumStake = sourceGateway.settings.minDelegatedStake
			local maxAllowedToWithdraw = existingStake - requiredMinimumStake
			if maxAllowedToWithdraw < stakeToTakeFromSource and stakeToTakeFromSource ~= existingStake then
				error(
					"Remaining delegated stake must be greater than the minimum delegated stake. Adjust the amount or re-delegate all stake."
				)
			end

			-- If the delegate has enough stake to redelegate, move the stake. If its all the stake, remove the delegate
			if existingDelegate.delegatedStake == stakeToTakeFromSource then
				gar.pruneDelegateFromGateway(delegateAddress, sourceGateway)
			else
				sourceGateway.delegates[delegateAddress].delegatedStake = sourceGateway.delegates[delegateAddress].delegatedStake
					- stakeToTakeFromSource
			end
			sourceGateway.totalDelegatedStake = sourceGateway.totalDelegatedStake - stakeToTakeFromSource
		end
	end

	local existingTargetDelegate = targetGateway.delegates[delegateAddress]
	local minimumStakeForGatewayAndDelegate
	if existingTargetDelegate and existingTargetDelegate.delegatedStake ~= 0 then
		-- It already has a stake that is not zero
		minimumStakeForGatewayAndDelegate = 1 -- Delegate must provide at least one additional IO
	else
		-- Consider if the operator increases the minimum amount after you've already staked
		minimumStakeForGatewayAndDelegate = targetGateway.settings.minDelegatedStake
	end

	-- Check if the delegate has enough stake to redelegate
	if stakeToDelegate < minimumStakeForGatewayAndDelegate then
		error("Quantity must be greater than the minimum delegated stake amount.")
	end

	-- The stake can now be applied to the targetGateway
	if targetAddress == delegateAddress then
		-- move the stake to the operator's stake
		targetGateway.operatorStake = targetGateway.operatorStake + stakeToDelegate
	else
		if targetGateway.delegates[delegateAddress] == nil then
			-- create the new delegate stake
			targetGateway.delegates[delegateAddress] = {
				delegatedStake = stakeToDelegate,
				startTimestamp = currentTimestamp,
				vaults = {},
			}
		else
			-- increment the existing delegate's stake
			targetGateway.delegates[delegateAddress].delegatedStake = targetGateway.delegates[delegateAddress].delegatedStake
				+ stakeToDelegate
		end
		targetGateway.totalDelegatedStake = targetGateway.totalDelegatedStake + stakeToDelegate
	end

	-- Move redelegation fee to protocol balance
	balances.increaseBalance(ao.id, redelegationFee)

	-- Update redelegations

	if not previousReDelegations then
		ReDelegations[delegateAddress] = {
			timestamp = currentTimestamp,
			redelegations = 1,
		}
	else
		ReDelegations[delegateAddress] = {
			timestamp = currentTimestamp,
			redelegations = previousReDelegations.redelegations + 1,
		}
	end

	-- prune user from allow list, if necessary, to save memory
	if sourceGateway.settings.allowedDelegatesLookup then
		sourceGateway.settings.allowedDelegatesLookup[delegateAddress] = nil
	end

	-- update the gateway
	GatewayRegistry[sourceAddress] = sourceGateway

	-- update the target gateway
	GatewayRegistry[targetAddress] = targetGateway

	return {
		sourceGateway = sourceGateway,
		targetGateway = targetGateway,
		reDelegationFee = redelegationFee,
		feeResetTimestamp = currentTimestamp + 7 * 24 * 60 * 60 * 1000, -- 7 days
		reDelegationsSinceFeeReset = ReDelegations[delegateAddress].redelegations,
	}
end

function gar.getReDelegationFee(delegateAddress)
	local previousReDelegations = gar.getReDelegationUnsafe(delegateAddress)

	local reDelegationFeePct = math.min(
		previousReDelegations and previousReDelegations.redelegations >= 1 and 0.1 * previousReDelegations.redelegations
			or 0,
		0.6
	)

	return {
		reDelegationFeePct = reDelegationFeePct,
		feeResetTimestamp = previousReDelegations and previousReDelegations.timestamp + 7 * 24 * 60 * 60 * 1000 or nil,
	}
end

return gar
