local tick = {}
local arns = require("arns")
local gar = require("gar")
local vaults = require("vaults")

function tick.pruneState(timestamp)
	arns.pruneRecords(timestamp)
	arns.pruneReservedNames(timestamp)
	vaults.pruneVaults(timestamp)
	gar.pruneGateways(timestamp)
	-- TODO: prune epochs to only keep the current epoch and the last 2 epochs
end

return tick
