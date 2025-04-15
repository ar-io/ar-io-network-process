--[[
	Allow delegates to instantly withdraw their stake from leaving gateways.

	TODO: ALLOW GATEWAY OPERATORS TO INSTANTLY WITHDRAW THEIR VAULTS, IF LEAVING, SO LONG AS THEY ARE NOT THE REQUIRED MINIMUM STAKE.

	Related PR: https://github.com/ar-io/ar-io-network-process/pull/412

	Reviewers: Dylan, Jonathon, Ariel, Phil
]]
--
local gar = require(".src.gar")
local balances = require(".src.balances")
local utils = require(".src.utils")

--- This is a local function that is used to process instant withdrawals. It must be redeclared here as it is not available in the global scope.
local function processInstantWithdrawal(stake, elapsedTimeMs, totalWithdrawalTimeMs, from)
	-- Calculate the withdrawal fee and the amount to withdraw
	local maxPenaltyRate = gar.getSettings().expeditedWithdrawals.maxExpeditedWithdrawalPenaltyRate
	local minPenaltyRate = gar.getSettings().expeditedWithdrawals.minExpeditedWithdrawalPenaltyRate
	local penaltyRateDecay = (maxPenaltyRate - minPenaltyRate) * elapsedTimeMs / totalWithdrawalTimeMs
	local penaltyRateAfterDecay = maxPenaltyRate - penaltyRateDecay
	-- the maximum rate they'll pay based on the decay
	local maximumPenaltyRate = math.min(maxPenaltyRate, penaltyRateAfterDecay)
	-- take the maximum rate between the minimum rate and the maximum rate after decay
	local floatingPenaltyRate = math.max(minPenaltyRate, maximumPenaltyRate)

	-- round to three decimal places to avoid floating point precision loss with small numbers
	local finalPenaltyRate = utils.roundToPrecision(floatingPenaltyRate, 3)
	-- round down to avoid any floating point precision loss with small numbers
	local expeditedWithdrawalFee = math.floor(stake * finalPenaltyRate)
	local amountToWithdraw = stake - expeditedWithdrawalFee

	-- Withdraw the tokens to the delegate and the protocol balance
	balances.increaseBalance(ao.id, expeditedWithdrawalFee)
	balances.increaseBalance(from, amountToWithdraw)

	return expeditedWithdrawalFee, amountToWithdraw, finalPenaltyRate
end

-- Updates the global gar scope function to allow delegate vaults to be instantly withdrawn.
function gar.instantGatewayWithdrawal(from, gatewayAddress, vaultId, currentTimestamp)
	local gateway = gar.getGateway(gatewayAddress)
	assert(gateway, "Gateway not found")

	local isGatewayWithdrawal = from == gatewayAddress
	local isGatewayProtectedVault = vaultId == gatewayAddress -- when we create the minimum staked vault, we use the gateway address as the vault id - this vault cannot be instantly withdrawn
	local vault
	local delegate
	if isGatewayWithdrawal then
		assert(gateway.vaults[vaultId], "Vault not found")
		assert(not isGatewayProtectedVault, "Gateway operator vault cannot be instantly withdrawn.")
		vault = gateway.vaults[vaultId]
	else
		delegate = gateway.delegates[from]
		assert(delegate, "Delegate not found")
		assert(delegate.vaults[vaultId], "Vault not found")
		vault = delegate.vaults[vaultId]
	end

	---@type number
	local elapsedTime = currentTimestamp - vault.startTimestamp
	---@type number
	local totalWithdrawalTime = vault.endTimestamp - vault.startTimestamp

	-- Ensure the elapsed time is not negative
	assert(elapsedTime >= 0, "Invalid elapsed time")

	-- Process the instant withdrawal
	local expeditedWithdrawalFee, amountToWithdraw, penaltyRate =
		processInstantWithdrawal(vault.balance, elapsedTime, totalWithdrawalTime, from)

	-- Remove the vault after withdrawal
	if isGatewayWithdrawal then
		gateway.vaults[vaultId] = nil
	else
		assert(delegate, "Delegate not found")
		delegate.vaults[vaultId] = nil
		-- Remove the delegate if no stake is left
		if delegate.delegatedStake == 0 and next(delegate.vaults) == nil then
			gar.pruneDelegateFromGatewayIfNecessary(from, gateway)
		end
	end

	-- Update the gateway
	GatewayRegistry[gatewayAddress] = gateway
	return {
		gateway = gateway,
		elapsedTime = elapsedTime,
		remainingTime = totalWithdrawalTime - elapsedTime,
		penaltyRate = penaltyRate,
		expeditedWithdrawalFee = expeditedWithdrawalFee,
		amountWithdrawn = amountToWithdraw,
	}
end
