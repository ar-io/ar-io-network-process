local prune = {}
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
---@field prunedPrimaryNamesAndOwners table<string, RemovedPrimaryName[]>
---@field prunedPrimaryNameRequests table<WalletAddress, PrimaryNameRequest>
---@field delegatorsWithFeeReset WalletAddress[]

--- Prunes the state
--- @param timestamp number The timestamp
--- @param msgId string The message ID
--- @param lastGracePeriodEntryEndTimestamp number The end timestamp of the last known record to enter grace period
--- @return PruneStateResult pruneStateResult - the result of the state pruning
function prune.pruneState(timestamp, msgId, lastGracePeriodEntryEndTimestamp)
	local prunedRecords, newGracePeriodRecords = arns.pruneRecords(timestamp, lastGracePeriodEntryEndTimestamp)
	-- for all the pruned records, create auctions and remove primary name claims
	local prunedPrimaryNamesAndOwners = {}
	for name, _ in pairs(prunedRecords) do
		-- remove primary names
		local removedPrimaryNamesAndOwners = primaryNames.removePrimaryNamesForBaseName(name)
		if #removedPrimaryNamesAndOwners > 0 then
			prunedPrimaryNamesAndOwners[name] = removedPrimaryNamesAndOwners
		end
		-- create auction for records that have finally expired
		arns.createAuction(name, timestamp, ao.id)
	end
	local prunedPrimaryNameRequests = primaryNames.prunePrimaryNameRequests(timestamp)
	local prunedAuctions = arns.pruneAuctions(timestamp)
	local prunedReserved = arns.pruneReservedNames(timestamp)
	local prunedVaults = vaults.pruneVaults(timestamp)
	local pruneGatewaysResult = gar.pruneGateways(timestamp, msgId)
	local delegatorsWithFeeReset = gar.pruneRedelegationFeeData(timestamp)
	local prunedEpochs = epochs.pruneEpochs(timestamp)
	return {
		prunedRecords = prunedRecords,
		newGracePeriodRecords = newGracePeriodRecords,
		prunedAuctions = prunedAuctions,
		prunedReserved = prunedReserved,
		prunedVaults = prunedVaults,
		pruneGatewaysResult = pruneGatewaysResult,
		prunedEpochs = prunedEpochs,
		prunedPrimaryNamesAndOwners = prunedPrimaryNamesAndOwners,
		prunedPrimaryNameRequests = prunedPrimaryNameRequests,
		delegatorsWithFeeReset = delegatorsWithFeeReset,
	}
end

return prune
