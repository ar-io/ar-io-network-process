local tick = {}
local epochs = require("epochs")
local gar = require("gar")

--- @class TickResult
--- @field maybeNewEpoch PrescribedEpoch | nil The new epoch
--- @field maybePrescribedEpoch PrescribedEpoch | nil The prescribed epoch
--- @field maybeDistributedEpoch DistributedEpoch | nil The distributed epoch
--- @field maybeDemandFactor number | nil The demand factor
--- @field pruneGatewaysResult PruneGatewaysResult The prune gateways result

--- Ticks an epoch. A tick is the process of updating the demand factor, distributing rewards, pruning gateways, and creating a new epoch.
--- @param currentTimestamp number The current timestamp
--- @param currentBlockHeight number The current block height
--- @param currentHashchain string The current hashchain
--- @param currentMsgId string The current message ID
--- @param epochIndexToTick number The epoch index to tick
--- @return TickResult # The ticked epoch
function tick.tickEpoch(currentTimestamp, currentBlockHeight, currentHashchain, currentMsgId, epochIndexToTick)
	if currentTimestamp < epochs.getSettings().epochZeroStartTimestamp then
		print("Genesis epoch has not started yet, skipping tick")
		return {
			maybeNewEpoch = nil,
			maybePrescribedEpoch = nil,
			maybeDistributedEpoch = nil,
		}
	end
	local currentEpochIndex = epochs.getEpochIndexForTimestamp(currentTimestamp)
	local distributedEpoch = nil
	local pruneGatewaysResult = nil
	-- if the epoch index to tick is less than the current epoch index, distribute the rewards for the epoch and prune the gateways that failed after it, then we create the new one
	if epochIndexToTick < currentEpochIndex then
		-- distribute rewards for the epoch and increments stats for gateways, this closes the epoch if the timestamp is greater than the epochs required distribution timestamp
		distributedEpoch = epochs.distributeEpoch(epochIndexToTick, currentTimestamp)
		-- prune any gateway that has hit the failed 30 consecutive epoch threshold after the epoch has been distributed
		pruneGatewaysResult = gar.pruneGateways(currentTimestamp, currentMsgId)
	end
	-- now create the new epoch with the current message hashchain and block height
	local newPrescribedEpoch = epochs.createAndPrescribeNewEpoch(currentTimestamp, currentBlockHeight, currentHashchain)
	return {
		maybeDistributedEpoch = distributedEpoch,
		maybeNewEpoch = newPrescribedEpoch,
		pruneGatewaysResult = pruneGatewaysResult,
	}
end

return tick
