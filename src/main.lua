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
	-- NAME REGISTRY READ APIS
	Record = "Record",
	Records = "Records",
	ReservedNames = "Reserved-Names",
	ReservedName = "Reserved-Name",
	TokenCost = "Token-Cost",
	CostDetails = "Get-Cost-Details-For-Action",
	GetRegistrationFees = "Get-Registration-Fees",
	-- GATEWAY REGISTRY READ APIS
	Gateway = "Gateway",
	Gateways = "Gateways",
	GatewayRegistrySettings = "Gateway-Registry-Settings",
	-- writes
	Vault = "Vault",
	Vaults = "Vaults",
	CreateVault = "Create-Vault",
	VaultedTransfer = "Vaulted-Transfer",
	ExtendVault = "Extend-Vault",
	IncreaseVault = "Increase-Vault",
	BuyRecord = "Buy-Record", -- TODO: standardize these as `Buy-Name` or `Upgrade-Record`
	UpgradeName = "Upgrade-Name", -- TODO: may be more aligned to `Upgrade-Record`
	ExtendLease = "Extend-Lease",
	IncreaseUndernameLimit = "Increase-Undername-Limit",
	JoinNetwork = "Join-Network",
	LeaveNetwork = "Leave-Network",
	IncreaseOperatorStake = "Increase-Operator-Stake",
	DecreaseOperatorStake = "Decrease-Operator-Stake",
	UpdateGatewaySettings = "Update-Gateway-Settings",
	SaveObservations = "Save-Observations",
	DelegateStake = "Delegate-Stake",
	DecreaseDelegateStake = "Decrease-Delegate-Stake",
	CancelWithdrawal = "Cancel-Withdrawal",
	InstantWithdrawal = "Instant-Withdrawal",
	ReassignName = "Reassign-Name",
	-- auctions
	Auctions = "Auctions",
	ReleaseName = "Release-Name",
	AuctionInfo = "Auction-Info",
	AuctionBid = "Auction-Bid",
	AuctionPrices = "Auction-Prices",
	AllowDelegates = "Allow-Delegates",
	DisallowDelegates = "Disallow-Delegates",
	Delegations = "Delegations",
	-- PRIMARY NAMES
	RemovePrimaryNames = "Remove-Primary-Names",
	CreatePrimaryNameClaim = "Create-Primary-Name-Claim",
	RevokeClaims = "Revoke-Claims",
	ClaimPrimaryName = "Claim-Primary-Name",
	PrimaryNames = "Primary-Names",
	PrimaryName = "Primary-Name",
}

-- Low fidelity trackers
LastKnownCirculatingSupply = LastKnownCirculatingSupply or 0 -- total circulating supply (e.g. balances - protocol balance)
LastKnownLockedSupply = LastKnownLockedSupply or 0 -- total vault balance across all vaults
LastKnownStakedSupply = LastKnownStakedSupply or 0 -- total operator stake across all gateways
LastKnownDelegatedSupply = LastKnownDelegatedSupply or 0 -- total delegated stake across all gateways
LastKnownWithdrawSupply = LastKnownWithdrawSupply or 0 -- total withdraw supply across all gateways (gateways and delegates)
local function lastKnownTotalTokenSupply()
	return LastKnownCirculatingSupply
		+ LastKnownLockedSupply
		+ LastKnownStakedSupply
		+ LastKnownDelegatedSupply
		+ LastKnownWithdrawSupply
		+ Balances[Protocol]
end
LastGracePeriodEntryEndTimestamp = LastGracePeriodEntryEndTimestamp or 0

local function eventingPcall(ioEvent, onError, fnToCall, ...)
	local status, result = pcall(fnToCall, ...)
	if not status then
		onError(result)
		ioEvent:addField("Error", result)
		return status
	end
	return status, result
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
end

local function addSupplyData(ioEvent, supplyData)
	supplyData = supplyData or {}
	ioEvent:addField("Circulating-Supply", supplyData.circulatingSupply or LastKnownCirculatingSupply)
	ioEvent:addField("Locked-Supply", supplyData.lockedSupply or LastKnownLockedSupply)
	ioEvent:addField("Staked-Supply", supplyData.stakedSupply or LastKnownStakedSupply)
	ioEvent:addField("Delegated-Supply", supplyData.delegatedSupply or LastKnownDelegatedSupply)
	ioEvent:addField("Withdraw-Supply", supplyData.withdrawSupply or LastKnownWithdrawSupply)
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
			local gw = gar.getGateway(gwAddress) or {}
			if gw and (gw.totalDelegatedStake > 0) then
				invariantSlashedGateways[gwAddress] = gw.totalDelegatedStake
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
		eventingPcall(msg.ioEvent, function()
			-- No op
		end, handleFn, msg)
		msg.ioEvent:printEvent()
	end)
end

-- prune state before every interaction
Handlers.add("prune", function()
	return "continue" -- continue is a pattern that matches every message and continues to the next handler that matches the tags
end, function(msg)
	assert(msg.Timestamp, "Timestamp is required for a tick interaction")

	-- Stash a new IOEvent with the message
	msg.ioEvent = IOEvent(msg)
	local epochIndex = epochs.getEpochIndexForTimestamp(tonumber(msg.Tags.Timestamp or msg.Timestamp))
	msg.ioEvent:addField("epochIndex", epochIndex)

	local msgId = msg.Id
	local msgTimestamp = tonumber(msg.Timestamp)
	print("Pruning state at timestamp: " .. msgTimestamp)
	-- we need to be concious about deep copying here, as it could consume a large amount of memory. so long as we are pruning effectively, this should be fine
	local previousState = {
		Vaults = utils.deepCopy(Vaults),
		GatewayRegistry = utils.deepCopy(GatewayRegistry),
		NameRegistry = utils.deepCopy(NameRegistry),
		Epochs = utils.deepCopy(Epochs),
		Balances = utils.deepCopy(Balances),
		lastKnownCirculatingSupply = LastKnownCirculatingSupply,
		lastKnownLockedSupply = LastKnownLockedSupply,
		lastKnownStakedSupply = LastKnownStakedSupply,
		lastKnownDelegatedSupply = LastKnownDelegatedSupply,
		lastKnownWithdrawSupply = LastKnownWithdrawSupply,
		lastKnownTotalSupply = lastKnownTotalTokenSupply(),
	}
	local status, resultOrError = pcall(prune.pruneState, msgTimestamp, msgId, LastGracePeriodEntryEndTimestamp)
	if not status then
		ao.send({
			Target = msg.From,
			Action = "Invalid-Tick-Notice",
			Error = "Invalid-Tick",
			Data = json.encode(resultOrError),
		})
		Vaults = previousState.Vaults
		GatewayRegistry = previousState.GatewayRegistry
		NameRegistry = previousState.NameRegistry
		Epochs = previousState.Epochs
		Balances = previousState.Balances
		msg.ioEvent:addField("Tick-Error", tostring(resultOrError))
		return true -- stop processing here and return
	end

	if resultOrError ~= nil then
		local prunedRecordsCount = utils.lengthOfTable(resultOrError.prunedRecords or {})
		if prunedRecordsCount > 0 then
			local prunedRecordNames = {}
			for name, _ in pairs(resultOrError.prunedRecords) do
				table.insert(prunedRecordNames, name)
			end
			msg.ioEvent:addField("Pruned-Records", prunedRecordNames)
			msg.ioEvent:addField("Pruned-Records-Count", prunedRecordsCount)
			msg.ioEvent:addField("Records-Count", utils.lengthOfTable(NameRegistry.records))
		end
		local newGracePeriodRecordsCount = utils.lengthOfTable(resultOrError.newGracePeriodRecords or {})
		if newGracePeriodRecordsCount > 0 then
			local newGracePeriodRecordNames = {}
			for name, record in pairs(resultOrError.newGracePeriodRecords) do
				table.insert(newGracePeriodRecordNames, name)
				if record.endTimestamp > LastGracePeriodEntryEndTimestamp then
					LastGracePeriodEntryEndTimestamp = record.endTimestamp
				end
			end
			msg.ioEvent:addField("New-Grace-Period-Records", newGracePeriodRecordNames)
			msg.ioEvent:addField("New-Grace-Period-Records-Count", newGracePeriodRecordsCount)
			msg.ioEvent:addField("Last-Grace-Period-Entry-End-Timestamp", LastGracePeriodEntryEndTimestamp)
		end
		local prunedAuctions = resultOrError.prunedAuctions or {}
		local prunedAuctionsCount = utils.lengthOfTable(prunedAuctions)
		if prunedAuctionsCount > 0 then
			msg.ioEvent:addField("Pruned-Auctions", prunedAuctions)
			msg.ioEvent:addField("Pruned-Auctions-Count", prunedAuctionsCount)
		end
		local prunedReserved = resultOrError.prunedReserved or {}
		local prunedReservedCount = utils.lengthOfTable(prunedReserved)
		if prunedReservedCount > 0 then
			msg.ioEvent:addField("Pruned-Reserved", prunedReserved)
			msg.ioEvent:addField("Pruned-Reserved-Count", prunedReservedCount)
		end
		local prunedVaultsCount = utils.lengthOfTable(resultOrError.prunedVaults or {})
		if prunedVaultsCount > 0 then
			msg.ioEvent:addField("Pruned-Vaults", resultOrError.prunedVaults)
			msg.ioEvent:addField("Pruned-Vaults-Count", prunedVaultsCount)
			for _, vault in pairs(resultOrError.prunedVaults) do
				LastKnownLockedSupply = LastKnownLockedSupply - vault.balance
				LastKnownCirculatingSupply = LastKnownCirculatingSupply + vault.balance
			end
		end
		local prunedEpochsCount = utils.lengthOfTable(resultOrError.prunedEpochs or {})
		if prunedEpochsCount > 0 then
			msg.ioEvent:addField("Pruned-Epochs", resultOrError.prunedEpochs)
			msg.ioEvent:addField("Pruned-Epochs-Count", prunedEpochsCount)
		end

		local pruneGatewaysResult = resultOrError.pruneGatewaysResult or {}
		addPruneGatewaysResult(msg.ioEvent, pruneGatewaysResult)
	end

	if
		LastKnownCirculatingSupply ~= previousState.lastKnownCirculatingSupply
		or LastKnownLockedSupply ~= previousState.lastKnownLockedSupply
		or LastKnownStakedSupply ~= previousState.lastKnownStakedSupply
		or LastKnownDelegatedSupply ~= previousState.lastKnownDelegatedSupply
		or LastKnownWithdrawSupply ~= previousState.lastKnownWithdrawSupply
		or Balances[Protocol] ~= previousState.Balances[Protocol]
		or lastKnownTotalTokenSupply() ~= previousState.lastKnownTotalSupply
	then
		addSupplyData(msg.ioEvent)
	end

	return status
end)

-- Write handlers
addEventingHandler(ActionMap.Transfer, utils.hasMatchingTag("Action", ActionMap.Transfer), function(msg)
	-- assert recipient is a valid arweave address
	local function checkAssertions()
		assert(utils.isValidAOAddress(msg.Tags.Recipient), "Invalid recipient")
		assert(
			tonumber(msg.Tags.Quantity) > 0 and utils.isInteger(tonumber(msg.Tags.Quantity)),
			"Invalid quantity. Must be integer greater than 0"
		)
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.Transfer .. "-Notice",
				Error = "Bad-Input",
			},
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local from = utils.formatAddress(msg.From)
	local recipient = utils.formatAddress(msg.Tags.Recipient)
	local quantity = tonumber(msg.Tags.Quantity)
	msg.ioEvent:addField("RecipientFormatted", recipient)

	local shouldContinue2, result = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.Transfer .. "-Notice", Error = "Transfer-Error" },
			Data = tostring(error),
		})
	end, balances.transfer, recipient, from, quantity)
	if not shouldContinue2 then
		return
	end

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
	local function checkAssertions()
		assert(
			msg.Tags["Lock-Length"]
				and tonumber(msg.Tags["Lock-Length"]) > 0
				and utils.isInteger(tonumber(msg.Tags["Lock-Length"])),
			"Invalid lock length. Must be integer greater than 0"
		)
		assert(
			msg.Tags.Quantity and tonumber(msg.Tags.Quantity) > 0 and utils.isInteger(tonumber(msg.Tags.Quantity)),
			"Invalid quantity. Must be integer greater than 0"
		)
	end

	local from = utils.formatAddress(msg.From)
	local quantity = tonumber(msg.Tags.Quantity)
	local lockLengthMs = tonumber(msg.Tags["Lock-Length"])
	local timestamp = tonumber(msg.Timestamp)
	local msgId = msg.Id

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = from,
			Tags = { Action = "Invalid-" .. ActionMap.CreateVault .. "-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local shouldContinue2, vault = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = from,
			Tags = {
				Action = "Invalid-" .. ActionMap.CreateVault .. "-Notice",
				Error = "Invalid-" .. ActionMap.CreateVault,
			},
			Data = tostring(error),
		})
	end, vaults.createVault, from, quantity, lockLengthMs, timestamp, msgId)
	if not shouldContinue2 then
		return
	end

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
	local function checkAssertions()
		assert(utils.isValidAOAddress(msg.Tags.Recipient), "Invalid recipient")
		assert(
			tonumber(msg.Tags["Lock-Length"]) > 0 and utils.isInteger(tonumber(msg.Tags["Lock-Length"])),
			"Invalid lock length. Must be integer greater than 0"
		)
		assert(
			tonumber(msg.Tags.Quantity) > 0 and utils.isInteger(tonumber(msg.Tags.Quantity)),
			"Invalid quantity. Must be integer greater than 0"
		)
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Vaulted-Transfer-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local from = utils.formatAddress(msg.From)
	local recipient = utils.formatAddress(msg.Tags.Recipient)
	local quantity = tonumber(msg.Tags.Quantity)
	local lockLengthMs = tonumber(msg.Tags["Lock-Length"])
	local timestamp = tonumber(msg.Timestamp)
	local msgId = msg.Id

	local shouldContinue2, vault = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.VaultedTransfer .. "-Notice",
				Error = "Invalid-" .. ActionMap.VaultedTransfer,
			},
			Data = tostring(error),
		})
	end, vaults.vaultedTransfer, from, recipient, quantity, lockLengthMs, timestamp, msgId)
	if not shouldContinue2 then
		return
	end

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
	local checkAssertions = function()
		assert(utils.isValidAOAddress(msg.Tags["Vault-Id"]), "Invalid vault id")
		assert(
			tonumber(msg.Tags["Extend-Length"]) > 0 and utils.isInteger(tonumber(msg.Tags["Extend-Length"])),
			"Invalid extension length. Must be integer greater than 0"
		)
	end
	local from = utils.formatAddress(msg.From)
	local vaultId = utils.formatAddress(msg.Tags["Vault-Id"])
	local timestamp = tonumber(msg.Timestamp)
	local extendLengthMs = tonumber(msg.Tags["Extend-Length"])
	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.ExtendVault .. "-Notice",
				Error = "Bad-Input",
			},
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local shouldContinue2, vault = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.ExtendVault .. "-Notice",
				Error = "Invalid-" .. ActionMap.ExtendVault,
			},
			Data = tostring(error),
		})
	end, vaults.extendVault, from, extendLengthMs, timestamp, vaultId)
	if not shouldContinue2 then
		return
	end

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
	local function checkAssertions()
		assert(utils.isValidArweaveAddress(msg.Tags["Vault-Id"]), "Invalid vault id")
		assert(
			tonumber(msg.Tags.Quantity) > 0 and utils.isInteger(tonumber(msg.Tags.Quantity)),
			"Invalid quantity. Must be integer greater than 0"
		)
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.IncreaseVault .. "-Notice",
				Error = "Bad-Input",
			},
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local quantity = tonumber(msg.Tags.Quantity)
	local vaultId = msg.Tags["Vault-Id"]

	local shouldContinue2, vault = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.IncreaseVault .. "-Notice",
				Error = "Invalid-" .. ActionMap.IncreaseVault,
			},
			Data = tostring(error),
		})
	end, vaults.increaseVault, msg.From, quantity, vaultId, msg.Timestamp)
	if not shouldContinue2 then
		return
	end

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

	local checkAssertions = function()
		assert(
			type(purchaseType) == "string" and purchaseType == "lease" or purchaseType == "permabuy",
			"Invalid purchase type"
		)
		assert(
			type(name) == "string" and #name > 0 and #name <= 51 and not utils.isValidAOAddress(name),
			"Invalid name"
		) -- make sure it's a string, not empty, not longer than 51 characters, and not an arweave address
		-- assert processId is valid pattern
		assert(type(processId) == "string", "Process id is required and must be a string.")
		assert(utils.isValidAOAddress(processId), "Process Id must be a valid AO signer address..")
		if years then
			assert(
				years >= 1 and years <= 5 and utils.isInteger(years),
				"Invalid years. Must be integer between 1 and 5"
			)
		end
		assertValidFundFrom(fundFrom)
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.BuyRecord .. "-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	msg.ioEvent:addField("nameLength", #msg.Tags.Name)

	local shouldContinue2, result = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.BuyRecord .. "-Notice",
				Error = "Invalid-" .. ActionMap.BuyRecord,
			},
			Data = tostring(error),
		})
	end, arns.buyRecord, name, purchaseType, years, from, timestamp, processId, msg.Id, fundFrom)
	if not shouldContinue2 then
		return
	end

	local record = {}
	if result ~= nil then
		record = result.record
		addRecordResultFields(msg.ioEvent, result)
		LastKnownCirculatingSupply = LastKnownCirculatingSupply - record.purchasePrice
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
	local checkAssertions = function()
		assert(type(msg.Tags.Name) == "string", "Invalid name")
		assert(msg.Timestamp, "Timestamp is required")
		assertValidFundFrom(fundFrom)
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.UpgradeName .. "-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local name = string.lower(msg.Tags.Name)
	local from = utils.formatAddress(msg.From)
	local timestamp = tonumber(msg.Timestamp)

	local shouldContinue2, result = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.UpgradeName .. "-Notice",
				Error = "Invalid-" .. ActionMap.UpgradeName,
			},
			Data = tostring(error),
		})
	end, arns.upgradeRecord, from, name, timestamp, msg.Id, fundFrom)
	if not shouldContinue2 then
		return
	end

	local record = {}
	if result ~= nil then
		record = result.record
		addRecordResultFields(msg.ioEvent, result)
		LastKnownCirculatingSupply = LastKnownCirculatingSupply - record.purchasePrice
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
	local fundFrom = msg.Tags["Fund-From"]
	local checkAssertions = function()
		assert(type(msg.Tags.Name) == "string", "Invalid name")
		assert(
			tonumber(msg.Tags.Years) > 0 and tonumber(msg.Tags.Years) < 5 and utils.isInteger(tonumber(msg.Tags.Years)),
			"Invalid years. Must be integer between 1 and 5"
		)
		assertValidFundFrom(fundFrom)
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.ExtendLease .. "-Notice",
				Error = "Bad-Input",
			},
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local shouldContinue2, result = eventingPcall(
		msg.ioEvent,
		function(error)
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-" .. ActionMap.ExtendLease .. "-Notice",
					Error = "Invalid-" .. ActionMap.ExtendLease,
				},
				Data = tostring(error),
			})
		end,
		arns.extendLease,
		msg.From,
		string.lower(msg.Tags.Name),
		tonumber(msg.Tags.Years),
		msg.Timestamp,
		msg.Id,
		fundFrom
	)
	if not shouldContinue2 then
		return
	end

	local recordResult = {}
	if result ~= nil then
		msg.ioEvent:addField("Total-Extension-Fee", result.totalExtensionFee)
		addRecordResultFields(msg.ioEvent, result)

		LastKnownCirculatingSupply = LastKnownCirculatingSupply - result.totalExtensionFee
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
		local fundFrom = msg.Tags["Fund-From"]
		local checkAssertions = function()
			assert(type(msg.Tags.Name) == "string", "Invalid name")
			assert(
				msg.Tags.Quantity
					and tonumber(msg.Tags.Quantity) > 0
					and tonumber(msg.Tags.Quantity) < 9990
					and utils.isInteger(msg.Tags.Quantity),
				"Invalid quantity. Must be an integer value greater than 0 and less than 9990"
			)
			assertValidFundFrom(fundFrom)
		end

		local shouldContinue = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-" .. ActionMap.IncreaseUndernameLimit .. "-Notice",
					Error = "Bad-Input",
				},
				Data = tostring(error),
			})
		end, checkAssertions)
		if not shouldContinue then
			return
		end

		local shouldContinue2, result = eventingPcall(
			msg.ioEvent,
			function(error)
				ao.send({
					Target = msg.From,
					Tags = {
						Action = "Invalid-" .. ActionMap.IncreaseUndernameLimit .. "-Notice",
						Error = "Invalid-" .. ActionMap.IncreaseUndernameLimit,
					},
					Data = tostring(error),
				})
			end,
			arns.increaseundernameLimit,
			msg.From,
			string.lower(msg.Tags.Name),
			tonumber(msg.Tags.Quantity),
			msg.Timestamp,
			msg.Id,
			fundFrom
		)
		if not shouldContinue2 then
			return
		end

		local recordResult = {}
		if result ~= nil then
			recordResult = result.record
			addRecordResultFields(msg.ioEvent, result)
			msg.ioEvent:addField("previousUndernameLimit", recordResult.undernameLimit - tonumber(msg.Tags.Quantity))
			msg.ioEvent:addField("additionalUndernameCost", result.additionalUndernameCost)
			LastKnownCirculatingSupply = LastKnownCirculatingSupply - result.additionalUndernameCost
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
	local checkAssertions = function()
		assertTokenCostTags(msg)
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.TokenCost .. "-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local shouldContinue2, tokenCostResult = eventingPcall(
		msg.ioEvent,
		function(error)
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-" .. ActionMap.TokenCost .. "-Notice",
					Error = "Invalid-" .. ActionMap.TokenCost,
				},
				Data = tostring(error),
			})
		end,
		arns.getTokenCost,
		{
			intent = msg.Tags.Intent,
			name = string.lower(msg.Tags.Name),
			years = tonumber(msg.Tags.Years) or 1,
			quantity = tonumber(msg.Tags.Quantity),
			purchaseType = msg.Tags["Purchase-Type"] or "lease",
			currentTimestamp = tonumber(msg.Timestamp) or tonumber(msg.Tags.Timestamp),
			from = msg.From,
		}
	)
	if not shouldContinue2 or not tokenCostResult then
		return
	end
	local tokenCost = tokenCostResult.tokenCost

	ao.send({
		Target = msg.From,
		Tags = { Action = ActionMap.TokenCost .. "-Notice", ["Token-Cost"] = tostring(tokenCost) },
		Data = json.encode(tokenCost),
	})
end)

addEventingHandler(ActionMap.CostDetails, utils.hasMatchingTag("Action", ActionMap.CostDetails), function(msg)
	local fundFrom = msg.Tags["Fund-From"]
	local checkAssertions = function()
		assertTokenCostTags(msg)
		assertValidFundFrom(fundFrom)
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.CostDetails .. "-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local shouldContinue2, tokenCostAndFundingPlan = eventingPcall(
		msg.ioEvent,
		function(error)
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-" .. ActionMap.CostDetails .. "-Notice",
					Error = "Invalid-" .. ActionMap.CostDetails,
				},
				Data = tostring(error),
			})
		end,
		arns.getTokenCostAndFundingPlanForIntent,
		msg.Tags.Intent,
		string.lower(msg.Tags.Name),
		tonumber(msg.Tags.Years) or 1,
		tonumber(msg.Tags.Quantity),
		msg.Tags["Purchase-Type"] or "lease",
		tonumber(msg.Timestamp) or tonumber(msg.Tags.Timestamp),
		msg.From,
		fundFrom
	)
	if not shouldContinue2 or tokenCostAndFundingPlan == nil then
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
		local status, priceList = pcall(arns.getRegistrationFees)

		if not status then
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-" .. ActionMap.GetRegistrationFees .. "-Notice",
					Error = "Invalid-" .. ActionMap.GetRegistrationFees,
				},
				Data = tostring(priceList),
			})
		else
			ao.send({
				Target = msg.From,
				Tags = { Action = ActionMap.GetRegistrationFees .. "-Notice" },
				Data = json.encode(priceList),
			})
		end
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

	if msg.Tags.Services and not updatedServices then
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.JoinNetwork .. "-Notice",
				Error = "Invalid-" .. ActionMap.JoinNetwork .. "-Input",
			},
			Data = tostring("Failed to decode Services JSON: " .. msg.Tags.Services),
		})
		return
	end
	-- format join network and observer address
	local fromAddress = utils.formatAddress(msg.From)
	local observerAddress = msg.Tags["Observer-Address"] or fromAddress
	local formattedObserverAddress = utils.formatAddress(observerAddress)
	local stake = tonumber(msg.Tags["Operator-Stake"])
	local timestamp = tonumber(msg.Timestamp)

	msg.ioEvent:addField("Resolved-Observer-Address", formattedObserverAddress)
	msg.ioEvent:addField("Sender-Previous-Balance", Balances[fromAddress] or 0)

	local shouldContinue, gateway = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = fromAddress,
			Tags = {
				Action = "Invalid-" .. ActionMap.JoinNetwork .. "-Notice",
				Error = "Invalid-" .. ActionMap.JoinNetwork,
			},
			Data = tostring(error),
		})
	end, gar.joinNetwork, fromAddress, stake, updatedSettings, updatedServices, formattedObserverAddress, timestamp)
	if not shouldContinue then
		return
	end

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
	local gatewayBeforeLeaving = gar.getGateway(from)
	local gwPrevTotalDelegatedStake = 0
	local gwPrevStake = 0
	if gatewayBeforeLeaving ~= nil then
		gwPrevTotalDelegatedStake = gatewayBeforeLeaving.totalDelegatedStake
		gwPrevStake = gatewayBeforeLeaving.operatorStake
	end
	local shouldContinue, gateway = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.LeaveNetwork .. "-Notice",
				Error = "Invalid-" .. ActionMap.LeaveNetwork,
			},
			Data = tostring(error),
		})
	end, gar.leaveNetwork, from, msg.Timestamp, msg.Id)
	if not shouldContinue then
		return
	end

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
		local checkAssertions = function()
			assert(
				utils.isInteger(tonumber(msg.Tags.Quantity)) and tonumber(msg.Tags.Quantity) > 0,
				"Invalid quantity. Must be integer greater than 0"
			)
		end

		local shouldContinue = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-" .. ActionMap.IncreaseOperatorStake .. "-Notice",
					Error = "Bad-Input",
				},
				Data = tostring(error),
			})
		end, checkAssertions)
		if not shouldContinue then
			return
		end

		msg.ioEvent:addField("Sender-Previous-Balance", Balances[msg.From])
		local quantity = tonumber(msg.Tags.Quantity)

		local shouldContinue2, gateway = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-" .. ActionMap.IncreaseOperatorStake .. "-Notice",
					Error = "Invalid-" .. ActionMap.IncreaseOperatorStake,
				},
				Data = tostring(error),
			})
		end, gar.increaseOperatorStake, msg.From, quantity)
		if not shouldContinue2 then
			return
		end

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
		local checkAssertions = function()
			assert(
				msg.Tags.Quantity
					and tonumber(msg.Tags.Quantity)
					and utils.isInteger(tonumber(msg.Tags.Quantity))
					and tonumber(msg.Tags.Quantity) > constants.minimumWithdrawalAmount,
				"Invalid quantity. Must be integer greater than " .. constants.minimumWithdrawalAmount
			)
			if msg.Tags.Instant ~= nil then
				assert(
					msg.Tags.Instant == "true" or msg.Tags.Instant == "false",
					"Instant must be a string with value 'true' or 'false'"
				)
			end
		end

		local shouldContinue = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-" .. ActionMap.DecreaseOperatorStake .. "-Notice",
					Error = "Bad-Input",
				},
				Data = tostring(error),
			})
		end, checkAssertions)
		if not shouldContinue then
			return
		end

		local quantity = tonumber(msg.Tags.Quantity)
		local instantWithdraw = msg.Tags.Instant and msg.Tags.Instant == "true" or false
		msg.ioEvent:addField("Sender-Previous-Balance", Balances[msg.From])

		local shouldContinue2, result = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-" .. ActionMap.DecreaseOperatorStake .. "-Notice",
					Error = "Invalid-" .. ActionMap.DecreaseOperatorStake,
				},
				Data = tostring(error),
			})
		end, gar.decreaseOperatorStake, msg.From, quantity, msg.Timestamp, msg.Id, instantWithdraw)
		if not shouldContinue2 then
			return
		end

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
	local checkAssertions = function()
		assert(utils.isValidAOAddress(msg.Tags.Target or msg.Tags.Address), "Invalid gateway address")
		assert(
			msg.Tags.Quantity and tonumber(msg.Tags.Quantity) > 0 and utils.isInteger(tonumber(msg.Tags.Quantity)),
			"Invalid quantity. Must be integer greater than 0"
		)
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.DelegateStake .. "-Notice",
				Error = "Bad-Input",
			},
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local target = utils.formatAddress(msg.Tags.Target or msg.Tags.Address)
	local from = utils.formatAddress(msg.From)
	local quantity = tonumber(msg.Tags.Quantity)
	msg.ioEvent:addField("Target-Formatted", target)

	local shouldContinue2, gateway = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = from,
			Tags = {
				Action = "Invalid-" .. ActionMap.DelegateStake .. "-Notice",
				Error = tostring(error),
			},
			Data = tostring(error),
		})
	end, gar.delegateStake, from, target, quantity, tonumber(msg.Timestamp))
	if not shouldContinue2 then
		return
	end

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
	local checkAssertions = function()
		assert(utils.isValidAOAddress(msg.Tags.Target or msg.Tags.Address or msg.From), "Invalid gateway address")
		assert(utils.isValidAOAddress(msg.Tags["Vault-Id"]), "Invalid vault id")
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.CancelWithdrawal .. "-Notice",
				Error = "Bad-Input",
			},
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local gatewayAddress = utils.formatAddress(msg.Tags.Target or msg.Tags.Address or msg.From)
	local fromAddress = utils.formatAddress(msg.From)
	local vaultId = msg.Tags["Vault-Id"]
	msg.ioEvent:addField("Target-Formatted", gatewayAddress)

	local shouldContinue2, result = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.CancelWithdrawal .. "-Notice",
				Error = "Invalid-" .. ActionMap.CancelWithdrawal,
			},
			Data = tostring(error),
		})
	end, gar.cancelGatewayWithdrawal, fromAddress, gatewayAddress, vaultId)
	if not shouldContinue2 then
		return
	end

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

		local checkAssertions = function()
			assert(utils.isValidAOAddress(target), "Invalid gateway address")
			assert(utils.isValidAOAddress(vaultId), "Invalid vault id")
		end

		local shouldContinue = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-" .. ActionMap.InstantWithdrawal .. "-Notice",
					Error = "Bad-Input",
				},
				Data = tostring(error),
			})
		end, checkAssertions)
		if not shouldContinue then
			return
		end

		local shouldContinue2, result = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-" .. ActionMap.InstantWithdrawal .. "-Notice",
					Error = "Invalid-" .. ActionMap.InstantWithdrawal,
				},
				Data = tostring(error),
			})
		end, gar.instantGatewayWithdrawal, from, target, vaultId, timestamp)
		if not shouldContinue2 then
			return
		end

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
		local checkAssertions = function()
			assert(utils.isValidAOAddress(msg.Tags.Target or msg.Tags.Address), "Invalid gateway address")
			assert(
				msg.Tags.Quantity
					and tonumber(msg.Tags.Quantity) > constants.minimumWithdrawalAmount
					and utils.isInteger(msg.Tags.Quantity),
				"Invalid quantity. Must be integer greater than " .. constants.minimumWithdrawalAmount
			)
			if msg.Tags.Instant ~= nil then
				assert(
					msg.Tags.Instant == "true" or msg.Tags.Instant == "false",
					"Instant must be a string with value 'true' or 'false'"
				)
			end
		end

		local shouldContinue = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Decrease-Delegate-Stake-Notice", Error = "Bad-Input" },
				Data = tostring(error),
			})
		end, checkAssertions)
		if not shouldContinue then
			return
		end

		local from = utils.formatAddress(msg.From)
		local target = utils.formatAddress(msg.Tags.Target or msg.Tags.Address)
		local quantity = tonumber(msg.Tags.Quantity)
		local instantWithdraw = msg.Tags.Instant and msg.Tags.Instant == "true" or false
		local timestamp = tonumber(msg.Timestamp)
		local messageId = msg.Id
		msg.ioEvent:addField("Target-Formatted", target)
		msg.ioEvent:addField("Quantity", quantity)

		local shouldContinue2, result = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = from,
				Tags = {
					Action = "Invalid-" .. ActionMap.DecreaseDelegateStake .. "-Notice",
					Error = "Invalid-" .. ActionMap.DecreaseDelegateStake,
				},
				Data = tostring(error),
			})
		end, gar.decreaseDelegateStake, target, from, quantity, timestamp, messageId, instantWithdraw)
		if not shouldContinue2 then
			return
		end

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
		local gateway = gar.getGateway(msg.From)
		if not gateway then
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-" .. ActionMap.UpdateGatewaySettings .. "-Notice",
					Error = "Failed-Update-Gateway-Settings",
				},
				Data = "Gateway not found",
			})
			return
		end

		local updatedServices = utils.safeDecodeJson(msg.Tags.Services)

		if msg.Tags.Services and not updatedServices then
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-" .. ActionMap.UpdateGatewaySettings .. "-Notice",
					Error = "Invalid-" .. ActionMap.UpdateGatewaySettings,
				},
				Data = tostring("Failed to decode Services JSON: " .. msg.Tags.Services),
			})
			return
		end

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
				or (gateway.settings.allowedDelegatedLooksup and msg.Tags["Allowed-Delegates"] ~= nil)
			)

		local updatedSettings = {
			label = msg.Tags.Label or gateway.settings.label,
			note = msg.Tags.Note or gateway.settings.note,
			fqdn = msg.Tags.FQDN or gateway.settings.fqdn,
			port = tonumber(msg.Tags.Port) or gateway.settings.port,
			protocol = msg.Tags.Protocol or gateway.settings.protocol,
			allowDelegatedStaking = enableOpenDelegatedStaking -- clear directive to enable
				or enableLimitedDelegatedStaking -- clear directive to enable
				or not disableDelegatedStaking -- NOT clear directive to DISABLE
					and gateway.settings.allowDelegatedStaking, -- otherwise unspecified, so use previous setting

			allowedDelegates = needNewAllowlist and utils.splitAndTrimString(msg.Tags["Allowed-Delegates"], ",") -- replace the lookup list
				or nil, -- change nothing

			minDelegatedStake = tonumber(msg.Tags["Min-Delegated-Stake"]) or gateway.settings.minDelegatedStake,
			delegateRewardShareRatio = tonumber(msg.Tags["Delegate-Reward-Share-Ratio"])
				or gateway.settings.delegateRewardShareRatio,
			properties = msg.Tags.Properties or gateway.settings.properties,
			autoStake = not msg.Tags["Auto-Stake"] and gateway.settings.autoStake or msg.Tags["Auto-Stake"] == "true",
		}

		-- TODO: we could standardize this on our prepended handler to inject and ensure formatted addresses and converted values
		local observerAddress = msg.Tags["Observer-Address"] or gateway.observerAddress
		local formattedAddress = utils.formatAddress(msg.From)
		local formattedObserverAddress = utils.formatAddress(observerAddress)
		local timestamp = tonumber(msg.Timestamp)
		local status, result = pcall(
			gar.updateGatewaySettings,
			formattedAddress,
			updatedSettings,
			updatedServices,
			formattedObserverAddress,
			timestamp,
			msg.Id
		)
		if not status then
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-" .. ActionMap.UpdateGatewaySettings .. "-Notice",
					Error = "Failed-Update-Gateway-Settings",
				},
				Data = tostring(result),
			})
		else
			ao.send({
				Target = msg.From,
				Tags = { Action = ActionMap.UpdateGatewaySettings .. "-Notice" },
				Data = json.encode(result),
			})
		end
	end
)

addEventingHandler(ActionMap.ReassignName, utils.hasMatchingTag("Action", ActionMap.ReassignName), function(msg)
	local newProcessId = utils.formatAddress(msg.Tags["Process-Id"])
	local name = string.lower(msg.Tags.Name)
	local initiator = utils.formatAddress(msg.Tags.Initiator)
	local checkAssertions = function()
		assert(name and #name > 0, "Name is required")
		assert(utils.isValidAOAddress(newProcessId), "Process Id must be a valid AO signer address..")
		if initiator ~= nil then
			assert(utils.isValidAOAddress(initiator), "Invalid initiator address.")
		end
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.ReassignName .. "-Notice",
				Error = "Bad-Input",
			},
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local status, reassignmentOrError = pcall(arns.reassignName, name, msg.From, tonumber(msg.Timestamp), newProcessId)
	if not status then
		ao.send({
			Target = msg.From,
			Action = "Invalid-" .. ActionMap.ReassignName .. "-Notice",
			Error = ActionMap.ReassignName .. "-Error",
			Data = tostring(reassignmentOrError),
		})

		if initiator ~= nil then
			ao.send({
				Target = initiator,
				Action = "Invalid-" .. ActionMap.ReassignName .. "-Notice",
				Error = ActionMap.ReassignName .. "-Error",
				Data = tostring(reassignmentOrError),
			})
		end

		return
	end

	ao.send({
		Target = msg.From,
		Action = ActionMap.ReassignName .. "-Notice",
		Name = name,
		Data = json.encode(reassignmentOrError),
	})

	if initiator ~= nil then
		ao.send({
			Target = initiator,
			Action = ActionMap.ReassignName .. "-Notice",
			Name = name,
			Data = json.encode(reassignmentOrError),
		})
	end
	return
end)

addEventingHandler(ActionMap.SaveObservations, utils.hasMatchingTag("Action", ActionMap.SaveObservations), function(msg)
	local reportTxId = msg.Tags["Report-Tx-Id"]
	local failedGateways = utils.splitAndTrimString(msg.Tags["Failed-Gateways"], ",")
	local checkAssertions = function()
		assert(utils.isValidAOAddress(reportTxId), "Invalid report tx id")
		for _, gateway in ipairs(failedGateways) do
			assert(utils.isValidAOAddress(gateway), "Invalid failed gateway address: " .. gateway)
		end
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.SaveObservations .. "-Notice",
				Error = "Invalid-Save-Observations",
			},
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local shouldContinue2, observations = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Action = "Invalid-" .. ActionMap.SaveObservations .. "-Notice",
			Error = "Invalid-" .. ActionMap.SaveObservations,
			Data = json.encode(error),
		})
	end, epochs.saveObservations, msg.From, reportTxId, failedGateways, msg.Timestamp)
	if not shouldContinue2 then
		return
	end

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

	LastKnownCirculatingSupply = circulatingSupply
	LastKnownLockedSupply = lockedSupply
	LastKnownStakedSupply = stakedSupply
	LastKnownDelegatedSupply = delegatedSupply
	LastKnownWithdrawSupply = withdrawSupply

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

addEventingHandler(ActionMap.State, Handlers.utils.hasMatchingTag("Action", ActionMap.State), function(msg)
	ao.send({
		Target = msg.From,
		Action = "State-Notice",
		Data = json.encode({
			Name = Name,
			Ticker = Ticker,
			Denomination = Denomination,
			Balances = json.encode(Balances),
			GatewayRegistry = json.encode(GatewayRegistry),
			NameRegistry = json.encode(NameRegistry),
			Epochs = json.encode(Epochs),
			Vaults = json.encode(Vaults),
			DemandFactor = json.encode(DemandFactor),
		}),
	})
end)

addEventingHandler(ActionMap.Gateways, Handlers.utils.hasMatchingTag("Action", ActionMap.Gateways), function(msg)
	local gateways = gar.getGateways()
	ao.send({
		Target = msg.From,
		Action = "Gateways-Notice",
		Data = json.encode(gateways),
	})
end)

addEventingHandler(ActionMap.Gateway, Handlers.utils.hasMatchingTag("Action", ActionMap.Gateway), function(msg)
	local gateway = gar.getGateway(msg.Tags.Address or msg.From)
	ao.send({
		Target = msg.From,
		Action = "Gateway-Notice",
		Gateway = msg.Tags.Address or msg.From,
		Data = json.encode(gateway),
	})
end)

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
	-- wrap in a protected call, and return the result or error accoringly to sender
	local status, result = pcall(demand.getDemandFactor)
	if status then
		ao.send({ Target = msg.From, Action = "Demand-Factor-Notice", Data = json.encode(result) })
	else
		ao.send({
			Target = msg.From,
			Action = "Invalid-Demand-Factor-Notice",
			Error = "Invalid-Demand-Factor",
			Data = json.encode(result),
		})
	end
end)

addEventingHandler(ActionMap.DemandFactorInfo, utils.hasMatchingTag("Action", ActionMap.DemandFactorInfo), function(msg)
	local status, result = pcall(demand.getDemandFactorInfo)
	if status then
		ao.send({ Target = msg.From, Action = "Demand-Factor-Info-Notice", Data = json.encode(result) })
	else
		ao.send({
			Target = msg.From,
			Action = "Invalid-Demand-Factor-Info-Notice",
			Error = "Invalid-Demand-Info-Factor",
			Data = json.encode(result),
		})
	end
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

addEventingHandler(ActionMap.Records, utils.hasMatchingTag("Action", ActionMap.Records), function(msg)
	local records = arns.getRecords()

	-- Credit-Notice message template, that is sent to the Recipient of the transfer
	local recordsNotice = {
		Target = msg.From,
		Action = "Records-Notice",
		Data = json.encode(records),
	}

	-- Add forwarded tags to the records notice messages
	for tagName, tagValue in pairs(msg) do
		-- Tags beginning with "X-" are forwarded
		if string.sub(tagName, 1, 2) == "X-" then
			recordsNotice[tagName] = tagValue
		end
	end

	-- Send Records-Notice
	ao.send(recordsNotice)
end)

addEventingHandler(ActionMap.Epoch, utils.hasMatchingTag("Action", ActionMap.Epoch), function(msg)
	-- check if the epoch number is provided, if not get the epoch number from the timestamp
	local checkAssertions = function()
		assert(msg.Tags["Epoch-Index"] or msg.Tags.Timestamp or msg.Timestamp, "Epoch index or timestamp is required")
	end

	local inputStatus, inputResult = pcall(checkAssertions)

	if not inputStatus then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Epoch-Notice", Error = "Bad-Input" },
			Data = tostring(inputResult),
		})
		return
	end

	local epochIndex = tonumber(msg.Tags["Epoch-Index"])
		or epochs.getEpochIndexForTimestamp(tonumber(msg.Tags.Timestamp or msg.Timestamp))
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
		local checkAssertions = function()
			assert(
				msg.Tags["Epoch-Index"] or msg.Timestamp or msg.Tags.Timestamp,
				"Epoch index or timestamp is required"
			)
		end

		local inputStatus, inputResult = pcall(checkAssertions)

		if not inputStatus then
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Prescribed-Observers-Notice", Error = "Bad-Input" },
				Data = tostring(inputResult),
			})
			return
		end

		local epochIndex = tonumber(msg.Tags["Epoch-Index"])
			or epochs.getEpochIndexForTimestamp(tonumber(msg.Timestamp))
		local prescribedObservers = epochs.getPrescribedObserversForEpoch(epochIndex)
		ao.send({ Target = msg.From, Action = "Prescribed-Observers-Notice", Data = json.encode(prescribedObservers) })
	end
)

addEventingHandler(ActionMap.Observations, utils.hasMatchingTag("Action", ActionMap.Observations), function(msg)
	-- check if the epoch number is provided, if not get the epoch number from the timestamp
	local checkAssertions = function()
		assert(msg.Tags["Epoch-Index"] or msg.Timestamp or msg.Tags.Timestamp, "Epoch index or timestamp is required")
	end

	local inputStatus, inputResult = pcall(checkAssertions)

	if not inputStatus then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Observations-Notice", Error = "Bad-Input" },
			Data = tostring(inputResult),
		})
		return
	end

	local epochIndex = tonumber(msg.Tags["Epoch-Index"])
		or epochs.getEpochIndexForTimestamp(tonumber(msg.Timestamp or msg.Tags.Timestamp))
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
	local checkAssertions = function()
		assert(msg.Tags["Epoch-Index"] or msg.Tags.Timestamp or msg.Timestamp, "Epoch index or timestamp is required")
	end

	local inputStatus, inputResult = pcall(checkAssertions)

	if not inputStatus then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Prescribed-Names-Notice", Error = "Bad-Input" },
			Data = tostring(inputResult),
		})
		return
	end

	local epochIndex = tonumber(msg.Tags["Epoch-Index"])
		or epochs.getEpochIndexForTimestamp(tonumber(msg.Timestamp or msg.Tags.Timestamp))
	local prescribedNames = epochs.getPrescribedNamesForEpoch(epochIndex)
	ao.send({ Target = msg.From, Action = "Prescribed-Names-Notice", Data = json.encode(prescribedNames) })
end)

addEventingHandler(ActionMap.Distributions, utils.hasMatchingTag("Action", ActionMap.Distributions), function(msg)
	-- check if the epoch number is provided, if not get the epoch number from the timestamp
	local checkAssertions = function()
		assert(msg.Tags["Epoch-Index"] or msg.Timestamp or msg.Tags.Timestamp, "Epoch index or timestamp is required")
	end

	local inputStatus, inputResult = pcall(checkAssertions)

	if not inputStatus then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Distributions-Notice", Error = "Bad-Input" },
			Data = tostring(inputResult),
		})
		return
	end

	local epochIndex = tonumber(msg.Tags["Epoch-Index"])
		or epochs.getEpochIndexForTimestamp(tonumber(msg.Timestamp or msg.Tags.Timestamp))
	local distributions = epochs.getDistributionsForEpoch(epochIndex)
	ao.send({ Target = msg.From, Action = "Distributions-Notice", Data = json.encode(distributions) })
end)

addEventingHandler(ActionMap.ReservedNames, utils.hasMatchingTag("Action", ActionMap.ReservedNames), function(msg)
	local reservedNames = arns.getReservedNames()
	ao.send({ Target = msg.From, Action = "Reserved-Names-Notice", Data = json.encode(reservedNames) })
end)

addEventingHandler(ActionMap.ReservedName, utils.hasMatchingTag("Action", ActionMap.ReservedName), function(msg)
	local reservedName = arns.getReservedName(msg.Tags.Name)
	ao.send({
		Target = msg.From,
		Action = "Reserved-Name-Notice",
		ReservedName = msg.Tags.Name,
		Data = json.encode(reservedName),
	})
end)

addEventingHandler(ActionMap.Vaults, utils.hasMatchingTag("Action", ActionMap.Vaults), function(msg)
	ao.send({ Target = msg.From, Action = "Vaults-Notice", Data = json.encode(Vaults) })
end)

addEventingHandler(ActionMap.Vault, utils.hasMatchingTag("Action", ActionMap.Vault), function(msg)
	local address = msg.Tags.Address or msg.From
	local vaultId = msg.Tags["Vault-Id"]
	local vault = vaults.getVault(address, vaultId)
	if not vault then
		ao.send({
			Target = msg.From,
			Action = "Invalid-Vault-Notice",
			Error = "Vault-Not-Found",
			Tags = {
				Address = address,
				["Vault-Id"] = vaultId,
			},
		})
		return
	else
		ao.send({
			Target = msg.From,
			Action = "Vault-Notice",
			Address = address,
			["Vault-Id"] = vaultId,
			Data = json.encode(vault),
		})
	end
end)

-- Pagination handlers

addEventingHandler("paginatedRecords", utils.hasMatchingTag("Action", "Paginated-Records"), function(msg)
	local page = utils.parsePaginationTags(msg)
	local status, result =
		pcall(arns.getPaginatedRecords, page.cursor, page.limit, page.sortBy or "startTimestamp", page.sortOrder)
	if not status then
		ao.send({
			Target = msg.From,
			Action = "Invalid-Records-Notice",
			Error = "Pagination-Error",
			Data = json.encode(result),
		})
	else
		ao.send({ Target = msg.From, Action = "Records-Notice", Data = json.encode(result) })
	end
end)

addEventingHandler("paginatedGateways", utils.hasMatchingTag("Action", "Paginated-Gateways"), function(msg)
	local page = utils.parsePaginationTags(msg)
	local status, result = pcall(
		gar.getPaginatedGateways,
		page.cursor,
		page.limit,
		page.sortBy or "startTimestamp",
		page.sortOrder or "desc"
	)
	if not status then
		ao.send({
			Target = msg.From,
			Action = "Invalid-Gateways-Notice",
			Error = "Pagination-Error",
			Data = json.encode(result),
		})
	else
		ao.send({ Target = msg.From, Action = "Gateways-Notice", Data = json.encode(result) })
	end
end)

addEventingHandler("paginatedBalances", utils.hasMatchingTag("Action", "Paginated-Balances"), function(msg)
	local page = utils.parsePaginationTags(msg)
	local status, result =
		pcall(balances.getPaginatedBalances, page.cursor, page.limit, page.sortBy or "balance", page.sortOrder)
	if not status then
		ao.send({
			Target = msg.From,
			Action = "Invalid-Balances-Notice",
			Error = "Pagination-Error",
			Data = json.encode(result),
		})
	else
		ao.send({ Target = msg.From, Action = "Balances-Notice", Data = json.encode(result) })
	end
end)

addEventingHandler("paginatedVaults", utils.hasMatchingTag("Action", "Paginated-Vaults"), function(msg)
	local page = utils.parsePaginationTags(msg)
	local status, result = pcall(vaults.getPaginatedVaults, page.cursor, page.limit, page.sortOrder, page.sortBy)

	if not status then
		ao.send({
			Target = msg.From,
			Action = "Invalid-Vaults-Notice",
			Error = "Pagination-Error",
			Data = json.encode(result),
		})
	else
		ao.send({ Target = msg.From, Action = "Vaults-Notice", Data = json.encode(result) })
	end
end)

addEventingHandler("paginatedDelegates", utils.hasMatchingTag("Action", "Paginated-Delegates"), function(msg)
	local page = utils.parsePaginationTags(msg)
	local shouldContinue, result = eventingPcall(
		msg.ioEvent,
		function(error)
			ao.send({
				Target = msg.From,
				Action = "Invalid-Delegates-Notice",
				Error = "Pagination-Error",
				Data = json.encode(error),
			})
		end,
		gar.getPaginatedDelegates,
		msg.Tags.Address or msg.From,
		page.cursor,
		page.limit,
		page.sortBy or "startTimestamp",
		page.sortOrder
	)
	if not shouldContinue then
		return
	end
	ao.send({ Target = msg.From, Action = "Delegates-Notice", Data = json.encode(result) })
end)

addEventingHandler(
	"paginatedAllowedDelegates",
	utils.hasMatchingTag("Action", "Paginated-Allowed-Delegates"),
	function(msg)
		local page = utils.parsePaginationTags(msg)
		local shouldContinue, result = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Action = "Invalid-Allowed-Delegates-Notice",
				Error = "Pagination-Error",
				Data = json.encode(error),
			})
		end, gar.getPaginatedAllowedDelegates, msg.Tags.Address or msg.From, page.cursor, page.limit, page.sortOrder)
		if not shouldContinue then
			return
		end
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

	local checkAssertions = function()
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
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Action = "Invalid-" .. ActionMap.ReleaseName .. "-Notice",
			Error = "Bad-Input",
			Data = tostring(error),
		})
		return
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	-- Removes the record and primary names, then create the auction
	---@param releasedName string
	---@param releaseTimestamp number
	---@param releasedInitiator string
	local removeRecordsAndCreateAuction = function(releasedName, releaseTimestamp, releasedInitiator)
		local removedRecord = arns.removeRecord(releasedName)
		local removedPrimaryNamesAndOwners = primaryNames.removePrimaryNamesForBaseName(releasedName) -- NOTE: this should be empty if there are no primary names allowed before release
		local auction = arns.createAuction(releasedName, releaseTimestamp, releasedInitiator)
		return {
			removedRecord = removedRecord,
			removedPrimaryNamesAndOwners = removedPrimaryNamesAndOwners,
			auction = auction,
		}
	end

	-- we should be able to create the auction here
	local status, createAuctionDataOrError = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Action = "Invalid-" .. ActionMap.ReleaseName .. "-Notice",
			Error = "Auction-Creation-Error",
			Data = tostring(error),
		})
	end, removeRecordsAndCreateAuction, name, timestamp, initiator)

	if not status or not createAuctionDataOrError then
		ao.send({
			Target = msg.From,
			Action = "Invalid-" .. ActionMap.ReleaseName .. "-Notice",
			Error = "Auction-Creation-Error",
			Data = tostring(createAuctionDataOrError),
		})
		return
	end

	-- add the auction result fields
	addAuctionResultFields(msg.ioEvent, {
		name = name,
		auction = createAuctionDataOrError.auction,
		removedRecord = createAuctionDataOrError.removedRecord,
		removedPrimaryNamesAndOwners = createAuctionDataOrError.removedPrimaryNamesAndOwners,
	})

	-- note: no change to token supply here - only on auction bids
	msg.ioEvent:addField("Auctions-Count", utils.lengthOfTable(NameRegistry.auctions))
	msg.ioEvent:addField("Records-Count", utils.lengthOfTable(NameRegistry.records))

	local auction = {
		name = name,
		startTimestamp = createAuctionDataOrError.auction.startTimestamp,
		endTimestamp = createAuctionDataOrError.auction.endTimestamp,
		initiator = createAuctionDataOrError.auction.initiator,
		baseFee = createAuctionDataOrError.auction.baseFee,
		demandFactor = createAuctionDataOrError.auction.demandFactor,
		settings = createAuctionDataOrError.auction.settings,
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

-- hadnler to get auction for a name
addEventingHandler("auctionInfo", utils.hasMatchingTag("Action", ActionMap.AuctionInfo), function(msg)
	local name = string.lower(msg.Tags.Name)
	local auction = arns.getAuction(name)
	if not auction then
		ao.send({
			Target = msg.From,
			Action = "Invalid-" .. ActionMap.AuctionInfo .. "-Notice",
			Error = "Auction-Not-Found",
		})
		return
	end

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

	if not auction then
		ao.send({
			Target = msg.From,
			Action = "Invalid-" .. ActionMap.AuctionPrices .. "-Notice",
			Error = "Auction-Not-Found",
		})
		return
	end

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
	local name = string.lower(msg.Tags.Name)
	local bidAmount = msg.Tags.Quantity and tonumber(msg.Tags.Quantity) or nil -- if nil, we use the current bid price
	local bidder = utils.formatAddress(msg.From)
	local processId = utils.formatAddress(msg.Tags["Process-Id"])
	local timestamp = tonumber(msg.Timestamp)
	local type = msg.Tags["Purchase-Type"] or "permabuy"
	local years = msg.Tags.Years and tonumber(msg.Tags.Years) or nil

	-- assert name, bidder, processId are provided
	local checkAssertions = function()
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
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.AuctionBid .. "-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local shouldContinue2, result = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.AuctionBid .. "-Notice", Error = "Auction-Bid-Error" },
			Data = tostring(error),
		})
	end, arns.submitAuctionBid, name, bidAmount, bidder, timestamp, processId, type, years)
	if not shouldContinue2 then
		return
	end

	if result ~= nil then
		local record = result.record
		addAuctionResultFields(msg.ioEvent, result)
		LastKnownCirculatingSupply = LastKnownCirculatingSupply - record.purchasePrice
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
	local function checkAssertions()
		assert(
			#(msg.Tags["Allowed-Delegates"] or ""),
			"Allowed-Delegates, a comma-separated list string of delegate addresses, is required"
		)
	end
	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.AllowDelegates .. "-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local newAllowedDelegates = utils.splitAndTrimString(msg.Tags["Allowed-Delegates"])
	msg.ioEvent:addField("Input-New-Delegates-Count", utils.lengthOfTable(newAllowedDelegates))

	local shouldContinue2, result = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.AllowDelegates .. "-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, gar.allowDelegates, newAllowedDelegates, msg.From)
	if not shouldContinue2 then
		return
	end

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
	local function checkAssertions()
		assert(
			#(msg.Tags["Disallowed-Delegates"] or ""),
			"Disallowed-Delegates, a comma-separated list string of delegate addresses, is required"
		)
	end
	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.DisallowDelegates .. "-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local disallowedDelegates = utils.splitAndTrimString(msg.Tags["Disallowed-Delegates"])
	msg.ioEvent:addField("Input-Disallowed-Delegates-Count", utils.lengthOfTable(disallowedDelegates))

	local shouldContinue2, result = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.DisallowDelegates .. "-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, gar.disallowDelegates, disallowedDelegates, msg.From)
	if not shouldContinue2 then
		return
	end

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
	local function checkAssertions()
		assert(utils.isValidAOAddress(address), "Invalid address.")
	end
	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.Delegations .. "-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local shouldContinue2, result = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.Delegations .. "-Notice", Error = "Pagination-Error" },
			Data = tostring(error),
		})
	end, gar.getPaginatedDelegations, address, page.cursor, page.limit, page.sortBy, page.sortOrder)
	if not shouldContinue2 then
		return
	end

	ao.send({
		Target = msg.From,
		Tags = { Action = ActionMap.Delegations .. "-Notice" },
		Data = json.encode(result),
	})
end)

--- PRIMARY NAMES
addEventingHandler("removePrimaryName", utils.hasMatchingTag("Action", ActionMap.RemovePrimaryNames), function(msg)
	local names = msg.Tags.Names and utils.splitAndTrimString(msg.Tags.Names, ",") or nil
	local from = utils.formatAddress(msg.From)
	-- TODO: names must be provided
	local shouldContinue, removedPrimaryNamesAndOwners = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.RemovePrimaryNames .. "-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, primaryNames.removePrimaryNames, names, from)
	if not shouldContinue or not removedPrimaryNamesAndOwners then
		return
	end

	ao.send({
		Target = msg.From,
		Action = ActionMap.RemovePrimaryNames .. "-Notice",
		Data = json.encode(removedPrimaryNamesAndOwners),
	})

	-- send messages to the previous owners of the primary names
	for _, removedPrimaryNameAndOwner in pairs(removedPrimaryNamesAndOwners) do
		ao.send({
			Target = removedPrimaryNameAndOwner.owner,
			Action = ActionMap.RemovePrimaryNames .. "-Notice",
			Tags = { Name = removedPrimaryNameAndOwner.name },
			Data = json.encode(removedPrimaryNameAndOwner),
		})
	end
end)

addEventingHandler(
	"createPrimaryNameClaim",
	utils.hasMatchingTag("Action", ActionMap.CreatePrimaryNameClaim),
	function(msg)
		local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
		local recipient = utils.formatAddress(msg.Recipient) -- the recipient of the primary name
		local from = utils.formatAddress(msg.From) -- the process that is creating the claim
		local timestamp = tonumber(msg.Timestamp)

		local shouldContinue, primaryNameClaim = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = from,
				Tags = { Action = "Invalid-" .. ActionMap.CreatePrimaryNameClaim .. "-Notice", Error = "Bad-Input" },
				Data = tostring(error),
			})
		end, primaryNames.createNameClaim, name, recipient, from, timestamp)
		if not shouldContinue or not primaryNameClaim then
			return
		end

		ao.send({
			Target = from,
			Action = ActionMap.CreatePrimaryNameClaim .. "-Notice",
			Data = json.encode(primaryNameClaim),
		})
		ao.send({
			Target = recipient,
			Action = ActionMap.CreatePrimaryNameClaim .. "-Notice",
			Data = json.encode(primaryNameClaim),
		})
	end
)

addEventingHandler("claimPrimaryName", utils.hasMatchingTag("Action", ActionMap.ClaimPrimaryName), function(msg)
	local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
	local from = utils.formatAddress(msg.From) -- the recipient of the primary name
	local timestamp = tonumber(msg.Timestamp)
	local shouldContinue, claimPrimaryNameResult = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.ClaimPrimaryName .. "-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, primaryNames.claimPrimaryName, name, from, timestamp)
	if not shouldContinue or not claimPrimaryNameResult then
		return
	end

	-- send two notices, one to the owner and one to the initiator
	ao.send({
		Target = claimPrimaryNameResult.claim.initiator,
		Action = ActionMap.ClaimPrimaryName .. "-Notice",
		Data = json.encode(claimPrimaryNameResult),
	})
	ao.send({
		Target = claimPrimaryNameResult.primaryName.owner,
		Action = ActionMap.ClaimPrimaryName .. "-Notice",
		Data = json.encode(claimPrimaryNameResult),
	})
end)

-- revoke all claims for a given initiator
addEventingHandler("revokeClaims", utils.hasMatchingTag("Action", ActionMap.RevokeClaims), function(msg)
	local initiator = utils.formatAddress(msg.From)
	local names = msg.Tags["Names"] and utils.splitAndTrimString(msg.Tags["Names"], ",") or nil
	local shouldContinue, revokedClaimsArray = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-" .. ActionMap.RevokeClaims .. "-Notice",
				Error = "Bad-Input",
			},
			Data = tostring(error),
		})
	end, primaryNames.revokeClaimsForInitiator, initiator, names)
	if not shouldContinue or not revokedClaimsArray then
		return
	end

	ao.send({
		Target = initiator,
		Action = ActionMap.RevokeClaims .. "-Notice",
		Data = json.encode(revokedClaimsArray),
	})

	-- TODO: send messages to the recipients of the claims? we could index on unique recipients and send one per recipient to avoid multiple messages
	for _, revokedClaim in ipairs(revokedClaimsArray) do
		ao.send({
			Target = revokedClaim.recipient,
			Action = ActionMap.RevokeClaims .. "-Notice",
			Data = json.encode(revokedClaim),
		})
	end
end)

--- Handles forward and reverse resolutions (e.g. name -> address and address -> name)
addEventingHandler("getPrimaryNameData", utils.hasMatchingTag("Action", ActionMap.PrimaryName), function(msg)
	local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
	local address = msg.Tags.Address and utils.formatAddress(msg.Tags.Address) or utils.formatAddress(msg.From)
	local primaryNameData = name and primaryNames.getPrimaryNameDataWithOwnerFromName(name)
		or address and primaryNames.getPrimaryNameDataWithOwnerFromAddress(address)
	if not primaryNameData then
		return ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.PrimaryName .. "-Notice", Error = "Primary-Name-Not-Found" },
		})
	end
	return ao.send({
		Target = msg.From,
		Action = ActionMap.PrimaryName .. "-Notice",
		Tags = { Owner = primaryNameData.owner, Name = primaryNameData.name },
		Data = json.encode(primaryNameData),
	})
end)

addEventingHandler("getPaginatedPrimaryNames", utils.hasMatchingTag("Action", ActionMap.PrimaryNames), function(msg)
	local page = utils.parsePaginationTags(msg)
	local status, result = pcall(
		primaryNames.getPaginatedPrimaryNames,
		page.cursor,
		page.limit,
		page.sortBy or "name",
		page.sortOrder or "asc"
	)

	if not status or not result then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-" .. ActionMap.PrimaryNames .. "-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
		return
	end

	return ao.send({
		Target = msg.From,
		Action = ActionMap.PrimaryNames .. "-Notice",
		Data = json.encode(result),
	})
end)

return process
