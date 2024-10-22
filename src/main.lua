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
local tick = require("tick")

local ActionMap = {
	-- reads
	Info = "Info",
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
	BuyRecord = "Buy-Record",
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
	CancelDelegateWithdrawal = "Cancel-Delegate-Withdrawal",
	InstantDelegateWithdrawal = "Instant-Delegate-Withdrawal",
}

-- Low fidelity trackers
local lastKnownCirculatingSupply = lastKnownCirculatingSupply or 0
local lastKnownLockedSupply = lastKnownLockedSupply or 0
local lastKnownStakedSupply = lastKnownStakedSupply or 0
local lastKnownDelegatedSupply = lastKnownDelegatedSupply or 0
local lastKnownWithdrawSupply = lastKnownWithdrawSupply or 0
local function lastKnownTotalTokenSupply()
	return lastKnownCirculatingSupply
		+ lastKnownLockedSupply
		+ lastKnownStakedSupply
		+ lastKnownDelegatedSupply
		+ lastKnownWithdrawSupply
		+ Balances[Protocol]
end

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
end

local function addSupplyData(ioEvent, supplyData)
	supplyData = supplyData or {}
	ioEvent:addField("Circulating-Supply", supplyData.circulatingSupply or lastKnownCirculatingSupply)
	ioEvent:addField("Locked-Supply", supplyData.lockedSupply or lastKnownLockedSupply)
	ioEvent:addField("Staked-Supply", supplyData.stakedSupply or lastKnownStakedSupply)
	ioEvent:addField("Delegated-Supply", supplyData.delegatedSupply or lastKnownDelegatedSupply)
	ioEvent:addField("Withdraw-Supply", supplyData.withdrawSupply or lastKnownWithdrawSupply)
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
		lastKnownCirculatingSupply = lastKnownCirculatingSupply,
		lastKnownLockedSupply = lastKnownLockedSupply,
		lastKnownStakedSupply = lastKnownStakedSupply,
		lastKnownDelegatedSupply = lastKnownDelegatedSupply,
		lastKnownWithdrawSupply = lastKnownWithdrawSupply,
		lastKnownTotalSupply = lastKnownTotalTokenSupply(),
	}
	local status, resultOrError = pcall(tick.pruneState, msgTimestamp, msgId)
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
		msg.ioEvent:addField("TickError", tostring(resultOrError))
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
		local prunedVaultsCount = utils.lengthOfTable(resultOrError.prunedVaults or {})
		if prunedVaultsCount > 0 then
			msg.ioEvent:addField("Pruned-Vaults", resultOrError.prunedVaults)
			msg.ioEvent:addField("Pruned-Vaults-Count", prunedVaultsCount)
			for _, vault in pairs(resultOrError.prunedVaults) do
				lastKnownLockedSupply = lastKnownLockedSupply - vault.balance
				lastKnownCirculatingSupply = lastKnownCirculatingSupply + vault.balance
			end
		end
		local prunedEpochsCount = utils.lengthOfTable(resultOrError.prunedEpochs or {})
		if prunedEpochsCount > 0 then
			msg.ioEvent:addField("Pruned-Epochs", resultOrError.prunedEpochs)
			msg.ioEvent:addField("Pruned-Epochs-Count", prunedEpochsCount)
		end

		local pruneGatewayResults = resultOrError.pruneGatewayResults or {}
		lastKnownCirculatingSupply = lastKnownCirculatingSupply
			+ (pruneGatewayResults.delegateStakeReturned or 0)
			+ (pruneGatewayResults.gatewayStakeReturned or 0)
		lastKnownStakedSupply = lastKnownStakedSupply - (pruneGatewayResults.stakeSlashed or 0)

		local prunedGateways = pruneGatewayResults.prunedGateways or {}
		local prunedGatewaysCount = utils.lengthOfTable(prunedGateways)
		if prunedGatewaysCount > 0 then
			msg.ioEvent:addField("Pruned-Gateways", prunedGateways)
			msg.ioEvent:addField("Pruned-Gateways-Count", prunedGatewaysCount)
			local gwStats = gatewayStats()
			msg.ioEvent:addField("Joined-Gateways-Count", gwStats.joined)
			msg.ioEvent:addField("Leaving-Gateways-Count", gwStats.leaving)
		end

		local slashedGateways = pruneGatewayResults.slashedGateways or {}
		local slashedGatewaysCount = utils.lengthOfTable(slashedGateways or {})
		if slashedGatewaysCount > 0 then
			msg.ioEvent:addField("Slashed-Gateways", slashedGateways)
			msg.ioEvent:addField("Slashed-Gateways-Count", slashedGatewaysCount)
			local invariantSlashedGateways = {}
			for _, gwAddress in pairs(slashedGateways) do
				local gw = gar.getGateway(gwAddress) or {}
				if gw.totalDelegatedStake > 0 then
					invariantSlashedGateways[gwAddress] = gw.totalDelegatedStake
				end
			end
			if utils.lengthOfTable(invariantSlashedGateways) > 0 then
				msg.ioEvent:addField("Invariant-Slashed-Gateways", invariantSlashedGateways)
			end
		end
	end

	if
		lastKnownCirculatingSupply ~= previousState.lastKnownCirculatingSupply
		or lastKnownLockedSupply ~= previousState.lastKnownLockedSupply
		or lastKnownStakedSupply ~= previousState.lastKnownStakedSupply
		or lastKnownDelegatedSupply ~= previousState.lastKnownDelegatedSupply
		or lastKnownWithdrawSupply ~= previousState.lastKnownWithdrawSupply
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
			Tags = { Action = "Invalid-Transfer-Notice", Error = "Transfer-Error" },
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
			Tags = { Action = "Invalid-Transfer-Notice", Error = "Transfer-Error" },
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
			Tags = { Action = "Invalid-Create-Vault-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local shouldContinue2, vault = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = from,
			Tags = { Action = "Invalid-Create-Vault-Notice", Error = "Invalid-Create-Vault" },
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

	lastKnownLockedSupply = lastKnownLockedSupply + quantity
	lastKnownCirculatingSupply = lastKnownCirculatingSupply - quantity
	addSupplyData(msg.ioEvent)

	ao.send({
		Target = from,
		Tags = {
			Action = "Vault-Created-Notice",
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
			Tags = { Action = "Invalid-Vaulted-Transfer", Error = "Invalid-Vaulted-Transfer" },
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

	lastKnownLockedSupply = lastKnownLockedSupply + quantity
	lastKnownCirculatingSupply = lastKnownCirculatingSupply - quantity
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
		Tags = { Action = "Create-Vault-Notice", ["Vault-Id"] = msgId },
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
			Tags = { Action = "Invalid-Extend-Vault-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local shouldContinue2, vault = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Extend-Vault-Notice", Error = "Invalid-Extend-Vault" },
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
		Tags = { Action = "Vault-Extended-Notice" },
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
			Tags = { Action = "Invalid-Increase-Vault-Notice", Error = "Bad-Input" },
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
			Tags = { Action = "Invalid-Increase-Vault-Notice", Error = "Invalid-Increase-Vault" },
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

	lastKnownLockedSupply = lastKnownLockedSupply + quantity
	lastKnownCirculatingSupply = lastKnownCirculatingSupply - quantity
	addSupplyData(msg.ioEvent)

	ao.send({
		Target = msg.From,
		Tags = { Action = "Vault-Increased-Notice" },
		Data = json.encode(vault),
	})
end)

addEventingHandler(ActionMap.BuyRecord, utils.hasMatchingTag("Action", ActionMap.BuyRecord), function(msg)
	local checkAssertions = function()
		assert(type(msg.Tags.Name) == "string", "Invalid name")
		assert(type(msg.Tags["Purchase-Type"]) == "string", "Invalid purchase type")
		assert(utils.isValidArweaveAddress(msg.Tags["Process-Id"]), "Invalid process id")
		if msg.Tags.Years then
			assert(
				tonumber(msg.Tags.Years) >= 1
					and tonumber(msg.Tags.Years) <= 5
					and utils.isInteger(tonumber(msg.Tags.Years)),
				"Invalid years. Must be integer between 1 and 5"
			)
		end
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Buy-Record-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	msg.ioEvent:addField("nameLength", #msg.Tags.Name)

	local shouldContinue2, result = eventingPcall(
		msg.ioEvent,
		function(error)
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-Buy-Record-Notice",
					Error = "Invalid-Buy-Record",
				},
				Data = tostring(error),
			})
		end,
		arns.buyRecord,
		string.lower(msg.Tags.Name),
		msg.Tags["Purchase-Type"],
		tonumber(msg.Tags.Years),
		msg.From,
		msg.Timestamp,
		msg.Tags["Process-Id"]
	)
	if not shouldContinue2 then
		return
	end

	local record = {}
	if result ~= nil then
		record = result.record
		addRecordResultFields(msg.ioEvent, result)
		lastKnownCirculatingSupply = lastKnownCirculatingSupply - record.purchasePrice
		addSupplyData(msg.ioEvent)
	end

	msg.ioEvent:addField("Records-Count", utils.lengthOfTable(NameRegistry.records))

	ao.send({
		Target = msg.From,
		Tags = { Action = "Buy-Record-Notice", Name = msg.Tags.Name },
		Data = json.encode(record),
	})
end)

addEventingHandler(ActionMap.ExtendLease, utils.hasMatchingTag("Action", ActionMap.ExtendLease), function(msg)
	local checkAssertions = function()
		assert(type(msg.Tags.Name) == "string", "Invalid name")
		assert(
			tonumber(msg.Tags.Years) > 0 and tonumber(msg.Tags.Years) < 5 and utils.isInteger(tonumber(msg.Tags.Years)),
			"Invalid years. Must be integer between 1 and 5"
		)
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Extend-Lease-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local shouldContinue2, result = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Extend-Lease-Notice", Error = "Invalid-Extend-Lease" },
			Data = tostring(error),
		})
	end, arns.extendLease, msg.From, string.lower(msg.Tags.Name), tonumber(msg.Tags.Years), msg.Timestamp)
	if not shouldContinue2 then
		return
	end

	local recordResult = {}
	if result ~= nil then
		recordResult = result.record
		addRecordResultFields(msg.ioEvent, result)
		msg.ioEvent:addField("totalExtensionFee", recordResult.totalExtensionFee)
		lastKnownCirculatingSupply = lastKnownCirculatingSupply - recordResult.totalExtensionFee
		addSupplyData(msg.ioEvent)
	end

	ao.send({
		Target = msg.From,
		Tags = { Action = "Extend-Lease-Notice", Name = string.lower(msg.Tags.Name) },
		Data = json.encode(recordResult),
	})
end)

addEventingHandler(
	ActionMap.IncreaseUndernameLimit,
	utils.hasMatchingTag("Action", ActionMap.IncreaseUndernameLimit),
	function(msg)
		local checkAssertions = function()
			assert(type(msg.Tags.Name) == "string", "Invalid name")
			assert(
				tonumber(msg.Tags.Quantity) > 0
					and tonumber(msg.Tags.Quantity) < 9990
					and utils.isInteger(msg.Tags.Quantity),
				"Invalid quantity. Must be an integer value greater than 0 and less than 9990"
			)
		end

		local shouldContinue = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Increase-Undername-Limit-Notice", Error = "Bad-Input" },
				Data = tostring(error),
			})
		end, checkAssertions)
		if not shouldContinue then
			return
		end

		local shouldContinue2, result = eventingPcall(
			ioEvent,
			function(error)
				ao.send({
					Target = msg.From,
					Tags = { Action = "Invalid-Increase-Undername-Limit-Notice", Error = "Invalid-Undername-Increase" },
					Data = tostring(error),
				})
			end,
			arns.increaseundernameLimit,
			msg.From,
			string.lower(msg.Tags.Name),
			tonumber(msg.Tags.Quantity),
			msg.Timestamp
		)
		if not shouldContinue2 then
			return
		end

		local recordResult = {}
		if result ~= nil then
			recordResult = result.record
			addRecordResultFields(msg.ioEvent, result)
			msg.ioEvent:addField("previousUndernameLimit", recordResult.undernameLimit - tonumber(msg.Tags.Quantity))
			msg.ioEvent:addField("additionalUndernameCost", recordResult.additionalUndernameCost)
			lastKnownCirculatingSupply = lastKnownCirculatingSupply - recordResult.additionalUndernameCost
			addSupplyData(msg.ioEvent)
		end

		ao.send({
			Target = msg.From,
			Tags = { Action = "Increase-Undername-Limit-Notice", Name = string.lower(msg.Tags.Name) },
			Data = json.encode(recordResult),
		})
	end
)

addEventingHandler(ActionMap.TokenCost, utils.hasMatchingTag("Action", ActionMap.TokenCost), function(msg)
	local checkAssertions = function()
		assert(
			type(msg.Tags.Intent) == "string",
			-- assert is one of those three interactions
			msg.Tags.Intent == ActionMap.BuyRecord
				or msg.Tags.Intent == ActionMap.ExtendLease
				or msg.Tags.Intent == ActionMap.IncreaseUndernameLimit,
			"Intent must be valid registry interaction (e.g. BuyRecord, ExtendLease, IncreaseUndernameLimit). Provided intent: "
				.. (msg.Tags.Intent or "nil")
		)
		-- if years is provided, assert it is a number and integer between 1 and 5
		if msg.Tags.Years then
			assert(utils.isInteger(tonumber(msg.Tags.Years)), "Invalid years. Must be integer between 1 and 5")
		end

		-- if quantity provided must be a number and integer greater than 0
		if msg.Tags.Quantity then
			assert(utils.isInteger(tonumber(msg.Tags.Quantity)), "Invalid quantity. Must be integer greater than 0")
		end
	end

	local inputStatus, inputResult = pcall(checkAssertions)

	if not inputStatus then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Token-Cost-Notice", Error = "Bad-Input" },
			Data = tostring(inputResult),
		})
		return
	end

	local status, result = pcall(arns.getTokenCost, {
		intent = msg.Tags.Intent,
		name = string.lower(msg.Tags.Name),
		years = tonumber(msg.Tags.Years) or 1,
		quantity = tonumber(msg.Tags.Quantity),
		purchaseType = msg.Tags["Purchase-Type"] or "lease",
		currentTimestamp = tonumber(msg.Timestamp) or tonumber(msg.Tags.Timestamp),
	})
	if not status then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Token-Cost-Notice", Error = "Invalid-Token-Cost" },
			Data = tostring(result),
		})
	else
		ao.send({
			Target = msg.From,
			Tags = { Action = "Token-Cost-Notice", ["Token-Cost"] = tostring(result) },
			Data = json.encode(result),
		})
	end
end)

addEventingHandler(
	ActionMap.GetRegistrationFees,
	utils.hasMatchingTag("Action", ActionMap.GetRegistrationFees),
	function(msg)
		local status, priceList = pcall(arns.getRegistrationFees)

		if not status then
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Get-Registration-Fees-Notice", Error = "Invalid-Get-Registration-Fees" },
				Data = tostring(priceList),
			})
		else
			ao.send({
				Target = msg.From,
				Tags = { Action = "Get-Registration-Fees-Notice" },
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
		allowDelegatedStaking = msg.Tags["Allow-Delegated-Staking"] == "true",
		minDelegatedStake = tonumber(msg.Tags["Min-Delegated-Stake"]),
		delegateRewardShareRatio = tonumber(msg.Tags["Delegate-Reward-Share-Ratio"]) or 0,
		properties = msg.Tags.Properties or "FH1aVetOoulPGqgYukj0VE0wIhDy90WiQoV3U2PeY44",
		autoStake = msg.Tags["Auto-Stake"] == "true",
	}

	local updatedServices = utils.safeDecodeJson(msg.Tags.Services)

	if msg.Tags.Services and not updatedServices then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Join-Network-Notice", Error = "Invalid-Join-Network-Input" },
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
			Tags = { Action = "Invalid-Join-Network-Notice", Error = "Invalid-Join-Network" },
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

	lastKnownCirculatingSupply = lastKnownCirculatingSupply - stake
	lastKnownStakedSupply = lastKnownStakedSupply + stake
	addSupplyData(msg.ioEvent)

	ao.send({
		Target = fromAddress,
		Tags = { Action = "Join-Network-Notice" },
		Data = json.encode(gateway),
	})
end)

addEventingHandler(ActionMap.LeaveNetwork, utils.hasMatchingTag("Action", ActionMap.LeaveNetwork), function(msg)
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
			Tags = { Action = "Invalid-Leave-Network-Notice", Error = "Invalid-Leave-Network" },
			Data = tostring(error),
		})
	end, gar.leaveNetwork, msg.From, msg.Timestamp, msg.Id)
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

	lastKnownStakedSupply = lastKnownStakedSupply - gwPrevStake - gwPrevTotalDelegatedStake
	lastKnownWithdrawSupply = lastKnownWithdrawSupply + gwPrevStake + gwPrevTotalDelegatedStake
	addSupplyData(msg.ioEvent)

	ao.send({
		Target = msg.From,
		Tags = { Action = "Leave-Network-Notice" },
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
				Tags = { Action = "Invalid-Increase-Operator-Stake-Notice", Error = "Bad-Input" },
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
				Tags = { Action = "Invalid-Increase-Operator-Stake-Notice", Error = "Invalid-Increase-Operator-Stake" },
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

		lastKnownCirculatingSupply = lastKnownCirculatingSupply - quantity
		lastKnownStakedSupply = lastKnownStakedSupply + quantity
		addSupplyData(msg.ioEvent)

		ao.send({
			Target = msg.From,
			Tags = { Action = "Increase-Operator-Stake-Notice" },
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
				utils.isInteger(tonumber(msg.Tags.Quantity)) and tonumber(msg.Tags.Quantity) > 0,
				"Invalid quantity. Must be integer greater than 0"
			)
		end

		local shouldContinue = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Decrease-Operator-Stake-Notice", Error = "Bad-Input" },
				Data = tostring(error),
			})
		end, checkAssertions)
		if not shouldContinue then
			return
		end

		local quantity = tonumber(msg.Tags.Quantity)
		msg.ioEvent:addField("Sender-Previous-Balance", Balances[msg.From])

		local shouldContinue2, gateway = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Decrease-Operator-Stake-Notice", Error = "Invalid-Stake-Decrease" },
				Data = tostring(error),
			})
		end, gar.decreaseOperatorStake, msg.From, quantity, msg.Timestamp, msg.Id)
		if not shouldContinue2 then
			return
		end

		msg.ioEvent:addField("Sender-New-Balance", Balances[msg.From]) -- should be unchanged
		if gateway ~= nil then
			local previousStake = gateway.operatorStake + quantity
			msg.ioEvent:addField("New-Operator-Stake", gateway.operatorStake)
			msg.ioEvent:addField("Previous-Operator-Stake", previousStake)
			msg.ioEvent:addField("GW-Vaults-Count", utils.lengthOfTable(gateway.vaults or {}))
			local decreaseStakeVault = gateway.vaults[msg.Id]
			if decreaseStakeVault ~= nil then
				previousStake = previousStake + decreaseStakeVault.balance
				msg.ioEvent:addFieldsWithPrefixIfExist(
					decreaseStakeVault,
					"Decrease-Stake-Vault-",
					{ "balance", "startTimestamp", "endTimestamp" }
				)
			end
		end

		lastKnownStakedSupply = lastKnownStakedSupply - quantity
		lastKnownWithdrawSupply = lastKnownWithdrawSupply + quantity
		addSupplyData(msg.ioEvent)

		ao.send({
			Target = msg.From,
			Tags = { Action = "Decrease-Operator-Stake-Notice" },
			Data = json.encode(gateway),
		})
	end
)

addEventingHandler(ActionMap.DelegateStake, utils.hasMatchingTag("Action", ActionMap.DelegateStake), function(msg)
	local checkAssertions = function()
		assert(utils.isValidAOAddress(msg.Tags.Target or msg.Tags.Address), "Invalid target address")
		assert(
			tonumber(msg.Tags.Quantity) > 0 and utils.isInteger(tonumber(msg.Tags.Quantity)),
			"Invalid quantity. Must be integer greater than 0"
		)
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Delegate-Stake-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local target = utils.formatAddress(msg.Tags.Target or msg.Tags.Address)
	local from = utils.formatAddress(msg.From)
	local quantity = tonumber(msg.Tags.Quantity)
	msg.ioEvent:addField("TargetFormatted", target)

	local shouldContinue2, gateway = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = from,
			Tags = { Action = "Invalid-Delegate-Stake-Notice", Error = tostring(error) },
			Data = tostring(error),
		})
	end, gar.delegateStake, from, target, quantity, tonumber(msg.Timestamp))
	if not shouldContinue2 then
		return
	end

	local delegateResult = {}
	if gateway ~= nil then
		local newStake = gateway.delegates[from].delegatedStake
		msg.ioEvent:addField("PreviousStake", newStake - quantity)
		msg.ioEvent:addField("NewStake", newStake)
		msg.ioEvent:addField("GatewayTotalDelegatedStake", gateway.totalDelegatedStake)
		delegateResult = gateway.delegates[from]
	end

	lastKnownCirculatingSupply = lastKnownCirculatingSupply - quantity
	lastKnownStakedSupply = lastKnownStakedSupply + quantity
	addSupplyData(msg.ioEvent)

	ao.send({
		Target = msg.From,
		Tags = { Action = "Delegate-Stake-Notice", Gateway = msg.Tags.Target },
		Data = json.encode(delegateResult),
	})
end)

addEventingHandler(
	ActionMap.CancelDelegateWithdrawal,
	utils.hasMatchingTag("Action", ActionMap.CancelDelegateWithdrawal),
	function(msg)
		local checkAssertions = function()
			assert(utils.isValidAOAddress(msg.Tags.Target or msg.Tags.Address), "Invalid gateway address")
			assert(utils.isValidAOAddress(msg.Tags["Vault-Id"]), "Invalid vault id")
		end

		local shouldContinue = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Cancel-Delegate-Withdrawal-Notice", Error = "Bad-Input" },
				Data = tostring(error),
			})
		end, checkAssertions)
		if not shouldContinue then
			return
		end

		local gatewayAddress = utils.formatAddress(msg.Tags.Target or msg.Tags.Address)
		local fromAddress = utils.formatAddress(msg.From)
		local vaultId = msg.Tags["Vault-Id"]
		msg.ioEvent:addField("TargetFormatted", gatewayAddress)

		local shouldContinue2, result = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-Cancel-Delegate-Withdrawal-Notice",
					Error = "Invalid-Cancel-Delegate-Withdrawal",
				},
				Data = tostring(error),
			})
		end, gar.cancelDelegateWithdrawal, fromAddress, gatewayAddress, vaultId)
		if not shouldContinue2 then
			return
		end

		local delegateResult = {}
		if result ~= nil then
			if result.delegate ~= nil then
				delegateResult = result.delegate
				local newStake = delegateResult.delegatedStake
				local vaultBalance = delegateResult.vaults[vaultId].balance
				msg.ioEvent:addField("PreviousStake", newStake - vaultBalance)
				msg.ioEvent:addField("NewStake", newStake)
				msg.ioEvent:addField("GatewayTotalDelegatedStake", result.totalDelegatedStake)

				lastKnownStakedSupply = lastKnownStakedSupply + vaultBalance
				lastKnownWithdrawSupply = lastKnownWithdrawSupply - vaultBalance
				addSupplyData(msg.ioEvent)
			end
		end

		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Cancel-Delegate-Withdrawal-Notice",
				Address = gatewayAddress,
				["Vault-Id"] = msg.Tags["Vault-Id"],
			},
			Data = json.encode(delegateResult),
		})
	end
)

addEventingHandler(
	ActionMap.InstantDelegateWithdrawal,
	utils.hasMatchingTag("Action", ActionMap.InstantDelegateWithdrawal),
	function(msg)
		local checkAssertions = function()
			assert(utils.isValidAOAddress(msg.Tags.Target or msg.Tags.Address), "Invalid gateway address")
			assert(utils.isValidAOAddress(msg.Tags["Vault-Id"]), "Invalid vault id")
		end

		local shouldContinue = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Instant-Delegate-Withdrawal-Notice", Error = "Bad-Input" },
				Data = tostring(error),
			})
		end, checkAssertions)
		if not shouldContinue then
			return
		end

		local gatewayAddress = utils.formatAddress(msg.Tags.Target or msg.Tags.Address)
		local fromAddress = utils.formatAddress(msg.From)
		local vaultId = msg.Tags["Vault-Id"]
		msg.ioEvent:addField("TargetFormatted", gatewayAddress)

		local shouldContinue2, result = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = msg.From,
				Tags = {
					Action = "Invalid-Instant-Delegate-Withdrawal-Notice",
					Error = "Invalid-Instant-Delegate-Withdrawal",
				},
				Data = tostring(error),
			})
		end, gar.instantDelegateWithdrawal, fromAddress, gatewayAddress, vaultId, msg.Timestamp)
		if not shouldContinue2 then
			return
		end

		local delegateResult = {}
		if result ~= nil then
			if result.delegate ~= nil then
				delegateResult = result.delegate
				local newStake = delegateResult.delegatedStake
				msg.ioEvent:addField("PreviousStake", newStake - delegateResult.vaults[vaultId].balance)
				msg.ioEvent:addField("NewStake", newStake)
				msg.ioEvent:addField("GatewayTotalDelegatedStake", result.totalDelegatedStake)
			end
		end

		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Instant-Delegate-Withdrawal-Notice",
				Address = gatewayAddress,
				["Vault-Id"] = msg.Tags["Vault-Id"],
			},
			Data = json.encode(delegateResult),
		})
	end
)

addEventingHandler(
	ActionMap.DecreaseDelegateStake,
	utils.hasMatchingTag("Action", ActionMap.DecreaseDelegateStake),
	function(msg)
		local checkAssertions = function()
			assert(utils.isValidArweaveAddress(msg.Tags.Target or msg.Tags.Address), "Invalid target address")
			assert(
				tonumber(msg.Tags.Quantity) > 0 and utils.isInteger(tonumber(msg.Tags.Quantity)),
				"Invalid quantity. Must be integer greater than 0"
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

		local shouldContinue2, gateway = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = from,
				Tags = { Action = "Invalid-Decrease-Delegate-Stake-Notice", Error = "Invalid-Decrease-Delegate-Stake" },
				Data = tostring(error),
			})
		end, gar.decreaseDelegateStake, target, from, quantity, timestamp, messageId, instantWithdraw)
		if not shouldContinue2 then
			return
		end

		local delegateResult = {}
		if gateway ~= nil then
			local newStake = gateway.delegates[from].delegatedStake
			msg.ioEvent:addField("Previous-Stake", newStake + quantity)
			msg.ioEvent:addField("New-Stake", newStake)
			msg.ioEvent:addField("Gateway-Total-Delegated-Stake", gateway.totalDelegatedStake)
			msg.ioEvent:addField("Instant-Withdrawal", instantWithdraw)
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

		lastKnownStakedSupply = lastKnownStakedSupply - quantity
		lastKnownWithdrawSupply = lastKnownWithdrawSupply + quantity
		addSupplyData(msg.ioEvent)

		ao.send({
			Target = from,
			Tags = { Action = "Decrease-Delegate-Stake-Notice", Address = target, Quantity = quantity },
			Data = json.encode(delegateResult),
		})
	end
)

addEventingHandler(
	ActionMap.UpdateGatewaySettings,
	utils.hasMatchingTag("Action", ActionMap.UpdateGatewaySettings),
	function(msg)
		local gateway = gar.getGateway(msg.From)
		if not gateway then
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Update-Gateway-Settings-Notice", Error = "Failed-Update-Gateway-Settings" },
				Data = "Gateway not found",
			})
			return
		end

		local updatedServices = utils.safeDecodeJson(msg.Tags.Services)

		if msg.Tags.Services and not updatedServices then
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Join-Network-Notice", Error = "Invalid-Join-Network-Input" },
				Data = tostring("Failed to decode Services JSON: " .. msg.Tags.Services),
			})
			return
		end

		-- keep defaults, but update any new ones
		local updatedSettings = {
			label = msg.Tags.Label or gateway.settings.label,
			note = msg.Tags.Note or gateway.settings.note,
			fqdn = msg.Tags.FQDN or gateway.settings.fqdn,
			port = tonumber(msg.Tags.Port) or gateway.settings.port,
			protocol = msg.Tags.Protocol or gateway.settings.protocol,
			allowDelegatedStaking = not msg.Tags["Allow-Delegated-Staking"] and gateway.settings.allowDelegatedStaking
				or msg.Tags["Allow-Delegated-Staking"] == "true",
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
				Tags = { Action = "Invalid-Update-Gateway-Settings-Notice", Error = "Failed-Update-Gateway-Settings" },
				Data = tostring(result),
			})
		else
			ao.send({
				Target = msg.From,
				Tags = { Action = "Update-Gateway-Settings-Notice" },
				Data = json.encode(result),
			})
		end
	end
)

addEventingHandler(ActionMap.SaveObservations, utils.hasMatchingTag("Action", ActionMap.SaveObservations), function(msg)
	local reportTxId = msg.Tags["Report-Tx-Id"]
	local failedGateways = utils.splitString(msg.Tags["Failed-Gateways"], ",")
	local checkAssertions = function()
		assert(utils.isValidArweaveAddress(reportTxId), "Invalid report tx id")
		for _, gateway in ipairs(failedGateways) do
			assert(utils.isValidArweaveAddress(gateway), "Invalid gateway address")
		end
	end

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Save-Observations-Notice", Error = "Invalid-Save-Observations" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local shouldContinue2, observations = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Action = "Invalid-Save-Observations-Notice",
			Error = "Invalid-Saved-Observations",
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

	ao.send({ Target = msg.From, Action = "Save-Observations-Notice", Data = json.encode(observations) })
end)

addEventingHandler(ActionMap.EpochSettings, utils.hasMatchingTag("Action", ActionMap.EpochSettings), function(msg)
	local epochSettings = epochs.getSettings()
	ao.send({
		Target = msg.From,
		Action = "Epoch-Settings-Notice",
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
			Action = "Demand-Factor-Settings-Notice",
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
			Action = "Gateway-Registry-Settings-Notice",
			Data = json.encode(gatewayRegistrySettings),
		})
	end
)

addEventingHandler("totalTokenSupply", utils.hasMatchingTag("Action", "Total-Token-Supply"), function(msg)
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
	totalSupply = protocolBalance + circulatingSupply

	-- tally supply stashed in gateways and delegates
	local gateways = gar.getGateways()
	for _, gateway in pairs(gateways) do
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

	lastKnownCirculatingSupply = circulatingSupply
	lastKnownLockedSupply = lockedSupply
	lastKnownStakedSupply = stakedSupply
	lastKnownDelegatedSupply = delegatedSupply
	lastKnownWithdrawSupply = withdrawSupply

	addSupplyData(msg.ioEvent, {
		totalTokenSupply = totalSupply,
	})
	msg.ioEvent:addField("Last-Known-Total-Token-Supply", lastKnownTotalTokenSupply())

	ao.send({
		Target = msg.From,
		Action = "Total-Token-Supply-Notice",
		["Total-Token-Supply"] = totalSupply,
		["Circulating-Supply"] = circulatingSupply,
		["Locked-Supply"] = lockedSupply,
		["Staked-Supply"] = stakedSupply,
		["Delegated-Supply"] = delegatedSupply,
		["Withdraw-Supply"] = withdrawSupply,
		["Protocol-Balance"] = protocolBalance,
		Data = json.encode({
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
	local function tickEpoch(timestamp, blockHeight, hashchain)
		-- update demand factor if necessary
		local demandFactor = demand.updateDemandFactor(timestamp)
		local distributedEpoch = epochs.distributeRewardsForEpoch(timestamp)
		if distributedEpoch ~= nil and distributedEpoch.epochIndex ~= nil then
			tickedRewardDistributions[tostring(distributedEpoch.epochIndex)] =
				distributedEpoch.distributions.totalDistributedRewards
			totalTickedRewardsDistributed = totalTickedRewardsDistributed
				+ distributedEpoch.distributions.totalDistributedRewards
		end

		local newEpoch = epochs.createEpoch(timestamp, tonumber(blockHeight), hashchain)
		return {
			maybeEpoch = newEpoch,
			maybeDemandFactor = demandFactor,
		}
	end

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
	for i = lastTickedEpochIndex + 1, targetCurrentEpochIndex do
		print("Ticking epoch: " .. i)
		local previousState = {
			Balances = utils.deepCopy(Balances),
			GatewayRegistry = utils.deepCopy(GatewayRegistry),
			Epochs = utils.deepCopy(Epochs), -- we probably only need to copy the last ticked epoch
			DemandFactor = utils.deepCopy(DemandFactor),
			LastTickedEpochIndex = utils.deepCopy(LastTickedEpochIndex),
		}
		local _, _, epochDistributionTimestamp = epochs.getEpochTimestampsForIndex(i)
		-- use the minimum of the msg timestamp or the epoch distribution timestamp, this ensures an epoch gets created for the genesis block and that we don't try and distribute before an epoch is created
		local tickTimestamp = math.min(msgTimestamp or 0, epochDistributionTimestamp)
		-- TODO: if we need to "recover" epochs, we can't rely on just the current message hashchain and block height, we should set the prescribed observers and names to empty arrays and distribute rewards accordingly
		local tickSuceeded, resultOrError = pcall(tickEpoch, tickTimestamp, msg["Block-Height"], msg["Hash-Chain"])
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
	if utils.lengthOfTable(tickedRewardDistributions) > 0 then
		msg.ioEvent:addField("Ticked-Reward-Distributions", tickedRewardDistributions)
		msg.ioEvent:addField("Total-Ticked-Rewards-Distributed", totalTickedRewardsDistributed)
	end

	local gwStats = gatewayStats()
	msg.ioEvent:addField("Joined-Gateways-Count", gwStats.joined)
	msg.ioEvent:addField("Leaving-Gateways-Count", gwStats.leaving)
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

	-- TODO: arconnect et. all expect to accept Target
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
	local epochs = epochs.getEpochs()
	ao.send({ Target = msg.From, Action = "Epochs-Notice", Data = epochs })
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
	local status, result =
		pcall(gar.getPaginatedGateways, page.cursor, page.limit, page.sortBy or "startTimestamp", page.sortOrder)
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

-- END READ HANDLERS

return process
