local tick = {}
local arns = require("arns")
local gar = require("gar")
local vaults = require("vaults")
local epochs = require("epochs")
function tick.pruneState(timestamp, msgId)
	local prunedRecords = arns.pruneRecords(timestamp)
	arns.pruneReservedNames(timestamp)
	local prunedVaults = vaults.pruneVaults(timestamp)
	local gatewayResults = gar.pruneGateways(timestamp, msgId)
	local prunedEpochs = epochs.pruneEpochs(timestamp)
	return {
		prunedRecords = prunedRecords,
		prunedVaults = prunedVaults,
		pruneGatewayResults = gatewayResults,
		prunedEpochs = prunedEpochs,
	}
end

return tick
