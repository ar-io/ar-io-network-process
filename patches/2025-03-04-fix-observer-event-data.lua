--[[
	Fixes a bug where the prescribed observers were not being added to event data on tick.

	Related PR: https://github.com/ar-io/ar-io-network-process/pull/406

	Reviewers: Dylan, Ariel, Derek, Jonathon, Phil
]]
--

local utils = require(".src.utils")

-- Find reference to the handler for the distribute action in the Handlers table
local distributeHandlerIndex = utils.findInArray(Handlers.list, function(handler)
	return handler.name == "distribute"
end)

if not distributeHandlerIndex then
	error("Distribute handler not found")
end

local distributeHandler = Handlers.list[distributeHandlerIndex]

-- Override the handle function for the distribute action
distributeHandler.handle = function(msg)
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
end
