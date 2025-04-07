--[[
	Fixes a bug where the prescribed observers were not being added to event data on tick.

	Related PR: https://github.com/ar-io/ar-io-network-process/pull/406

	Reviewers: Dylan, Ariel, Derek, Jonathon, Phil
]]
--

local utils = require(".src.utils")
local demand = require(".src.demand")
local json = require(".src.json")
local epochs = require(".src.epochs")
local tick = require(".src.tick")
local gar = require(".src.gar")
local token = require(".src.token")
local ARIOEvent = require(".src.ario_event")

--[[
	These changes update the handler defined in main.lua. All local functions are defined in this patch as they are not available in global scope.

	We also must use the `addEventingHandler` function to add the handler to the Handlers table and ensure we continue to get event data.
]]
--
local function Send(msg, response)
	if msg.reply then
		--- Reference: https://github.com/permaweb/aos/blob/main/blueprints/patch-legacy-reply.lua
		msg.reply(response)
	else
		ao.send(response)
	end
end

local function eventingPcall(ioEvent, onError, fnToCall, ...)
	local status, result = pcall(fnToCall, ...)
	if not status then
		onError(result)
		ioEvent:addField("Error", result)
		return status, result
	end
	return status, result
end

--- @class SupplyData
--- @field circulatingSupply number|nil
--- @field lockedSupply number|nil
--- @field stakedSupply number|nil
--- @field delegatedSupply number|nil
--- @field withdrawSupply number|nil
--- @field totalTokenSupply number|nil
--- @field protocolBalance number|nil

--- @param ioEvent ARIOEvent
--- @param supplyData SupplyData|nil
local function addSupplyData(ioEvent, supplyData)
	supplyData = supplyData or {}
	ioEvent:addField("Circulating-Supply", supplyData.circulatingSupply or LastKnownCirculatingSupply)
	ioEvent:addField("Locked-Supply", supplyData.lockedSupply or LastKnownLockedSupply)
	ioEvent:addField("Staked-Supply", supplyData.stakedSupply or LastKnownStakedSupply)
	ioEvent:addField("Delegated-Supply", supplyData.delegatedSupply or LastKnownDelegatedSupply)
	ioEvent:addField("Withdraw-Supply", supplyData.withdrawSupply or LastKnownWithdrawSupply)
	ioEvent:addField("Total-Token-Supply", supplyData.totalTokenSupply or token.lastKnownTotalTokenSupply())
	ioEvent:addField("Protocol-Balance", Balances[ao.id])
end

local function gatewayStats()
	local numJoinedGateways = 0
	local numLeavingGateways = 0
	for _, gateway in pairs(GatewayRegistry) do
		if gateway.status == "joined" then
			numJoinedGateways = numJoinedGateways + 1
		else
			numLeavingGateways = numLeavingGateways + 1
		end
	end
	return {
		joined = numJoinedGateways,
		leaving = numLeavingGateways,
	}
end

--- @param ioEvent ARIOEvent
--- @param talliesData StateObjectTallies|GatewayObjectTallies|nil
local function addTalliesData(ioEvent, talliesData)
	ioEvent:addFieldsIfExist(talliesData, {
		"numAddressesVaulting",
		"numBalanceVaults",
		"numBalances",
		"numDelegateVaults",
		"numDelegatesVaulting",
		"numDelegates",
		"numDelegations",
		"numExitingDelegations",
		"numGatewayVaults",
		"numGatewaysVaulting",
		"numGateways",
		"numExitingGateways",
	})
end

--- @param ioEvent ARIOEvent
--- @param pruneGatewaysResult PruneGatewaysResult
local function addPruneGatewaysResult(ioEvent, pruneGatewaysResult)
	LastKnownCirculatingSupply = LastKnownCirculatingSupply
		+ (pruneGatewaysResult.delegateStakeReturned or 0)
		+ (pruneGatewaysResult.gatewayStakeReturned or 0)

	LastKnownWithdrawSupply = LastKnownWithdrawSupply
		- (pruneGatewaysResult.delegateStakeReturned or 0)
		- (pruneGatewaysResult.gatewayStakeReturned or 0)
		+ (pruneGatewaysResult.delegateStakeWithdrawing or 0)
		+ (pruneGatewaysResult.gatewayStakeWithdrawing or 0)

	LastKnownDelegatedSupply = LastKnownDelegatedSupply - (pruneGatewaysResult.delegateStakeWithdrawing or 0)

	local totalGwStakesSlashed = (pruneGatewaysResult.stakeSlashed or 0)
	LastKnownStakedSupply = LastKnownStakedSupply
		- totalGwStakesSlashed
		- (pruneGatewaysResult.gatewayStakeWithdrawing or 0)

	if totalGwStakesSlashed > 0 then
		ioEvent:addField("Total-Gateways-Stake-Slashed", totalGwStakesSlashed)
	end

	local prunedGateways = pruneGatewaysResult.prunedGateways or {}
	local prunedGatewaysCount = utils.lengthOfTable(prunedGateways)
	if prunedGatewaysCount > 0 then
		ioEvent:addField("Pruned-Gateways", prunedGateways)
		ioEvent:addField("Pruned-Gateways-Count", prunedGatewaysCount)
		local gwStats = gatewayStats()
		ioEvent:addField("Joined-Gateways-Count", gwStats.joined)
		ioEvent:addField("Leaving-Gateways-Count", gwStats.leaving)
	end

	local slashedGateways = pruneGatewaysResult.slashedGateways or {}
	local slashedGatewaysCount = utils.lengthOfTable(slashedGateways or {})
	if slashedGatewaysCount > 0 then
		ioEvent:addField("Slashed-Gateway-Amounts", slashedGateways)
		ioEvent:addField("Slashed-Gateways-Count", slashedGatewaysCount)
		local invariantSlashedGateways = {}
		for gwAddress, _ in pairs(slashedGateways) do
			local unsafeGateway = gar.getGatewayUnsafe(gwAddress) or {}
			if unsafeGateway and (unsafeGateway.totalDelegatedStake > 0) then
				invariantSlashedGateways[gwAddress] = unsafeGateway.totalDelegatedStake
			end
		end
		if utils.lengthOfTable(invariantSlashedGateways) > 0 then
			ioEvent:addField("Invariant-Slashed-Gateways", invariantSlashedGateways)
		end
	end

	addTalliesData(ioEvent, pruneGatewaysResult.gatewayObjectTallies)
end

local function addEventingHandler(handlerName, pattern, handleFn, critical, printEvent)
	critical = critical or false
	printEvent = printEvent == nil and true or printEvent
	Handlers.add(handlerName, pattern, function(msg)
		-- add an ARIOEvent to the message if it doesn't exist
		msg.ioEvent = msg.ioEvent or ARIOEvent(msg)
		-- global handler for all eventing errors, so we can log them and send a notice to the sender for non critical errors and discard the memory on critical errors
		local status, resultOrError = eventingPcall(msg.ioEvent, function(error)
			--- non critical errors will send an invalid notice back to the caller with the error information, memory is not discarded
			Send(msg, {
				Target = msg.From,
				Action = "Invalid-" .. utils.toTrainCase(handlerName) .. "-Notice",
				Error = tostring(error),
				Data = tostring(error),
			})
		end, handleFn, msg)
		if not status and critical then
			local errorEvent = ARIOEvent(msg)
			-- For critical handlers we want to make sure the event data gets sent to the CU for processing, but that the memory is discarded on failures
			-- These handlers (distribute, prune) severely modify global state, and partial updates are dangerous.
			-- So we json encode the error and the event data and then throw, so the CU will discard the memory and still process the event data.
			-- An alternative approach is to modify the implementation of ao.result - to also return the Output on error.
			-- Reference: https://github.com/permaweb/ao/blob/76a618722b201430a372894b3e2753ac01e63d3d/dev-cli/src/starters/lua/ao.lua#L284-L287
			local errorWithEvent = tostring(resultOrError) .. "\n" .. errorEvent:toJSON()
			error(errorWithEvent, 0) -- 0 ensures not to include this line number in the error message
		end

		msg.ioEvent:addField("Handler-Memory-KiB-Used", collectgarbage("count"), false)
		collectgarbage("collect")
		msg.ioEvent:addField("Final-Memory-KiB-Used", collectgarbage("count"), false)

		if printEvent then
			msg.ioEvent:printEvent()
		end
	end)
end

-- Override the handle function for the distribute action
addEventingHandler("distribute", function(msg)
	return msg.Action == "Tick" or msg.Action == "Distribute"
end, function(msg)
	local msgId = msg.Id
	local blockHeight = tonumber(msg["Block-Height"])
	local hashchain = msg["Hash-Chain"]
	local lastCreatedEpochIndex = LastCreatedEpochIndex
	local lastDistributedEpochIndex = LastDistributedEpochIndex
	local targetCurrentEpochIndex = epochs.getEpochIndexForTimestamp(msg.Timestamp)

	assert(blockHeight, "Block height is required")
	assert(hashchain, "Hash chain is required")

	msg.ioEvent:addField("Last-Created-Epoch-Index", lastCreatedEpochIndex)
	msg.ioEvent:addField("Last-Distributed-Epoch-Index", lastDistributedEpochIndex)
	msg.ioEvent:addField("Target-Current-Epoch-Index", targetCurrentEpochIndex)

	-- tick and distribute rewards for every index between the last ticked epoch and the current epoch
	local distributedEpochIndexes = {}
	local newEpochIndexes = {}
	local newPruneGatewaysResults = {}
	local tickedRewardDistributions = {}
	local totalTickedRewardsDistributed = 0

	-- tick the demand factor all the way to the current period
	local latestDemandFactor, newDemandFactors = demand.updateDemandFactor(msg.Timestamp)
	if latestDemandFactor ~= nil then
		Send(msg, {
			Target = msg.From,
			Action = "Demand-Factor-Updated-Notice",
			Data = tostring(latestDemandFactor),
		})
	end

	--[[
		Tick up to the target epoch index, this will create new epochs and distribute rewards for existing epochs
		This should never fall behind, but in the case it does, it will create the epochs and distribute rewards for the epochs
		accordingly. It should finish at the target epoch index - which is computed based on the message timestamp
	]]
	--
	print("Ticking from " .. lastCreatedEpochIndex .. " to " .. targetCurrentEpochIndex)
	for epochIndexToTick = lastCreatedEpochIndex, targetCurrentEpochIndex do
		local tickResult = tick.tickEpoch(msg.Timestamp, blockHeight, hashchain, msgId, epochIndexToTick)
		if tickResult.pruneGatewaysResult ~= nil then
			table.insert(newPruneGatewaysResults, tickResult.pruneGatewaysResult)
		end
		if tickResult.maybeNewEpoch ~= nil then
			print("Created epoch " .. tickResult.maybeNewEpoch.epochIndex)
			LastCreatedEpochIndex = tickResult.maybeNewEpoch.epochIndex
			table.insert(newEpochIndexes, tickResult.maybeNewEpoch.epochIndex)
			Send(msg, {
				Target = msg.From,
				Action = "Epoch-Created-Notice",
				["Epoch-Index"] = tostring(tickResult.maybeNewEpoch.epochIndex),
				Data = json.encode(tickResult.maybeNewEpoch),
			})
		end
		if tickResult.maybeDistributedEpoch ~= nil then
			print("Distributed rewards for epoch " .. tickResult.maybeDistributedEpoch.epochIndex)
			LastDistributedEpochIndex = tickResult.maybeDistributedEpoch.epochIndex
			tickedRewardDistributions[tostring(tickResult.maybeDistributedEpoch.epochIndex)] =
				tickResult.maybeDistributedEpoch.distributions.totalDistributedRewards
			totalTickedRewardsDistributed = totalTickedRewardsDistributed
				+ tickResult.maybeDistributedEpoch.distributions.totalDistributedRewards
			table.insert(distributedEpochIndexes, tickResult.maybeDistributedEpoch.epochIndex)
			Send(msg, {
				Target = msg.From,
				Action = "Epoch-Distribution-Notice",
				["Epoch-Index"] = tostring(tickResult.maybeDistributedEpoch.epochIndex),
				Data = json.encode(tickResult.maybeDistributedEpoch),
			})
		end
	end
	if #distributedEpochIndexes > 0 then
		msg.ioEvent:addField("Distributed-Epoch-Indexes", distributedEpochIndexes)
	end
	if #newEpochIndexes > 0 then
		msg.ioEvent:addField("New-Epoch-Indexes", newEpochIndexes)
		-- Only print the prescribed observers of the newest epoch
		local newestEpoch = epochs.getEpoch(math.max(table.unpack(newEpochIndexes)))
		local prescribedObserverAddresses = newestEpoch
			and utils.map(newestEpoch.prescribedObservers, function(observerAddress, _)
				return observerAddress
			end)
		msg.ioEvent:addField("Prescribed-Observers", prescribedObserverAddresses)
	end
	local updatedDemandFactorCount = utils.lengthOfTable(newDemandFactors)
	if updatedDemandFactorCount > 0 then
		local updatedDemandFactorPeriods = utils.map(newDemandFactors, function(_, df)
			return df.period
		end)
		local updatedDemandFactorValues = utils.map(newDemandFactors, function(_, df)
			return df.demandFactor
		end)
		msg.ioEvent:addField("New-Demand-Factor-Periods", updatedDemandFactorPeriods)
		msg.ioEvent:addField("New-Demand-Factor-Values", updatedDemandFactorValues)
	end
	if #newPruneGatewaysResults > 0 then
		-- Reduce the prune gateways results and then track changes
		--- @type PruneGatewaysResult
		local aggregatedPruneGatewaysResult = utils.reduce(
			newPruneGatewaysResults,
			--- @param acc PruneGatewaysResult
			--- @param _ any
			--- @param pruneGatewaysResult PruneGatewaysResult
			function(acc, _, pruneGatewaysResult)
				for _, address in pairs(pruneGatewaysResult.prunedGateways) do
					table.insert(acc.prunedGateways, address)
				end
				for address, slashAmount in pairs(pruneGatewaysResult.slashedGateways) do
					acc.slashedGateways[address] = (acc.slashedGateways[address] or 0) + slashAmount
				end
				acc.gatewayStakeReturned = acc.gatewayStakeReturned + pruneGatewaysResult.gatewayStakeReturned
				acc.delegateStakeReturned = acc.delegateStakeReturned + pruneGatewaysResult.delegateStakeReturned
				acc.gatewayStakeWithdrawing = acc.gatewayStakeWithdrawing + pruneGatewaysResult.gatewayStakeWithdrawing
				acc.delegateStakeWithdrawing = acc.delegateStakeWithdrawing
					+ pruneGatewaysResult.delegateStakeWithdrawing
				acc.stakeSlashed = acc.stakeSlashed + pruneGatewaysResult.stakeSlashed
				-- Upsert to the latest tallies if available
				acc.gatewayObjectTallies = pruneGatewaysResult.gatewayObjectTallies or acc.gatewayObjectTallies
				return acc
			end,
			{
				prunedGateways = {},
				slashedGateways = {},
				gatewayStakeReturned = 0,
				delegateStakeReturned = 0,
				gatewayStakeWithdrawing = 0,
				delegateStakeWithdrawing = 0,
				stakeSlashed = 0,
			}
		)
		addPruneGatewaysResult(msg.ioEvent, aggregatedPruneGatewaysResult)
	end
	if utils.lengthOfTable(tickedRewardDistributions) > 0 then
		msg.ioEvent:addField("Ticked-Reward-Distributions", tickedRewardDistributions)
		msg.ioEvent:addField("Total-Ticked-Rewards-Distributed", totalTickedRewardsDistributed)
		LastKnownCirculatingSupply = LastKnownCirculatingSupply + totalTickedRewardsDistributed
	end

	local gwStats = gatewayStats()
	msg.ioEvent:addField("Joined-Gateways-Count", gwStats.joined)
	msg.ioEvent:addField("Leaving-Gateways-Count", gwStats.leaving)
	addSupplyData(msg.ioEvent)

	-- Send a single tick notice to the sender after all epochs have been ticked
	Send(msg, {
		Target = msg.From,
		Action = "Tick-Notice",
		Data = json.encode({
			distributedEpochIndexes = distributedEpochIndexes,
			newEpochIndexes = newEpochIndexes,
			newDemandFactors = newDemandFactors,
			newPruneGatewaysResults = newPruneGatewaysResults,
			tickedRewardDistributions = tickedRewardDistributions,
			totalTickedRewardsDistributed = totalTickedRewardsDistributed,
		}),
	})
end, CRITICAL)
