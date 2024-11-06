local tick = {}
local arns = require("arns")
local gar = require("gar")
local vaults = require("vaults")
local epochs = require("epochs")

--- Prunes the state
--- @param timestamp number The timestamp
--- @param msgId string The message ID
--- @param lastGracePeriodEntryEndTimestamp number The end timestamp of the last known record to enter grace period
--- @return table The pruned records, auctions, reserved names, vaults, gateways, and epochs
function tick.pruneState(timestamp, msgId, lastGracePeriodEntryEndTimestamp)
	local prunedRecords, newGracePeriodRecords = arns.pruneRecords(timestamp, lastGracePeriodEntryEndTimestamp)
	local prunedAuctions = arns.pruneAuctions(timestamp)
	local prunedReserved = arns.pruneReservedNames(timestamp)
	local prunedVaults = vaults.pruneVaults(timestamp)
	local pruneGatewaysResult = gar.pruneGateways(timestamp, msgId)
	local prunedEpochs = epochs.pruneEpochs(timestamp)
	return {
		prunedRecords = prunedRecords,
		newGracePeriodRecords = newGracePeriodRecords,
		prunedAuctions = prunedAuctions,
		prunedReserved = prunedReserved,
		prunedVaults = prunedVaults,
		pruneGatewaysResult = pruneGatewaysResult,
		prunedEpochs = prunedEpochs,
	}
end

return tick
