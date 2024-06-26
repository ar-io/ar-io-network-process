-- Adjust package.path to include the current directory
local process = { _version = "0.0.1" }
local constants = require("constants")

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
	-- GATEWAY REGISTRY READ APIS
	Gateway = "Gateway",
	Gateways = "Gateways",
	GatewayRegistrySettings = "Gateway-Registry-Settings",
	-- writes
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
}

-- Write handlers
Handlers.add(ActionMap.Transfer, utils.hasMatchingTag("Action", ActionMap.Transfer), function(msg)
	-- assert recipient is a valid arweave address
	local function checkAssertions()
		assert(utils.isValidArweaveAddress(msg.Tags.Recipient), "Invalid recipient")
		assert(
			tonumber(msg.Tags.Quantity) > 0 and utils.isInteger(tonumber(msg.Tags.Quantity)),
			"Invalid quantity. Must be integer greater than 0"
		)
	end

	local inputStatus, inputResult = pcall(checkAssertions)

	if not inputStatus then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Transfer-Notice", Error = "Transfer-Error" },
			Data = tostring(inputResult),
		})
		return
	end

	local status, result = pcall(balances.transfer, msg.Tags.Recipient, msg.From, tonumber(msg.Tags.Quantity))
	if not status then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Transfer-Notice", Error = "Transfer-Error" },
			Data = tostring(result),
		})
	else
		if msg.Cast then
			-- Debit-Notice message template, that is sent to the Sender of the transfer
			local debitNotice = {
				Target = msg.From,
				Action = "Debit-Notice",
				Recipient = msg.Recipient,
				Quantity = msg.Quantity,
				Data = "You transferred " .. msg.Quantity .. " to " .. msg.Recipient,
			}
			-- Credit-Notice message template, that is sent to the Recipient of the transfer
			local creditNotice = {
				Target = msg.Recipient,
				Action = "Credit-Notice",
				Sender = msg.From,
				Quantity = msg.Quantity,
				Data = "You received " .. msg.Quantity .. " from " .. msg.From,
			}

			-- Add forwarded tags to the credit and debit notice messages
			for tagName, tagValue in pairs(msg) do
				-- Tags beginning with "X-" are forwarded
				if string.sub(tagName, 1, 2) == "X-" then
					debitNotice[tagName] = tagValue
					creditNotice[tagName] = tagValue
				end
			end

			-- Send Debit-Notice and Credit-Notice
			ao.send(debitNotice)
			ao.send(creditNotice)
		end
	end
end)

Handlers.add(ActionMap.CreateVault, utils.hasMatchingTag("Action", ActionMap.CreateVault), function(msg)
	local function checkAssertions()
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
			Tags = { Action = "Invalid-Create-Vault-Notice", Error = "Bad-Input" },
			Data = tostring(inputResult),
		})
		return
	end

	local result, err =
		balances.createVault(msg.From, msg.Tags.Quantity, tonumber(msg.Tags["Lock-Length"]), msg.Timestamp, msg.Id)
	if err then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Create-Vault-Notice", Error = "Invalid-Create-Vault" },
			Data = tostring(err),
		})
	else
		ao.send({
			Target = msg.From,
			Tags = { Action = "Vault-Created-Notice" },
			Data = json.encode(result),
		})
	end
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

	local inputStatus, inputResult = pcall(checkAssertions)

	if not inputStatus then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Extend-Vault-Notice", Error = "Bad-Input" },
			Data = tostring(inputResult),
		})
		return
	end

	local result, err = balances.extendVault(msg.From, msg.Tags["Extend-Length"], msg.Timestamp, msg.Tags["Vault-Id"])
	if err then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Extend-Vault-Notice", Error = "Invalid-Extend-Vault" },
			Data = tostring(err),
		})
	else
		ao.send({
			Target = msg.From,
			Tags = { Action = "Vault-Extended-Notice" },
			Data = json.encode(result),
		})
	end
end)

Handlers.add(ActionMap.IncreaseVault, utils.hasMatchingTag("Action", ActionMap.IncreaseVault), function(msg)
	local function checkAssertions()
		assert(utils.isValidArweaveAddress(msg.Tags["Vault-Id"]), "Invalid vault id")
		assert(
			tonumber(msg.Tags.Quantity) > 0 and utils.isInteger(tonumber(msg.Tags.Quantity)),
			"Invalid quantity. Must be integer greater than 0"
		)
	end

	local inputStatus, inputResult = pcall(checkAssertions)

	if not inputStatus then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Increase-Vault-Notice", Error = "Bad-Input" },
			Data = tostring(inputResult),
		})
		return
	end

	local result, err = balances.increaseVault(msg.From, msg.Tags.Quantity, msg.Tags["Vault-Id"], msg.Timestamp)
	if err then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Increase-Vault-Notice", Error = "Invalid-Increase-Vault" },
			Data = tostring(err),
		})
	else
		ao.send({
			Target = msg.From,
			Tags = { Action = "Vault-Increased-Notice" },
			Data = json.encode(result),
		})
	end
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

	local inputStatus, inputResult = pcall(checkAssertions)

	if not inputStatus then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Buy-Record-Notice", Error = "Bad-Input" },
			Data = tostring(inputResult),
		})
		return
	end

	local status, result = pcall(
		arns.buyRecord,
		string.lower(msg.Tags.Name),
		msg.Tags["Purchase-Type"],
		tonumber(msg.Tags.Years),
		msg.From,
		msg.Timestamp,
		msg.Tags["Process-Id"]
	)
	if not status then
		ao.send({
			Target = msg.From,
			Tags = {
				Action = "Invalid-Buy-Record-Notice",
				Error = "Invalid-Buy-Record",
			},
			Data = tostring(result),
		})
		return
	else
		ao.send({
			Target = msg.From,
			Tags = { Action = "Buy-Record-Notice", Name = msg.Tags.Name },
			Data = json.encode(result),
		})
	end
end)

Handlers.add(ActionMap.ExtendLease, utils.hasMatchingTag("Action", ActionMap.ExtendLease), function(msg)
	local checkAssertions = function()
		assert(type(msg.Tags.Name) == "string", "Invalid name")
		assert(
			tonumber(msg.Tags.Years) > 0 and tonumber(msg.Tags.Years) < 5 and utils.isInteger(tonumber(msg.Tags.Years)),
			"Invalid years. Must be integer between 1 and 5"
		)
	end

	local inputStatus, inputResult = pcall(checkAssertions)

	if not inputStatus then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Extend-Lease-Notice", Error = "Bad-Input" },
			Data = tostring(inputResult),
		})
		return
	end

	local status, result =
		pcall(arns.extendLease, msg.From, string.lower(msg.Tags.Name), tonumber(msg.Tags.Years), msg.Timestamp)
	if not status then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Extend-Lease-Notice", Error = "Invalid-Extend-Lease" },
			Data = tostring(result),
		})
	else
		ao.send({
			Target = msg.From,
			Tags = { Action = "Extend-Lease-Notice", Name = string.lower(msg.Tags.Name) },
			Data = json.encode(result),
		})
	end
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

		local inputStatus, inputResult = pcall(checkAssertions)

		if not inputStatus then
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Increase-Undername-Limit-Notice", Error = "Bad-Input" },
				Data = tostring(inputResult),
			})
			return
		end

		local status, result = pcall(
			arns.increaseundernameLimit,
			msg.From,
			string.lower(msg.Tags.Name),
			tonumber(msg.Tags.Quantity),
			msg.Timestamp
		)
		if not status then
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Increase-Undername-Limit-Notice", Error = "Invalid-Undername-Increase" },
				Data = tostring(result),
			})
		else
			ao.send({
				Target = msg.From,
				Tags = { Action = "Increase-Undername-Limit-Notice", Name = string.lower(msg.Tags.Name) },
				Data = json.encode(result),
			})
		end
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
					.. msg.Tags.Intent
				or "nil"
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

	local status, result = pcall(
		gar.joinNetwork,
		msg.From,
		tonumber(msg.Tags["Operator-Stake"]),
		updatedSettings,
		observerAddress,
		msg.Timestamp
	)
	if not status then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Join-Network-Notice", Error = "Invalid-Join-Network" },
			Data = tostring(result),
		})
	else
		ao.send({
			Target = msg.From,
			Tags = { Action = "Join-Network-Notice" },
			Data = json.encode(result),
		})
	end
end)

Handlers.add(ActionMap.LeaveNetwork, utils.hasMatchingTag("Action", ActionMap.LeaveNetwork), function(msg)
	local status, result = pcall(gar.leaveNetwork, msg.From, msg.Timestamp, msg.Id)
	if not status then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Leave-Network-Notice", Error = "Invalid-Leave-Network" },
			Data = tostring(result),
		})
	else
		ao.send({
			Target = msg.From,
			Tags = { Action = "Leave-Network-Notice" },
			Data = json.encode(result),
		})
	end
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
		assert(utils.isValidArweaveAddress(msg.Tags.Target), "Invalid target address")
		assert(
			tonumber(msg.Tags.Quantity) > 0 and utils.isInteger(tonumber(msg.Tags.Quantity)),
			"Invalid quantity. Must be integer greater than 0"
		)
	end

	local inputStatus, inputResult = pcall(checkAssertions)

	if not inputStatus then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Delegate-Stake-Notice", Error = "Bad-Input" },
			Data = tostring(inputResult),
		})
		return
	end

	local status, result =
		pcall(gar.delegateStake, msg.From, msg.Tags.Target, tonumber(msg.Tags.Quantity), tonumber(msg.Timestamp))
	if not status then
		ao.send({
			Target = msg.From,
			Tags = { Action = "Invalid-Delegate-Stake-Notice", Error = "Invalid-Delegate-Stake", Message = result },
			Data = json.encode(result),
		})
	else
		ao.send({
			Target = msg.From,
			Tags = { Action = "Delegate-Stake-Notice", Gateway = msg.Tags.Target },
			Data = json.encode(result),
		})
	end
end)

Handlers.add(
	ActionMap.DecreaseDelegateStake,
	utils.hasMatchingTag("Action", ActionMap.DecreaseDelegateStake),
	function(msg)
		local checkAssertions = function()
			assert(utils.isValidArweaveAddress(msg.Tags.Target), "Invalid target address")
			assert(
				tonumber(msg.Tags.Quantity) > 0 and utils.isInteger(tonumber(msg.Tags.Quantity)),
				"Invalid quantity. Must be integer greater than 0"
			)
		end

		local inputStatus, inputResult = pcall(checkAssertions)

		if not inputStatus then
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Decrease-Delegate-Stake-Notice", Error = "Bad-Input" },
				Data = tostring(inputResult),
			})
			return
		end

		local status, result = pcall(
			gar.decreaseDelegateStake,
			msg.Tags.Target,
			msg.From,
			tonumber(msg.Tags.Quantity),
			msg.Timestamp,
			msg.Id
		)
		if not status then
			ao.send({
				Target = msg.From,
				Tags = { Action = "Invalid-Decrease-Delegate-Stake-Notice", Error = "Invalid-Decrease-Delegate-Stake" },
				Data = tostring(result),
			})
		else
			ao.send({
				Target = msg.From,
				Tags = { Action = "Decrease-Delegate-Stake-Notice", Gateway = msg.Tags.Target },
				Data = json.encode(result),
			})
		end
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

-- TICK HANDLER
Handlers.add("tick", utils.hasMatchingTag("Action", "Tick"), function(msg)
	-- assert this is a write interaction and we have a timetsamp
	assert(msg.Timestamp, "Timestamp is required for a tick interaction")
	-- tick the things that only require timestamp and don't need to happen for every epoch
	local function tickState(timestamp)
		arns.pruneRecords(timestamp)
		arns.pruneReservedNames(timestamp)
		vaults.pruneVaults(timestamp)
		gar.pruneGateways(timestamp)
	end

	local previousState = {
		Balances = utils.deepCopy(Balances),
		Vaults = utils.deepCopy(Vaults),
		GatewayRegistry = utils.deepCopy(GatewayRegistry),
		NameRegistry = utils.deepCopy(NameRegistry),
		Epochs = utils.deepCopy(Epochs),
		DemandFactor = utils.deepCopy(DemandFactor),
		LastTickedEpochIndex = utils.deepCopy(LastTickedEpochIndex),
	}
	local msgTimestamp = tonumber(msg.Timestamp)

	-- tick the state and demand factor using just the timestamp
	local stateStatus, stateResult = pcall(tickState, msgTimestamp)
	if not stateStatus then
		-- reset the state to previous state
		Balances = previousState.Balances
		Vaults = previousState.Vaults
		GatewayRegistry = previousState.GatewayRegistry
		NameRegistry = previousState.NameRegistry
		Epochs = previousState.Epochs
		DemandFactor = previousState.DemandFactor
		LastTickedEpochIndex = previousState.LastTickedEpochIndex
		ao.send({
			Target = msg.From,
			Action = "Invalid-Tick-Notice",
			Error = "Invalid-Tick",
			Data = json.encode(stateResult),
		})
	end

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
			Vaults = utils.deepCopy(Vaults),
			GatewayRegistry = utils.deepCopy(GatewayRegistry),
			NameRegistry = utils.deepCopy(NameRegistry),
			Epochs = utils.deepCopy(Epochs),
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
			Vaults = previousState.Vaults
			GatewayRegistry = previousState.GatewayRegistry
			NameRegistry = previousState.NameRegistry
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
	ao.send({
		Target = msg.From,
		Action = "Info-Notice",
		Tags = { Name = Name, Ticker = Ticker, Logo = Logo, Denomination = tostring(Denomination) },
		Data = json.encode({ Name = Name, Ticker = Ticker, Logo = Logo, Denomination = Denomination }),
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
	-- TODO: arconnect et. all expect to accept Target
	local balance = balances.getBalance(msg.Tags.Target or msg.Tags.Address or msg.From)
	-- must adhere to token.lua spec for arconnect compatibility
	ao.send({
		Target = msg.From,
		Action = "Balance-Notice",
		Data = balance,
		Balance = balance,
		Ticker = Ticker,
		Address = msg.Tags.Target or msg.Tags.Address or msg.From,
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
	ao.send({ Target = msg.From, Action = "Epochs-Notice", Data = json.encode(epochs) })
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

-- END READ HANDLERS

-- UTILITY HANDLERS USED FOR MIGRATION
Handlers.add("addGateway", utils.hasMatchingTag("Action", "AddGateway"), function(msg)
	if msg.From ~= Owner then
		ao.send({ Target = msg.From, Data = "Unauthorized" })
		return
	end
	local operatorStake = tonumber(json.decode(msg.Data).operatorStake)
	assert(operatorStake > 0, "Operator stake must be greater than 0")
	local status, result = pcall(gar.addGateway, msg.Tags.Address, json.decode(msg.Data))
	balances.reduceBalance(Owner, operatorStake)
	if status then
		ao.send({ Target = msg.From, Data = json.encode(result) })
	else
		ao.send({ Target = msg.From, Data = json.encode(result) })
	end
end)

Handlers.add("addRecord", utils.hasMatchingTag("Action", "AddRecord"), function(msg)
	if msg.From ~= Owner then
		ao.send({ Target = msg.From, Data = "Unauthorized" })
		return
	end
	local status, result = pcall(arns.addRecord, string.lower(msg.Tags.Name), json.decode(msg.Data))
	if status then
		ao.send({ Target = msg.From, Data = json.encode(result) })
	else
		ao.send({ Target = msg.From, Data = json.encode(result) })
	end
end)

Handlers.add("addReservedName", utils.hasMatchingTag("Action", "AddReservedName"), function(msg)
	if msg.From ~= Owner then
		ao.send({ Target = msg.From, Data = "Unauthorized" })
		return
	end
	local status, result = pcall(arns.addReservedName, string.lower(msg.Tags.Name), json.decode(msg.Data))
	if status then
		ao.send({ Target = msg.From, Data = json.encode(result) })
	else
		ao.send({ Target = msg.From, Data = json.encode(result) })
	end
end)

Handlers.add("sortedRecords", utils.hasMatchingTag("Action", "Sorted-Records"), function(msg)
	local page = tonumber(msg.Tags.Page) or 1
	local pageLimit = tonumber(msg.Tags["Page-Size"]) or 10
	local sortOrder = msg.Tags.SortOrder and string.lower(msg.Tags["Sort-Order"]) or "asc"
	local sortBy = msg.Tags.SortBy and string.lower(msg.Tags["Sort-By"]) or "name"
	local sortedRecords = arns.getSortedRecords(page, pageLimit, sortBy, sortOrder)
	ao.send({ Target = msg.From, Data = json.encode(sortedRecords) })
end)

-- END UTILITY HANDLERS USED FOR MIGRATION

return process
