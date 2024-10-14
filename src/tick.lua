local tick = {}
local arns = require("arns")
local gar = require("gar")
local vaults = require("vaults")
local epochs = require("epochs")
function tick.pruneState(timestamp, msgId)
	local prunedRecords = arns.pruneRecords(timestamp)
	local prunedAuctions = arns.pruneAuctions(timestamp)
	local prunedReserved = arns.pruneReservedNames(timestamp)
	-- TODO: return vaults and updated balances from vault pruning
	vaults.pruneVaults(timestamp)
	local gatewayResults = gar.pruneGateways(timestamp, msgId)
	local prunedEpochs = epochs.pruneEpochs(timestamp)
	return {
		prunedRecords = prunedRecords,
		prunedAuctions = prunedAuctions,
		prunedReserved = prunedReserved,
		prunedGateways = gatewayResults.prunedGateways,
		slashedGateways = gatewayResults.slashedGateways,
		prunedEpochs = prunedEpochs,
	}
end

return tick
