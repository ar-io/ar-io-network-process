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
Balances = Balances or {}
if not Balances[ao.id] then -- initialize the balance for the process id
	Balances = {
		[ao.id] = math.floor(50000000 * 1000000), -- 50M IO
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
}

local function eventingPcall(ioEvent, onError, fnToCall, ...)
	local status, result = pcall(fnToCall, ...)
	if not status then
		onError(result)
		ioEvent:addField("Error", result)
		ioEvent:printEvent()
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
		ioEvent:addField("DF-Trailing-Period-Purchases", table.concat(result.df.trailingPeriodPurchases or {}, ","))
		ioEvent:addField("DF-Trailing-Period-Revenues", table.concat(result.df.trailingPeriodRevenues or {}, ","))
		ioEvent:addFieldsWithPrefixIfExist(result.df, "DF-", {
			"currentPeriod",
			"currentDemandFactor",
			"consecutivePeriodsWithMinDemandFactor",
			"revenueThisPeriod",
			"purchasesThisPeriod",
		})
	end
end

-- prune state before every interaction
Handlers.after("_default").add("prune", function()
	return "continue" -- continue is a pattern that matches every message and continues to the next handler that matches the tags
end, function(msg)
	assert(msg.Timestamp, "Timestamp is required for a tick interaction")

	-- Stash a new IOEvent with the message
	msg.ioEvent = IOEvent(msg)
	local epochIndex = epochs.getEpochIndexForTimestamp(tonumber(msg.Tags.Timestamp or msg.Timestamp))
	msg.ioEvent:addField("epochIndex", epochIndex)

	local msgTimestamp = tonumber(msg.Timestamp)
	print("Pruning state at timestamp: " .. msgTimestamp)
	-- TODO: we should copy state here and restore if tick fails, but that requires larger memory - DO NOT DO THIS UNTIL WE START PRUNING STATE of epochs and distributions
	local status, resultOrError = pcall(tick.pruneState, msgTimestamp, msgId)
	local previousState = {
		Vaults = utils.deepCopy(Vaults),
		GatewayRegistry = utils.deepCopy(GatewayRegistry),
		NameRegistry = utils.deepCopy(NameRegistry),
	}
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
		msg.ioEvent:addField("TickError", tostring(resultOrError))
		return true -- stop processing here and return
	end

	if resultOrError ~= nil then
		local prunedRecordsCount = #(resultOrError.prunedRecords or {})
		if prunedRecordsCount > 0 then
			msg.ioEvent:addField("PrunedRecords", table.concat(msg.prunedRecords, ";"))
			msg.ioEvent:addField("PrunedRecordsCount", prunedRecordsCount)
		end

		local prunedGatewaysCount = #(resultOrError.prunedGateways or {})
		if prunedGatewaysCount > 0 then
			msg.ioEvent:addField("Pruned-Gateways", table.concat(msg.prunedGateways, ";"))
			msg.ioEvent:addField("Pruned-Gateways-Count", prunedGatewaysCount)
		end

		local slashedGatewaysCount = #(resultOrError.slashedGateways or {})
		if slashedGatewaysCount > 0 then
			msg.ioEvent:addField("Slashed-Gateways", table.concat(msg.slashedGateways, ";"))
			msg.ioEvent:addField("Slashed-Gateways-Count", slashedGatewaysCount)
		end
	end

	return status
end)

-- Write handlers
Handlers.add(ActionMap.Transfer, utils.hasMatchingTag("Action", ActionMap.Transfer), function(msg)
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
	msg.ioEvent:printEvent()
end)

Handlers.add(ActionMap.CreateVault, utils.hasMatchingTag("Action", ActionMap.CreateVault), function(msg)
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

	local shouldContinue = eventingPcall(msg.ioEvent, function(error)
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Create-Vault-Notice", Error = "Bad-Input" },
			Data = tostring(error),
		})
	end, checkAssertions)
	if not shouldContinue then
		return
	end

	local shouldContinue2, vault = eventingPcall(
		ioEvent,
		function(error)
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Create-Vault-Notice", Error = "Invalid-Create-Vault" },
				Data = tostring(error),
			})
		end,
		vaults.createVault,
		msg.From,
		tonumber(msg.Tags.Quantity),
		tonumber(msg.Tags["Lock-Length"]),
		tonumber(msg.Timestamp),
		msg.Id
	)
	if not shouldContinue2 then
		return
	end

	if vault ~= nil then
		msg.ioEvent:addField("Vault-Id", msg.Id)
		msg.ioEvent:addField("VaultBalance", vault.balance)
		msg.ioEvent:addField("VaultStartTimestamp", vault.startTimestamp)
		msg.ioEvent:addField("VaultEndTimestamp", vault.endTimestamp)
	end

	ao.send({
		Target = msg.From,
		Tags = {
			Action = "Vault-Created-Notice",
			["Vault-Id"] = msg.Id,
		},
		Data = json.encode(vault),
	})
	msg.ioEvent:printEvent()
end)

Handlers.add(ActionMap.VaultedTransfer, utils.hasMatchingTag("Action", ActionMap.VaultedTransfer), function(msg)
	local function checkAssertions()
		assert(utils.isValidArweaveAddress(msg.Tags.Recipient), "Invalid recipient")
		assert(
			tonumber(msg.Tags["Lock-Length"]) > 0 and utils.isInteger(tonumber(msg.Tags["Lock-Length"])),
			"Invalid lock length. Must be integer greater than 0"
		)
		assert(
			tonumber(msg.Tags.Quantity) > 0 and utils.isInteger(tonumber(msg.Tags.Quantity)),
			"Invalid quantity. Must be integer greater than 0"
		)
	end

	local inputStatus, inputResult = pcall(checkAssertions)

	if not inputStatus then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Vaulted-Transfer-Notice", Error = "Bad-Input" },
			Data = tostring(inputResult),
		})
		return
	end

	local result, err = balances.vaultedTransfer(
		msg.From,
		msg.Tags.Recipient,
		tonumber(msg.Tags.Quantity),
		tonumber(msg.Tags["Lock-Length"]),
		msg.Timestamp,
		msg.Id
	)
	if err then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Vaulted-Transfer", Error = "Invalid-Vaulted-Transfer" },
			Data = tostring(err),
		})
	else
		ao.send({
			Target = msg.From,
			Recipient = msg.Tags.Recipient,
			Quantity = msg.Tags.Quantity,
			Tags = { Action = "Debit-Notice" },
			Data = json.encode(result),
		})
		ao.send({
			Target = msg.Tags.Recipient,
			Tags = { Action = "Vaulted-Credit-Notice" },
			Data = json.encode(result),
		})
	end
end)

Handlers.add(ActionMap.ExtendVault, utils.hasMatchingTag("Action", ActionMap.ExtendVault), function(msg)
	local checkAssertions = function()
		assert(utils.isValidArweaveAddress(msg.Tags["Vault-Id"]), "Invalid vault id")
		assert(
			tonumber(msg.Tags["Extend-Length"]) > 0 and utils.isInteger(tonumber(msg.Tags["Extend-Length"])),
			"Invalid extension length. Must be integer greater than 0"
		)
	end

	local vaultId = msg.Tags["Vault-Id"]
	local extendLength = tonumber(msg.Tags["Extend-Length"])
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
	end, vaults.extendVault, msg.From, extendLength, msg.Timestamp, vaultId)
	if not shouldContinue2 then
		return
	end

	if vault ~= nil then
		msg.ioEvent:addField("Vault-Id", vaultId)
		msg.ioEvent:addField("VaultBalance", vault.balance)
		msg.ioEvent:addField("VaultStartTimestamp", vault.startTimestamp)
		msg.ioEvent:addField("VaultEndTimestamp", vault.endTimestamp)
		msg.ioEvent:addField("VaultPrevEndTimestamp", vault.endTimestamp - extendLength)
	end

	ao.send({
		Target = msg.From,
		Tags = { Action = "Vault-Extended-Notice" },
		Data = json.encode(vault),
	})
	msg.ioEvent:printEvent()
end)

Handlers.add(ActionMap.IncreaseVault, utils.hasMatchingTag("Action", ActionMap.IncreaseVault), function(msg)
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

	ao.send({
		Target = msg.From,
		Tags = { Action = "Vault-Increased-Notice" },
		Data = json.encode(vault),
	})
	msg.ioEvent:printEvent()
end)

Handlers.add(ActionMap.BuyRecord, utils.hasMatchingTag("Action", ActionMap.BuyRecord), function(msg)
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
	end

	ao.send({
		Target = msg.From,
		Tags = { Action = "Buy-Record-Notice", Name = msg.Tags.Name },
		Data = json.encode(record),
	})
	msg.ioEvent:printEvent()
end)

Handlers.add(ActionMap.ExtendLease, utils.hasMatchingTag("Action", ActionMap.ExtendLease), function(msg)
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
	end

	ao.send({
		Target = msg.From,
		Tags = { Action = "Extend-Lease-Notice", Name = string.lower(msg.Tags.Name) },
		Data = json.encode(recordResult),
	})
	msg.ioEvent:printEvent()
end)

Handlers.add(
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
		end

		ao.send({
			Target = msg.From,
			Tags = { Action = "Increase-Undername-Limit-Notice", Name = string.lower(msg.Tags.Name) },
			Data = json.encode(recordResult),
		})
	end
)

Handlers.add(ActionMap.TokenCost, utils.hasMatchingTag("Action", ActionMap.TokenCost), function(msg)
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

Handlers.add(ActionMap.GetRegistrationFees, utils.hasMatchingTag("Action", ActionMap.GetRegistrationFees), function(msg)
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
end)

Handlers.add(ActionMap.JoinNetwork, utils.hasMatchingTag("Action", ActionMap.JoinNetwork), function(msg)
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
	local observerAddress = msg.Tags["Observer-Address"] or msg.Tags.From
	msg.ioEvent:addField("ResolvedObserverAddress", observerAddress)
	msg.ioEvent:addField("SenderPreviousBalance", balances[msg.From])

	local shouldContinue, gateway = eventingPcall(
		msg.ioEvent,
		function(error)
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Join-Network-Notice", Error = "Invalid-Join-Network" },
				Data = tostring(error),
			})
		end,
		gar.joinNetwork,
		msg.From,
		tonumber(msg.Tags["Operator-Stake"]),
		updatedSettings,
		observerAddress,
		msg.Timestamp
	)
	if not shouldContinue then
		return
	end

	msg.ioEvent:addField("Sender-New-Balance", balances[msg.From])
	if gateway ~= nil then
		msg.ioEvent:addField("GW-Start-Timestamp", gateway.startTimestamp)
	end

	ao.send({
		Target = msg.From,
		Tags = { Action = "Join-Network-Notice" },
		Data = json.encode(gateway),
	})
	msg.ioEvent:printEvent()
end)

Handlers.add(ActionMap.LeaveNetwork, utils.hasMatchingTag("Action", ActionMap.LeaveNetwork), function(msg)
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
		msg.ioEvent:addField("GW-Vaults-Count", #(gateway.vaults or {}))
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

	ao.send({
		Target = msg.From,
		Tags = { Action = "Leave-Network-Notice" },
		Data = json.encode(gateway),
	})
	msg.ioEvent:printEvent()
end)

Handlers.add(
	ActionMap.IncreaseOperatorStake,
	utils.hasMatchingTag("Action", ActionMap.IncreaseOperatorStake),
	function(msg)
		local checkAssertions = function()
			assert(
				utils.isInteger(tonumber(msg.Tags.Quantity)) and tonumber(msg.Tags.Quantity) > 0,
				"Invalid quantity. Must be integer greater than 0"
			)
		end

		local inputStatus, inputResult = pcall(checkAssertions)

		if not inputStatus then
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Increase-Operator-Stake-Notice", Error = "Bad-Input" },
				Data = tostring(inputResult),
			})
			return
		end

		local result, err = gar.increaseOperatorStake(msg.From, tonumber(msg.Tags.Quantity))
		if err then
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Increase-Operator-Stake-Notice" },
				Data = tostring(err),
			})
		else
			ao.send({
				Target = msg.From,
				Tags = { Action = "Increase-Operator-Stake-Notice" },
				Data = json.encode(result),
			})
		end
	end
)

Handlers.add(
	ActionMap.DecreaseOperatorStake,
	utils.hasMatchingTag("Action", ActionMap.DecreaseOperatorStake),
	function(msg)
		local checkAssertions = function()
			assert(
				utils.isInteger(tonumber(msg.Tags.Quantity)) and tonumber(msg.Tags.Quantity) > 0,
				"Invalid quantity. Must be integer greater than 0"
			)
		end

		local inputStatus, inputResult = pcall(checkAssertions)

		if not inputStatus then
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Decrease-Operator-Stake-Notice", Error = "Bad-Input" },
				Data = tostring(inputResult),
			})
			return
		end
		local status, result =
			pcall(gar.decreaseOperatorStake, msg.From, tonumber(msg.Tags.Quantity), msg.Timestamp, msg.Id)
		if not status then
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Decrease-Operator-Stake-Notice", Error = "Invalid-Stake-Decrease" },
				Data = tostring(result),
			})
		else
			ao.send({
				Target = msg.From,
				Tags = { Action = "Decrease-Operator-Stake-Notice" },
				Data = json.encode(result),
			})
		end
	end
)

Handlers.add(ActionMap.DelegateStake, utils.hasMatchingTag("Action", ActionMap.DelegateStake), function(msg)
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
			Tags = { Action = "Invalid-Delegate-Stake-Notice", Error = "Invalid-Delegate-Stake", Message = error }, -- TODO: is this still right?
			Data = json.encode(error),
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

	ao.send({
		Target = msg.From,
		Tags = { Action = "Delegate-Stake-Notice", Gateway = msg.Tags.Target },
		Data = json.encode(delegateResult),
	})
	msg.ioEvent:printEvent()
end)

Handlers.add(
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
				msg.ioEvent:addField("PreviousStake", newStake - delegateResult.vaults[vaultId].balance)
				msg.ioEvent:addField("NewStake", newStake)
				msg.ioEvent:addField("GatewayTotalDelegatedStake", result.totalDelegatedStake)
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
		msg.ioEvent:printEvent()
	end
)

Handlers.add(
	ActionMap.DecreaseDelegateStake,
	utils.hasMatchingTag("Action", ActionMap.DecreaseDelegateStake),
	function(msg)
		local checkAssertions = function()
			assert(utils.isValidArweaveAddress(msg.Tags.Target or msg.Tags.Address), "Invalid target address")
			assert(
				tonumber(msg.Tags.Quantity) > 0 and utils.isInteger(tonumber(msg.Tags.Quantity)),
				"Invalid quantity. Must be integer greater than 0"
			)
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
		msg.ioEvent:addField("TargetFormatted", target)

		local shouldContinue2, gateway = eventingPcall(msg.ioEvent, function(error)
			ao.send({
				Target = from,
				Tags = { Action = "Invalid-Decrease-Delegate-Stake-Notice", Error = "Invalid-Decrease-Delegate-Stake" },
				Data = tostring(error),
			})
		end, gar.decreaseDelegateStake, target, from, quantity, msg.Timestamp, msg.Id)
		if not shouldContinue2 then
			return
		end

		local delegateResult = {}
		if gateway ~= nil then
			local newStake = gateway.delegates[from].delegatedStake
			msg.ioEvent:addField("PreviousStake", newStake + quantity)
			msg.ioEvent:addField("NewStake", newStake)
			msg.ioEvent:addField("GatewayTotalDelegatedStake", gateway.totalDelegatedStake)

			delegateResult = gateway.delegates[from]
			local newDelegateVaults = delegateResult.vaults
			if newDelegateVaults ~= nil then
				msg.ioEvent:addField("VaultsCount", utils.lengthOfTable(newDelegateVaults))
				local newDelegateVault = newDelegateVaults[msg.Id]
				if newDelegateVault ~= nil then
					msg.ioEvent:addField("Vault-Id", msg.Id)
					msg.ioEvent:addField("VaultBalance", newDelegateVault.balance)
					msg.ioEvent:addField("VaultStartTimestamp", newDelegateVault.startTimestamp)
					msg.ioEvent:addField("VaultEndTimestamp", newDelegateVault.endTimestamp)
				end
			end
		end

		ao.send({
			Target = from,
			Tags = { Action = "Decrease-Delegate-Stake-Notice", Adddress = target, Quantity = msg.Tags.Quantity },
			Data = json.encode(delegateResult),
		})
		msg.ioEvent:printEvent()
	end
)

Handlers.add(
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
		local observerAddress = msg.Tags["Observer-Address"] or gateway.observerAddress
		local status, result =
			pcall(gar.updateGatewaySettings, msg.From, updatedSettings, observerAddress, msg.Timestamp, msg.Id)
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

Handlers.add(ActionMap.SaveObservations, utils.hasMatchingTag("Action", ActionMap.SaveObservations), function(msg)
	local reportTxId = msg.Tags["Report-Tx-Id"]
	local failedGateways = utils.splitString(msg.Tags["Failed-Gateways"], ",")
	local checkAssertions = function()
		assert(utils.isValidArweaveAddress(reportTxId), "Invalid report tx id")
		for _, gateway in ipairs(failedGateways) do
			assert(utils.isValidArweaveAddress(gateway), "Invalid gateway address")
		end
	end

	local inputStatus, inputResult = pcall(checkAssertions)

	if not inputStatus then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Save-Observations-Notice", Error = "Invalid-Save-Observations" },
			Data = tostring(inputResult),
		})
		return
	end

	local status, result = pcall(epochs.saveObservations, msg.From, reportTxId, failedGateways, msg.Timestamp)
	if status then
		ao.send({ Target = msg.From, Action = "Save-Observations-Notice", Data = json.encode(result) })
	else
		ao.send({
			Target = msg.From,
			Action = "Invalid-Save-Observations-Notice",
			Error = "Invalid-Saved-Observations",
			Data = json.encode(result),
		})
	end
end)

Handlers.add(ActionMap.EpochSettings, utils.hasMatchingTag("Action", ActionMap.EpochSettings), function(msg)
	local epochSettings = epochs.getSettings()
	ao.send({
		Target = msg.From,
		Action = "Epoch-Settings-Notice",
		Data = json.encode(epochSettings),
	})
end)

Handlers.add(
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

Handlers.add(
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

Handlers.add("totalTokenSupply", utils.hasMatchingTag("Action", "Total-Token-Supply"), function(msg)
	-- add all the balances
	local totalSupply = 0
	local balances = balances.getBalances()
	for _, balance in pairs(balances) do
		totalSupply = totalSupply + balance
	end
	-- gateways and delegates
	local gateways = gar.getGateways()
	for _, gateway in pairs(gateways) do
		totalSupply = totalSupply + gateway.operatorStake + gateway.totalDelegatedStake
		for _, delegate in pairs(gateway.delegates) do
			-- check vaults
			for _, vault in pairs(delegate.vaults) do
				totalSupply = totalSupply + vault.balance
			end
		end
		-- iterate through vaults
		for _, vault in pairs(gateway.vaults) do
			totalSupply = totalSupply + vault.balance
		end
	end

	-- vaults
	local vaults = vaults.getVaults()
	for _, vaultsForAddress in pairs(vaults) do
		-- they may have several vaults iterate through them
		for _, vault in pairs(vaultsForAddress) do
			totalSupply = totalSupply + vault.balance
		end
	end

	ao.send({
		Target = msg.From,
		Action = "Total-Token-Supply-Notice",
		["Total-Token-Supply"] = totalSupply,
		Data = json.encode(totalSupply),
	})
end)

-- TICK HANDLER - TODO: this may be better as a "Distribute" rewards handler instead of `Tick` tag
Handlers.add("distribute", utils.hasMatchingTag("Action", "Tick"), function(msg)
	assert(msg.Timestamp, "Timestamp is required for a tick interaction")
	local msgTimestamp = tonumber(msg.Timestamp)
	-- tick and distribute rewards for every index between the last ticked epoch and the current epoch
	local function tickEpochs(timestamp, blockHeight, hashchain)
		-- update demand factor if necessary
		demand.updateDemandFactor(timestamp)
		epochs.distributeRewardsForEpoch(timestamp)
		epochs.createEpoch(timestamp, tonumber(blockHeight), hashchain)
	end

	local lastTickedEpochIndex = LastTickedEpochIndex
	local currentEpochIndex = epochs.getEpochIndexForTimestamp(msgTimestamp)
	-- if epoch index is -1 then we are before the genesis epoch and we should not tick
	if currentEpochIndex < 0 then
		-- do nothing and just send a notice back to the sender
		ao.send({
			Target = msg.From,
			Action = "Tick-Notice",
			LastTickedEpochIndex = LastTickedEpochIndex,
			Data = json.encode("Genesis epocch has not started yet."),
		})
	end

	-- tick and distribute rewards for every index between the last ticked epoch and the current epoch
	for i = lastTickedEpochIndex + 1, currentEpochIndex do
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
		local status, result = pcall(tickEpochs, tickTimestamp, msg["Block-Height"], msg["Hash-Chain"])
		if status then
			if tickTimestamp == epochDistributionTimestamp then
				-- if we are distributing rewards, we should update the last ticked epoch index to the current epoch index
				LastTickedEpochIndex = i
			end
			ao.send({
				Target = msg.From,
				Action = "Tick-Notice",
				LastTickedEpochIndex = LastTickedEpochIndex,
				Data = json.encode(result),
			})
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
				Data = json.encode(result),
			})
		end
	end
end)

-- READ HANDLERS

Handlers.add(ActionMap.Info, Handlers.utils.hasMatchingTag("Action", ActionMap.Info), function(msg)
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

Handlers.add(ActionMap.State, Handlers.utils.hasMatchingTag("Action", ActionMap.State), function(msg)
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

Handlers.add(ActionMap.Gateways, Handlers.utils.hasMatchingTag("Action", ActionMap.Gateways), function(msg)
	local gateways = gar.getGateways()
	ao.send({
		Target = msg.From,
		Action = "Gateways-Notice",
		Data = json.encode(gateways),
	})
end)

Handlers.add(ActionMap.Gateway, Handlers.utils.hasMatchingTag("Action", ActionMap.Gateway), function(msg)
	local gateway = gar.getGateway(msg.Tags.Address or msg.From)
	ao.send({
		Target = msg.From,
		Action = "Gateway-Notice",
		Gateway = msg.Tags.Address or msg.From,
		Data = json.encode(gateway),
	})
end)

Handlers.add(ActionMap.Balances, Handlers.utils.hasMatchingTag("Action", ActionMap.Balances), function(msg)
	ao.send({
		Target = msg.From,
		Action = "Balances-Notice",
		Data = json.encode(Balances),
	})
end)

Handlers.add(ActionMap.Balance, Handlers.utils.hasMatchingTag("Action", ActionMap.Balance), function(msg)
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

Handlers.add(ActionMap.DemandFactor, utils.hasMatchingTag("Action", ActionMap.DemandFactor), function(msg)
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

Handlers.add(ActionMap.DemandFactorInfo, utils.hasMatchingTag("Action", ActionMap.DemandFactorInfo), function(msg)
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

Handlers.add(ActionMap.Record, utils.hasMatchingTag("Action", ActionMap.Record), function(msg)
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

Handlers.add(ActionMap.Records, utils.hasMatchingTag("Action", ActionMap.Records), function(msg)
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

Handlers.add(ActionMap.Epoch, utils.hasMatchingTag("Action", ActionMap.Epoch), function(msg)
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

Handlers.add(ActionMap.Epochs, utils.hasMatchingTag("Action", ActionMap.Epochs), function(msg)
	local epochs = epochs.getEpochs()
	ao.send({ Target = msg.From, Action = "Epochs-Notice", Data = epochs })
end)

Handlers.add(ActionMap.PrescribedObservers, utils.hasMatchingTag("Action", ActionMap.PrescribedObservers), function(msg)
	-- check if the epoch number is provided, if not get the epoch number from the timestamp
	local checkAssertions = function()
		assert(msg.Tags["Epoch-Index"] or msg.Timestamp or msg.Tags.Timestamp, "Epoch index or timestamp is required")
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

	local epochIndex = tonumber(msg.Tags["Epoch-Index"]) or epochs.getEpochIndexForTimestamp(tonumber(msg.Timestamp))
	local prescribedObservers = epochs.getPrescribedObserversForEpoch(epochIndex)
	ao.send({ Target = msg.From, Action = "Prescribed-Observers-Notice", Data = json.encode(prescribedObservers) })
end)

Handlers.add(ActionMap.Observations, utils.hasMatchingTag("Action", ActionMap.Observations), function(msg)
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

Handlers.add(ActionMap.PrescribedNames, utils.hasMatchingTag("Action", ActionMap.PrescribedNames), function(msg)
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

Handlers.add(ActionMap.Distributions, utils.hasMatchingTag("Action", ActionMap.Distributions), function(msg)
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

Handlers.add(ActionMap.ReservedNames, utils.hasMatchingTag("Action", ActionMap.ReservedNames), function(msg)
	local reservedNames = arns.getReservedNames()
	ao.send({ Target = msg.From, Action = "Reserved-Names-Notice", Data = json.encode(reservedNames) })
end)

Handlers.add(ActionMap.ReservedName, utils.hasMatchingTag("Action", ActionMap.ReservedName), function(msg)
	local reservedName = arns.getReservedName(msg.Tags.Name)
	ao.send({
		Target = msg.From,
		Action = "Reserved-Name-Notice",
		ReservedName = msg.Tags.Name,
		Data = json.encode(reservedName),
	})
end)

Handlers.add(ActionMap.Vaults, utils.hasMatchingTag("Action", ActionMap.Vaults), function(msg)
	ao.send({ Target = msg.From, Action = "Vaults-Notice", Data = json.encode(Vaults) })
end)

Handlers.add(ActionMap.Vault, utils.hasMatchingTag("Action", ActionMap.Vault), function(msg)
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

Handlers.add("paginatedRecords", utils.hasMatchingTag("Action", "Paginated-Records"), function(msg)
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

Handlers.add("paginatedGateways", utils.hasMatchingTag("Action", "Paginated-Gateways"), function(msg)
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

Handlers.add("paginatedBalances", utils.hasMatchingTag("Action", "Paginated-Balances"), function(msg)
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
