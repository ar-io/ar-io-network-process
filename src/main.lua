-- Adjust package.path to include the current directory
local process = { _version = "0.0.1" }
local constants = require("constants")
local token = require("token")
local IOEvent = require("io_event")

Name = Name or "Testnet IO"
Ticker = Ticker or "tIO"
Logo = Logo or "qUjrTmHdVjXX4D6rU6Fik02bUOzWkOR6oOqUg39g4-s"
Denomination = 6
DemandFactor = DemandFactor or {}
Owner = Owner or ao.env.Process.Owner
Protocol = Protocol or ao.env.Process.Id
Balances = Balances or {}
if not Balances[Protocol] then -- initialize the balance for the process id
	Balances = {
		[Protocol] = math.floor(50000000 * 1000000), -- 50M IO
		[Owner] = math.floor(constants.totalTokenSupply - (50000000 * 1000000)), -- 950M IO
	}
end
Vaults = Vaults or {}
GatewayRegistry = GatewayRegistry or {}
NameRegistry = NameRegistry or {}
Epochs = Epochs or {}
LastTickedEpochIndex = LastTickedEpochIndex or -1
LastGracePeriodEntryEndTimestamp = LastGracePeriodEntryEndTimestamp or 0

local utils = require("utils")
local json = require("json")
local ao = ao or require("ao")
local balances = require("balances")
local arns = require("arns")
local gar = require("gar")
local demand = require("demand")
local epochs = require("epochs")
local vaults = require("vaults")
local prune = require("prune")
local tick = require("tick")
local primaryNames = require("primary_names")

-- handlers that are critical should discard the memory on error (see prune for an example)
local CRITICAL = true

local ActionMap = {
	-- reads
	Info = "Info",
	TotalSupply = "Total-Supply", -- for token.lua spec compatibility, gives just the total supply (circulating + locked + staked + delegated + withdraw)
	TotalTokenSupply = "Total-Token-Supply", -- gives the total token supply and all components (protocol balance, locked supply, staked supply, delegated supply, and withdraw supply)
	State = "State",
	Transfer = "Transfer",
	Balance = "Balance",
	Balances = "Balances",
	DemandFactor = "Demand-Factor",
	DemandFactorInfo = "Demand-Factor-Info",
	DemandFactorSettings = "Demand-Factor-Settings",
	-- EPOCH READ APIS
	Epochs = "Epochs",
	Epoch = "Epoch",
	EpochSettings = "Epoch-Settings",
	PrescribedObservers = "Epoch-Prescribed-Observers",
	PrescribedNames = "Epoch-Prescribed-Names",
	Observations = "Epoch-Observations",
	Distributions = "Epoch-Distributions",
	--- Vaults
	Vault = "Vault",
	Vaults = "Vaults",
	CreateVault = "Create-Vault",
	VaultedTransfer = "Vaulted-Transfer",
	ExtendVault = "Extend-Vault",
	IncreaseVault = "Increase-Vault",
	-- GATEWAY REGISTRY READ APIS
	Gateway = "Gateway",
	Gateways = "Gateways",
	GatewayRegistrySettings = "Gateway-Registry-Settings",
	Delegates = "Delegates",
	JoinNetwork = "Join-Network",
	LeaveNetwork = "Leave-Network",
	IncreaseOperatorStake = "Increase-Operator-Stake",
	DecreaseOperatorStake = "Decrease-Operator-Stake",
	UpdateGatewaySettings = "Update-Gateway-Settings",
	SaveObservations = "Save-Observations",
	DelegateStake = "Delegate-Stake",
	RedelegateStake = "Redelegate-Stake",
	DecreaseDelegateStake = "Decrease-Delegate-Stake",
	CancelWithdrawal = "Cancel-Withdrawal",
	InstantWithdrawal = "Instant-Withdrawal",
	RedelegationFee = "Redelegation-Fee",
	--- ArNS
	Record = "Record",
	Records = "Records",
	BuyRecord = "Buy-Record", -- TODO: standardize these as `Buy-Name` or `Upgrade-Record`
	UpgradeName = "Upgrade-Name", -- TODO: may be more aligned to `Upgrade-Record`
	ExtendLease = "Extend-Lease",
	IncreaseUndernameLimit = "Increase-Undername-Limit",
	ReassignName = "Reassign-Name",
	ReleaseName = "Release-Name",
	ReservedNames = "Reserved-Names",
	ReservedName = "Reserved-Name",
	TokenCost = "Token-Cost",
	CostDetails = "Get-Cost-Details-For-Action",
	GetRegistrationFees = "Get-Registration-Fees",
	-- auctions
	Auctions = "Auctions",
	AuctionInfo = "Auction-Info",
	AuctionBid = "Auction-Bid",
	AuctionPrices = "Auction-Prices",
	AllowDelegates = "Allow-Delegates",
	DisallowDelegates = "Disallow-Delegates",
	Delegations = "Delegations",
	-- PRIMARY NAMES
	RemovePrimaryNames = "Remove-Primary-Names",
	RequestPrimaryName = "Request-Primary-Name",
	PrimaryNameRequest = "Primary-Name-Request",
	PrimaryNameRequests = "Primary-Name-Requests",
	ApprovePrimaryNameRequest = "Approve-Primary-Name-Request",
	PrimaryNames = "Primary-Names",
	PrimaryName = "Primary-Name",
}

--- @alias Message table<string, any> -- an AO message TODO - update this type with the actual Message type
--- @param msg Message
--- @param response any
local function Send(msg, response)
	if msg.reply then
		--- Reference: https://github.com/permaweb/aos/blob/main/blueprints/patch-legacy-reply.lua
		msg.reply(response)
	else
		ao.send(response)
	end
end

local function eventingPcall(ioEvent, onError, fnToCall, ...)
	local status, result = pcall(fnToCall, ...)
	if not status then
		onError(result)
		ioEvent:addField("Error", result)
		return status, result
	end
	return status, result
end

--- @param fundingPlan FundingPlan|nil
--- @param rewardForInitiator number|nil only applies in auction bids for released names
local function adjustSuppliesForFundingPlan(fundingPlan, rewardForInitiator)
	if not fundingPlan then
		return
	end
	rewardForInitiator = rewardForInitiator or 0
	local totalActiveStakesUsed = utils.reduce(fundingPlan.stakes, function(acc, _, stakeSpendingPlan)
		return acc + stakeSpendingPlan.delegatedStake
	end, 0)
	local totalWithdrawStakesUsed = utils.reduce(fundingPlan.stakes, function(acc, _, stakeSpendingPlan)
		return acc
			+ utils.reduce(stakeSpendingPlan.vaults, function(acc2, _, vaultBalance)
				return acc2 + vaultBalance
			end, 0)
	end, 0)
	LastKnownStakedSupply = LastKnownStakedSupply - totalActiveStakesUsed
	LastKnownWithdrawSupply = LastKnownWithdrawSupply - totalWithdrawStakesUsed
	LastKnownCirculatingSupply = LastKnownCirculatingSupply - fundingPlan.balance + rewardForInitiator
end

local function addResultFundingPlanFields(ioEvent, result)
	ioEvent:addFieldsWithPrefixIfExist(result.fundingPlan, "FP-", { "balance" })
	local fundingPlanVaultsCount = 0
	local fundingPlanStakesAmount = utils.reduce(
		result.fundingPlan and result.fundingPlan.stakes or {},
		function(acc, _, delegation)
			return acc
				+ delegation.delegatedStake
				+ utils.reduce(delegation.vaults, function(acc2, _, vaultAmount)
					fundingPlanVaultsCount = fundingPlanVaultsCount + 1
					return acc2 + vaultAmount
				end, 0)
		end,
		0
	)
	if fundingPlanStakesAmount > 0 then
		ioEvent:addField("FP-Stakes-Amount", fundingPlanStakesAmount)
	end
	if fundingPlanVaultsCount > 0 then
		ioEvent:addField("FP-Vaults-Count", fundingPlanVaultsCount)
	end
	local newWithdrawVaultsTallies = utils.reduce(
		result.fundingResult and result.fundingResult.newWithdrawVaults or {},
		function(acc, _, newWithdrawVault)
			acc.totalBalance = acc.totalBalance
				+ utils.reduce(newWithdrawVault, function(acc2, _, vault)
					acc.count = acc.count + 1
					return acc2 + vault.balance
				end, 0)
			return acc
		end,
		{ count = 0, totalBalance = 0 }
	)
	if newWithdrawVaultsTallies.count > 0 then
		ioEvent:addField("New-Withdraw-Vaults-Count", newWithdrawVaultsTallies.count)
		ioEvent:addField("New-Withdraw-Vaults-Total-Balance", newWithdrawVaultsTallies.totalBalance)
	end
	adjustSuppliesForFundingPlan(result.fundingPlan, result.rewardForInitiator)
end

local function addRecordResultFields(ioEvent, result)
	ioEvent:addFieldsIfExist(
		result,
		{ "baseRegistrationFee", "remainingBalance", "protocolBalance", "recordsCount", "reservedRecordsCount" }
	)
	ioEvent:addFieldsIfExist(result.record, { "startTimestamp", "endTimestamp", "undernameLimit", "purchasePrice" })
	if result.df ~= nil and type(result.df) == "table" then
		ioEvent:addField("DF-Trailing-Period-Purchases", (result.df.trailingPeriodPurchases or {}))
		ioEvent:addField("DF-Trailing-Period-Revenues", (result.df.trailingPeriodRevenues or {}))
		ioEvent:addFieldsWithPrefixIfExist(result.df, "DF-", {
			"currentPeriod",
			"currentDemandFactor",
			"consecutivePeriodsWithMinDemandFactor",
			"revenueThisPeriod",
			"purchasesThisPeriod",
		})
	end
	addResultFundingPlanFields(ioEvent, result)
end

local function addAuctionResultFields(ioEvent, result)
	ioEvent:addFieldsIfExist(result, {
		"bidAmount",
		"rewardForInitiator",
		"rewardForProtocol",
		"startPrice",
		"floorPrice",
		"type",
		"years",
	})
	ioEvent:addFieldsIfExist(result.record, { "startTimestamp", "endTimestamp", "undernameLimit", "purchasePrice" })
	ioEvent:addFieldsIfExist(result.auction, {
		"name",
		"initiator",
		"startTimestamp",
		"endTimestamp",
		"baseFee",
		"demandFactor",
	})
	-- TODO: add removedPrimaryNamesAndOwners to ioEvent
	addResultFundingPlanFields(ioEvent, result)
end

local function addSupplyData(ioEvent, supplyData)
	supplyData = supplyData or {}
	ioEvent:addField("Circulating-Supply", supplyData.circulatingSupply or LastKnownCirculatingSupply)
	ioEvent:addField("Locked-Supply", supplyData.lockedSupply or LastKnownLockedSupply)
	ioEvent:addField("Staked-Supply", supplyData.stakedSupply or LastKnownStakedSupply)
	ioEvent:addField("Delegated-Supply", supplyData.delegatedSupply or LastKnownDelegatedSupply)
	ioEvent:addField("Withdraw-Supply", supplyData.withdrawSupply or LastKnownWithdrawSupply)
	ioEvent:addField("Total-Token-Supply", supplyData.totalTokenSupply or token.lastKnownTotalTokenSupply())
	ioEvent:addField("Protocol-Balance", Balances[Protocol])
end

local function gatewayStats()
	local numJoinedGateways = 0
	local numLeavingGateways = 0
	for _, gateway in pairs(GatewayRegistry) do
		if gateway.status == "joined" then
			numJoinedGateways = numJoinedGateways + 1
		else
			numLeavingGateways = numLeavingGateways + 1
		end
	end
	return {
		joined = numJoinedGateways,
		leaving = numLeavingGateways,
	}
end

local function addPruneGatewaysResult(ioEvent, pruneGatewaysResult)
	LastKnownCirculatingSupply = LastKnownCirculatingSupply
		+ (pruneGatewaysResult.delegateStakeReturned or 0)
		+ (pruneGatewaysResult.gatewayStakeReturned or 0)

	LastKnownWithdrawSupply = LastKnownWithdrawSupply
		- (pruneGatewaysResult.delegateStakeReturned or 0)
		- (pruneGatewaysResult.gatewayStakeReturned or 0)
		+ (pruneGatewaysResult.delegateStakeWithdrawing or 0)
		+ (pruneGatewaysResult.gatewayStakeWithdrawing or 0)

	LastKnownDelegatedSupply = LastKnownDelegatedSupply - (pruneGatewaysResult.delegateStakeWithdrawing or 0)

	local totalGwStakesSlashed = (pruneGatewaysResult.stakeSlashed or 0)
	LastKnownStakedSupply = LastKnownStakedSupply
		- totalGwStakesSlashed
		- (pruneGatewaysResult.gatewayStakeWithdrawing or 0)

	if totalGwStakesSlashed > 0 then
		ioEvent:addField("Total-Gateways-Stake-Slashed", totalGwStakesSlashed)
	end

	local prunedGateways = pruneGatewaysResult.prunedGateways or {}
	local prunedGatewaysCount = utils.lengthOfTable(prunedGateways)
	if prunedGatewaysCount > 0 then
		ioEvent:addField("Pruned-Gateways", prunedGateways)
		ioEvent:addField("Pruned-Gateways-Count", prunedGatewaysCount)
		local gwStats = gatewayStats()
		ioEvent:addField("Joined-Gateways-Count", gwStats.joined)
		ioEvent:addField("Leaving-Gateways-Count", gwStats.leaving)
	end

	local slashedGateways = pruneGatewaysResult.slashedGateways or {}
	local slashedGatewaysCount = utils.lengthOfTable(slashedGateways or {})
	if slashedGatewaysCount > 0 then
		ioEvent:addField("Slashed-Gateway-Amounts", slashedGateways)
		ioEvent:addField("Slashed-Gateways-Count", slashedGatewaysCount)
		local invariantSlashedGateways = {}
		for gwAddress, _ in pairs(slashedGateways) do
			local unsafeGateway = gar.getGatewayUnsafe(gwAddress) or {}
			if unsafeGateway and (unsafeGateway.totalDelegatedStake > 0) then
				invariantSlashedGateways[gwAddress] = unsafeGateway.totalDelegatedStake
			end
		end
		if utils.lengthOfTable(invariantSlashedGateways) > 0 then
			ioEvent:addField("Invariant-Slashed-Gateways", invariantSlashedGateways)
		end
	end
end

--- @param ioEvent table
--- @param prunedStateResult PruneStateResult
local function addNextPruneTimestampsResults(ioEvent, prunedStateResult)
	--- @type PrunedGatewaysResult
	local pruneGatewaysResult = prunedStateResult.pruneGatewaysResult

	-- If anything meaningful was pruned, collect the next prune timestamps
	if
		next(prunedStateResult.prunedAuctions)
		or next(prunedStateResult.prunedEpochs)
		or next(prunedStateResult.prunedPrimaryNameRequests)
		or next(prunedStateResult.prunedEpochs)
		or next(prunedStateResult.prunedRecords)
		or next(pruneGatewaysResult.prunedGateways)
		or next(prunedStateResult.delegatorsWithFeeReset)
		or next(pruneGatewaysResult.slashedGateways)
		or pruneGatewaysResult.delegateStakeReturned > 0
		or pruneGatewaysResult.gatewayStakeReturned > 0
		or pruneGatewaysResult.delegateStakeWithdrawing > 0
		or pruneGatewaysResult.gatewayStakeWithdrawing > 0
		or pruneGatewaysResult.stakeSlashed > 0
	then
		ioEvent:addField("Next-Auctions-Prune-Timestamp", arns.nextAuctionsPruneTimestamp())
		ioEvent:addField("Next-Records-Prune-Timestamp", arns.nextRecordsPruneTimestamp())
		ioEvent:addField("Next-Vaults-Prune-Timestamp", vaults.nextVaultsPruneTimestamp())
		ioEvent:addField("Next-Gateways-Prune-Timestamp", gar.nextGatewaysPruneTimestamp())
		ioEvent:addField("Next-Redelegations-Prune-Timestamp", gar.nextRedelegationsPruneTimestamp())
		ioEvent:addField("Next-Primary-Names-Prune-Timestamp", primaryNames.nextPrimaryNamesPruneTimestamp())
	end
end

local function assertValidFundFrom(fundFrom)
	if fundFrom == nil then
		return
	end
	local validFundFrom = utils.createLookupTable({ "any", "balance", "stakes" })
	assert(validFundFrom[fundFrom], "Invalid fund from type. Must be one of: any, balance, stake")
end

local function addEventingHandler(handlerName, pattern, handleFn, critical)
	critical = critical or false
	Handlers.add(handlerName, pattern, function(msg)
		-- add an IOEvent to the message if it doesn't exist
		msg.ioEvent = msg.ioEvent or IOEvent(msg)
		-- global handler for all eventing errors, so we can log them and send a notice to the sender for non critical errors and discard the memory on critical errors
		local status, resultOrError = eventingPcall(msg.ioEvent, function(error)
			--- non critical errors will send an invalid notice back to the caller with the error information, memory is not discarded
			Send(msg, {
				Target = msg.From,
				Action = "Invalid-" .. handlerName .. "-Notice",
				Error = tostring(error),
				Data = tostring(error),
			})
		end, handleFn, msg)
		if not status and critical then
			local errorEvent = IOEvent(msg)
			-- For critical handlers we want to make sure the event data gets sent to the CU for processing, but that the memory is discarded on failures
			-- These handlers (distribute, prune) severely modify global state, and partial updates are dangerous.
			-- So we json encode the error and the event data and then throw, so the CU will discard the memory and still process the event data.
			-- An alternative approach is to modify the implementation of ao.result - to also return the Output on error.
			-- Reference: https://github.com/permaweb/ao/blob/76a618722b201430a372894b3e2753ac01e63d3d/dev-cli/src/starters/lua/ao.lua#L284-L287
			local errorWithEvent = tostring(resultOrError) .. "\n" .. errorEvent:toJSON()
			error(errorWithEvent, 0) -- 0 ensures not to include this line number in the error message
		end
		-- isolate out prune handler here when printing
		if handlerName ~= "prune" then
			msg.ioEvent:printEvent()
		end
	end)
end

-- prune state before every interaction
-- NOTE: THIS IS A CRITICAL HANDLER AND WILL DISCARD THE MEMORY ON ERROR
addEventingHandler("prune", function()
	return "continue" -- continue is a pattern that matches every message and continues to the next handler that matches the tags
end, function(msg)
	local msgTimestamp = tonumber(msg.Timestamp or msg.Tags.Timestamp)
	assert(msgTimestamp, "Timestamp is required for a tick interaction")
	local epochIndex = epochs.getEpochIndexForTimestamp(msgTimestamp)
	msg.ioEvent:addField("epochIndex", epochIndex)

	local previousStateSupplies = {
		protocolBalance = Balances[Protocol],
		lastKnownCirculatingSupply = LastKnownCirculatingSupply,
		lastKnownLockedSupply = LastKnownLockedSupply,
		lastKnownStakedSupply = LastKnownStakedSupply,
		lastKnownDelegatedSupply = LastKnownDelegatedSupply,
		lastKnownWithdrawSupply = LastKnownWithdrawSupply,
		lastKnownTotalSupply = token.lastKnownTotalTokenSupply(),
	}

	msg.From = utils.formatAddress(msg.From)
	msg.Timestamp = msg.Timestamp and tonumber(msg.Timestamp) or nil

	local knownAddressTags = {
		"Recipient",
		"Initiator",
		"Target",
		"Source",
		"Address",
		"Vault-Id",
		"Process-Id",
		"Observer-Address",
	}

	for _, tagName in ipairs(knownAddressTags) do
		-- Format all incoming addresses
		msg.Tags[tagName] = msg.Tags[tagName] and utils.formatAddress(msg.Tags[tagName]) or nil
	end

	local knownNumberTags = {
		"Quantity",
		"Lock-Length",
		"Operator-Stake",
		"Delegated-Stake",
		"Withdraw-Stake",
		"Timestamp",
		"Years",
		"Min-Delegated-Stake",
		"Port",
		"Extend-Length",
		"Delegate-Reward-Share-Ratio",
		"Epoch-Index",
		"Price-Interval-Ms",
		"Block-Height",
	}
	for _, tagName in ipairs(knownNumberTags) do
		-- Format all incoming numbers
		msg.Tags[tagName] = msg.Tags[tagName] and tonumber(msg.Tags[tagName]) or nil
	end

	local knownBooleanTags = {
		"Allow-Unsafe-Addresses",
		"Force-Prune",
	}
	for _, tagName in ipairs(knownBooleanTags) do
		msg.Tags[tagName] = msg.Tags[tagName] and msg.Tags[tagName] == "true" or false
	end

	if msg.Tags["Force-Prune"] then
		gar.scheduleNextGatewaysPruning(0)
		gar.scheduleNextRedelegationsPruning(0)
		arns.scheduleNextAuctionsPrune(0)
		arns.scheduleNextRecordsPrune(0)
		primaryNames.scheduleNextPrimaryNamesPruning(0)
		vaults.scheduleNextVaultsPruning(0)
	end

	local msgId = msg.Id
	print("Pruning state at timestamp: " .. msgTimestamp)
	local prunedStateResult = prune.pruneState(msgTimestamp, msgId, LastGracePeriodEntryEndTimestamp)

	if prunedStateResult then
		local prunedRecordsCount = utils.lengthOfTable(prunedStateResult.prunedRecords or {})
		if prunedRecordsCount > 0 then
			local prunedRecordNames = {}
			for name, _ in pairs(prunedStateResult.prunedRecords) do
				table.insert(prunedRecordNames, name)
			end
			msg.ioEvent:addField("Pruned-Records", prunedRecordNames)
			msg.ioEvent:addField("Pruned-Records-Count", prunedRecordsCount)
			msg.ioEvent:addField("Records-Count", utils.lengthOfTable(NameRegistry.records))
		end
		local newGracePeriodRecordsCount = utils.lengthOfTable(prunedStateResult.newGracePeriodRecords or {})
		if newGracePeriodRecordsCount > 0 then
			local newGracePeriodRecordNames = {}
			for name, record in pairs(prunedStateResult.newGracePeriodRecords) do
				table.insert(newGracePeriodRecordNames, name)
				if record.endTimestamp > LastGracePeriodEntryEndTimestamp then
					LastGracePeriodEntryEndTimestamp = record.endTimestamp
				end
			end
			msg.ioEvent:addField("New-Grace-Period-Records", newGracePeriodRecordNames)
			msg.ioEvent:addField("New-Grace-Period-Records-Count", newGracePeriodRecordsCount)
			msg.ioEvent:addField("Last-Grace-Period-Entry-End-Timestamp", LastGracePeriodEntryEndTimestamp)
		end
		local prunedAuctions = prunedStateResult.prunedAuctions or {}
		local prunedAuctionsCount = utils.lengthOfTable(prunedAuctions)
		if prunedAuctionsCount > 0 then
			msg.ioEvent:addField("Pruned-Auctions", prunedAuctions)
			msg.ioEvent:addField("Pruned-Auctions-Count", prunedAuctionsCount)
		end
		local prunedReserved = prunedStateResult.prunedReserved or {}
		local prunedReservedCount = utils.lengthOfTable(prunedReserved)
		if prunedReservedCount > 0 then
			msg.ioEvent:addField("Pruned-Reserved", prunedReserved)
			msg.ioEvent:addField("Pruned-Reserved-Count", prunedReservedCount)
		end
		local prunedVaultsCount = utils.lengthOfTable(prunedStateResult.prunedVaults or {})
		if prunedVaultsCount > 0 then
			msg.ioEvent:addField("Pruned-Vaults", prunedStateResult.prunedVaults)
			msg.ioEvent:addField("Pruned-Vaults-Count", prunedVaultsCount)
			for _, vault in pairs(prunedStateResult.prunedVaults) do
				LastKnownLockedSupply = LastKnownLockedSupply - vault.balance
				LastKnownCirculatingSupply = LastKnownCirculatingSupply + vault.balance
			end
		end
		local prunedEpochsCount = utils.lengthOfTable(prunedStateResult.prunedEpochs or {})
		if prunedEpochsCount > 0 then
			msg.ioEvent:addField("Pruned-Epochs", prunedStateResult.prunedEpochs)
			msg.ioEvent:addField("Pruned-Epochs-Count", prunedEpochsCount)
		end

		local pruneGatewaysResult = prunedStateResult.pruneGatewaysResult or {}
		addPruneGatewaysResult(msg.ioEvent, pruneGatewaysResult)

		local prunedPrimaryNameRequests = prunedStateResult.prunedPrimaryNameRequests or {}
		local prunedRequestsCount = utils.lengthOfTable(prunedPrimaryNameRequests)
		if prunedRequestsCount then
			msg.ioEvent:addField("Pruned-Requests-Count", prunedRequestsCount)
		end

		addNextPruneTimestampsResults(msg.ioEvent, prunedStateResult)
	end

	-- add supply data if it has changed since the last state
	if
		LastKnownCirculatingSupply ~= previousStateSupplies.lastKnownCirculatingSupply
		or LastKnownLockedSupply ~= previousStateSupplies.lastKnownLockedSupply
		or LastKnownStakedSupply ~= previousStateSupplies.lastKnownStakedSupply
		or LastKnownDelegatedSupply ~= previousStateSupplies.lastKnownDelegatedSupply
		or LastKnownWithdrawSupply ~= previousStateSupplies.lastKnownWithdrawSupply
		or Balances[Protocol] ~= previousStateSupplies.protocolBalance
		or token.lastKnownTotalTokenSupply() ~= previousStateSupplies.lastKnownTotalSupply
	then
		addSupplyData(msg.ioEvent)
	end

	return prunedStateResult
end, CRITICAL)

-- Write handlers
addEventingHandler(ActionMap.Transfer, utils.hasMatchingTag("Action", ActionMap.Transfer), function(msg)
	-- assert recipient is a valid arweave address
	local recipient = msg.Tags.Recipient
	local quantity = msg.Tags.Quantity
	local allowUnsafeAddresses = msg.Tags["Allow-Unsafe-Addresses"] or false
	assert(utils.isValidAddress(recipient, allowUnsafeAddresses), "Invalid recipient")
	assert(quantity > 0 and utils.isInteger(quantity), "Invalid quantity. Must be integer greater than 0")
	assert(recipient ~= msg.From, "Cannot transfer to self")

	msg.ioEvent:addField("RecipientFormatted", recipient)

	local result = balances.transfer(recipient, msg.From, quantity, allowUnsafeAddresses)
	if result ~= nil then
		local senderNewBalance = result[msg.From]
		local recipientNewBalance = result[recipient]
		msg.ioEvent:addField("SenderPreviousBalance", senderNewBalance + quantity)
		msg.ioEvent:addField("SenderNewBalance", senderNewBalance)
		msg.ioEvent:addField("RecipientPreviousBalance", recipientNewBalance - quantity)
		msg.ioEvent:addField("RecipientNewBalance", recipientNewBalance)
	end

	-- Casting implies that the sender does not want a response - Reference: https://elixirforum.com/t/what-is-the-etymology-of-genserver-cast/33610/3
	if not msg.Cast then
		-- Debit-Notice message template, that is sent to the Sender of the transfer
		local debitNotice = {
			Target = msg.From,
			Action = "Debit-Notice",
			Recipient = recipient,
			Quantity = tostring(quantity),
			["Allow-Unsafe-Addresses"] = allowUnsafeAddresses,
			Data = "You transferred " .. msg.Tags.Quantity .. " to " .. recipient,
		}
		-- Credit-Notice message template, that is sent to the Recipient of the transfer
		local creditNotice = {
			Target = recipient,
			Action = "Credit-Notice",
			Sender = msg.From,
			Quantity = tostring(quantity),
			["Allow-Unsafe-Addresses"] = allowUnsafeAddresses,
			Data = "You received " .. msg.Tags.Quantity .. " from " .. msg.From,
		}

		-- Add forwarded tags to the credit and debit notice messages
		local didForwardTags = false
		for tagName, tagValue in pairs(msg) do
			-- Tags beginning with "X-" are forwarded
			if string.sub(tagName, 1, 2) == "X-" then
				debitNotice[tagName] = tagValue
				creditNotice[tagName] = tagValue
				didForwardTags = true
				msg.ioEvent:addField(tagName, tagValue)
			end
		end
		if didForwardTags then
			msg.ioEvent:addField("ForwardedTags", "true")
		end

		-- Send Debit-Notice and Credit-Notice
		Send(msg, debitNotice)
		Send(msg, creditNotice)
	end
end)

addEventingHandler(ActionMap.CreateVault, utils.hasMatchingTag("Action", ActionMap.CreateVault), function(msg)
	local quantity = msg.Tags.Quantity
	local lockLengthMs = msg.Tags["Lock-Length"]
	local timestamp = msg.Timestamp
	local msgId = msg.Id
	assert(
		lockLengthMs and lockLengthMs > 0 and utils.isInteger(lockLengthMs),
		"Invalid lock length. Must be integer greater than 0"
	)
	assert(
		quantity and utils.isInteger(quantity) and quantity >= constants.MIN_VAULT_SIZE,
		"Invalid quantity. Must be integer greater than or equal to " .. constants.MIN_VAULT_SIZE .. " mIO"
	)
	assert(timestamp, "Timestamp is required for a tick interaction")
	local vault = vaults.createVault(msg.From, quantity, lockLengthMs, timestamp, msgId)

	if vault ~= nil then
		msg.ioEvent:addField("Vault-Id", msgId)
		msg.ioEvent:addField("Vault-Balance", vault.balance)
		msg.ioEvent:addField("Vault-Start-Timestamp", vault.startTimestamp)
		msg.ioEvent:addField("Vault-End-Timestamp", vault.endTimestamp)
	end

	LastKnownLockedSupply = LastKnownLockedSupply + quantity
	LastKnownCirculatingSupply = LastKnownCirculatingSupply - quantity
	addSupplyData(msg.ioEvent)

	Send(msg, {
		Target = msg.From,
		Tags = {
			Action = ActionMap.CreateVault .. "-Notice",
			["Vault-Id"] = msgId,
		},
		Data = json.encode(vault),
	})
end)

addEventingHandler(ActionMap.VaultedTransfer, utils.hasMatchingTag("Action", ActionMap.VaultedTransfer), function(msg)
	local recipient = msg.Tags.Recipient
	local quantity = msg.Tags.Quantity
	local lockLengthMs = msg.Tags["Lock-Length"]
	local timestamp = msg.Timestamp
	local msgId = msg.Id
	local allowUnsafeAddresses = msg.Tags["Allow-Unsafe-Addresses"] or false
	assert(utils.isValidAddress(recipient, allowUnsafeAddresses), "Invalid recipient")
	assert(
		lockLengthMs and lockLengthMs > 0 and utils.isInteger(lockLengthMs),
		"Invalid lock length. Must be integer greater than 0"
	)
	assert(
		quantity and utils.isInteger(quantity) and quantity >= constants.MIN_VAULT_SIZE,
		"Invalid quantity. Must be integer greater than or equal to " .. constants.MIN_VAULT_SIZE .. " mIO"
	)
	assert(timestamp, "Timestamp is required for a tick interaction")
	assert(recipient ~= msg.From, "Cannot transfer to self")

	local vault =
		vaults.vaultedTransfer(msg.From, recipient, quantity, lockLengthMs, timestamp, msgId, allowUnsafeAddresses)

	if vault ~= nil then
		msg.ioEvent:addField("Vault-Id", msgId)
		msg.ioEvent:addField("Vault-Balance", vault.balance)
		msg.ioEvent:addField("Vault-Start-Timestamp", vault.startTimestamp)
		msg.ioEvent:addField("Vault-End-Timestamp", vault.endTimestamp)
	end

	LastKnownLockedSupply = LastKnownLockedSupply + quantity
	LastKnownCirculatingSupply = LastKnownCirculatingSupply - quantity
	addSupplyData(msg.ioEvent)

	-- sender gets an immediate debit notice as the quantity is debited from their balance
	Send(msg, {
		Target = msg.From,
		Recipient = recipient,
		Quantity = quantity,
		Tags = { Action = "Debit-Notice", ["Vault-Id"] = msgId, ["Allow-Unsafe-Addresses"] = allowUnsafeAddresses },
		Data = json.encode(vault),
	})
	-- to the receiver, they get a vault notice
	Send(msg, {
		Target = recipient,
		Quantity = quantity,
		Sender = msg.From,
		Tags = {
			Action = ActionMap.CreateVault .. "-Notice",
			["Vault-Id"] = msgId,
			["Allow-Unsafe-Addresses"] = allowUnsafeAddresses,
		},
		Data = json.encode(vault),
	})
end)

addEventingHandler(ActionMap.ExtendVault, utils.hasMatchingTag("Action", ActionMap.ExtendVault), function(msg)
	local vaultId = msg.Tags["Vault-Id"]
	local timestamp = msg.Timestamp
	local extendLengthMs = msg.Tags["Extend-Length"]
	assert(utils.isValidAddress(vaultId, true), "Invalid vault id")
	assert(
		extendLengthMs and extendLengthMs > 0 and utils.isInteger(extendLengthMs),
		"Invalid extension length. Must be integer greater than 0"
	)
	assert(timestamp, "Timestamp is required for a tick interaction")

	local vault = vaults.extendVault(msg.From, extendLengthMs, timestamp, vaultId)

	if vault ~= nil then
		msg.ioEvent:addField("Vault-Id", vaultId)
		msg.ioEvent:addField("Vault-Balance", vault.balance)
		msg.ioEvent:addField("Vault-Start-Timestamp", vault.startTimestamp)
		msg.ioEvent:addField("Vault-End-Timestamp", vault.endTimestamp)
		msg.ioEvent:addField("Vault-Prev-End-Timestamp", vault.endTimestamp - extendLengthMs)
	end

	Send(msg, {
		Target = msg.From,
		Tags = { Action = ActionMap.ExtendVault .. "-Notice" },
		Data = json.encode(vault),
	})
end)

addEventingHandler(ActionMap.IncreaseVault, utils.hasMatchingTag("Action", ActionMap.IncreaseVault), function(msg)
	local vaultId = msg.Tags["Vault-Id"]
	local quantity = msg.Tags.Quantity
	assert(utils.isValidAddress(vaultId, true), "Invalid vault id")
	assert(quantity and quantity > 0 and utils.isInteger(quantity), "Invalid quantity. Must be integer greater than 0")

	local vault = vaults.increaseVault(msg.From, quantity, vaultId, msg.Timestamp)

	if vault ~= nil then
		msg.ioEvent:addField("Vault-Id", vaultId)
		msg.ioEvent:addField("VaultBalance", vault.balance)
		msg.ioEvent:addField("VaultPrevBalance", vault.balance - quantity)
		msg.ioEvent:addField("VaultStartTimestamp", vault.startTimestamp)
		msg.ioEvent:addField("VaultEndTimestamp", vault.endTimestamp)
	end

	LastKnownLockedSupply = LastKnownLockedSupply + quantity
	LastKnownCirculatingSupply = LastKnownCirculatingSupply - quantity
	addSupplyData(msg.ioEvent)

	Send(msg, {
		Target = msg.From,
		Tags = { Action = ActionMap.IncreaseVault .. "-Notice" },
		Data = json.encode(vault),
	})
end)

addEventingHandler(ActionMap.BuyRecord, utils.hasMatchingTag("Action", ActionMap.BuyRecord), function(msg)
	local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
	local purchaseType = msg.Tags["Purchase-Type"] and string.lower(msg.Tags["Purchase-Type"]) or "lease"
	local years = msg.Tags.Years or nil
	local processId = msg.Tags["Process-Id"]
	local timestamp = msg.Timestamp
	local fundFrom = msg.Tags["Fund-From"]
	local allowUnsafeProcessId = msg.Tags["Allow-Unsafe-Addresses"]
	assert(
		type(purchaseType) == "string" and purchaseType == "lease" or purchaseType == "permabuy",
		"Invalid purchase type"
	)
	assert(timestamp, "Timestamp is required for a tick interaction")
	arns.assertValidArNSName(name)
	assert(utils.isValidAddress(processId, true), "Process Id must be a valid address.")
	if years then
		assert(years >= 1 and years <= 5 and utils.isInteger(years), "Invalid years. Must be integer between 1 and 5")
	end
	assertValidFundFrom(fundFrom)

	msg.ioEvent:addField("Name-Length", #name)

	local result = arns.buyRecord(
		name,
		purchaseType,
		years,
		msg.From,
		timestamp,
		processId,
		msg.Id,
		fundFrom,
		allowUnsafeProcessId
	)
	local record = {}
	if result ~= nil then
		record = result.record
		addRecordResultFields(msg.ioEvent, result)
		addSupplyData(msg.ioEvent)
	end

	msg.ioEvent:addField("Records-Count", utils.lengthOfTable(NameRegistry.records))

	-- TODO: Send back fundingPlan and fundingResult as well?
	Send(msg, {
		Target = msg.From,
		Tags = { Action = ActionMap.BuyRecord .. "-Notice", Name = name },
		Data = json.encode(fundFrom and result or {
			name = name,
			startTimestamp = record.startTimestamp,
			endTimestamp = record.endTimestamp,
			undernameLimit = record.undernameLimit,
			purchasePrice = record.purchasePrice,
			processId = record.processId,
		}),
	})
end)

addEventingHandler("upgradeName", utils.hasMatchingTag("Action", ActionMap.UpgradeName), function(msg)
	local fundFrom = msg.Tags["Fund-From"]
	local name = string.lower(msg.Tags.Name)
	local timestamp = msg.Timestamp
	assert(type(name) == "string", "Invalid name")
	assert(timestamp, "Timestamp is required")
	assertValidFundFrom(fundFrom)

	local result = arns.upgradeRecord(msg.From, name, timestamp, msg.Id, fundFrom)

	local record = {}
	if result ~= nil then
		record = result.record
		addRecordResultFields(msg.ioEvent, result)
		addSupplyData(msg.ioEvent)
	end

	Send(msg, {
		Target = msg.From,
		Tags = { Action = ActionMap.UpgradeName .. "-Notice", Name = name },
		Data = json.encode(fundFrom and result or {
			name = name,
			startTimestamp = record.startTimestamp,
			endTimestamp = record.endTimestamp,
			undernameLimit = record.undernameLimit,
			purchasePrice = record.purchasePrice,
			processId = record.processId,
			type = record.type,
		}),
	})
end)

addEventingHandler(ActionMap.ExtendLease, utils.hasMatchingTag("Action", ActionMap.ExtendLease), function(msg)
	local fundFrom = msg.Tags["Fund-From"]
	local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
	local years = msg.Tags.Years
	local timestamp = msg.Timestamp
	assert(type(name) == "string", "Invalid name")
	assert(
		years and years > 0 and years < 5 and utils.isInteger(years),
		"Invalid years. Must be integer between 1 and 5"
	)
	assert(timestamp, "Timestamp is required")
	assertValidFundFrom(fundFrom)
	local result = arns.extendLease(msg.From, name, years, timestamp, msg.Id, fundFrom)
	local recordResult = {}
	if result ~= nil then
		msg.ioEvent:addField("Total-Extension-Fee", result.totalExtensionFee)
		addRecordResultFields(msg.ioEvent, result)
		addSupplyData(msg.ioEvent)
		recordResult = result.record
	end

	Send(msg, {
		Target = msg.From,
		Tags = { Action = ActionMap.ExtendLease .. "-Notice", Name = name },
		Data = json.encode(fundFrom and result or recordResult),
	})
end)

addEventingHandler(
	ActionMap.IncreaseUndernameLimit,
	utils.hasMatchingTag("Action", ActionMap.IncreaseUndernameLimit),
	function(msg)
		local fundFrom = msg.Tags["Fund-From"]
		local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
		local quantity = msg.Tags.Quantity
		local timestamp = msg.Timestamp
		assert(type(name) == "string", "Invalid name")
		assert(
			quantity and quantity > 0 and quantity < 9990 and utils.isInteger(quantity),
			"Invalid quantity. Must be an integer value greater than 0 and less than 9990"
		)
		assert(timestamp, "Timestamp is required")
		assertValidFundFrom(fundFrom)

		local result = arns.increaseundernameLimit(msg.From, name, quantity, timestamp, msg.Id, fundFrom)
		local recordResult = {}
		if result ~= nil then
			recordResult = result.record
			addRecordResultFields(msg.ioEvent, result)
			msg.ioEvent:addField("previousUndernameLimit", recordResult.undernameLimit - msg.Tags.Quantity)
			msg.ioEvent:addField("additionalUndernameCost", result.additionalUndernameCost)
			addSupplyData(msg.ioEvent)
		end

		Send(msg, {
			Target = msg.From,
			Tags = {
				Action = ActionMap.IncreaseUndernameLimit .. "-Notice",
				Name = name,
			},
			Data = json.encode(fundFrom and result or recordResult),
		})
	end
)

function assertTokenCostTags(msg)
	local intentType = msg.Tags.Intent
	local validIntents = utils.createLookupTable({
		ActionMap.BuyRecord,
		ActionMap.ExtendLease,
		ActionMap.IncreaseUndernameLimit,
		ActionMap.UpgradeName,
		ActionMap.PrimaryNameRequest,
	})
	assert(
		intentType and type(intentType) == "string" and validIntents[intentType],
		"Intent must be valid registry interaction (e.g. Buy-Record, Extend-Lease, Increase-Undername-Limit, Upgrade-Name, Primary-Name-Request). Provided intent: "
			.. (intentType or "nil")
	)
	arns.assertValidArNSName(msg.Tags.Name)
	-- if years is provided, assert it is a number and integer between 1 and 5
	if msg.Tags.Years then
		assert(utils.isInteger(msg.Tags.Years), "Invalid years. Must be integer between 1 and 5")
	end

	-- if quantity provided must be a number and integer greater than 0
	if msg.Tags.Quantity then
		assert(utils.isInteger(msg.Tags.Quantity), "Invalid quantity. Must be integer greater than 0")
	end
end

addEventingHandler(ActionMap.TokenCost, utils.hasMatchingTag("Action", ActionMap.TokenCost), function(msg)
	assertTokenCostTags(msg)
	local intent = msg.Tags.Intent
	local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
	local years = msg.Tags.Years or nil
	local quantity = msg.Tags.Quantity or nil
	local purchaseType = msg.Tags["Purchase-Type"] or "lease"
	local timestamp = msg.Timestamp or msg.Tags.Timestamp

	local intendedAction = {
		intent = intent,
		name = name,
		years = years,
		quantity = quantity,
		purchaseType = purchaseType,
		currentTimestamp = timestamp,
		from = msg.From,
	}

	local tokenCostResult = arns.getTokenCost(intendedAction)
	local tokenCost = tokenCostResult.tokenCost

	Send(msg, {
		Target = msg.From,
		Tags = { Action = ActionMap.TokenCost .. "-Notice", ["Token-Cost"] = tostring(tokenCost) },
		Data = json.encode(tokenCost),
	})
end)

addEventingHandler(ActionMap.CostDetails, utils.hasMatchingTag("Action", ActionMap.CostDetails), function(msg)
	local fundFrom = msg.Tags["Fund-From"]
	local name = string.lower(msg.Tags.Name)
	local years = msg.Tags.Years or 1
	local quantity = msg.Tags.Quantity
	local purchaseType = msg.Tags["Purchase-Type"] or "lease"
	local timestamp = msg.Timestamp or msg.Tags.Timestamp
	assertTokenCostTags(msg)
	assertValidFundFrom(fundFrom)

	local tokenCostAndFundingPlan = arns.getTokenCostAndFundingPlanForIntent(
		msg.Tags.Intent,
		name,
		years,
		quantity,
		purchaseType,
		timestamp,
		msg.From,
		fundFrom
	)
	if not tokenCostAndFundingPlan then
		return
	end

	Send(msg, {
		Target = msg.From,
		Tags = { Action = ActionMap.CostDetails .. "-Notice" },
		Data = json.encode(tokenCostAndFundingPlan),
	})
end)

addEventingHandler(
	ActionMap.GetRegistrationFees,
	utils.hasMatchingTag("Action", ActionMap.GetRegistrationFees),
	function(msg)
		local priceList = arns.getRegistrationFees()

		Send(msg, {
			Target = msg.From,
			Tags = { Action = ActionMap.GetRegistrationFees .. "-Notice" },
			Data = json.encode(priceList),
		})
	end
)

addEventingHandler(ActionMap.JoinNetwork, utils.hasMatchingTag("Action", ActionMap.JoinNetwork), function(msg)
	-- TODO: add assertions on all the provided input, although the joinNetwork function will throw an error if the input is invalid

	local updatedSettings = {
		label = msg.Tags.Label,
		note = msg.Tags.Note,
		fqdn = msg.Tags.FQDN,
		port = msg.Tags.Port or 443,
		protocol = msg.Tags.Protocol or "https",
		allowDelegatedStaking = msg.Tags["Allow-Delegated-Staking"] == "true"
			or msg.Tags["Allow-Delegated-Staking"] == "allowlist",
		allowedDelegates = msg.Tags["Allow-Delegated-Staking"] == "allowlist"
				and utils.splitAndTrimString(msg.Tags["Allowed-Delegates"] or "", ",")
			or nil,
		minDelegatedStake = msg.Tags["Min-Delegated-Stake"],
		delegateRewardShareRatio = msg.Tags["Delegate-Reward-Share-Ratio"] or 0,
		properties = msg.Tags.Properties or "FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44",
		autoStake = msg.Tags["Auto-Stake"] == "true",
	}

	local updatedServices = utils.safeDecodeJson(msg.Tags.Services)
	local fromAddress = msg.From
	local observerAddress = msg.Tags["Observer-Address"] or fromAddress
	local stake = msg.Tags["Operator-Stake"]
	local timestamp = msg.Timestamp

	assert(not msg.Tags.Services or updatedServices, "Services must be a valid JSON string")

	msg.ioEvent:addField("Resolved-Observer-Address", observerAddress)
	msg.ioEvent:addField("Sender-Previous-Balance", Balances[fromAddress] or 0)

	local gateway = gar.joinNetwork(fromAddress, stake, updatedSettings, updatedServices, observerAddress, timestamp)
	msg.ioEvent:addField("Sender-New-Balance", Balances[fromAddress] or 0)
	if gateway ~= nil then
		msg.ioEvent:addField("GW-Start-Timestamp", gateway.startTimestamp)
	end
	local gwStats = gatewayStats()
	msg.ioEvent:addField("Joined-Gateways-Count", gwStats.joined)
	msg.ioEvent:addField("Leaving-Gateways-Count", gwStats.leaving)

	LastKnownCirculatingSupply = LastKnownCirculatingSupply - stake
	LastKnownStakedSupply = LastKnownStakedSupply + stake
	addSupplyData(msg.ioEvent)

	Send(msg, {
		Target = msg.From,
		Tags = { Action = ActionMap.JoinNetwork .. "-Notice" },
		Data = json.encode(gateway),
	})
end)

addEventingHandler(ActionMap.LeaveNetwork, utils.hasMatchingTag("Action", ActionMap.LeaveNetwork), function(msg)
	local timestamp = msg.Timestamp
	local unsafeGatewayBeforeLeaving = gar.getGatewayUnsafe(msg.From)
	local gwPrevTotalDelegatedStake = 0
	local gwPrevStake = 0
	if unsafeGatewayBeforeLeaving ~= nil then
		gwPrevTotalDelegatedStake = unsafeGatewayBeforeLeaving.totalDelegatedStake
		gwPrevStake = unsafeGatewayBeforeLeaving.operatorStake
	end

	assert(unsafeGatewayBeforeLeaving, "Gateway not found")
	assert(timestamp, "Timestamp is required")

	local gateway = gar.leaveNetwork(msg.From, timestamp, msg.Id)

	if gateway ~= nil then
		msg.ioEvent:addField("GW-Vaults-Count", utils.lengthOfTable(gateway.vaults or {}))
		local exitVault = gateway.vaults[msg.From]
		local withdrawVault = gateway.vaults[msg.Id]
		local previousStake = exitVault.balance
		if exitVault ~= nil then
			msg.ioEvent:addFieldsWithPrefixIfExist(
				exitVault,
				"Exit-Vault-",
				{ "balance", "startTimestamp", "endTimestamp" }
			)
		end
		if withdrawVault ~= nil then
			previousStake = previousStake + withdrawVault.balance
			msg.ioEvent:addFieldsWithPrefixIfExist(
				withdrawVault,
				"Withdraw-Vault-",
				{ "balance", "startTimestamp", "endTimestamp" }
			)
		end
		msg.ioEvent:addField("Previous-Operator-Stake", previousStake)
		msg.ioEvent:addFieldsWithPrefixIfExist(
			gateway,
			"GW-",
			{ "totalDelegatedStake", "observerAddress", "startTimestamp", "endTimestamp" }
		)
		msg.ioEvent:addFields(gateway.stats or {})
	end

	local gwStats = gatewayStats()
	msg.ioEvent:addField("Joined-Gateways-Count", gwStats.joined)
	msg.ioEvent:addField("Leaving-Gateways-Count", gwStats.leaving)

	LastKnownStakedSupply = LastKnownStakedSupply - gwPrevStake - gwPrevTotalDelegatedStake
	LastKnownWithdrawSupply = LastKnownWithdrawSupply + gwPrevStake + gwPrevTotalDelegatedStake
	addSupplyData(msg.ioEvent)

	Send(msg, {
		Target = msg.From,
		Tags = { Action = ActionMap.LeaveNetwork .. "-Notice" },
		Data = json.encode(gateway),
	})
end)

addEventingHandler(
	ActionMap.IncreaseOperatorStake,
	utils.hasMatchingTag("Action", ActionMap.IncreaseOperatorStake),
	function(msg)
		local quantity = msg.Tags.Quantity
		assert(
			quantity and utils.isInteger(quantity) and quantity > 0,
			"Invalid quantity. Must be integer greater than 0"
		)

		msg.ioEvent:addField("Sender-Previous-Balance", Balances[msg.From])
		local gateway = gar.increaseOperatorStake(msg.From, quantity)

		msg.ioEvent:addField("Sender-New-Balance", Balances[msg.From])
		if gateway ~= nil then
			msg.ioEvent:addField("New-Operator-Stake", gateway.operatorStake)
			msg.ioEvent:addField("Previous-Operator-Stake", gateway.operatorStake - quantity)
		end

		LastKnownCirculatingSupply = LastKnownCirculatingSupply - quantity
		LastKnownStakedSupply = LastKnownStakedSupply + quantity
		addSupplyData(msg.ioEvent)

		Send(msg, {
			Target = msg.From,
			Tags = { Action = ActionMap.IncreaseOperatorStake .. "-Notice" },
			Data = json.encode(gateway),
		})
	end
)

addEventingHandler(
	ActionMap.DecreaseOperatorStake,
	utils.hasMatchingTag("Action", ActionMap.DecreaseOperatorStake),
	function(msg)
		local quantity = msg.Tags.Quantity
		local instantWithdraw = msg.Tags.Instant and msg.Tags.Instant == "true" or false
		local timestamp = msg.Timestamp
		assert(timestamp, "Timestamp is required")
		assert(
			quantity and utils.isInteger(quantity) and quantity > constants.minimumWithdrawalAmount,
			"Invalid quantity. Must be integer greater than " .. constants.minimumWithdrawalAmount
		)
		assert(
			msg.Tags.Instant == nil or (msg.Tags.Instant == "true" or msg.Tags.Instant == "false"),
			"Instant must be a string with value 'true' or 'false'"
		)

		msg.ioEvent:addField("Sender-Previous-Balance", Balances[msg.From])

		local result = gar.decreaseOperatorStake(msg.From, quantity, timestamp, msg.Id, instantWithdraw)
		local decreaseOperatorStakeResult = {
			gateway = result and result.gateway or {},
			penaltyRate = result and result.penaltyRate or 0,
			expeditedWithdrawalFee = result and result.expeditedWithdrawalFee or 0,
			amountWithdrawn = result and result.amountWithdrawn or 0,
		}

		msg.ioEvent:addField("Sender-New-Balance", Balances[msg.From]) -- should be unchanged
		if result ~= nil and result.gateway ~= nil then
			local gateway = result.gateway
			local previousStake = gateway.operatorStake + quantity
			msg.ioEvent:addField("New-Operator-Stake", gateway.operatorStake)
			msg.ioEvent:addField("GW-Vaults-Count", utils.lengthOfTable(gateway.vaults or {}))
			if instantWithdraw then
				msg.ioEvent:addField("Instant-Withdrawal", instantWithdraw)
				msg.ioEvent:addField("Instant-Withdrawal-Fee", result.expeditedWithdrawalFee)
				msg.ioEvent:addField("Amount-Withdrawn", result.amountWithdrawn)
				msg.ioEvent:addField("Penalty-Rate", result.penaltyRate)
			end
			local decreaseStakeVault = gateway.vaults[msg.Id]
			if decreaseStakeVault ~= nil then
				previousStake = previousStake + decreaseStakeVault.balance
				msg.ioEvent:addFieldsWithPrefixIfExist(
					decreaseStakeVault,
					"Decrease-Stake-Vault-",
					{ "balance", "startTimestamp", "endTimestamp" }
				)
			end
			msg.ioEvent:addField("Previous-Operator-Stake", previousStake)
		end

		LastKnownStakedSupply = LastKnownStakedSupply - quantity
		LastKnownWithdrawSupply = LastKnownWithdrawSupply + quantity
		addSupplyData(msg.ioEvent)

		Send(msg, {
			Target = msg.From,
			Tags = {
				Action = ActionMap.DecreaseOperatorStake .. "-Notice",
				["Penalty-Rate"] = tostring(decreaseOperatorStakeResult.penaltyRate),
				["Expedited-Withdrawal-Fee"] = tostring(decreaseOperatorStakeResult.expeditedWithdrawalFee),
				["Amount-Withdrawn"] = tostring(decreaseOperatorStakeResult.amountWithdrawn),
			},
			Data = json.encode(decreaseOperatorStakeResult.gateway),
		})
	end
)

addEventingHandler(ActionMap.DelegateStake, utils.hasMatchingTag("Action", ActionMap.DelegateStake), function(msg)
	local gatewayTarget = msg.Tags.Target or msg.Tags.Address
	local quantity = msg.Tags.Quantity
	local timestamp = msg.Timestamp
	assert(utils.isValidAddress(gatewayTarget, true), "Invalid gateway address")
	assert(
		msg.Tags.Quantity and msg.Tags.Quantity > 0 and utils.isInteger(msg.Tags.Quantity),
		"Invalid quantity. Must be integer greater than 0"
	)

	msg.ioEvent:addField("Target-Formatted", gatewayTarget)

	local gateway = gar.delegateStake(msg.From, gatewayTarget, quantity, timestamp)
	local delegateResult = {}
	if gateway ~= nil then
		local newStake = gateway.delegates[msg.From].delegatedStake
		msg.ioEvent:addField("Previous-Stake", newStake - quantity)
		msg.ioEvent:addField("New-Stake", newStake)
		msg.ioEvent:addField("Gateway-Total-Delegated-Stake", gateway.totalDelegatedStake)
		delegateResult = gateway.delegates[msg.From]
	end

	LastKnownCirculatingSupply = LastKnownCirculatingSupply - quantity
	LastKnownDelegatedSupply = LastKnownDelegatedSupply + quantity
	addSupplyData(msg.ioEvent)

	Send(msg, {
		Target = msg.From,
		Tags = { Action = ActionMap.DelegateStake .. "-Notice", Gateway = gatewayTarget },
		Data = json.encode(delegateResult),
	})
end)

addEventingHandler(ActionMap.CancelWithdrawal, utils.hasMatchingTag("Action", ActionMap.CancelWithdrawal), function(msg)
	local gatewayAddress = msg.Tags.Target or msg.Tags.Address or msg.From
	local vaultId = msg.Tags["Vault-Id"]
	assert(utils.isValidAddress(gatewayAddress, true), "Invalid gateway address")
	assert(utils.isValidAddress(vaultId, true), "Invalid vault id")

	msg.ioEvent:addField("Target-Formatted", gatewayAddress)

	local result = gar.cancelGatewayWithdrawal(msg.From, gatewayAddress, vaultId)
	local updatedGateway = {}
	if result ~= nil then
		updatedGateway = result.gateway
		local vaultBalance = result.vaultBalance
		local previousOperatorStake = result.previousOperatorStake
		local newOperatorStake = result.totalOperatorStake
		local previousTotalDelegatedStake = result.previousTotalDelegatedStake
		local newTotalDelegatedStake = result.totalDelegatedStake
		local operatorStakeChange = newOperatorStake - previousOperatorStake
		local delegatedStakeChange = newTotalDelegatedStake - previousTotalDelegatedStake
		msg.ioEvent:addField("Previous-Operator-Stake", previousOperatorStake)
		msg.ioEvent:addField("New-Operator-Stake", newOperatorStake)
		msg.ioEvent:addField("Previous-Total-Delegated-Stake", previousTotalDelegatedStake)
		msg.ioEvent:addField("New-Total-Delegated-Stake", newTotalDelegatedStake)
		msg.ioEvent:addField("Stake-Amount-Withdrawn", vaultBalance)
		LastKnownStakedSupply = LastKnownStakedSupply + operatorStakeChange
		LastKnownDelegatedSupply = LastKnownDelegatedSupply + delegatedStakeChange
		LastKnownWithdrawSupply = LastKnownWithdrawSupply - vaultBalance
		addSupplyData(msg.ioEvent)
	end

	Send(msg, {
		Target = msg.From,
		Tags = {
			Action = ActionMap.CancelWithdrawal .. "-Notice",
			Address = gatewayAddress,
			["Vault-Id"] = msg.Tags["Vault-Id"],
		},
		Data = json.encode(updatedGateway),
	})
end)

addEventingHandler(
	ActionMap.InstantWithdrawal,
	utils.hasMatchingTag("Action", ActionMap.InstantWithdrawal),
	function(msg)
		local target = msg.Tags.Target or msg.Tags.Address or msg.From -- if not provided, use sender
		local vaultId = msg.Tags["Vault-Id"]
		local timestamp = msg.Timestamp
		msg.ioEvent:addField("Target-Formatted", target)
		assert(utils.isValidAddress(target, true), "Invalid gateway address")
		assert(utils.isValidAddress(vaultId, true), "Invalid vault id")
		assert(timestamp, "Timestamp is required")

		local result = gar.instantGatewayWithdrawal(msg.From, target, vaultId, timestamp)
		if result ~= nil then
			local vaultBalance = result.vaultBalance
			msg.ioEvent:addField("Stake-Amount-Withdrawn", vaultBalance)
			msg.ioEvent:addField("Vault-Elapsed-Time", result.elapsedTime)
			msg.ioEvent:addField("Vault-Remaining-Time", result.remainingTime)
			msg.ioEvent:addField("Penalty-Rate", result.penaltyRate)
			msg.ioEvent:addField("Instant-Withdrawal-Fee", result.expeditedWithdrawalFee)
			msg.ioEvent:addField("Amount-Withdrawn", result.amountWithdrawn)
			msg.ioEvent:addField("Previous-Vault-Balance", result.amountWithdrawn + result.expeditedWithdrawalFee)
			LastKnownCirculatingSupply = LastKnownCirculatingSupply + result.amountWithdrawn
			LastKnownWithdrawSupply = LastKnownWithdrawSupply - result.amountWithdrawn - result.expeditedWithdrawalFee
			addSupplyData(msg.ioEvent)
			Send(msg, {
				Target = msg.From,
				Tags = {
					Action = ActionMap.InstantWithdrawal .. "-Notice",
					Address = target,
					["Vault-Id"] = vaultId,
					["Amount-Withdrawn"] = tostring(result.amountWithdrawn),
					["Penalty-Rate"] = tostring(result.penaltyRate),
					["Expedited-Withdrawal-Fee"] = tostring(result.expeditedWithdrawalFee),
				},
				Data = json.encode(result),
			})
		end
	end
)

addEventingHandler(
	ActionMap.DecreaseDelegateStake,
	utils.hasMatchingTag("Action", ActionMap.DecreaseDelegateStake),
	function(msg)
		local target = msg.Tags.Target or msg.Tags.Address
		local quantity = msg.Tags.Quantity
		local instantWithdraw = msg.Tags.Instant and msg.Tags.Instant == "true" or false
		local timestamp = msg.Timestamp
		msg.ioEvent:addField("Target-Formatted", target)
		msg.ioEvent:addField("Quantity", quantity)
		assert(
			quantity and utils.isInteger(quantity) and quantity > constants.minimumWithdrawalAmount,
			"Invalid quantity. Must be integer greater than " .. constants.minimumWithdrawalAmount
		)

		local result = gar.decreaseDelegateStake(target, msg.From, quantity, timestamp, msg.Id, instantWithdraw)
		local decreaseDelegateStakeResult = {
			gateway = result and result.gateway or {},
			penaltyRate = result and result.penaltyRate or 0,
			expeditedWithdrawalFee = result and result.expeditedWithdrawalFee or 0,
			amountWithdrawn = result and result.amountWithdrawn or 0,
		}

		msg.ioEvent:addField("Sender-New-Balance", Balances[msg.From]) -- should be unchanged

		local delegateResult = {}
		if result ~= nil and result.gateway ~= nil then
			local gateway = result.gateway
			local newStake = gateway.delegates[msg.From].delegatedStake
			msg.ioEvent:addField("Previous-Stake", newStake + quantity)
			msg.ioEvent:addField("New-Stake", newStake)
			msg.ioEvent:addField("Gateway-Total-Delegated-Stake", gateway.totalDelegatedStake)

			if instantWithdraw then
				msg.ioEvent:addField("Instant-Withdrawal", instantWithdraw)
				msg.ioEvent:addField("Instant-Withdrawal-Fee", result.expeditedWithdrawalFee)
				msg.ioEvent:addField("Amount-Withdrawn", result.amountWithdrawn)
				msg.ioEvent:addField("Penalty-Rate", result.penaltyRate)
			end

			delegateResult = gateway.delegates[msg.From]
			local newDelegateVaults = delegateResult.vaults
			if newDelegateVaults ~= nil then
				msg.ioEvent:addField("Vaults-Count", utils.lengthOfTable(newDelegateVaults))
				local newDelegateVault = newDelegateVaults[msg.Id]
				if newDelegateVault ~= nil then
					msg.ioEvent:addField("Vault-Id", msg.Id)
					msg.ioEvent:addField("Vault-Balance", newDelegateVault.balance)
					msg.ioEvent:addField("Vault-Start-Timestamp", newDelegateVault.startTimestamp)
					msg.ioEvent:addField("Vault-End-Timestamp", newDelegateVault.endTimestamp)
				end
			end
		end

		LastKnownDelegatedSupply = LastKnownDelegatedSupply - quantity
		if not instantWithdraw then
			LastKnownWithdrawSupply = LastKnownWithdrawSupply + quantity
		end
		LastKnownCirculatingSupply = LastKnownCirculatingSupply + decreaseDelegateStakeResult.amountWithdrawn
		addSupplyData(msg.ioEvent)

		Send(msg, {
			Target = msg.From,
			Tags = {
				Action = ActionMap.DecreaseDelegateStake .. "-Notice",
				Address = target,
				Quantity = quantity,
				["Penalty-Rate"] = tostring(decreaseDelegateStakeResult.penaltyRate),
				["Expedited-Withdrawal-Fee"] = tostring(decreaseDelegateStakeResult.expeditedWithdrawalFee),
				["Amount-Withdrawn"] = tostring(decreaseDelegateStakeResult.amountWithdrawn),
			},
			Data = json.encode(delegateResult),
		})
	end
)

-- TODO: Update the UpdateGatewaySettings handler to consider replacing the allowedDelegates list
addEventingHandler(
	ActionMap.UpdateGatewaySettings,
	utils.hasMatchingTag("Action", ActionMap.UpdateGatewaySettings),
	function(msg)
		local unsafeGateway = gar.getGatewayUnsafe(msg.From)
		local updatedServices = utils.safeDecodeJson(msg.Tags.Services)

		assert(unsafeGateway, "Gateway not found")
		assert(not msg.Tags.Services or updatedServices, "Services must be provided if Services-Json is provided")
		-- keep defaults, but update any new ones

		-- If delegated staking is being fully enabled or disabled, clear the allowlist
		local allowDelegatedStakingOverride = msg.Tags["Allow-Delegated-Staking"]
		local enableOpenDelegatedStaking = allowDelegatedStakingOverride == "true"
		local enableLimitedDelegatedStaking = allowDelegatedStakingOverride == "allowlist"
		local disableDelegatedStaking = allowDelegatedStakingOverride == "false"
		local shouldClearAllowlist = enableOpenDelegatedStaking or disableDelegatedStaking
		local needNewAllowlist = not shouldClearAllowlist
			and (
				enableLimitedDelegatedStaking
				or (unsafeGateway.settings.allowedDelegatesLookup and msg.Tags["Allowed-Delegates"] ~= nil)
			)

		local updatedSettings = {
			label = msg.Tags.Label or unsafeGateway.settings.label,
			note = msg.Tags.Note or unsafeGateway.settings.note,
			fqdn = msg.Tags.FQDN or unsafeGateway.settings.fqdn,
			port = msg.Tags.Port or unsafeGateway.settings.port,
			protocol = msg.Tags.Protocol or unsafeGateway.settings.protocol,
			allowDelegatedStaking = enableOpenDelegatedStaking -- clear directive to enable
				or enableLimitedDelegatedStaking -- clear directive to enable
				or not disableDelegatedStaking -- NOT clear directive to DISABLE
					and unsafeGateway.settings.allowDelegatedStaking, -- otherwise unspecified, so use previous setting

			allowedDelegates = needNewAllowlist and utils.splitAndTrimString(msg.Tags["Allowed-Delegates"], ",") -- replace the lookup list
				or nil, -- change nothing

			minDelegatedStake = msg.Tags["Min-Delegated-Stake"] or unsafeGateway.settings.minDelegatedStake,
			delegateRewardShareRatio = msg.Tags["Delegate-Reward-Share-Ratio"]
				or unsafeGateway.settings.delegateRewardShareRatio,
			properties = msg.Tags.Properties or unsafeGateway.settings.properties,
			autoStake = not msg.Tags["Auto-Stake"] and unsafeGateway.settings.autoStake
				or msg.Tags["Auto-Stake"] == "true",
		}

		-- TODO: we could standardize this on our prepended handler to inject and ensure formatted addresses and converted values
		local observerAddress = msg.Tags["Observer-Address"] or unsafeGateway.observerAddress
		local timestamp = msg.Timestamp
		local result =
			gar.updateGatewaySettings(msg.From, updatedSettings, updatedServices, observerAddress, timestamp, msg.Id)
		Send(msg, {
			Target = msg.From,
			Tags = { Action = ActionMap.UpdateGatewaySettings .. "-Notice" },
			Data = json.encode(result),
		})
	end
)

addEventingHandler(ActionMap.ReassignName, utils.hasMatchingTag("Action", ActionMap.ReassignName), function(msg)
	local newProcessId = msg.Tags["Process-Id"]
	local name = string.lower(msg.Tags.Name)
	local initiator = msg.Tags.Initiator
	local timestamp = msg.Timestamp
	local allowUnsafeProcessId = msg.Tags["Allow-Unsafe-Addresses"]
	assert(name and #name > 0, "Name is required")
	assert(utils.isValidAddress(newProcessId, true), "Process Id must be a valid address.")
	assert(timestamp, "Timestamp is required")
	if initiator ~= nil then
		assert(utils.isValidAddress(initiator, true), "Invalid initiator address.")
	end

	local reassignment = arns.reassignName(name, msg.From, timestamp, newProcessId, allowUnsafeProcessId)

	Send(msg, {
		Target = msg.From,
		Action = ActionMap.ReassignName .. "-Notice",
		Name = name,
		Data = json.encode(reassignment),
	})

	if initiator ~= nil then
		Send(msg, {
			Target = initiator,
			Action = ActionMap.ReassignName .. "-Notice",
			Name = name,
			Data = json.encode(reassignment),
		})
	end
	return
end)

addEventingHandler(ActionMap.SaveObservations, utils.hasMatchingTag("Action", ActionMap.SaveObservations), function(msg)
	local reportTxId = msg.Tags["Report-Tx-Id"]
	local failedGateways = utils.splitAndTrimString(msg.Tags["Failed-Gateways"], ",")
	local timestamp = msg.Timestamp
	assert(utils.isValidArweaveAddress(reportTxId), "Invalid report tx id. Must be a valid Arweave address.")
	for _, gateway in ipairs(failedGateways) do
		assert(utils.isValidAddress(gateway, true), "Invalid failed gateway address: " .. gateway)
	end

	local observations = epochs.saveObservations(msg.From, reportTxId, failedGateways, timestamp)
	if observations ~= nil then
		local failureSummariesCount = utils.lengthOfTable(observations.failureSummaries or {})
		if failureSummariesCount > 0 then
			msg.ioEvent:addField("Failure-Summaries-Count", failureSummariesCount)
		end
		local reportsCount = utils.lengthOfTable(observations.reports or {})
		if reportsCount > 0 then
			msg.ioEvent:addField("Reports-Count", reportsCount)
		end
	end

	Send(msg, {
		Target = msg.From,
		Action = ActionMap.SaveObservations .. "-Notice",
		Data = json.encode(observations),
	})
end)

addEventingHandler(ActionMap.EpochSettings, utils.hasMatchingTag("Action", ActionMap.EpochSettings), function(msg)
	local epochSettings = epochs.getSettings()

	Send(msg, {
		Target = msg.From,
		Action = ActionMap.EpochSettings .. "-Notice",
		Data = json.encode(epochSettings),
	})
end)

addEventingHandler(
	ActionMap.DemandFactorSettings,
	utils.hasMatchingTag("Action", ActionMap.DemandFactorSettings),
	function(msg)
		local demandFactorSettings = demand.getSettings()
		Send(msg, {
			Target = msg.From,
			Action = ActionMap.DemandFactorSettings .. "-Notice",
			Data = json.encode(demandFactorSettings),
		})
	end
)

addEventingHandler(
	ActionMap.GatewayRegistrySettings,
	utils.hasMatchingTag("Action", ActionMap.GatewayRegistrySettings),
	function(msg)
		local gatewayRegistrySettings = gar.getSettings()
		Send(msg, {
			Target = msg.From,
			Action = ActionMap.GatewayRegistrySettings .. "-Notice",
			Data = json.encode(gatewayRegistrySettings),
		})
	end
)

-- Reference: https://github.com/permaweb/aos/blob/eea71b68a4f89ac14bf6797804f97d0d39612258/blueprints/token.lua#L264-L280
addEventingHandler("totalSupply", utils.hasMatchingTag("Action", ActionMap.TotalSupply), function(msg)
	assert(msg.From ~= ao.id, "Cannot call Total-Supply from the same process!")
	local totalSupplyDetails = token.computeTotalSupply()
	addSupplyData(msg.ioEvent, {
		totalTokenSupply = totalSupplyDetails.totalSupply,
	})
	msg.ioEvent:addField("Last-Known-Total-Token-Supply", token.lastKnownTotalTokenSupply())
	Send(msg, {
		Action = "Total-Supply",
		Data = tostring(totalSupplyDetails.totalSupply),
		Ticker = Ticker,
	})
end)

addEventingHandler("totalTokenSupply", utils.hasMatchingTag("Action", ActionMap.TotalTokenSupply), function(msg)
	local totalSupplyDetails = token.computeTotalSupply()
	addSupplyData(msg.ioEvent, {
		totalTokenSupply = totalSupplyDetails.totalSupply,
	})
	msg.ioEvent:addField("Last-Known-Total-Token-Supply", token.lastKnownTotalTokenSupply())

	Send(msg, {
		Target = msg.From,
		Action = ActionMap.TotalTokenSupply .. "-Notice",
		["Total-Supply"] = tostring(totalSupplyDetails.totalSupply),
		["Circulating-Supply"] = tostring(totalSupplyDetails.circulatingSupply),
		["Locked-Supply"] = tostring(totalSupplyDetails.lockedSupply),
		["Staked-Supply"] = tostring(totalSupplyDetails.stakedSupply),
		["Delegated-Supply"] = tostring(totalSupplyDetails.delegatedSupply),
		["Withdraw-Supply"] = tostring(totalSupplyDetails.withdrawSupply),
		["Protocol-Balance"] = tostring(totalSupplyDetails.protocolBalance),
		Data = json.encode({
			-- TODO: we are losing precision on these values unexpectedly. This has been brought to the AO team - for now the tags should be correct as they are stringified
			total = totalSupplyDetails.totalSupply,
			circulating = totalSupplyDetails.circulatingSupply,
			locked = totalSupplyDetails.lockedSupply,
			staked = totalSupplyDetails.stakedSupply,
			delegated = totalSupplyDetails.delegatedSupply,
			withdrawn = totalSupplyDetails.withdrawSupply,
			protocolBalance = totalSupplyDetails.protocolBalance,
		}),
	})
end)

-- distribute rewards
-- NOTE: THIS IS A CRITICAL HANDLER AND WILL DISCARD THE MEMORY ON ERROR
addEventingHandler("distribute", utils.hasMatchingTag("Action", "Tick"), function(msg)
	local msgTimestamp = msg.Timestamp
	local msgId = msg.Id
	local blockHeight = tonumber(msg["Block-Height"])
	local hashchain = msg["Hash-Chain"]
	local lastTickedEpochIndex = LastTickedEpochIndex
	local targetCurrentEpochIndex = epochs.getEpochIndexForTimestamp(msgTimestamp)

	assert(blockHeight, "Block height is required")
	assert(hashchain, "Hash chain is required")

	msg.ioEvent:addField("Last-Ticked-Epoch-Index", lastTickedEpochIndex)
	msg.ioEvent:addField("Current-Epoch-Index", lastTickedEpochIndex + 1)
	msg.ioEvent:addField("Target-Current-Epoch-Index", targetCurrentEpochIndex)

	-- if epoch index is -1 then we are before the genesis epoch and we should not tick
	if targetCurrentEpochIndex < 0 then
		-- do nothing and just send a notice back to the sender
		Send(msg, {
			Target = msg.From,
			Action = "Tick-Notice",
			LastTickedEpochIndex = LastTickedEpochIndex,
			Data = json.encode("Genesis epoch has not started yet."),
		})
		return
	end

	-- tick and distribute rewards for every index between the last ticked epoch and the current epoch
	local tickedEpochIndexes = {}
	local newEpochIndexes = {}
	local newDemandFactors = {}
	local newPruneGatewaysResults = {}
	local tickedRewardDistributions = {}
	local totalTickedRewardsDistributed = 0

	--- tick to the newest epoch, and stub out any epochs that are not yet created
	for i = lastTickedEpochIndex + 1, targetCurrentEpochIndex do
		local _, _, epochDistributionTimestamp = epochs.getEpochTimestampsForIndex(i)
		-- use the minimum of the msg timestamp or the epoch distribution timestamp, this ensures an epoch gets created for the genesis block
		-- and that we don't try and distribute before an epoch is created
		local tickTimestamp = math.min(msgTimestamp or 0, epochDistributionTimestamp)
		-- TODO: if we need to "recover" epochs, we can't rely on just the current message hashchain and block height,
		-- we should set the prescribed observers and names to empty arrays and distribute rewards accordingly
		local tickResult = tick.tickEpoch(tickTimestamp, blockHeight, hashchain, msgId)
		if tickTimestamp == epochDistributionTimestamp then
			-- if we are distributing rewards, we should update the last ticked epoch index to the current epoch index
			LastTickedEpochIndex = i
			table.insert(tickedEpochIndexes, i)
		end
		Send(msg, {
			Target = msg.From,
			Action = "Tick-Notice",
			LastTickedEpochIndex = tostring(LastTickedEpochIndex),
			Data = json.encode(tickResult),
		})
		if tickResult.maybeNewEpoch ~= nil then
			table.insert(newEpochIndexes, tickResult.maybeNewEpoch.epochIndex)
		end
		if tickResult.maybeDemandFactor ~= nil then
			table.insert(newDemandFactors, tickResult.maybeDemandFactor)
		end
		if tickResult.pruneGatewaysResult ~= nil then
			table.insert(newPruneGatewaysResults, tickResult.pruneGatewaysResult)
		end
		if tickResult.maybeDistributedEpoch ~= nil then
			tickedRewardDistributions[tostring(tickResult.maybeDistributedEpoch.epochIndex)] =
				tickResult.maybeDistributedEpoch.distributions.totalDistributedRewards
			totalTickedRewardsDistributed = totalTickedRewardsDistributed
				+ tickResult.maybeDistributedEpoch.distributions.totalDistributedRewards
		end
	end
	if #tickedEpochIndexes > 0 then
		msg.ioEvent:addField("Ticked-Epoch-Indexes", tickedEpochIndexes)
	end
	if #newEpochIndexes > 0 then
		msg.ioEvent:addField("New-Epoch-Indexes", newEpochIndexes)
		-- Only print the prescribed observers of the newest epoch
		local newestEpoch = epochs.getEpoch(math.max(table.unpack(newEpochIndexes)))
		local prescribedObserverAddresses = utils.map(newestEpoch.prescribedObservers, function(_, observer)
			return observer.gatewayAddress
		end)
		msg.ioEvent:addField("Prescribed-Observers", prescribedObserverAddresses)
	end
	if #newDemandFactors > 0 then
		msg.ioEvent:addField("New-Demand-Factors", newDemandFactors, ";")
	end
	if #newPruneGatewaysResults > 0 then
		-- Reduce the prune gateways results and then track changes
		local aggregatedPruneGatewaysResult = utils.reduce(
			newPruneGatewaysResults,
			function(acc, _, pruneGatewaysResult)
				for _, address in pairs(pruneGatewaysResult.prunedGateways) do
					table.insert(acc.prunedGateways, address)
				end
				for address, slashAmount in pairs(pruneGatewaysResult.slashedGateways) do
					acc.slashedGateways[address] = (acc.slashedGateways[address] or 0) + slashAmount
				end
				acc.gatewayStakeReturned = acc.gatewayStakeReturned + pruneGatewaysResult.gatewayStakeReturned
				acc.delegateStakeReturned = acc.delegateStakeReturned + pruneGatewaysResult.delegateStakeReturned
				acc.gatewayStakeWithdrawing = acc.gatewayStakeWithdrawing + pruneGatewaysResult.gatewayStakeWithdrawing
				acc.delegateStakeWithdrawing = acc.delegateStakeWithdrawing
					+ pruneGatewaysResult.delegateStakeWithdrawing
				acc.stakeSlashed = acc.stakeSlashed + pruneGatewaysResult.stakeSlashed
				return acc
			end,
			{
				prunedGateways = {},
				slashedGateways = {},
				gatewayStakeReturned = 0,
				delegateStakeReturned = 0,
				gatewayStakeWithdrawing = 0,
				delegateStakeWithdrawing = 0,
				stakeSlashed = 0,
			}
		)
		addPruneGatewaysResult(msg.ioEvent, aggregatedPruneGatewaysResult)
	end
	if utils.lengthOfTable(tickedRewardDistributions) > 0 then
		msg.ioEvent:addField("Ticked-Reward-Distributions", tickedRewardDistributions)
		msg.ioEvent:addField("Total-Ticked-Rewards-Distributed", totalTickedRewardsDistributed)
		LastKnownCirculatingSupply = LastKnownCirculatingSupply + totalTickedRewardsDistributed
	end

	local gwStats = gatewayStats()
	msg.ioEvent:addField("Joined-Gateways-Count", gwStats.joined)
	msg.ioEvent:addField("Leaving-Gateways-Count", gwStats.leaving)
	addSupplyData(msg.ioEvent)
end, CRITICAL)

-- READ HANDLERS

addEventingHandler(ActionMap.Info, Handlers.utils.hasMatchingTag("Action", ActionMap.Info), function(msg)
	local handlers = Handlers.list
	local handlerNames = {}

	for _, handler in ipairs(handlers) do
		table.insert(handlerNames, handler.name)
	end

	Send(msg, {
		Target = msg.From,
		Action = "Info-Notice",
		Tags = {
			Name = Name,
			Ticker = Ticker,
			Logo = Logo,
			Owner = Owner,
			Denomination = tostring(Denomination),
			LastTickedEpochIndex = tostring(LastTickedEpochIndex),
			Handlers = json.encode(handlerNames),
		},
		Data = json.encode({
			Name = Name,
			Ticker = Ticker,
			Logo = Logo,
			Owner = Owner,
			Denomination = Denomination,
			LastTickedEpochIndex = LastTickedEpochIndex,
			Handlers = handlerNames,
		}),
	})
end)

addEventingHandler(ActionMap.Gateway, Handlers.utils.hasMatchingTag("Action", ActionMap.Gateway), function(msg)
	local gateway = gar.getCompactGateway(msg.Tags.Address or msg.From)
	Send(msg, {
		Target = msg.From,
		Action = "Gateway-Notice",
		Gateway = msg.Tags.Address or msg.From,
		Data = json.encode(gateway),
	})
end)

--- TODO: we want to remove this but need to ensure we don't break downstream apps
addEventingHandler(ActionMap.Balances, Handlers.utils.hasMatchingTag("Action", ActionMap.Balances), function(msg)
	Send(msg, {
		Target = msg.From,
		Action = "Balances-Notice",
		Data = json.encode(Balances),
	})
end)

addEventingHandler(ActionMap.Balance, Handlers.utils.hasMatchingTag("Action", ActionMap.Balance), function(msg)
	local target = msg.Tags.Target or msg.Tags.Address or msg.From
	local balance = balances.getBalance(target)

	-- must adhere to token.lua spec for arconnect compatibility
	Send(msg, {
		Target = msg.From,
		Action = "Balance-Notice",
		Data = balance,
		Balance = tostring(balance),
		Ticker = Ticker,
		Address = target,
	})
end)

addEventingHandler(ActionMap.DemandFactor, utils.hasMatchingTag("Action", ActionMap.DemandFactor), function(msg)
	local demandFactor = demand.getDemandFactor()
	Send(msg, {
		Target = msg.From,
		Action = "Demand-Factor-Notice",
		Data = json.encode(demandFactor),
	})
end)

addEventingHandler(ActionMap.DemandFactorInfo, utils.hasMatchingTag("Action", ActionMap.DemandFactorInfo), function(msg)
	local result = demand.getDemandFactorInfo()
	Send(msg, { Target = msg.From, Action = "Demand-Factor-Info-Notice", Data = json.encode(result) })
end)

addEventingHandler(ActionMap.Record, utils.hasMatchingTag("Action", ActionMap.Record), function(msg)
	local record = arns.getRecord(msg.Tags.Name)

	local recordNotice = {
		Target = msg.From,
		Action = "Record-Notice",
		Name = msg.Tags.Name,
		Data = json.encode(record),
	}

	-- Add forwarded tags to the credit and debit notice messages
	for tagName, tagValue in pairs(msg) do
		-- Tags beginning with "X-" are forwarded
		if string.sub(tagName, 1, 2) == "X-" then
			recordNotice[tagName] = tagValue
		end
	end

	-- Send Record-Notice
	Send(msg, recordNotice)
end)

addEventingHandler(ActionMap.Epoch, utils.hasMatchingTag("Action", ActionMap.Epoch), function(msg)
	-- check if the epoch number is provided, if not get the epoch number from the timestamp
	local providedEpochIndex = msg.Tags["Epoch-Index"]
	local timestamp = msg.Timestamp

	assert(providedEpochIndex or timestamp, "Epoch index or timestamp is required")

	local epochIndex = providedEpochIndex or epochs.getEpochIndexForTimestamp(timestamp)
	local epoch = epochs.getEpoch(epochIndex)
	Send(msg, { Target = msg.From, Action = "Epoch-Notice", Data = json.encode(epoch) })
end)

addEventingHandler(ActionMap.Epochs, utils.hasMatchingTag("Action", ActionMap.Epochs), function(msg)
	local allEpochs = epochs.getEpochs()

	Send(msg, { Target = msg.From, Action = "Epochs-Notice", Data = json.encode(allEpochs) })
end)

addEventingHandler(
	ActionMap.PrescribedObservers,
	utils.hasMatchingTag("Action", ActionMap.PrescribedObservers),
	function(msg)
		-- check if the epoch number is provided, if not get the epoch number from the timestamp
		local providedEpochIndex = msg.Tags["Epoch-Index"]
		local timestamp = msg.Timestamp

		assert(providedEpochIndex or timestamp, "Epoch index or timestamp is required")

		local epochIndex = providedEpochIndex or epochs.getEpochIndexForTimestamp(timestamp)
		local prescribedObservers = epochs.getPrescribedObserversForEpoch(epochIndex)
		Send(msg, {
			Target = msg.From,
			Action = "Prescribed-Observers-Notice",
			Data = json.encode(prescribedObservers),
		})
	end
)

addEventingHandler(ActionMap.Observations, utils.hasMatchingTag("Action", ActionMap.Observations), function(msg)
	local providedEpochIndex = msg.Tags["Epoch-Index"]
	local timestamp = msg.Timestamp

	assert(providedEpochIndex or timestamp, "Epoch index or timestamp is required")

	local epochIndex = providedEpochIndex or epochs.getEpochIndexForTimestamp(timestamp)
	local observations = epochs.getObservationsForEpoch(epochIndex)
	Send(msg, {
		Target = msg.From,
		Action = "Observations-Notice",
		EpochIndex = tostring(epochIndex),
		Data = json.encode(observations),
	})
end)

addEventingHandler(ActionMap.PrescribedNames, utils.hasMatchingTag("Action", ActionMap.PrescribedNames), function(msg)
	-- check if the epoch number is provided, if not get the epoch number from the timestamp
	local providedEpochIndex = msg.Tags["Epoch-Index"]
	local timestamp = msg.Timestamp

	assert(providedEpochIndex or timestamp, "Epoch index or timestamp is required")

	local epochIndex = providedEpochIndex or epochs.getEpochIndexForTimestamp(timestamp)
	local prescribedNames = epochs.getPrescribedNamesForEpoch(epochIndex)
	Send(msg, {
		Target = msg.From,
		Action = "Prescribed-Names-Notice",
		Data = json.encode(prescribedNames),
	})
end)

addEventingHandler(ActionMap.Distributions, utils.hasMatchingTag("Action", ActionMap.Distributions), function(msg)
	-- check if the epoch number is provided, if not get the epoch number from the timestamp
	local providedEpochIndex = msg.Tags["Epoch-Index"]
	local timestamp = msg.Timestamp

	assert(providedEpochIndex or timestamp, "Epoch index or timestamp is required")

	local epochIndex = providedEpochIndex or epochs.getEpochIndexForTimestamp(timestamp)
	local distributions = epochs.getDistributionsForEpoch(epochIndex)
	Send(msg, {
		Target = msg.From,
		Action = "Distributions-Notice",
		Data = json.encode(distributions),
	})
end)

addEventingHandler("paginatedReservedNames", utils.hasMatchingTag("Action", ActionMap.ReservedNames), function(msg)
	local page = utils.parsePaginationTags(msg)
	local reservedNames = arns.getPaginatedReservedNames(page.cursor, page.limit, page.sortBy or "name", page.sortOrder)
	Send(msg, { Target = msg.From, Action = "Reserved-Names-Notice", Data = json.encode(reservedNames) })
end)

addEventingHandler(ActionMap.ReservedName, utils.hasMatchingTag("Action", ActionMap.ReservedName), function(msg)
	local name = msg.Tags.Name and string.lower(msg.Tags.Name)
	assert(name, "Name is required")
	local reservedName = arns.getReservedName(name)
	Send(msg, {
		Target = msg.From,
		Action = "Reserved-Name-Notice",
		ReservedName = msg.Tags.Name,
		Data = json.encode(reservedName),
	})
end)

addEventingHandler(ActionMap.Vault, utils.hasMatchingTag("Action", ActionMap.Vault), function(msg)
	local address = msg.Tags.Address or msg.From
	local vaultId = msg.Tags["Vault-Id"]
	local vault = vaults.getVault(address, vaultId)
	assert(vault, "Vault not found")
	Send(msg, {
		Target = msg.From,
		Action = "Vault-Notice",
		Address = address,
		["Vault-Id"] = vaultId,
		Data = json.encode(vault),
	})
end)

-- Pagination handlers

addEventingHandler("paginatedRecords", function(msg)
	return msg.Action == "Paginated-Records" or msg.Action == ActionMap.Records
end, function(msg)
	local page = utils.parsePaginationTags(msg)
	local result = arns.getPaginatedRecords(page.cursor, page.limit, page.sortBy or "startTimestamp", page.sortOrder)
	Send(msg, { Target = msg.From, Action = "Records-Notice", Data = json.encode(result) })
end)

addEventingHandler("paginatedGateways", function(msg)
	return msg.Action == "Paginated-Gateways" or msg.Action == ActionMap.Gateways
end, function(msg)
	local page = utils.parsePaginationTags(msg)
	local result =
		gar.getPaginatedGateways(page.cursor, page.limit, page.sortBy or "startTimestamp", page.sortOrder or "desc")
	Send(msg, { Target = msg.From, Action = "Gateways-Notice", Data = json.encode(result) })
end)

--- TODO: make this support `Balances` requests
addEventingHandler("paginatedBalances", utils.hasMatchingTag("Action", "Paginated-Balances"), function(msg)
	local page = utils.parsePaginationTags(msg)
	local walletBalances =
		balances.getPaginatedBalances(page.cursor, page.limit, page.sortBy or "balance", page.sortOrder)
	Send(msg, { Target = msg.From, Action = "Balances-Notice", Data = json.encode(walletBalances) })
end)

addEventingHandler("paginatedVaults", function(msg)
	return msg.Action == "Paginated-Vaults" or msg.Action == ActionMap.Vaults
end, function(msg)
	local page = utils.parsePaginationTags(msg)
	local pageVaults = vaults.getPaginatedVaults(page.cursor, page.limit, page.sortOrder, page.sortBy)
	Send(msg, { Target = msg.From, Action = "Vaults-Notice", Data = json.encode(pageVaults) })
end)

addEventingHandler("paginatedDelegates", function(msg)
	return msg.Action == "Paginated-Delegates" or msg.Action == ActionMap.Delegates
end, function(msg)
	local page = utils.parsePaginationTags(msg)
	local result = gar.getPaginatedDelegates(
		msg.Tags.Address or msg.From,
		page.cursor,
		page.limit,
		page.sortBy or "startTimestamp",
		page.sortOrder
	)
	Send(msg, { Target = msg.From, Action = "Delegates-Notice", Data = json.encode(result) })
end)

addEventingHandler(
	"paginatedAllowedDelegates",
	utils.hasMatchingTag("Action", "Paginated-Allowed-Delegates"),
	function(msg)
		local page = utils.parsePaginationTags(msg)
		local result =
			gar.getPaginatedAllowedDelegates(msg.Tags.Address or msg.From, page.cursor, page.limit, page.sortOrder)
		Send(msg, { Target = msg.From, Action = "Allowed-Delegates-Notice", Data = json.encode(result) })
	end
)

-- END READ HANDLERS

-- AUCTION HANDLER
addEventingHandler("releaseName", utils.hasMatchingTag("Action", ActionMap.ReleaseName), function(msg)
	-- validate the name and process id exist, then create the auction using the auction function
	local name = msg.Tags.Name and string.lower(msg.Tags.Name)
	local processId = msg.From
	local record = arns.getRecord(name)
	local initiator = msg.Tags.Initiator or msg.From
	local timestamp = msg.Timestamp

	assert(name and #name > 0, "Name is required") --- this could be an undername, so we don't want to assertValidArNSName
	assert(processId and utils.isValidAddress(processId, true), "Process-Id must be a valid address")
	assert(initiator and utils.isValidAddress(initiator, true), "Initiator is required")
	assert(record, "Record not found")
	assert(record.type == "permabuy", "Only permabuy names can be released")
	assert(record.processId == processId, "Process-Id mismatch")
	-- TODO: throw an error here instead of allowing release and force removal of primary names? I tend to favor the protection for primary name owners.
	assert(
		#primaryNames.getPrimaryNamesForBaseName(name) == 0,
		"Primary names are associated with this name. They must be removed before releasing the name."
	)
	assert(timestamp, "Timestamp is required")
	-- we should be able to create the auction here
	local removedRecord = arns.removeRecord(name)
	local removedPrimaryNamesAndOwners = primaryNames.removePrimaryNamesForBaseName(name) -- NOTE: this should be empty if there are no primary names allowed before release
	local createdAuction = arns.createAuction(name, timestamp, initiator)
	local createAuctionData = {
		removedRecord = removedRecord,
		removedPrimaryNamesAndOwners = removedPrimaryNamesAndOwners,
		auction = createdAuction,
	}

	addAuctionResultFields(msg.ioEvent, {
		name = name,
		auction = createAuctionData.createdAuction,
		removedRecord = createAuctionData.removedRecord,
		removedPrimaryNamesAndOwners = createAuctionData.removedPrimaryNamesAndOwners,
	})

	-- note: no change to token supply here - only on auction bids
	msg.ioEvent:addField("Auctions-Count", utils.lengthOfTable(NameRegistry.auctions))
	msg.ioEvent:addField("Records-Count", utils.lengthOfTable(NameRegistry.records))

	local auction = {
		name = name,
		startTimestamp = createAuctionData.auction.startTimestamp,
		endTimestamp = createAuctionData.auction.endTimestamp,
		initiator = createAuctionData.auction.initiator,
		baseFee = createAuctionData.auction.baseFee,
		demandFactor = createAuctionData.auction.demandFactor,
		settings = createAuctionData.auction.settings,
	}

	-- send to the initiator and the process that released the name
	Send(msg, {
		Target = initiator,
		Action = "Auction-Notice",
		Name = name,
		Data = json.encode(auction),
	})
	Send(msg, {
		Target = processId,
		Action = "Auction-Notice",
		Name = name,
		Data = json.encode(auction),
	})
end)

-- AUCTIONS
addEventingHandler("auctions", utils.hasMatchingTag("Action", ActionMap.Auctions), function(msg)
	local page = utils.parsePaginationTags(msg)
	local auctions = arns.getAuctions()
	local auctionsWithoutFunctions = {}

	for _, v in ipairs(auctions) do
		table.insert(auctionsWithoutFunctions, {
			name = v.name,
			startTimestamp = v.startTimestamp,
			endTimestamp = v.endTimestamp,
			initiator = v.initiator,
			baseFee = v.baseFee,
			demandFactor = v.demandFactor,
			settings = v.settings,
		})
	end
	-- paginate the auctions by name, showing auctions nearest to the endTimestamp first
	local paginatedAuctions = utils.paginateTableWithCursor(
		auctionsWithoutFunctions,
		page.cursor,
		"name",
		page.limit,
		page.sortBy or "endTimestamp",
		page.sortOrder or "asc"
	)
	Send(msg, {
		Target = msg.From,
		Action = ActionMap.Auctions .. "-Notice",
		Data = json.encode(paginatedAuctions),
	})
end)

addEventingHandler("auctionInfo", utils.hasMatchingTag("Action", ActionMap.AuctionInfo), function(msg)
	local name = string.lower(msg.Tags.Name)
	local auction = arns.getAuction(name)

	assert(auction, "Auction not found")

	Send(msg, {
		Target = msg.From,
		Action = ActionMap.AuctionInfo .. "-Notice",
		Data = json.encode({
			name = auction.name,
			startTimestamp = auction.startTimestamp,
			endTimestamp = auction.endTimestamp,
			initiator = auction.initiator,
			baseFee = auction.baseFee,
			demandFactor = auction.demandFactor,
			settings = auction.settings,
		}),
	})
end)

-- Handler to get auction prices for a name
addEventingHandler("auctionPrices", utils.hasMatchingTag("Action", ActionMap.AuctionPrices), function(msg)
	local name = string.lower(msg.Tags.Name)
	local auction = arns.getAuction(name)
	local timestamp = msg.Tags.Timestamp or msg.Timestamp
	local type = msg.Tags["Purchase-Type"] or "permabuy"
	local years = msg.Tags.Years or nil
	local intervalMs = msg.Tags["Price-Interval-Ms"] or 15 * 60 * 1000 -- 15 minute intervals by default

	assert(auction, "Auction not found")
	assert(timestamp, "Timestamp is required")

	if not type then
		type = "permabuy"
	end

	if type == "lease" then
		years = years or 1
	else
		years = 20
	end

	local currentPrice = auction:getPriceForAuctionAtTimestamp(timestamp, type, years)
	local prices = auction:computePricesForAuction(type, years, intervalMs)

	local isEligibleForArNSDiscount = gar.isEligibleForArNSDiscount(msg.From)
	local discounts = {}

	if isEligibleForArNSDiscount then
		table.insert(discounts, {
			name = constants.ARNS_DISCOUNT_NAME,
			multiplier = constants.ARNS_DISCOUNT_PERCENTAGE,
		})
	end

	local jsonPrices = {}
	for k, v in pairs(prices) do
		jsonPrices[tostring(k)] = v
	end

	Send(msg, {
		Target = msg.From,
		Action = ActionMap.AuctionPrices .. "-Notice",
		Data = json.encode({
			name = auction.name,
			type = type,
			years = years,
			prices = jsonPrices,
			currentPrice = currentPrice,
			discounts = discounts,
		}),
	})
end)

addEventingHandler("auctionBid", utils.hasMatchingTag("Action", ActionMap.AuctionBid), function(msg)
	local fundFrom = msg.Tags["Fund-From"]
	local name = string.lower(msg.Tags.Name)
	local bidAmount = msg.Tags.Quantity or nil -- if nil, we use the current bid price
	local bidder = msg.From
	local processId = msg.Tags["Process-Id"]
	local timestamp = msg.Timestamp
	local type = msg.Tags["Purchase-Type"] or "permabuy"
	local years = msg.Tags.Years or nil

	-- assert name, bidder, processId are provided
	assert(name and #name > 0, "Name is required")
	assert(bidder and utils.isValidAddress(bidder, true), "Bidder is required")
	assert(processId and utils.isValidAddress(processId, true), "Process-Id must be a valid Arweave address")
	assert(timestamp and timestamp > 0, "Timestamp is required")
	-- if bidAmount is not nil assert that it is a number
	if bidAmount then
		assert(
			type(bidAmount) == "number" and bidAmount > 0 and utils.isInteger(bidAmount),
			"Bid amount must be a positive integer"
		)
	end
	if type then
		assert(type == "permabuy" or type == "lease", "Invalid auction type. Must be either 'permabuy' or 'lease'")
	end
	if type == "lease" then
		if years then
			assert(
				years and utils.isInteger(years) and years > 0 and years <= constants.maxLeaseLengthYears,
				"Years must be an integer between 1 and 5"
			)
		else
			years = years or 1
		end
	end

	local auction = arns.getAuction(name)
	assert(auction, "Auction not found")
	assertValidFundFrom(fundFrom)

	local result = arns.submitAuctionBid(name, bidAmount, bidder, timestamp, processId, type, years, msg.Id, fundFrom)

	if result ~= nil then
		local record = result.record
		addAuctionResultFields(msg.ioEvent, result)
		addSupplyData(msg.ioEvent)

		msg.ioEvent:addField("Records-Count", utils.lengthOfTable(NameRegistry.records))
		msg.ioEvent:addField("Auctions-Count", utils.lengthOfTable(NameRegistry.auctions))
		-- send buy record notice and auction close notice
		Send(msg, {
			Target = result.bidder,
			Action = ActionMap.BuyRecord .. "-Notice",
			Data = json.encode({
				name = name,
				startTimestamp = record.startTimestamp,
				endTimestamp = record.endTimestamp,
				undernameLimit = record.undernameLimit,
				purchasePrice = record.purchasePrice,
				processId = record.processId,
				type = record.type,
				fundingPlan = result.fundingPlan,
				fundingResult = result.fundingResult,
			}),
		})

		Send(msg, {
			Target = result.auction.initiator,
			Action = "Debit-Notice",
			Quantity = tostring(result.rewardForInitiator),
			Data = json.encode({
				name = name,
				bidder = result.bidder,
				bidAmount = result.bidAmount,
				rewardForInitiator = result.rewardForInitiator,
				rewardForProtocol = result.rewardForProtocol,
				record = result.record,
			}),
		})
	end
end)

addEventingHandler("allowDelegates", utils.hasMatchingTag("Action", ActionMap.AllowDelegates), function(msg)
	local allowedDelegates = msg.Tags["Allowed-Delegates"]
		and utils.splitAndTrimString(msg.Tags["Allowed-Delegates"], ",")
	assert(allowedDelegates and #allowedDelegates > 0, "Allowed-Delegates is required")
	msg.ioEvent:addField("Input-New-Delegates-Count", utils.lengthOfTable(allowedDelegates))
	local result = gar.allowDelegates(allowedDelegates, msg.From)

	if result ~= nil then
		msg.ioEvent:addField("New-Allowed-Delegates", result.newAllowedDelegates or {})
		msg.ioEvent:addField("New-Allowed-Delegates-Count", utils.lengthOfTable(result.newAllowedDelegates))
		msg.ioEvent:addField(
			"Gateway-Total-Allowed-Delegates",
			utils.lengthOfTable(result.gateway and result.gateway.settings.allowedDelegatesLookup or {})
				+ utils.lengthOfTable(result.gateway and result.gateway.delegates or {})
		)
	end

	Send(msg, {
		Target = msg.From,
		Tags = { Action = ActionMap.AllowDelegates .. "-Notice" },
		Data = json.encode(result and result.newAllowedDelegates or {}),
	})
end)

addEventingHandler("disallowDelegates", utils.hasMatchingTag("Action", ActionMap.DisallowDelegates), function(msg)
	local timestamp = msg.Timestamp
	local disallowedDelegates = msg.Tags["Disallowed-Delegates"]
		and utils.splitAndTrimString(msg.Tags["Disallowed-Delegates"], ",")
	assert(disallowedDelegates and #disallowedDelegates > 0, "Disallowed-Delegates is required")
	msg.ioEvent:addField("Input-Disallowed-Delegates-Count", utils.lengthOfTable(disallowedDelegates))
	local result = gar.disallowDelegates(disallowedDelegates, msg.From, msg.Id, timestamp)
	if result ~= nil then
		msg.ioEvent:addField("New-Disallowed-Delegates", result.removedDelegates or {})
		msg.ioEvent:addField("New-Disallowed-Delegates-Count", utils.lengthOfTable(result.removedDelegates))
		msg.ioEvent:addField(
			"Gateway-Total-Allowed-Delegates",
			utils.lengthOfTable(result.gateway and result.gateway.settings.allowedDelegatesLookup or {})
				+ utils.lengthOfTable(result.gateway and result.gateway.delegates or {})
		)
	end

	Send(msg, {
		Target = msg.From,
		Tags = { Action = ActionMap.DisallowDelegates .. "-Notice" },
		Data = json.encode(result and result.removedDelegates or {}),
	})
end)

addEventingHandler("paginatedDelegations", utils.hasMatchingTag("Action", "Paginated-Delegations"), function(msg)
	local address = msg.Tags.Address or msg.From
	local page = utils.parsePaginationTags(msg)

	assert(utils.isValidAddress(address, true), "Invalid address.")

	local result = gar.getPaginatedDelegations(address, page.cursor, page.limit, page.sortBy, page.sortOrder)
	Send(msg, {
		Target = msg.From,
		Tags = { Action = ActionMap.Delegations .. "-Notice" },
		Data = json.encode(result),
	})
end)

addEventingHandler(ActionMap.RedelegateStake, utils.hasMatchingTag("Action", ActionMap.RedelegateStake), function(msg)
	local sourceAddress = msg.Tags.Source
	local targetAddress = msg.Tags.Target
	local delegateAddress = msg.From
	local quantity = msg.Tags.Quantity or nil
	local vaultId = msg.Tags["Vault-Id"]
	local timestamp = msg.Timestamp

	assert(utils.isValidAddress(sourceAddress, true), "Invalid source gateway address")
	assert(utils.isValidAddress(targetAddress, true), "Invalid target gateway address")
	assert(utils.isValidAddress(delegateAddress, true), "Invalid delegator address")
	assert(timestamp, "Timestamp is required")
	if vaultId then
		assert(utils.isValidAddress(vaultId, true), "Invalid vault id")
	end

	assert(quantity and quantity > 0 and utils.isInteger(quantity), "Invalid quantity. Must be integer greater than 0")
	local redelegationResult = gar.redelegateStake({
		sourceAddress = sourceAddress,
		targetAddress = targetAddress,
		delegateAddress = delegateAddress,
		qty = quantity,
		currentTimestamp = timestamp,
		vaultId = vaultId,
	})

	local redelegationFee = redelegationResult.redelegationFee
	local stakeMoved = quantity - redelegationFee

	local isStakeMovingFromDelegateToOperator = delegateAddress == targetAddress
	local isStakeMovingFromOperatorToDelegate = delegateAddress == sourceAddress
	local isStakeMovingFromWithdrawal = vaultId ~= nil

	if isStakeMovingFromDelegateToOperator then
		if isStakeMovingFromWithdrawal then
			LastKnownWithdrawSupply = LastKnownWithdrawSupply - stakeMoved
		else
			LastKnownDelegatedSupply = LastKnownDelegatedSupply - stakeMoved
		end
		LastKnownStakedSupply = LastKnownStakedSupply + stakeMoved
	elseif isStakeMovingFromOperatorToDelegate then
		if isStakeMovingFromWithdrawal then
			LastKnownWithdrawSupply = LastKnownWithdrawSupply + stakeMoved
		else
			LastKnownStakedSupply = LastKnownStakedSupply - stakeMoved
		end
		LastKnownDelegatedSupply = LastKnownDelegatedSupply + stakeMoved
	end

	LastKnownCirculatingSupply = LastKnownCirculatingSupply - redelegationResult.redelegationFee
	addSupplyData(msg.ioEvent)

	Send(msg, {
		Target = msg.From,
		Tags = {
			Action = ActionMap.RedelegateStake .. "-Notice",
		},
		Data = json.encode(redelegationResult),
	})
end)

addEventingHandler(ActionMap.RedelegationFee, utils.hasMatchingTag("Action", ActionMap.RedelegationFee), function(msg)
	local delegateAddress = msg.Tags.Address or msg.From
	assert(utils.isValidAddress(delegateAddress, true), "Invalid delegator address")
	local feeResult = gar.getRedelegationFee(delegateAddress)
	Send(msg, {
		Target = msg.From,
		Tags = { Action = ActionMap.RedelegationFee .. "-Notice" },
		Data = json.encode(feeResult),
	})
end)

--- PRIMARY NAMES
addEventingHandler("removePrimaryName", utils.hasMatchingTag("Action", ActionMap.RemovePrimaryNames), function(msg)
	local names = utils.splitAndTrimString(msg.Tags.Names, ",")
	assert(names and #names > 0, "Names are required")
	assert(msg.From, "From is required")

	local removedPrimaryNamesAndOwners = primaryNames.removePrimaryNames(names, msg.From)

	Send(msg, {
		Target = msg.From,
		Action = ActionMap.RemovePrimaryNames .. "-Notice",
		Data = json.encode(removedPrimaryNamesAndOwners),
	})

	-- TODO: send messages to the recipients of the claims? we could index on unique recipients and send one per recipient to avoid multiple messages
	-- OR ANTS are responsible for sending messages to the recipients of the claims
	for _, removedPrimaryNameAndOwner in pairs(removedPrimaryNamesAndOwners) do
		Send(msg, {
			Target = removedPrimaryNameAndOwner.owner,
			Action = ActionMap.RemovePrimaryNames .. "-Notice",
			Tags = { Name = removedPrimaryNameAndOwner.name },
			Data = json.encode(removedPrimaryNameAndOwner),
		})
	end
end)

addEventingHandler("requestPrimaryName", utils.hasMatchingTag("Action", ActionMap.RequestPrimaryName), function(msg)
	local fundFrom = msg.Tags["Fund-From"]
	local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
	local initiator = msg.From
	local timestamp = msg.Timestamp
	assert(name, "Name is required")
	assert(initiator, "Initiator is required")
	assert(timestamp, "Timestamp is required")
	assertValidFundFrom(fundFrom)

	local primaryNameResult = primaryNames.createPrimaryNameRequest(name, initiator, timestamp, msg.Id, fundFrom)

	adjustSuppliesForFundingPlan(primaryNameResult.fundingPlan)

	--- if the from is the new owner, then send an approved notice to the from
	if primaryNameResult.newPrimaryName then
		Send(msg, {
			Target = msg.From,
			Action = ActionMap.ApprovePrimaryNameRequest .. "-Notice",
			Data = json.encode(primaryNameResult),
		})
		return
	end

	if primaryNameResult.request then
		--- send a notice to the msg.From, and the base name owner
		Send(msg, {
			Target = msg.From,
			Action = ActionMap.PrimaryNameRequest .. "-Notice",
			Data = json.encode(primaryNameResult),
		})
		Send(msg, {
			Target = primaryNameResult.baseNameOwner,
			Action = ActionMap.PrimaryNameRequest .. "-Notice",
			Data = json.encode(primaryNameResult),
		})
	end
end)

addEventingHandler(
	"approvePrimaryNameRequest",
	utils.hasMatchingTag("Action", ActionMap.ApprovePrimaryNameRequest),
	function(msg)
		local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
		local recipient = msg.Tags.Recipient or msg.From
		local timestamp = msg.Timestamp
		assert(name, "Name is required")
		assert(recipient, "Recipient is required")
		assert(msg.From, "From is required")
		assert(timestamp, "Timestamp is required")

		local approvedPrimaryNameResult = primaryNames.approvePrimaryNameRequest(recipient, name, msg.From, timestamp)

		--- send a notice to the from
		Send(msg, {
			Target = msg.From,
			Action = ActionMap.ApprovePrimaryNameRequest .. "-Notice",
			Data = json.encode(approvedPrimaryNameResult),
		})
		--- send a notice to the owner
		Send(msg, {
			Target = approvedPrimaryNameResult.newPrimaryName.owner,
			Action = ActionMap.ApprovePrimaryNameRequest .. "-Notice",
			Data = json.encode(approvedPrimaryNameResult),
		})
	end
)

--- Handles forward and reverse resolutions (e.g. name -> address and address -> name)
addEventingHandler("getPrimaryNameData", utils.hasMatchingTag("Action", ActionMap.PrimaryName), function(msg)
	local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
	local address = msg.Tags.Address or msg.From
	local primaryNameData = name and primaryNames.getPrimaryNameDataWithOwnerFromName(name)
		or address and primaryNames.getPrimaryNameDataWithOwnerFromAddress(address)
	assert(primaryNameData, "Primary name data not found")
	return Send(msg, {
		Target = msg.From,
		Action = ActionMap.PrimaryName .. "-Notice",
		Tags = { Owner = primaryNameData.owner, Name = primaryNameData.name },
		Data = json.encode(primaryNameData),
	})
end)

addEventingHandler("getPrimaryNameRequest", utils.hasMatchingTag("Action", ActionMap.PrimaryNameRequest), function(msg)
	local initiator = msg.Tags.Initiator or msg.From
	local result = primaryNames.getPrimaryNameRequest(initiator)
	assert(result, "Primary name request not found for " .. initiator)
	return Send(msg, {
		Target = msg.From,
		Action = ActionMap.PrimaryNameRequests .. "-Notice",
		Data = json.encode({
			name = result.name,
			startTimestamp = result.startTimestamp,
			endTimestamp = result.endTimestamp,
			initiator = initiator,
		}),
	})
end)

addEventingHandler(
	"getPaginatedPrimaryNameRequests",
	utils.hasMatchingTag("Action", ActionMap.PrimaryNameRequests),
	function(msg)
		local page = utils.parsePaginationTags(msg)
		local result = primaryNames.getPaginatedPrimaryNameRequests(
			page.cursor,
			page.limit,
			page.sortBy or "startTimestamp",
			page.sortOrder or "asc"
		)
		return Send(msg, {
			Target = msg.From,
			Action = ActionMap.PrimaryNameRequests .. "-Notice",
			Data = json.encode(result),
		})
	end
)

addEventingHandler("getPaginatedPrimaryNames", utils.hasMatchingTag("Action", ActionMap.PrimaryNames), function(msg)
	local page = utils.parsePaginationTags(msg)
	local result =
		primaryNames.getPaginatedPrimaryNames(page.cursor, page.limit, page.sortBy or "name", page.sortOrder or "asc")

	return Send(msg, {
		Target = msg.From,
		Action = ActionMap.PrimaryNames .. "-Notice",
		Data = json.encode(result),
	})
end)

addEventingHandler(
	"getPaginatedGatewayVaults",
	utils.hasMatchingTag("Action", "Paginated-Gateway-Vaults"),
	function(msg)
		local page = utils.parsePaginationTags(msg)
		local gatewayAddress = utils.formatAddress(msg.Tags.Address or msg.From)
		assert(utils.isValidAddress(gatewayAddress, true), "Invalid gateway address")
		local result = gar.getPaginatedVaultsForGateway(
			gatewayAddress,
			page.cursor,
			page.limit,
			page.sortBy or "endTimestamp",
			page.sortOrder or "desc"
		)
		return Send(msg, {
			Target = msg.From,
			Action = "Gateway-Vaults-Notice",
			Data = json.encode(result),
		})
	end
)

return process
