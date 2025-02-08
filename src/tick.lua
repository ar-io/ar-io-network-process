local tick = {}
local epochs = require("epochs")
local gar = require("gar")

--- @class TickResult
--- @field maybeNewEpoch Epoch | nil The new epoch
--- @field maybePrescribedEpoch PrescribedEpoch | nil The prescribed epoch
--- @field maybeDistributedEpoch DistributedEpoch | nil The distributed epoch
--- @field maybeDemandFactor number | nil The demand factor
--- @field pruneGatewaysResult PruneGatewaysResult The prune gateways result

--- Ticks an epoch. A tick is the process of updating the demand factor, distributing rewards, pruning gateways, and creating a new epoch.
--- @param timestamp number The timestamp
--- @param blockHeight number The block height
--- @param hashchain string The hashchain
--- @param msgId string The message ID
--- @return TickResult # The ticked epoch
function tick.tickEpoch(timestamp, blockHeight, hashchain, msgId)
	-- distribute rewards for the epoch and increments stats for gateways, this closes the epoch if the timestamp is greater than the epochs required distribution timestamp
	local distributedEpoch = epochs.distributeLastEpoch(timestamp)
	-- prune any gateway that has hit the failed 30 consecutive epoch threshold after the epoch has been distributed
	local pruneGatewaysResult = gar.pruneGateways(timestamp, msgId)
	-- now create the new epoch with the current message hashchain and block height
	local newEpoch = epochs.createNewEpoch(timestamp, blockHeight)
	-- prescribe the epoch if it is not already prescribed
	local prescribedEpoch = epochs.prescribeCurrentEpoch(timestamp, hashchain)
	return {
		maybeDistributedEpoch = distributedEpoch,
		maybeNewEpoch = newEpoch,
		pruneGatewaysResult = pruneGatewaysResult,
		maybePrescribedEpoch = prescribedEpoch,
	}
end

return tick
