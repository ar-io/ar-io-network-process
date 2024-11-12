local tick = {}
local arns = require("arns")
local gar = require("gar")
local vaults = require("vaults")
local epochs = require("epochs")
local primaryNames = require("primary_names")

---@class PruneStateResult
---@field prunedRecords table<string, Record>
---@field newGracePeriodRecords table<string, Record>
---@field prunedAuctions table<string, Auction>
---@field prunedReserved table<string, ReservedName>
---@field prunedVaults table<string, Vault>
---@field pruneGatewaysResult table<string, table>
---@field prunedEpochs table<string, Epoch>
---@field prunedPrimaryNames table<string, PrimaryNameWithOwner[]>
---@field prunedPrimaryNameClaims table<string, PrimaryNameClaim[]>

--- Prunes the state
--- @param timestamp number The timestamp
--- @param msgId string The message ID
--- @param lastGracePeriodEntryEndTimestamp number The end timestamp of the last known record to enter grace period
--- @return PruneStateResult
function tick.pruneState(timestamp, msgId, lastGracePeriodEntryEndTimestamp)
	local prunedRecords, newGracePeriodRecords = arns.pruneRecords(timestamp, lastGracePeriodEntryEndTimestamp)
	-- for all the pruned records, create auctions and remove primary name claims
	local prunedPrimaryNames = {}
	for name, _ in pairs(prunedRecords) do
		-- remove primary names
		local removedPrimaryNames = primaryNames.removePrimaryNamesForArNSName(name)
		if #removedPrimaryNames > 0 then
			prunedPrimaryNames[name] = removedPrimaryNames
		end
		-- create auction
		arns.createAuction(name, timestamp, ao.id)
	end
	local prunedPrimaryNameClaims = primaryNames.prunePrimaryNameClaims(timestamp)
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
		prunedPrimaryNames = prunedPrimaryNames,
		prunedPrimaryNameClaims = prunedPrimaryNameClaims,
	}
end

return tick
