local tick = {}
local epochs = require("epochs")
local demand = require("demand")
local gar = require("gar")

--- @class TickResult
--- @field maybeDistributedEpoch Epoch | nil The distributed epoch
--- @field maybeNewEpoch Epoch | nil The new epoch
--- @field maybeDemandFactor number | nil The demand factor
--- @field pruneGatewaysResult PrunedGatewaysResult The prune gateways result

--- Ticks an epoch. A tick is the process of updating the demand factor, distributing rewards, pruning gateways, and creating a new epoch.
--- @param timestamp number The timestamp
--- @param blockHeight number The block height
--- @param hashchain string The hashchain
--- @param msgId string The message ID
--- @return TickResult # The ticked epoch
function tick.tickEpoch(timestamp, blockHeight, hashchain, msgId)
	-- update demand factor if necessary
	local demandFactor = demand.updateDemandFactor(timestamp)
	-- distribute rewards for the epoch and increments stats for gateways, this closes the epoch if the timestamp is greater than the epochs required distribution timestamp
	local distributedEpoch = epochs.distributeRewardsForEpoch(timestamp)
	-- prune any gateway that has hit the failed 30 consecutive epoch threshold after the epoch has been distributed
	local pruneGatewaysResult = gar.pruneGateways(timestamp, msgId)
	-- now create the new epoch with the current message hashchain and block height
	local newEpoch = epochs.createEpoch(timestamp, blockHeight, hashchain)
	return {
		maybeDistributedEpoch = distributedEpoch,
		maybeNewEpoch = newEpoch,
		maybeDemandFactor = demandFactor,
		pruneGatewaysResult = pruneGatewaysResult,
	}
end

return tick
