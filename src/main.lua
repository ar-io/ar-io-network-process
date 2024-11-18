-- Adjust package.path to include the current directory
local process = { _version = "0.0.1" }
local constants = require("constants")
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
local primaryNames = require("primary_names")

local ActionMap = {
	-- reads
	Info = "Info",
	TotalTokenSupply = "Total-Token-Supply",
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
	PrimaryNameRequest = "Primary-Name-Request",
	PrimaryNameRequests = "Primary-Name-Requests",
	ApprovePrimaryNameRequest = "Approve-Primary-Name-Request",
	PrimaryNames = "Primary-Names",
	PrimaryName = "Primary-Name",
}

-- Low fidelity trackers
LastKnownCirculatingSupply = LastKnownCirculatingSupply or 0 -- total circulating supply (e.g. balances - protocol balance)
LastKnownLockedSupply = LastKnownLockedSupply or 0 -- total vault balance across all vaults
LastKnownStakedSupply = LastKnownStakedSupply or 0 -- total operator stake across all gateways
LastKnownDelegatedSupply = LastKnownDelegatedSupply or 0 -- total delegated stake across all gateways
LastKnownWithdrawSupply = LastKnownWithdrawSupply or 0 -- total withdraw supply across all gateways (gateways and delegates)
LastKnownPnpRequestSupply = LastKnownPnpRequestSupply or 0 -- total supply stashed in outstanding Primary Name Protocol requests
local function lastKnownTotalTokenSupply()
	return LastKnownCirculatingSupply
		+ LastKnownLockedSupply
		+ LastKnownStakedSupply
		+ LastKnownDelegatedSupply
		+ LastKnownWithdrawSupply
		+ LastKnownPnpRequestSupply
		+ Balances[Protocol]
end
LastGracePeriodEntryEndTimestamp = LastGracePeriodEntryEndTimestamp or 0

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
	ioEvent:addField("Request-Supply", supplyData.requestSupply or LastKnownPnpRequestSupply)
	ioEvent:addField("Total-Token-Supply", supplyData.totalTokenSupply or lastKnownTotalTokenSupply())
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

local function assertValidFundFrom(fundFrom)
	if fundFrom == nil then
		return
	end
	local validFundFrom = utils.createLookupTable({ "any", "balance", "stakes" })
	assert(validFundFrom[fundFrom], "Invalid fund from type. Must be one of: any, balance, stake")
end

local function addEventingHandler(handlerName, pattern, handleFn)
	Handlers.add(handlerName, pattern, function(msg)
		-- global handler for all eventing errors, so we can log them and send a notice to the sender
		eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Action = "Invalid-" .. handlerName .. "-Notice",
				Error = tostring(error),
				Data = tostring(error),
			})
		end, handleFn, msg)
		msg.ioEvent:printEvent()
	end)
end

-- prune state before every interaction
Handlers.add("prune", function()
	return "continue" -- continue is a pattern that matches every message and continues to the next handler that matches the tags
end, function(msg)
	local msgTimestamp = tonumber(msg.Timestamp or msg.Tags.Timestamp)
	assert(msgTimestamp, "Timestamp is required for a tick interaction")

	-- Stash a new IOEvent with the message
	msg.ioEvent = IOEvent(msg)
	local epochIndex = epochs.getEpochIndexForTimestamp(msgTimestamp)
	msg.ioEvent:addField("epochIndex", epochIndex)

	local previousStateSupplies = {
		protocolBalance = Balances[Protocol],
		lastKnownCirculatingSupply = LastKnownCirculatingSupply,
		lastKnownLockedSupply = LastKnownLockedSupply,
		lastKnownStakedSupply = LastKnownStakedSupply,
		lastKnownDelegatedSupply = LastKnownDelegatedSupply,
		lastKnownWithdrawSupply = LastKnownWithdrawSupply,
		lastKnownRequestSupply = LastKnownPnpRequestSupply,
		lastKnownTotalSupply = lastKnownTotalTokenSupply(),
	}

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
	end

	-- add supply data if it has changed since the last state
	if
		LastKnownCirculatingSupply ~= previousStateSupplies.lastKnownCirculatingSupply
		or LastKnownLockedSupply ~= previousStateSupplies.lastKnownLockedSupply
		or LastKnownStakedSupply ~= previousStateSupplies.lastKnownStakedSupply
		or LastKnownDelegatedSupply ~= previousStateSupplies.lastKnownDelegatedSupply
		or LastKnownWithdrawSupply ~= previousStateSupplies.lastKnownWithdrawSupply
		or LastKnownPnpRequestSupply ~= previousStateSupplies.lastKnownRequestSupply
		or Balances[Protocol] ~= previousStateSupplies.protocolBalance
		or lastKnownTotalTokenSupply() ~= previousStateSupplies.lastKnownTotalSupply
	then
		addSupplyData(msg.ioEvent)
	end

	return prunedStateResult
end)

-- Write handlers
addEventingHandler(ActionMap.Transfer, utils.hasMatchingTag("Action", ActionMap.Transfer), function(msg)
	-- assert recipient is a valid arweave address
	local from = utils.formatAddress(msg.From)
	local recipient = utils.formatAddress(msg.Tags.Recipient)
	local quantity = tonumber(msg.Tags.Quantity)
	assert(utils.isValidAOAddress(recipient), "Invalid recipient")
	assert(quantity > 0 and utils.isInteger(quantity), "Invalid quantity. Must be integer greater than 0")

	msg.ioEvent:addField("RecipientFormatted", recipient)

	local result = balances.transfer(recipient, from, quantity)
	if result ~= nil then
		local senderNewBalance = result[from]
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
			Quantity = msg.Tags.Quantity,
			Data = "You transferred " .. msg.Tags.Quantity .. " to " .. recipient,
		}
		-- Credit-Notice message template, that is sent to the Recipient of the transfer
		local creditNotice = {
			Target = recipient,
			Action = "Credit-Notice",
			Sender = msg.From,
			Quantity = msg.Tags.Quantity,
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
		ao.send(debitNotice)
		ao.send(creditNotice)
	end
end)

addEventingHandler(ActionMap.CreateVault, utils.hasMatchingTag("Action", ActionMap.CreateVault), function(msg)
	local from = utils.formatAddress(msg.From)
	local quantity = tonumber(msg.Tags.Quantity)
	local lockLengthMs = tonumber(msg.Tags["Lock-Length"])
	local timestamp = tonumber(msg.Timestamp)
	local msgId = msg.Id
	assert(
		lockLengthMs and lockLengthMs > 0 and utils.isInteger(lockLengthMs),
		"Invalid lock length. Must be integer greater than 0"
	)
	assert(quantity and quantity > 0 and utils.isInteger(quantity), "Invalid quantity. Must be integer greater than 0")
	assert(timestamp, "Timestamp is required for a tick interaction")
	local vault = vaults.createVault(from, quantity, lockLengthMs, timestamp, msgId)

	if vault ~= nil then
		msg.ioEvent:addField("Vault-Id", msgId)
		msg.ioEvent:addField("Vault-Balance", vault.balance)
		msg.ioEvent:addField("Vault-Start-Timestamp", vault.startTimestamp)
		msg.ioEvent:addField("Vault-End-Timestamp", vault.endTimestamp)
	end

	LastKnownLockedSupply = LastKnownLockedSupply + quantity
	LastKnownCirculatingSupply = LastKnownCirculatingSupply - quantity
	addSupplyData(msg.ioEvent)

	ao.send({
		Target = from,
		Tags = {
			Action = ActionMap.CreateVault .. "-Notice",
			["Vault-Id"] = msgId,
		},
		Data = json.encode(vault),
	})
end)

addEventingHandler(ActionMap.VaultedTransfer, utils.hasMatchingTag("Action", ActionMap.VaultedTransfer), function(msg)
	local from = utils.formatAddress(msg.From)
	local recipient = utils.formatAddress(msg.Tags.Recipient)
	local quantity = tonumber(msg.Tags.Quantity)
	local lockLengthMs = tonumber(msg.Tags["Lock-Length"])
	local timestamp = tonumber(msg.Timestamp)
	local msgId = msg.Id

	assert(utils.isValidAOAddress(recipient), "Invalid recipient")
	assert(
		lockLengthMs and lockLengthMs > 0 and utils.isInteger(lockLengthMs),
		"Invalid lock length. Must be integer greater than 0"
	)
	assert(quantity and quantity > 0 and utils.isInteger(quantity), "Invalid quantity. Must be integer greater than 0")
	assert(timestamp, "Timestamp is required for a tick interaction")

	local vault = vaults.vaultedTransfer(from, recipient, quantity, lockLengthMs, timestamp, msgId)

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
	ao.send({
		Target = from,
		Recipient = recipient,
		Quantity = quantity,
		Tags = { Action = "Debit-Notice", ["Vault-Id"] = msgId },
		Data = json.encode(vault),
	})
	-- to the receiver, they get a vault notice
	ao.send({
		Target = recipient,
		Quantity = quantity,
		Sender = from,
		Tags = {
			Action = ActionMap.CreateVault .. "-Notice",
			["Vault-Id"] = msgId,
		},
		Data = json.encode(vault),
	})
end)

addEventingHandler(ActionMap.ExtendVault, utils.hasMatchingTag("Action", ActionMap.ExtendVault), function(msg)
	local from = utils.formatAddress(msg.From)
	local vaultId = utils.formatAddress(msg.Tags["Vault-Id"])
	local timestamp = tonumber(msg.Timestamp)
	local extendLengthMs = tonumber(msg.Tags["Extend-Length"])
	assert(utils.isValidAOAddress(vaultId), "Invalid vault id")
	assert(
		extendLengthMs and extendLengthMs > 0 and utils.isInteger(extendLengthMs),
		"Invalid extension length. Must be integer greater than 0"
	)
	assert(timestamp, "Timestamp is required for a tick interaction")

	local vault = vaults.extendVault(from, extendLengthMs, timestamp, vaultId)

	if vault ~= nil then
		msg.ioEvent:addField("Vault-Id", vaultId)
		msg.ioEvent:addField("Vault-Balance", vault.balance)
		msg.ioEvent:addField("Vault-Start-Timestamp", vault.startTimestamp)
		msg.ioEvent:addField("Vault-End-Timestamp", vault.endTimestamp)
		msg.ioEvent:addField("Vault-Prev-End-Timestamp", vault.endTimestamp - extendLengthMs)
	end

	ao.send({
		Target = msg.From,
		Tags = { Action = ActionMap.ExtendVault .. "-Notice" },
		Data = json.encode(vault),
	})
end)

addEventingHandler(ActionMap.IncreaseVault, utils.hasMatchingTag("Action", ActionMap.IncreaseVault), function(msg)
	local from = utils.formatAddress(msg.From)
	local vaultId = utils.formatAddress(msg.Tags["Vault-Id"])
	local quantity = tonumber(msg.Tags.Quantity)
	assert(utils.isValidAOAddress(vaultId), "Invalid vault id")
	assert(quantity and quantity > 0 and utils.isInteger(quantity), "Invalid quantity. Must be integer greater than 0")

	local vault = vaults.increaseVault(from, quantity, vaultId, msg.Timestamp)

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

	ao.send({
		Target = msg.From,
		Tags = { Action = ActionMap.IncreaseVault .. "-Notice" },
		Data = json.encode(vault),
	})
end)

addEventingHandler(ActionMap.BuyRecord, utils.hasMatchingTag("Action", ActionMap.BuyRecord), function(msg)
	local name = string.lower(msg.Tags.Name)
	local purchaseType = msg.Tags["Purchase-Type"] and string.lower(msg.Tags["Purchase-Type"]) or "lease"
	local years = msg.Tags.Years and tonumber(msg.Tags.Years) or nil
	local from = utils.formatAddress(msg.From)
	local processId = utils.formatAddress(msg.Tags["Process-Id"] or msg.From)
	local timestamp = tonumber(msg.Timestamp)
	local fundFrom = msg.Tags["Fund-From"]

	assert(
		type(purchaseType) == "string" and purchaseType == "lease" or purchaseType == "permabuy",
		"Invalid purchase type"
	)
	assert(timestamp, "Timestamp is required for a tick interaction")
	assert(type(name) == "string" and #name > 0 and #name <= 51 and not utils.isValidAOAddress(name), "Invalid name")
	assert(type(processId) == "string", "Process id is required and must be a string.")
	assert(utils.isValidAOAddress(processId), "Process Id must be a valid AO signer address..")
	if years then
		assert(years >= 1 and years <= 5 and utils.isInteger(years), "Invalid years. Must be integer between 1 and 5")
	end
	assertValidFundFrom(fundFrom)

	msg.ioEvent:addField("nameLength", #msg.Tags.Name)

	local result = arns.buyRecord(name, purchaseType, years, from, timestamp, processId, msg.Id, fundFrom)
	local record = {}
	if result ~= nil then
		record = result.record
		addRecordResultFields(msg.ioEvent, result)
		addSupplyData(msg.ioEvent)
	end

	msg.ioEvent:addField("Records-Count", utils.lengthOfTable(NameRegistry.records))

	-- TODO: Send back fundingPlan and fundingResult as well?
	ao.send({
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
	local from = utils.formatAddress(msg.From)
	local timestamp = tonumber(msg.Timestamp)
	assert(type(name) == "string", "Invalid name")
	assert(timestamp, "Timestamp is required")
	assertValidFundFrom(fundFrom)

	local result = arns.upgradeRecord(from, name, timestamp, msg.Id, fundFrom)

	local record = {}
	if result ~= nil then
		record = result.record
		addRecordResultFields(msg.ioEvent, result)
		addSupplyData(msg.ioEvent)
	end

	ao.send({
		Target = from,
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
	local from = utils.formatAddress(msg.From)
	local fundFrom = msg.Tags["Fund-From"]
	local name = string.lower(msg.Tags.Name)
	local years = tonumber(msg.Tags.Years)
	local timestamp = tonumber(msg.Timestamp)
	assert(type(name) == "string", "Invalid name")
	assert(
		years and years > 0 and years < 5 and utils.isInteger(years),
		"Invalid years. Must be integer between 1 and 5"
	)
	assert(timestamp, "Timestamp is required")
	assertValidFundFrom(fundFrom)
	local result = arns.extendLease(from, name, years, timestamp, msg.Id, fundFrom)
	local recordResult = {}
	if result ~= nil then
		msg.ioEvent:addField("Total-Extension-Fee", result.totalExtensionFee)
		addRecordResultFields(msg.ioEvent, result)
		addSupplyData(msg.ioEvent)
		recordResult = result.record
	end

	ao.send({
		Target = msg.From,
		Tags = { Action = ActionMap.ExtendLease .. "-Notice", Name = string.lower(msg.Tags.Name) },
		Data = json.encode(fundFrom and result or recordResult),
	})
end)

addEventingHandler(
	ActionMap.IncreaseUndernameLimit,
	utils.hasMatchingTag("Action", ActionMap.IncreaseUndernameLimit),
	function(msg)
		local from = utils.formatAddress(msg.From)
		local fundFrom = msg.Tags["Fund-From"]
		local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
		local quantity = tonumber(msg.Tags.Quantity)
		local timestamp = tonumber(msg.Timestamp)
		assert(type(name) == "string", "Invalid name")
		assert(
			quantity and quantity > 0 and quantity < 9990 and utils.isInteger(quantity),
			"Invalid quantity. Must be an integer value greater than 0 and less than 9990"
		)
		assert(timestamp, "Timestamp is required")
		assertValidFundFrom(fundFrom)

		local result = arns.increaseundernameLimit(from, name, quantity, timestamp, msg.Id, fundFrom)
		local recordResult = {}
		if result ~= nil then
			recordResult = result.record
			addRecordResultFields(msg.ioEvent, result)
			msg.ioEvent:addField("previousUndernameLimit", recordResult.undernameLimit - tonumber(msg.Tags.Quantity))
			msg.ioEvent:addField("additionalUndernameCost", result.additionalUndernameCost)
			addSupplyData(msg.ioEvent)
		end

		ao.send({
			Target = msg.From,
			Tags = {
				Action = ActionMap.IncreaseUndernameLimit .. "-Notice",
				Name = string.lower(msg.Tags.Name),
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
	})
	assert(
		intentType and type(intentType) == "string" and validIntents[intentType],
		"Intent must be valid registry interaction (e.g. BuyRecord, ExtendLease, IncreaseUndernameLimit, UpgradeName). Provided intent: "
			.. (intentType or "nil")
	)
	assert(msg.Tags.Name, "Name is required")
	-- if years is provided, assert it is a number and integer between 1 and 5
	if msg.Tags.Years then
		assert(utils.isInteger(tonumber(msg.Tags.Years)), "Invalid years. Must be integer between 1 and 5")
	end

	-- if quantity provided must be a number and integer greater than 0
	if msg.Tags.Quantity then
		assert(utils.isInteger(tonumber(msg.Tags.Quantity)), "Invalid quantity. Must be integer greater than 0")
	end
end

addEventingHandler(ActionMap.TokenCost, utils.hasMatchingTag("Action", ActionMap.TokenCost), function(msg)
	assertTokenCostTags(msg)
	local from = utils.formatAddress(msg.From)
	local intent = msg.Tags.Intent
	local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
	local years = msg.Tags.Years and tonumber(msg.Tags.Years) or nil
	local quantity = msg.Tags.Quantity and tonumber(msg.Tags.Quantity) or nil
	local purchaseType = msg.Tags["Purchase-Type"] or "lease"
	local timestamp = tonumber(msg.Timestamp) or tonumber(msg.Tags.Timestamp)

	local intendedAction = {
		intent = intent,
		name = name,
		years = years,
		quantity = quantity,
		purchaseType = purchaseType,
		currentTimestamp = timestamp,
		from = from,
	}

	local tokenCostResult = arns.getTokenCost(intendedAction)
	local tokenCost = tokenCostResult.tokenCost

	ao.send({
		Target = msg.From,
		Tags = { Action = ActionMap.TokenCost .. "-Notice", ["Token-Cost"] = tostring(tokenCost) },
		Data = json.encode(tokenCost),
	})
end)

addEventingHandler(ActionMap.CostDetails, utils.hasMatchingTag("Action", ActionMap.CostDetails), function(msg)
	local fundFrom = msg.Tags["Fund-From"]
	local from = utils.formatAddress(msg.From)
	local name = string.lower(msg.Tags.Name)
	local years = tonumber(msg.Tags.Years) or 1
	local quantity = tonumber(msg.Tags.Quantity)
	local purchaseType = msg.Tags["Purchase-Type"] or "lease"
	local timestamp = tonumber(msg.Timestamp) or tonumber(msg.Tags.Timestamp)
	assertTokenCostTags(msg)
	assertValidFundFrom(fundFrom)

	local tokenCostAndFundingPlan = arns.getTokenCostAndFundingPlanForIntent(
		msg.Tags.Intent,
		name,
		years,
		quantity,
		purchaseType,
		timestamp,
		from,
		fundFrom
	)
	if not tokenCostAndFundingPlan then
		return
	end

	ao.send({
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

		ao.send({
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
		port = tonumber(msg.Tags.Port) or 443,
		protocol = msg.Tags.Protocol or "https",
		allowDelegatedStaking = msg.Tags["Allow-Delegated-Staking"] == "true"
			or msg.Tags["Allow-Delegated-Staking"] == "allowlist",
		allowedDelegates = msg.Tags["Allow-Delegated-Staking"] == "allowlist"
				and utils.splitAndTrimString(msg.Tags["Allowed-Delegates"] or "", ",")
			or nil,
		minDelegatedStake = tonumber(msg.Tags["Min-Delegated-Stake"]),
		delegateRewardShareRatio = tonumber(msg.Tags["Delegate-Reward-Share-Ratio"]) or 0,
		properties = msg.Tags.Properties or "FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44",
		autoStake = msg.Tags["Auto-Stake"] == "true",
	}

	local updatedServices = utils.safeDecodeJson(msg.Tags.Services)
	local fromAddress = utils.formatAddress(msg.From)
	local observerAddress = msg.Tags["Observer-Address"] or fromAddress
	local formattedObserverAddress = utils.formatAddress(observerAddress)
	local stake = tonumber(msg.Tags["Operator-Stake"])
	local timestamp = tonumber(msg.Timestamp)

	assert(not msg.Tags.Services or updatedServices, "Services must be a valid JSON string")

	msg.ioEvent:addField("Resolved-Observer-Address", formattedObserverAddress)
	msg.ioEvent:addField("Sender-Previous-Balance", Balances[fromAddress] or 0)

	local gateway =
		gar.joinNetwork(fromAddress, stake, updatedSettings, updatedServices, formattedObserverAddress, timestamp)
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

	ao.send({
		Target = fromAddress,
		Tags = { Action = ActionMap.JoinNetwork .. "-Notice" },
		Data = json.encode(gateway),
	})
end)

addEventingHandler(ActionMap.LeaveNetwork, utils.hasMatchingTag("Action", ActionMap.LeaveNetwork), function(msg)
	local from = utils.formatAddress(msg.From)
	local timestamp = tonumber(msg.Timestamp)
	local unsafeGatewayBeforeLeaving = gar.getGatewayUnsafe(from)
	local gwPrevTotalDelegatedStake = 0
	local gwPrevStake = 0
	if unsafeGatewayBeforeLeaving ~= nil then
		gwPrevTotalDelegatedStake = unsafeGatewayBeforeLeaving.totalDelegatedStake
		gwPrevStake = unsafeGatewayBeforeLeaving.operatorStake
	end

	assert(unsafeGatewayBeforeLeaving, "Gateway not found")
	assert(timestamp, "Timestamp is required")

	local gateway = gar.leaveNetwork(from, timestamp, msg.Id)

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

	ao.send({
		Target = msg.From,
		Tags = { Action = ActionMap.LeaveNetwork .. "-Notice" },
		Data = json.encode(gateway),
	})
end)

addEventingHandler(
	ActionMap.IncreaseOperatorStake,
	utils.hasMatchingTag("Action", ActionMap.IncreaseOperatorStake),
	function(msg)
		local from = utils.formatAddress(msg.From)
		local quantity = tonumber(msg.Tags.Quantity)
		assert(
			quantity and utils.isInteger(quantity) and quantity > 0,
			"Invalid quantity. Must be integer greater than 0"
		)

		msg.ioEvent:addField("Sender-Previous-Balance", Balances[msg.From])
		local gateway = gar.increaseOperatorStake(from, quantity)

		msg.ioEvent:addField("Sender-New-Balance", Balances[msg.From])
		if gateway ~= nil then
			msg.ioEvent:addField("New-Operator-Stake", gateway.operatorStake)
			msg.ioEvent:addField("Previous-Operator-Stake", gateway.operatorStake - quantity)
		end

		LastKnownCirculatingSupply = LastKnownCirculatingSupply - quantity
		LastKnownStakedSupply = LastKnownStakedSupply + quantity
		addSupplyData(msg.ioEvent)

		ao.send({
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
		local from = utils.formatAddress(msg.From)
		local quantity = tonumber(msg.Tags.Quantity)
		local instantWithdraw = msg.Tags.Instant and msg.Tags.Instant == "true" or false
		local timestamp = tonumber(msg.Timestamp)
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

		local result = gar.decreaseOperatorStake(from, quantity, timestamp, msg.Id, instantWithdraw)
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

		ao.send({
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
	local from = utils.formatAddress(msg.From)
	local gatewayTarget = utils.formatAddress(msg.Tags.Target or msg.Tags.Address)
	local quantity = tonumber(msg.Tags.Quantity)
	local timestamp = tonumber(msg.Timestamp)
	assert(utils.isValidAOAddress(gatewayTarget), "Invalid gateway address")
	assert(
		msg.Tags.Quantity and tonumber(msg.Tags.Quantity) > 0 and utils.isInteger(tonumber(msg.Tags.Quantity)),
		"Invalid quantity. Must be integer greater than 0"
	)

	msg.ioEvent:addField("Target-Formatted", gatewayTarget)

	local gateway = gar.delegateStake(from, gatewayTarget, quantity, timestamp)
	local delegateResult = {}
	if gateway ~= nil then
		local newStake = gateway.delegates[from].delegatedStake
		msg.ioEvent:addField("Previous-Stake", newStake - quantity)
		msg.ioEvent:addField("New-Stake", newStake)
		msg.ioEvent:addField("Gateway-Total-Delegated-Stake", gateway.totalDelegatedStake)
		delegateResult = gateway.delegates[from]
	end

	LastKnownCirculatingSupply = LastKnownCirculatingSupply - quantity
	LastKnownDelegatedSupply = LastKnownDelegatedSupply + quantity
	addSupplyData(msg.ioEvent)

	ao.send({
		Target = msg.From,
		Tags = { Action = ActionMap.DelegateStake .. "-Notice", Gateway = msg.Tags.Target },
		Data = json.encode(delegateResult),
	})
end)

addEventingHandler(ActionMap.CancelWithdrawal, utils.hasMatchingTag("Action", ActionMap.CancelWithdrawal), function(msg)
	local from = utils.formatAddress(msg.From)
	local gatewayAddress = utils.formatAddress(msg.Tags.Target or msg.Tags.Address or msg.From)
	local vaultId = msg.Tags["Vault-Id"]
	assert(utils.isValidAOAddress(gatewayAddress), "Invalid gateway address")
	assert(utils.isValidAOAddress(vaultId), "Invalid vault id")

	msg.ioEvent:addField("Target-Formatted", gatewayAddress)

	local result = gar.cancelGatewayWithdrawal(from, gatewayAddress, vaultId)
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

	ao.send({
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
		local from = utils.formatAddress(msg.From)
		local target = utils.formatAddress(msg.Tags.Target or msg.Tags.Address or msg.From) -- if not provided, use sender
		local vaultId = utils.formatAddress(msg.Tags["Vault-Id"])
		local timestamp = tonumber(msg.Timestamp)
		msg.ioEvent:addField("Target-Formatted", target)

		assert(utils.isValidAOAddress(target), "Invalid gateway address")
		assert(utils.isValidAOAddress(vaultId), "Invalid vault id")
		assert(timestamp, "Timestamp is required")

		local result = gar.instantGatewayWithdrawal(from, target, vaultId, timestamp)
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
			ao.send({
				Target = msg.From,
				Tags = {
					Action = ActionMap.InstantWithdrawal .. "-Notice",
					Address = target,
					["Vault-Id"] = vaultId,
					["Amount-Withdrawn"] = result.amountWithdrawn,
					["Penalty-Rate"] = result.penaltyRate,
					["Expedited-Withdrawal-Fee"] = result.expeditedWithdrawalFee,
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
		local from = utils.formatAddress(msg.From)
		local target = utils.formatAddress(msg.Tags.Target or msg.Tags.Address)
		local quantity = tonumber(msg.Tags.Quantity)
		local instantWithdraw = msg.Tags.Instant and msg.Tags.Instant == "true" or false
		local timestamp = tonumber(msg.Timestamp)
		local messageId = msg.Id
		msg.ioEvent:addField("Target-Formatted", target)
		msg.ioEvent:addField("Quantity", quantity)
		assert(utils.isValidAOAddress(target), "Invalid gateway address")
		assert(
			quantity
				and tonumber(msg.Tags.Quantity) > constants.minimumWithdrawalAmount
				and utils.isInteger(msg.Tags.Quantity),
			"Invalid quantity. Must be integer greater than " .. constants.minimumWithdrawalAmount
		)

		local result = gar.decreaseDelegateStake(target, from, quantity, timestamp, messageId, instantWithdraw)

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
			local newStake = gateway.delegates[from].delegatedStake
			msg.ioEvent:addField("Previous-Stake", newStake + quantity)
			msg.ioEvent:addField("New-Stake", newStake)
			msg.ioEvent:addField("Gateway-Total-Delegated-Stake", gateway.totalDelegatedStake)

			if instantWithdraw then
				msg.ioEvent:addField("Instant-Withdrawal", instantWithdraw)
				msg.ioEvent:addField("Instant-Withdrawal-Fee", result.expeditedWithdrawalFee)
				msg.ioEvent:addField("Amount-Withdrawn", result.amountWithdrawn)
				msg.ioEvent:addField("Penalty-Rate", result.penaltyRate)
			end

			delegateResult = gateway.delegates[from]
			local newDelegateVaults = delegateResult.vaults
			if newDelegateVaults ~= nil then
				msg.ioEvent:addField("Vaults-Count", utils.lengthOfTable(newDelegateVaults))
				local newDelegateVault = newDelegateVaults[msg.Id]
				if newDelegateVault ~= nil then
					msg.ioEvent:addField("Vault-Id", msg.Id)
					msg.ioEvent:addField("Vault-Balance", newDelegateVault.balance)
					msg.ioEvent:addField("Vaul-Start-Timestamp", newDelegateVault.startTimestamp)
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

		ao.send({
			Target = from,
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
			port = tonumber(msg.Tags.Port) or unsafeGateway.settings.port,
			protocol = msg.Tags.Protocol or unsafeGateway.settings.protocol,
			allowDelegatedStaking = enableOpenDelegatedStaking -- clear directive to enable
				or enableLimitedDelegatedStaking -- clear directive to enable
				or not disableDelegatedStaking -- NOT clear directive to DISABLE
					and unsafeGateway.settings.allowDelegatedStaking, -- otherwise unspecified, so use previous setting

			allowedDelegates = needNewAllowlist and utils.splitAndTrimString(msg.Tags["Allowed-Delegates"], ",") -- replace the lookup list
				or nil, -- change nothing

			minDelegatedStake = tonumber(msg.Tags["Min-Delegated-Stake"]) or unsafeGateway.settings.minDelegatedStake,
			delegateRewardShareRatio = tonumber(msg.Tags["Delegate-Reward-Share-Ratio"])
				or unsafeGateway.settings.delegateRewardShareRatio,
			properties = msg.Tags.Properties or unsafeGateway.settings.properties,
			autoStake = not msg.Tags["Auto-Stake"] and unsafeGateway.settings.autoStake
				or msg.Tags["Auto-Stake"] == "true",
		}

		-- TODO: we could standardize this on our prepended handler to inject and ensure formatted addresses and converted values
		local observerAddress = msg.Tags["Observer-Address"] or unsafeGateway.observerAddress
		local formattedAddress = utils.formatAddress(msg.From)
		local formattedObserverAddress = utils.formatAddress(observerAddress)
		local timestamp = tonumber(msg.Timestamp)
		local result = gar.updateGatewaySettings(
			formattedAddress,
			updatedSettings,
			updatedServices,
			formattedObserverAddress,
			timestamp,
			msg.Id
		)
		ao.send({
			Target = msg.From,
			Tags = { Action = ActionMap.UpdateGatewaySettings .. "-Notice" },
			Data = json.encode(result),
		})
	end
)

addEventingHandler(ActionMap.ReassignName, utils.hasMatchingTag("Action", ActionMap.ReassignName), function(msg)
	local from = utils.formatAddress(msg.From)
	local newProcessId = utils.formatAddress(msg.Tags["Process-Id"])
	local name = string.lower(msg.Tags.Name)
	local initiator = utils.formatAddress(msg.Tags.Initiator)
	local timestamp = tonumber(msg.Timestamp)
	assert(name and #name > 0, "Name is required")
	assert(utils.isValidAOAddress(newProcessId), "Process Id must be a valid AO signer address..")
	assert(timestamp, "Timestamp is required")
	if initiator ~= nil then
		assert(utils.isValidAOAddress(initiator), "Invalid initiator address.")
	end

	local reassignment = arns.reassignName(name, from, timestamp, newProcessId)

	ao.send({
		Target = msg.From,
		Action = ActionMap.ReassignName .. "-Notice",
		Name = name,
		Data = json.encode(reassignment),
	})

	if initiator ~= nil then
		ao.send({
			Target = initiator,
			Action = ActionMap.ReassignName .. "-Notice",
			Name = name,
			Data = json.encode(reassignment),
		})
	end
	return
end)

addEventingHandler(ActionMap.SaveObservations, utils.hasMatchingTag("Action", ActionMap.SaveObservations), function(msg)
	local from = utils.formatAddress(msg.From)
	local reportTxId = msg.Tags["Report-Tx-Id"]
	local failedGateways = utils.splitAndTrimString(msg.Tags["Failed-Gateways"], ",")
	local timestamp = tonumber(msg.Timestamp)
	assert(utils.isValidAOAddress(reportTxId), "Invalid report tx id")
	for _, gateway in ipairs(failedGateways) do
		assert(utils.isValidAOAddress(gateway), "Invalid failed gateway address: " .. gateway)
	end

	local observations = epochs.saveObservations(from, reportTxId, failedGateways, timestamp)
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

	ao.send({
		Target = msg.From,
		Action = ActionMap.SaveObservations .. "-Notice",
		Data = json.encode(observations),
	})
end)

addEventingHandler(ActionMap.EpochSettings, utils.hasMatchingTag("Action", ActionMap.EpochSettings), function(msg)
	local epochSettings = epochs.getSettings()
	ao.send({
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
		ao.send({
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
		ao.send({
			Target = msg.From,
			Action = ActionMap.GatewayRegistrySettings .. "-Notice",
			Data = json.encode(gatewayRegistrySettings),
		})
	end
)

addEventingHandler("totalTokenSupply", utils.hasMatchingTag("Action", ActionMap.TotalTokenSupply), function(msg)
	-- add all the balances
	local totalSupply = 0
	local circulatingSupply = 0
	local lockedSupply = 0
	local stakedSupply = 0
	local delegatedSupply = 0
	local withdrawSupply = 0
	local pnpRequestSupply = 0
	local protocolBalance = balances.getBalance(Protocol)
	local userBalances = balances.getBalances()

	-- tally circulating supply
	for _, balance in pairs(userBalances) do
		circulatingSupply = circulatingSupply + balance
	end
	circulatingSupply = circulatingSupply - protocolBalance
	totalSupply = totalSupply + protocolBalance + circulatingSupply

	-- tally supply stashed in gateways and delegates
	for _, gateway in pairs(gar.getGatewaysUnsafe()) do
		totalSupply = totalSupply + gateway.operatorStake + gateway.totalDelegatedStake
		stakedSupply = stakedSupply + gateway.operatorStake
		delegatedSupply = delegatedSupply + gateway.totalDelegatedStake
		for _, delegate in pairs(gateway.delegates) do
			-- tally delegates' vaults
			for _, vault in pairs(delegate.vaults) do
				totalSupply = totalSupply + vault.balance
				withdrawSupply = withdrawSupply + vault.balance
			end
		end
		-- tally gateway's own vaults
		for _, vault in pairs(gateway.vaults) do
			totalSupply = totalSupply + vault.balance
			withdrawSupply = withdrawSupply + vault.balance
		end
	end

	-- user vaults
	local userVaults = vaults.getVaults()
	for _, vaultsForAddress in pairs(userVaults) do
		-- they may have several vaults iterate through them
		for _, vault in pairs(vaultsForAddress) do
			totalSupply = totalSupply + vault.balance
			lockedSupply = lockedSupply + vault.balance
		end
	end

	-- pnp requests
	for _, pnpRequest in pairs(primaryNames.getUnsafePrimaryNameRequests()) do
		pnpRequestSupply = pnpRequestSupply + pnpRequest.balance
	end

	LastKnownCirculatingSupply = circulatingSupply
	LastKnownLockedSupply = lockedSupply
	LastKnownStakedSupply = stakedSupply
	LastKnownDelegatedSupply = delegatedSupply
	LastKnownWithdrawSupply = withdrawSupply
	LastKnownPnpRequestSupply = pnpRequestSupply

	addSupplyData(msg.ioEvent, {
		totalTokenSupply = totalSupply,
	})
	msg.ioEvent:addField("Last-Known-Total-Token-Supply", lastKnownTotalTokenSupply())

	ao.send({
		Target = msg.From,
		Action = ActionMap.TotalTokenSupply .. "-Notice",
		["Total-Token-Supply"] = tostring(totalSupply),
		["Circulating-Supply"] = tostring(circulatingSupply),
		["Locked-Supply"] = tostring(lockedSupply),
		["Staked-Supply"] = tostring(stakedSupply),
		["Delegated-Supply"] = tostring(delegatedSupply),
		["Withdraw-Supply"] = tostring(withdrawSupply),
		["Protocol-Balance"] = tostring(protocolBalance),
		Data = json.encode({
			-- TODO: we are losing precision on these values unexpectedly. This has been brought to the AO team - for now the tags should be correct as they are stringified
			total = totalSupply,
			circulating = circulatingSupply,
			locked = lockedSupply,
			staked = stakedSupply,
			delegated = delegatedSupply,
			withdrawn = withdrawSupply,
			protocolBalance = protocolBalance,
		}),
	})
end)

-- TICK HANDLER - TODO: this may be better as a "Distribute" rewards handler instead of `Tick` tag
addEventingHandler("distribute", utils.hasMatchingTag("Action", "Tick"), function(msg)
	assert(msg.Timestamp, "Timestamp is required for a tick interaction")
	local msgTimestamp = tonumber(msg.Timestamp)
	-- tick and distribute rewards for every index between the last ticked epoch and the current epoch
	local tickedRewardDistributions = {}
	local totalTickedRewardsDistributed = 0
	local function tickEpoch(timestamp, blockHeight, hashchain, msgId)
		-- update demand factor if necessary
		local demandFactor = demand.updateDemandFactor(timestamp)
		-- distribute rewards for the epoch and increments stats for gateways, this closes the epoch if the timestamp is greater than the epochs required distribution timestamp
		local distributedEpoch = epochs.distributeRewardsForEpoch(timestamp)
		if distributedEpoch ~= nil and distributedEpoch.epochIndex ~= nil then
			tickedRewardDistributions[tostring(distributedEpoch.epochIndex)] =
				distributedEpoch.distributions.totalDistributedRewards
			totalTickedRewardsDistributed = totalTickedRewardsDistributed
				+ distributedEpoch.distributions.totalDistributedRewards
		end
		-- prune any gateway that has hit the failed 30 consecutive epoch threshold after the epoch has been distributed
		local pruneGatewaysResult = gar.pruneGateways(timestamp, msgId)

		-- now create the new epoch with the current message hashchain and block height
		local newEpoch = epochs.createEpoch(timestamp, tonumber(blockHeight), hashchain)
		return {
			maybeEpoch = newEpoch,
			maybeDemandFactor = demandFactor,
			pruneGatewaysResult = pruneGatewaysResult,
		}
	end

	local msgId = msg.Id
	local lastTickedEpochIndex = LastTickedEpochIndex
	local targetCurrentEpochIndex = epochs.getEpochIndexForTimestamp(msgTimestamp)
	msg.ioEvent:addField("Last-Ticked-Epoch-Index", lastTickedEpochIndex)
	msg.ioEvent:addField("Current-Epoch-Index", lastTickedEpochIndex + 1)
	msg.ioEvent:addField("Target-Current-Epoch-Index", targetCurrentEpochIndex)

	-- if epoch index is -1 then we are before the genesis epoch and we should not tick
	if targetCurrentEpochIndex < 0 then
		-- do nothing and just send a notice back to the sender
		ao.send({
			Target = msg.From,
			Action = "Tick-Notice",
			LastTickedEpochIndex = LastTickedEpochIndex,
			Data = json.encode("Genesis epocch has not started yet."),
		})
	end

	-- tick and distribute rewards for every index between the last ticked epoch and the current epoch
	local tickedEpochIndexes = {}
	local newEpochIndexes = {}
	local newDemandFactors = {}
	local newPruneGatewaysResults = {}
	for i = lastTickedEpochIndex + 1, targetCurrentEpochIndex do
		print("Ticking epoch: " .. i)
		local previousState = {
			Balances = utils.deepCopy(Balances),
			GatewayRegistry = utils.deepCopy(GatewayRegistry),
			Epochs = utils.deepCopy(Epochs), -- we probably only need to copy the last ticked epoch
			DemandFactor = utils.deepCopy(DemandFactor),
			LastTickedEpochIndex = LastTickedEpochIndex,
		}
		local _, _, epochDistributionTimestamp = epochs.getEpochTimestampsForIndex(i)
		-- use the minimum of the msg timestamp or the epoch distribution timestamp, this ensures an epoch gets created for the genesis block
		-- and that we don't try and distribute before an epoch is created
		local tickTimestamp = math.min(msgTimestamp or 0, epochDistributionTimestamp)
		-- TODO: if we need to "recover" epochs, we can't rely on just the current message hashchain and block height,
		-- we should set the prescribed observers and names to empty arrays and distribute rewards accordingly
		local tickSuceeded, resultOrError =
			pcall(tickEpoch, tickTimestamp, msg["Block-Height"], msg["Hash-Chain"], msgId)
		if tickSuceeded then
			if tickTimestamp == epochDistributionTimestamp then
				-- if we are distributing rewards, we should update the last ticked epoch index to the current epoch index
				LastTickedEpochIndex = i
				table.insert(tickedEpochIndexes, i)
			end
			ao.send({
				Target = msg.From,
				Action = "Tick-Notice",
				LastTickedEpochIndex = LastTickedEpochIndex,
				Data = json.encode(resultOrError),
			})
			if resultOrError.maybeEpoch ~= nil then
				table.insert(newEpochIndexes, resultOrError.maybeEpoch.epochIndex)
			end
			if resultOrError.maybeDemandFactor ~= nil then
				table.insert(newDemandFactors, resultOrError.maybeDemandFactor)
			end
			if resultOrError.pruneGatewaysResult ~= nil then
				table.insert(newPruneGatewaysResults, resultOrError.pruneGatewaysResult)
			end
		else
			-- reset the state to previous state
			Balances = previousState.Balances
			GatewayRegistry = previousState.GatewayRegistry
			Epochs = previousState.Epochs
			DemandFactor = previousState.DemandFactor
			LastTickedEpochIndex = previousState.LastTickedEpochIndex
			ao.send({
				Target = msg.From,
				Action = "Invalid-Tick-Notice",
				Error = "Invalid-Tick",
				Data = json.encode(resultOrError),
			})
			-- TODO: But keep ticking ahead?!? We just need be to robust against potential failures here
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
		-- Reduce the prune gatways results and then track changes
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
end)

-- READ HANDLERS

addEventingHandler(ActionMap.Info, Handlers.utils.hasMatchingTag("Action", ActionMap.Info), function(msg)
	local handlers = Handlers.list
	local handlerNames = {}
	for _, handler in ipairs(handlers) do
		table.insert(handlerNames, handler.name)
	end

	ao.send({
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
	ao.send({
		Target = msg.From,
		Action = "Gateway-Notice",
		Gateway = msg.Tags.Address or msg.From,
		Data = json.encode(gateway),
	})
end)

--- TODO: we want to remove this but need to ensure we don't break downstream apps
addEventingHandler(ActionMap.Balances, Handlers.utils.hasMatchingTag("Action", ActionMap.Balances), function(msg)
	ao.send({
		Target = msg.From,
		Action = "Balances-Notice",
		Data = json.encode(Balances),
	})
end)

addEventingHandler(ActionMap.Balance, Handlers.utils.hasMatchingTag("Action", ActionMap.Balance), function(msg)
	local target = utils.formatAddress(msg.Tags.Target or msg.Tags.Address or msg.From)
	local balance = balances.getBalance(target)
	-- must adhere to token.lua spec for arconnect compatibility
	ao.send({
		Target = msg.From,
		Action = "Balance-Notice",
		Data = balance,
		Balance = balance,
		Ticker = Ticker,
		Address = target,
	})
end)

addEventingHandler(ActionMap.DemandFactor, utils.hasMatchingTag("Action", ActionMap.DemandFactor), function(msg)
	local demandFactor = demand.getDemandFactor()
	ao.send({
		Target = msg.From,
		Action = "Demand-Factor-Notice",
		Data = json.encode(demandFactor),
	})
end)

addEventingHandler(ActionMap.DemandFactorInfo, utils.hasMatchingTag("Action", ActionMap.DemandFactorInfo), function(msg)
	local result = demand.getDemandFactorInfo()
	ao.send({ Target = msg.From, Action = "Demand-Factor-Info-Notice", Data = json.encode(result) })
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
	ao.send(recordNotice)
end)

addEventingHandler(ActionMap.Epoch, utils.hasMatchingTag("Action", ActionMap.Epoch), function(msg)
	-- check if the epoch number is provided, if not get the epoch number from the timestamp
	local providedEpochIndex = tonumber(msg.Tags["Epoch-Index"])
	local timestamp = tonumber(msg.Timestamp)

	assert(providedEpochIndex or timestamp, "Epoch index or timestamp is required")

	local epochIndex = providedEpochIndex or epochs.getEpochIndexForTimestamp(timestamp)
	local epoch = epochs.getEpoch(epochIndex)
	ao.send({ Target = msg.From, Action = "Epoch-Notice", Data = json.encode(epoch) })
end)

addEventingHandler(ActionMap.Epochs, utils.hasMatchingTag("Action", ActionMap.Epochs), function(msg)
	local allEpochs = epochs.getEpochs()
	ao.send({ Target = msg.From, Action = "Epochs-Notice", Data = json.encode(allEpochs) })
end)

addEventingHandler(
	ActionMap.PrescribedObservers,
	utils.hasMatchingTag("Action", ActionMap.PrescribedObservers),
	function(msg)
		-- check if the epoch number is provided, if not get the epoch number from the timestamp
		local providedEpochIndex = tonumber(msg.Tags["Epoch-Index"])
		local timestamp = tonumber(msg.Timestamp)

		assert(providedEpochIndex or timestamp, "Epoch index or timestamp is required")

		local epochIndex = providedEpochIndex or epochs.getEpochIndexForTimestamp(timestamp)
		local prescribedObservers = epochs.getPrescribedObserversForEpoch(epochIndex)
		ao.send({ Target = msg.From, Action = "Prescribed-Observers-Notice", Data = json.encode(prescribedObservers) })
	end
)

addEventingHandler(ActionMap.Observations, utils.hasMatchingTag("Action", ActionMap.Observations), function(msg)
	local providedEpochIndex = tonumber(msg.Tags["Epoch-Index"])
	local timestamp = tonumber(msg.Timestamp)

	assert(providedEpochIndex or timestamp, "Epoch index or timestamp is required")

	local epochIndex = providedEpochIndex or epochs.getEpochIndexForTimestamp(timestamp)
	local observations = epochs.getObservationsForEpoch(epochIndex)
	ao.send({
		Target = msg.From,
		Action = "Observations-Notice",
		EpochIndex = tostring(epochIndex),
		Data = json.encode(observations),
	})
end)

addEventingHandler(ActionMap.PrescribedNames, utils.hasMatchingTag("Action", ActionMap.PrescribedNames), function(msg)
	-- check if the epoch number is provided, if not get the epoch number from the timestamp
	local providedEpochIndex = tonumber(msg.Tags["Epoch-Index"])
	local timestamp = tonumber(msg.Timestamp)

	assert(providedEpochIndex or timestamp, "Epoch index or timestamp is required")

	local epochIndex = providedEpochIndex or epochs.getEpochIndexForTimestamp(timestamp)
	local prescribedNames = epochs.getPrescribedNamesForEpoch(epochIndex)
	ao.send({ Target = msg.From, Action = "Prescribed-Names-Notice", Data = json.encode(prescribedNames) })
end)

addEventingHandler(ActionMap.Distributions, utils.hasMatchingTag("Action", ActionMap.Distributions), function(msg)
	-- check if the epoch number is provided, if not get the epoch number from the timestamp
	local providedEpochIndex = tonumber(msg.Tags["Epoch-Index"])
	local timestamp = tonumber(msg.Timestamp)

	assert(providedEpochIndex or timestamp, "Epoch index or timestamp is required")

	local epochIndex = providedEpochIndex or epochs.getEpochIndexForTimestamp(timestamp)
	local distributions = epochs.getDistributionsForEpoch(epochIndex)
	ao.send({ Target = msg.From, Action = "Distributions-Notice", Data = json.encode(distributions) })
end)

addEventingHandler(ActionMap.ReservedNames, utils.hasMatchingTag("Action", ActionMap.ReservedNames), function(msg)
	local page = utils.parsePaginationTags(msg)
	local reservedNames = arns.getPaginatedReservedNames(page.cursor, page.limit, page.sortBy or "name", page.sortOrder)
	ao.send({ Target = msg.From, Action = "Reserved-Names-Notice", Data = json.encode(reservedNames) })
end)

addEventingHandler(ActionMap.ReservedName, utils.hasMatchingTag("Action", ActionMap.ReservedName), function(msg)
	local name = msg.Tags.Name and string.lower(msg.Tags.Name)
	assert(name, "Name is required")
	local reservedName = arns.getReservedName(name)
	ao.send({
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

	ao.send({
		Target = msg.From,
		Action = "Vault-Notice",
		Address = address,
		["Vault-Id"] = vaultId,
		Data = json.encode(vault),
	})
end)

-- Pagination handlers

addEventingHandler(
	"paginatedRecords",
	utils.hasMatchingTag("Action", "Paginated-Records") or utils.hasMatchingTag("Action", ActionMap.Records),
	function(msg)
		local page = utils.parsePaginationTags(msg)
		local result =
			arns.getPaginatedRecords(page.cursor, page.limit, page.sortBy or "startTimestamp", page.sortOrder)
		ao.send({ Target = msg.From, Action = "Records-Notice", Data = json.encode(result) })
	end
)

addEventingHandler(
	"paginatedGateways",
	utils.hasMatchingTag("Action", "Paginated-Gateways") or utils.hasMatchingTag("Action", ActionMap.Gateways),
	function(msg)
		local page = utils.parsePaginationTags(msg)
		local result =
			gar.getPaginatedGateways(page.cursor, page.limit, page.sortBy or "startTimestamp", page.sortOrder or "desc")
		ao.send({ Target = msg.From, Action = "Gateways-Notice", Data = json.encode(result) })
	end
)

--- TODO: make this support `Balances` requests
addEventingHandler("paginatedBalances", utils.hasMatchingTag("Action", "Paginated-Balances"), function(msg)
	local page = utils.parsePaginationTags(msg)
	local walletBalances =
		balances.getPaginatedBalances(page.cursor, page.limit, page.sortBy or "balance", page.sortOrder)
	ao.send({ Target = msg.From, Action = "Balances-Notice", Data = json.encode(walletBalances) })
end)

addEventingHandler(
	"paginatedVaults",
	utils.hasMatchingTag("Action", "Paginated-Vaults") or utils.hasMatchingTag("Action", ActionMap.Vaults),
	function(msg)
		local page = utils.parsePaginationTags(msg)
		local pageVaults = vaults.getPaginatedVaults(page.cursor, page.limit, page.sortOrder, page.sortBy)
		ao.send({ Target = msg.From, Action = "Vaults-Notice", Data = json.encode(pageVaults) })
	end
)

addEventingHandler(
	"paginatedDelegates",
	utils.hasMatchingTag("Action", "Paginated-Delegates") or utils.hasMatchingTag("Action", ActionMap.Delegates),
	function(msg)
		local page = utils.parsePaginationTags(msg)
		local result = gar.getPaginatedDelegates(
			msg.Tags.Address or msg.From,
			page.cursor,
			page.limit,
			page.sortBy or "startTimestamp",
			page.sortOrder
		)
		ao.send({ Target = msg.From, Action = "Delegates-Notice", Data = json.encode(result) })
	end
)

addEventingHandler(
	"paginatedAllowedDelegates",
	utils.hasMatchingTag("Action", "Paginated-Allowed-Delegates"),
	function(msg)
		local page = utils.parsePaginationTags(msg)
		local result =
			gar.getPaginatedAllowedDelegates(msg.Tags.Address or msg.From, page.cursor, page.limit, page.sortOrder)
		ao.send({ Target = msg.From, Action = "Allowed-Delegates-Notice", Data = json.encode(result) })
	end
)

-- END READ HANDLERS

-- AUCTION HANDLER
addEventingHandler("releaseName", utils.hasMatchingTag("Action", ActionMap.ReleaseName), function(msg)
	-- validate the name and process id exist, then create the auction using the auction function
	local name = string.lower(msg.Tags.Name)
	local processId = utils.formatAddress(msg.From)
	local record = arns.getRecord(name)
	local initiator = utils.formatAddress(msg.Tags.Initiator or msg.From)
	local timestamp = tonumber(msg.Timestamp)

	assert(name and #name > 0, "Name is required")
	assert(processId and utils.isValidAOAddress(processId), "Process-Id is required")
	assert(initiator and utils.isValidAOAddress(initiator), "Initiator is required")
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
	ao.send({
		Target = initiator,
		Action = "Auction-Notice",
		Name = name,
		Data = json.encode(auction),
	})
	ao.send({
		Target = processId,
		Action = "Auction-Notice",
		Name = name,
		Data = json.encode(auction),
	})
	return
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
	ao.send({
		Target = msg.From,
		Action = ActionMap.Auctions .. "-Notice",
		Data = json.encode(paginatedAuctions),
	})
end)

addEventingHandler("auctionInfo", utils.hasMatchingTag("Action", ActionMap.AuctionInfo), function(msg)
	local name = string.lower(msg.Tags.Name)
	local auction = arns.getAuction(name)

	assert(auction, "Auction not found")

	ao.send({
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
	local timestamp = tonumber(msg.Tags.Timestamp or msg.Timestamp)
	local type = msg.Tags["Purchase-Type"] or "permabuy"
	local years = msg.Tags.Years and tonumber(msg.Tags.Years) or nil
	local intervalMs = msg.Tags["Price-Interval-Ms"] and tonumber(msg.Tags["Price-Interval-Ms"]) or 15 * 60 * 1000 -- 15 minute intervals by default

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

	ao.send({
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
	local bidAmount = msg.Tags.Quantity and tonumber(msg.Tags.Quantity) or nil -- if nil, we use the current bid price
	local bidder = utils.formatAddress(msg.From)
	local processId = utils.formatAddress(msg.Tags["Process-Id"])
	local timestamp = tonumber(msg.Timestamp)
	local type = msg.Tags["Purchase-Type"] or "permabuy"
	local years = msg.Tags.Years and tonumber(msg.Tags.Years) or nil

	-- assert name, bidder, processId are provided
	assert(name and #name > 0, "Name is required")
	assert(bidder and utils.isValidAOAddress(bidder), "Bidder is required")
	assert(processId and utils.isValidAOAddress(processId), "Process-Id is required")
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
		ao.send({
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

		ao.send({
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
	local from = utils.formatAddress(msg.From)
	local allowedDelegates = msg.Tags["Allowed-Delegates"]
		and utils.splitAndTrimString(msg.Tags["Allowed-Delegates"], ",")
	assert(allowedDelegates and #allowedDelegates > 0, "Allowed-Delegates is required")
	msg.ioEvent:addField("Input-New-Delegates-Count", utils.lengthOfTable(allowedDelegates))
	local result = gar.allowDelegates(allowedDelegates, from)

	if result ~= nil then
		msg.ioEvent:addField("New-Allowed-Delegates", result.newAllowedDelegates or {})
		msg.ioEvent:addField("New-Allowed-Delegates-Count", utils.lengthOfTable(result.newAllowedDelegates))
		msg.ioEvent:addField(
			"Gateway-Total-Allowed-Delegates",
			utils.lengthOfTable(result.gateway and result.gateway.settings.allowedDelegatesLookup or {})
				+ utils.lengthOfTable(result.gateway and result.gateway.delegates or {})
		)
	end

	ao.send({
		Target = msg.From,
		Tags = { Action = ActionMap.AllowDelegates .. "-Notice" },
		Data = json.encode(result and result.newAllowedDelegates or {}),
	})
end)

addEventingHandler("disallowDelegates", utils.hasMatchingTag("Action", ActionMap.DisallowDelegates), function(msg)
	local from = utils.formatAddress(msg.From)
	local timestamp = tonumber(msg.Timestamp)
	local disallowedDelegates = msg.Tags["Disallowed-Delegates"]
		and utils.splitAndTrimString(msg.Tags["Disallowed-Delegates"], ",")
	assert(disallowedDelegates and #disallowedDelegates > 0, "Disallowed-Delegates is required")
	msg.ioEvent:addField("Input-Disallowed-Delegates-Count", utils.lengthOfTable(disallowedDelegates))
	local result = gar.disallowDelegates(disallowedDelegates, from, msg.Id, timestamp)
	if result ~= nil then
		msg.ioEvent:addField("New-Disallowed-Delegates", result.removedDelegates or {})
		msg.ioEvent:addField("New-Disallowed-Delegates-Count", utils.lengthOfTable(result.removedDelegates))
		msg.ioEvent:addField(
			"Gateway-Total-Allowed-Delegates",
			utils.lengthOfTable(result.gateway and result.gateway.settings.allowedDelegatesLookup or {})
				+ utils.lengthOfTable(result.gateway and result.gateway.delegates or {})
		)
	end

	ao.send({
		Target = msg.From,
		Tags = { Action = ActionMap.DisallowDelegates .. "-Notice" },
		Data = json.encode(result and result.removedDelegates or {}),
	})
end)

addEventingHandler("paginatedDelegations", utils.hasMatchingTag("Action", "Paginated-Delegations"), function(msg)
	local address = utils.formatAddress(msg.Tags.Address or msg.From)
	local page = utils.parsePaginationTags(msg)

	assert(utils.isValidAOAddress(address), "Invalid address.")

	local result = gar.getPaginatedDelegations(address, page.cursor, page.limit, page.sortBy, page.sortOrder)
	ao.send({
		Target = msg.From,
		Tags = { Action = ActionMap.Delegations .. "-Notice" },
		Data = json.encode(result),
	})
end)

addEventingHandler(ActionMap.RedelegateStake, utils.hasMatchingTag("Action", ActionMap.RedelegateStake), function(msg)
	local sourceAddress = msg.Tags.Source
	local targetAddress = msg.Tags.Target
	local delegateAddress = msg.From
	local quantity = msg.Tags.Quantity and tonumber(msg.Tags.Quantity) or nil
	local vaultId = msg.Tags["Vault-Id"]
	local timestamp = tonumber(msg.Timestamp)

	assert(utils.isValidAOAddress(sourceAddress), "Invalid source gateway address")
	assert(utils.isValidAOAddress(targetAddress), "Invalid target gateway address")
	assert(utils.isValidAOAddress(delegateAddress), "Invalid delegator address")
	assert(timestamp, "Timestamp is required")
	if vaultId then
		assert(utils.isInteger(tonumber(vaultId)), "Invalid vault id")
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

	ao.send({
		Target = msg.From,
		Tags = { Action = ActionMap.RedelegateStake .. "-Notice", Gateway = msg.Tags.Target },
		Data = json.encode(redelegationResult),
	})
end)

addEventingHandler(ActionMap.RedelegationFee, utils.hasMatchingTag("Action", ActionMap.RedelegationFee), function(msg)
	local delegateAddress = msg.Tags.Address or utils.formatAddress(msg.From)
	assert(utils.isValidAOAddress(delegateAddress), "Invalid delegator address")
	local feeResult = gar.getRedelegationFee(delegateAddress, tonumber(msg.Timestamp))
	ao.send({
		Target = msg.From,
		Tags = { Action = ActionMap.RedelegationFee .. "-Notice" },
		Data = json.encode(feeResult),
	})
end)

--- PRIMARY NAMES
addEventingHandler("removePrimaryName", utils.hasMatchingTag("Action", ActionMap.RemovePrimaryNames), function(msg)
	local names = utils.splitAndTrimString(msg.Tags.Names, ",")
	local from = utils.formatAddress(msg.From)
	assert(names and #names > 0, "Names are required")
	assert(from, "From is required")

	local removedPrimaryNamesAndOwners = primaryNames.removePrimaryNames(names, from)

	ao.send({
		Target = msg.From,
		Action = ActionMap.RemovePrimaryNames .. "-Notice",
		Data = json.encode(removedPrimaryNamesAndOwners),
	})

	-- TODO: send messages to the recipients of the claims? we could index on unique recipients and send one per recipient to avoid multiple messages
	-- OR ANTS are responsible for sending messages to the recipients of the claims
	for _, removedPrimaryNameAndOwner in pairs(removedPrimaryNamesAndOwners) do
		ao.send({
			Target = removedPrimaryNameAndOwner.owner,
			Action = ActionMap.RemovePrimaryNames .. "-Notice",
			Tags = { Name = removedPrimaryNameAndOwner.name },
			Data = json.encode(removedPrimaryNameAndOwner),
		})
	end
end)

addEventingHandler("requestPrimaryName", utils.hasMatchingTag("Action", ActionMap.PrimaryNameRequest), function(msg)
	local fundFrom = msg.Tags["Fund-From"]
	local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
	local initiator = utils.formatAddress(msg.From) -- the process that is creating the claim
	local timestamp = tonumber(msg.Timestamp)
	assert(name, "Name is required")
	assert(initiator, "Initiator is required")
	assert(timestamp, "Timestamp is required")
	assertValidFundFrom(fundFrom)

	local primaryNameResult = primaryNames.createPrimaryNameRequest(name, initiator, timestamp, msg.Id, fundFrom)

	adjustSuppliesForFundingPlan(primaryNameResult.fundingPlan)

	--- if the from is the new owner, then send an approved notice to the from
	if primaryNameResult.newPrimaryName then
		ao.send({
			Target = msg.From,
			Action = ActionMap.ApprovePrimaryNameRequest .. "-Notice",
			Data = json.encode(primaryNameResult),
		})
		return
	end

	if primaryNameResult.request then
		--- send a notice to the from, and the base name owner
		ao.send({
			Target = msg.From,
			Action = ActionMap.PrimaryNameRequest .. "-Notice",
			Data = json.encode(primaryNameResult),
		})
		ao.send({
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
		local recipient = utils.formatAddress(msg.Tags.Recipient) or utils.formatAddress(msg.From)
		local from = utils.formatAddress(msg.From) -- the recipient of the primary name
		local timestamp = tonumber(msg.Timestamp)
		assert(name, "Name is required")
		assert(recipient, "Recipient is required")
		assert(from, "From is required")
		assert(timestamp, "Timestamp is required")

		local approvedPrimaryNameResult = primaryNames.approvePrimaryNameRequest(recipient, name, from, timestamp)

		--- send a notice to the from
		ao.send({
			Target = msg.From,
			Action = ActionMap.ApprovePrimaryNameRequest .. "-Notice",
			Data = json.encode(approvedPrimaryNameResult),
		})
		--- send a notice to the owner
		ao.send({
			Target = approvedPrimaryNameResult.newPrimaryName.owner,
			Action = ActionMap.ApprovePrimaryNameRequest .. "-Notice",
			Data = json.encode(approvedPrimaryNameResult),
		})
	end
)

--- Handles forward and reverse resolutions (e.g. name -> address and address -> name)
addEventingHandler("getPrimaryNameData", utils.hasMatchingTag("Action", ActionMap.PrimaryName), function(msg)
	local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
	local address = msg.Tags.Address and utils.formatAddress(msg.Tags.Address) or utils.formatAddress(msg.From)
	local primaryNameData = name and primaryNames.getPrimaryNameDataWithOwnerFromName(name)
		or address and primaryNames.getPrimaryNameDataWithOwnerFromAddress(address)
	assert(primaryNameData, "Primary name data not found")
	return ao.send({
		Target = msg.From,
		Action = ActionMap.PrimaryName .. "-Notice",
		Tags = { Owner = primaryNameData.owner, Name = primaryNameData.name },
		Data = json.encode(primaryNameData),
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
		return ao.send({
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

	return ao.send({
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
		assert(utils.isValidAOAddress(gatewayAddress), "Invalid gateway address")
		local result =
			gar.getPaginatedVaultsForGateway(gatewayAddress, page.cursor, page.limit, page.sortBy, page.sortOrder)
		return ao.send({
			Target = msg.From,
			Action = "Gateway-Vaults-Notice",
			Data = json.encode(result),
		})
	end
)

return process
