local tick = {}
local arns = require("arns")
local gar = require("gar")
local vaults = require("vaults")
local epochs = require("epochs")
function tick.pruneState(timestamp, msgId)
	local prunedRecords = arns.pruneRecords(timestamp)
	arns.pruneReservedNames(timestamp)
	vaults.pruneVaults(timestamp)
	gar.pruneGateways(timestamp, msgId)
	local prunedEpochs = epochs.pruneEpochs(timestamp)
	return {
		prunedRecords = prunedRecords,
		prunedEpochs = prunedEpochs,
	}
end

return tick
