local tick = {}
local arns = require("arns")
local gar = require("gar")
local vaults = require("vaults")
local epochs = require("epochs")
function tick.pruneState(timestamp, msgId)
	local prunedRecords = arns.pruneRecords(timestamp)
	arns.pruneReservedNames(timestamp)
	vaults.pruneVaults(timestamp)
	local gatewayResults = gar.pruneGateways(timestamp, msgId)
	epochs.pruneEpochs(timestamp)
	return {
		prunedRecords = prunedRecords,
		prunedGateways = gatewayResults.prunedGateways,
		slashedGateways = gatewayResults.slashedGateways,
	}
end

return tick
