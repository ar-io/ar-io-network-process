--[[
	Updates Vaulted-Transfer, Revoke-Vault, and Decrease-Delegate-Stake to send numbers as strings in the Tags field.


    We need to remount the handlers to update the messaging.


	Reviewers: Dylan, Ariel, Atticus
]]
--

local ARIOEvent = require(".src.ario_event")
local utils = require(".src.utils")
local constants = require(".src.constants")
local vaults = require(".src.vaults")
local gar = require(".src.gar")
local hb = require(".src.hb")
local token = require(".src.token")
local json = require(".src.json")

local ActionMap = {
	-- reads
	Info = "Info",
	TotalSupply = "Total-Supply", -- for token.lua spec compatibility, gives just the total supply (circulating + locked + staked + delegated + withdraw)
	TotalTokenSupply = "Total-Token-Supply", -- gives the total token supply and all components (protocol balance, locked supply, staked supply, delegated supply, and withdraw supply)
	Transfer = "Transfer",
	Balance = "Balance",
	Balances = "Balances",
	DemandFactor = "Demand-Factor",
	DemandFactorInfo = "Demand-Factor-Info",
	DemandFactorSettings = "Demand-Factor-Settings",
	-- EPOCH READ APIS
	Epoch = "Epoch",
	EpochSettings = "Epoch-Settings",
	PrescribedObservers = "Epoch-Prescribed-Observers",
	PrescribedNames = "Epoch-Prescribed-Names",
	Observations = "Epoch-Observations",
	Distributions = "Epoch-Distributions",
	EpochRewards = "Epoch-Eligible-Rewards",
	--- Vaults
	Vault = "Vault",
	Vaults = "Vaults",
	CreateVault = "Create-Vault",
	VaultedTransfer = "Vaulted-Transfer",
	ExtendVault = "Extend-Vault",
	IncreaseVault = "Increase-Vault",
	RevokeVault = "Revoke-Vault",
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
	AllPaginatedDelegates = "All-Paginated-Delegates",
	AllGatewayVaults = "All-Gateway-Vaults",
	--- ArNS
	Record = "Record",
	Records = "Records",
	BuyName = "Buy-Name",
	UpgradeName = "Upgrade-Name",
	ExtendLease = "Extend-Lease",
	IncreaseUndernameLimit = "Increase-Undername-Limit",
	ReassignName = "Reassign-Name",
	ReleaseName = "Release-Name",
	ReservedNames = "Reserved-Names",
	ReservedName = "Reserved-Name",
	TokenCost = "Token-Cost",
	CostDetails = "Cost-Details",
	RegistrationFees = "Registration-Fees",
	ReturnedNames = "Returned-Names",
	ReturnedName = "Returned-Name",
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
	-- Hyperbeam Patch Balances
	PatchHyperbeamBalances = "Patch-Hyperbeam-Balances",
}

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

local function addEventingHandler(handlerName, pattern, handleFn, critical, printEvent)
	critical = critical or false
	printEvent = printEvent == nil and true or printEvent
	Handlers.add(handlerName, pattern, function(msg)
		-- Store the old balances to compare after the handler has run for patching state
		-- Only do this for the last handler to avoid unnecessary copying

		local shouldPatchHbState = false
		if pattern(msg) ~= "continue" then
			shouldPatchHbState = true
		end
		-- add an ARIOEvent to the message if it doesn't exist
		msg.ioEvent = msg.ioEvent or ARIOEvent(msg)
		-- global handler for all eventing errors, so we can log them and send a notice to the sender for non critical errors and discard the memory on critical errors
		local status, resultOrError = eventingPcall(msg.ioEvent, function(error)
			--- non critical errors will send an invalid notice back to the caller with the error information, memory is not discarded
			Send(msg, {
				Target = msg.From,
				Action = "Invalid-" .. utils.toTrainCase(handlerName) .. "-Notice",
				Error = tostring(error),
				Data = tostring(error),
			})
		end, handleFn, msg)
		if not status and critical then
			local errorEvent = ARIOEvent(msg)
			-- For critical handlers we want to make sure the event data gets sent to the CU for processing, but that the memory is discarded on failures
			-- These handlers (distribute, prune) severely modify global state, and partial updates are dangerous.
			-- So we json encode the error and the event data and then throw, so the CU will discard the memory and still process the event data.
			-- An alternative approach is to modify the implementation of ao.result - to also return the Output on error.
			-- Reference: https://github.com/permaweb/ao/blob/76a618722b201430a372894b3e2753ac01e63d3d/dev-cli/src/starters/lua/ao.lua#L284-L287
			local errorWithEvent = tostring(resultOrError) .. "\n" .. errorEvent:toJSON()
			error(errorWithEvent, 0) -- 0 ensures not to include this line number in the error message
		end

		if shouldPatchHbState then
			hb.patchHyperbeamState()
		end

		msg.ioEvent:addField("Handler-Memory-KiB-Used", collectgarbage("count"), false)
		collectgarbage("collect")
		msg.ioEvent:addField("Final-Memory-KiB-Used", collectgarbage("count"), false)

		if printEvent then
			msg.ioEvent:printEvent()
		end
	end)
end

local function addSupplyData(ioEvent, supplyData)
	supplyData = supplyData or {}
	ioEvent:addField("Circulating-Supply", supplyData.circulatingSupply or LastKnownCirculatingSupply)
	ioEvent:addField("Locked-Supply", supplyData.lockedSupply or LastKnownLockedSupply)
	ioEvent:addField("Staked-Supply", supplyData.stakedSupply or LastKnownStakedSupply)
	ioEvent:addField("Delegated-Supply", supplyData.delegatedSupply or LastKnownDelegatedSupply)
	ioEvent:addField("Withdraw-Supply", supplyData.withdrawSupply or LastKnownWithdrawSupply)
	ioEvent:addField("Total-Token-Supply", supplyData.totalTokenSupply or token.lastKnownTotalTokenSupply())
	ioEvent:addField("Protocol-Balance", Balances[ao.id])
end

addEventingHandler(ActionMap.VaultedTransfer, utils.hasMatchingTag("Action", ActionMap.VaultedTransfer), function(msg)
	local recipient = msg.Tags.Recipient
	local quantity = msg.Tags.Quantity
	local lockLengthMs = msg.Tags["Lock-Length"]
	local msgId = msg.Id
	local allowUnsafeAddresses = msg.Tags["Allow-Unsafe-Addresses"] or false
	local revokable = msg.Tags.Revokable or false
	assert(utils.isValidAddress(recipient, allowUnsafeAddresses), "Invalid recipient")
	assert(
		lockLengthMs and lockLengthMs > 0 and utils.isInteger(lockLengthMs),
		"Invalid lock length. Must be integer greater than 0"
	)
	assert(
		quantity and utils.isInteger(quantity) and quantity >= constants.MIN_VAULT_SIZE,
		"Invalid quantity. Must be integer greater than or equal to " .. constants.MIN_VAULT_SIZE .. " mARIO"
	)
	assert(recipient ~= msg.From, "Cannot transfer to self")

	local vault = vaults.vaultedTransfer(
		msg.From,
		recipient,
		quantity,
		lockLengthMs,
		msg.Timestamp,
		msgId,
		allowUnsafeAddresses,
		revokable
	)

	msg.ioEvent:addField("Vault-Id", msgId)
	msg.ioEvent:addField("Vault-Balance", vault.balance)
	msg.ioEvent:addField("Vault-Start-Timestamp", vault.startTimestamp)
	msg.ioEvent:addField("Vault-End-Timestamp", vault.endTimestamp)
	if revokable then
		msg.ioEvent:addField("Vault-Controller", msg.From)
	end

	LastKnownLockedSupply = LastKnownLockedSupply + quantity
	LastKnownCirculatingSupply = LastKnownCirculatingSupply - quantity
	addSupplyData(msg.ioEvent)

	-- sender gets an immediate debit notice as the quantity is debited from their balance
	Send(msg, {
		Target = msg.From,
		Recipient = recipient,
		Quantity = tostring(quantity),
		Tags = {
			Action = "Debit-Notice",
			["Vault-Id"] = msgId,
			["Allow-Unsafe-Addresses"] = tostring(allowUnsafeAddresses),
		},
		Data = json.encode(vault),
	})
	-- to the receiver, they get a vault notice
	Send(msg, {
		Target = recipient,
		Quantity = tostring(quantity),
		Sender = msg.From,
		Tags = {
			Action = ActionMap.CreateVault .. "-Notice",
			["Vault-Id"] = msgId,
			["Allow-Unsafe-Addresses"] = tostring(allowUnsafeAddresses),
		},
		Data = json.encode(vault),
	})
end)

addEventingHandler(ActionMap.RevokeVault, utils.hasMatchingTag("Action", ActionMap.RevokeVault), function(msg)
	local vaultId = msg.Tags["Vault-Id"]
	local recipient = msg.Tags.Recipient
	assert(utils.isValidAddress(vaultId, true), "Invalid vault id")
	assert(utils.isValidAddress(recipient, true), "Invalid recipient")

	local vault = vaults.revokeVault(msg.From, recipient, vaultId, msg.Timestamp)

	msg.ioEvent:addField("Vault-Id", vaultId)
	msg.ioEvent:addField("Vault-Recipient", recipient)
	msg.ioEvent:addField("Vault-Controller", vault.controller)
	msg.ioEvent:addField("Vault-Balance", vault.balance)
	msg.ioEvent:addField("Vault-Start-Timestamp", vault.startTimestamp)
	msg.ioEvent:addField("Vault-End-Timestamp", vault.endTimestamp)

	LastKnownLockedSupply = LastKnownLockedSupply - vault.balance
	LastKnownCirculatingSupply = LastKnownCirculatingSupply + vault.balance
	addSupplyData(msg.ioEvent)

	-- to the controller, they get a credit notice
	Send(msg, {
		Target = msg.From,
		Recipient = recipient,
		Quantity = tostring(vault.balance),
		Tags = { Action = "Credit-Notice", ["Vault-Id"] = vaultId },
		Data = json.encode(vault),
	})

	-- to the receiver, they get a revoke vault notice
	Send(msg, {
		Target = recipient,
		Quantity = tostring(vault.balance),
		Sender = msg.From,
		Tags = { Action = ActionMap.RevokeVault .. "-Notice", ["Vault-Id"] = vaultId },
		Data = json.encode(vault),
	})
end)

addEventingHandler(
	ActionMap.DecreaseDelegateStake,
	utils.hasMatchingTag("Action", ActionMap.DecreaseDelegateStake),
	function(msg)
		local target = msg.Tags.Target or msg.Tags.Address
		local quantity = msg.Tags.Quantity
		local instantWithdraw = msg.Tags.Instant and msg.Tags.Instant == "true" or false
		msg.ioEvent:addField("Target-Formatted", target)
		msg.ioEvent:addField("Quantity", quantity)
		assert(
			quantity and utils.isInteger(quantity) and quantity > constants.MIN_WITHDRAWAL_AMOUNT,
			"Invalid quantity. Must be integer greater than " .. constants.MIN_WITHDRAWAL_AMOUNT
		)

		local result = gar.decreaseDelegateStake(target, msg.From, quantity, msg.Timestamp, msg.Id, instantWithdraw)
		local decreaseDelegateStakeResult = {
			penaltyRate = result and result.penaltyRate or 0,
			expeditedWithdrawalFee = result and result.expeditedWithdrawalFee or 0,
			amountWithdrawn = result and result.amountWithdrawn or 0,
		}

		msg.ioEvent:addField("Sender-New-Balance", Balances[msg.From]) -- should be unchanged

		if result ~= nil then
			local newStake = result.updatedDelegate.delegatedStake
			msg.ioEvent:addField("Previous-Stake", newStake + quantity)
			msg.ioEvent:addField("New-Stake", newStake)
			msg.ioEvent:addField("Gateway-Total-Delegated-Stake", result.gatewayTotalDelegatedStake)

			if instantWithdraw then
				msg.ioEvent:addField("Instant-Withdrawal", instantWithdraw)
				msg.ioEvent:addField("Instant-Withdrawal-Fee", result.expeditedWithdrawalFee)
				msg.ioEvent:addField("Amount-Withdrawn", result.amountWithdrawn)
				msg.ioEvent:addField("Penalty-Rate", result.penaltyRate)
			end

			local newDelegateVaults = result.updatedDelegate.vaults
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
				Quantity = tostring(quantity),
				["Penalty-Rate"] = tostring(decreaseDelegateStakeResult.penaltyRate),
				["Expedited-Withdrawal-Fee"] = tostring(decreaseDelegateStakeResult.expeditedWithdrawalFee),
				["Amount-Withdrawn"] = tostring(decreaseDelegateStakeResult.amountWithdrawn),
			},
			Data = json.encode(result and result.updatedDelegate or {}),
		})
	end
)
