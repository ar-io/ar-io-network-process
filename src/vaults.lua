Vaults = Vaults or {}

-- Utility functions that modify global Vaults object
local vaults = {}
local balances = require("balances")
local utils = require("utils")
local constants = require("constants")

function vaults.createVault(from, qty, lockLengthMs, currentTimestamp, msgId)
	if vaults.getVault(from, msgId) then
		error("Vault with id " .. msgId .. " already exists")
	end

	if lockLengthMs < constants.MIN_TOKEN_LOCK_TIME_MS or lockLengthMs > constants.MAX_TOKEN_LOCK_TIME_MS then
		error(
			"Invalid lock length. Must be between "
				.. constants.MIN_TOKEN_LOCK_TIME_MS
				.. " - "
				.. constants.MAX_TOKEN_LOCK_TIME_MS
				.. " ms"
		)
	end

	balances.reduceBalance(from, qty)
	vaults.setVault(from, msgId, {
		balance = qty,
		startTimestamp = currentTimestamp,
		endTimestamp = currentTimestamp + lockLengthMs,
	})
	return vaults.getVault(from, msgId)
end

function vaults.vaultedTransfer(from, recipient, qty, lockLengthMs, currentTimestamp, msgId)
	if balances.getBalance(from) < qty then
		error("Insufficient balance")
	end

	local vault = vaults.getVault(from, msgId)

	if vault then
		error("Vault with id " .. msgId .. " already exists")
	end

	if lockLengthMs < constants.MIN_TOKEN_LOCK_TIME_MS or lockLengthMs > constants.MAX_TOKEN_LOCK_TIME_MS then
		error(
			"Invalid lock length. Must be between "
				.. constants.MIN_TOKEN_LOCK_TIME_MS
				.. " - "
				.. constants.MAX_TOKEN_LOCK_TIME_MS
				.. " ms"
		)
	end

	balances.reduceBalance(from, qty)
	vaults.setVault(recipient, msgId, {
		balance = qty,
		startTimestamp = currentTimestamp,
		endTimestamp = currentTimestamp + lockLengthMs,
	})
	return vaults.getVault(recipient, msgId)
end

function vaults.extendVault(from, extendLengthMs, currentTimestamp, vaultId)
	local vault = vaults.getVault(from, vaultId)

	if not vault then
		error("Vault not found.")
	end

	if currentTimestamp >= vault.endTimestamp then
		error("This vault has ended.")
	end

	if extendLengthMs < 0 then
		error("Invalid extend length. Must be a positive number.")
	end

	local totalTimeRemaining = vault.endTimestamp - currentTimestamp
	local totalTimeRemainingWithExtension = totalTimeRemaining + extendLengthMs
	if totalTimeRemainingWithExtension > constants.MAX_TOKEN_LOCK_TIME_MS then
		error(
			"Invalid vault extension. Total lock time cannot be greater than "
				.. constants.MAX_TOKEN_LOCK_TIME_MS
				.. " ms"
		)
	end

	vault.endTimestamp = vault.endTimestamp + extendLengthMs
	-- update the vault
	Vaults[from][vaultId] = vault
	return vaults.getVault(from, vaultId)
end

function vaults.increaseVault(from, qty, vaultId, currentTimestamp)
	if balances.getBalance(from) < qty then
		error("Insufficient balance")
	end

	local vault = vaults.getVault(from, vaultId)

	if not vault then
		error("Invalid vault ID.")
	end

	if currentTimestamp >= vault.endTimestamp then
		error("This vault has ended.")
	end

	balances.reduceBalance(from, qty)
	vault.balance = vault.balance + qty
	-- update the vault
	Vaults[from][vaultId] = vault
	return vaults.getVault(from, vaultId)
end

function vaults.getVaults()
	local _vaults = utils.deepCopy(Vaults)
	return _vaults or {}
end

function vaults.getVault(target, id)
	local _vaults = vaults.getVaults()
	if not _vaults[target] then
		return nil
	end
	return _vaults[target][id]
end

function vaults.setVault(target, id, vault)
	-- create the top key first if not exists
	if not Vaults[target] then
		Vaults[target] = {}
	end
	-- set the vault
	Vaults[target][id] = vault
	return vault
end

-- return any vaults to owners that have expired
function vaults.pruneVaults(currentTimestamp)
	local allVaults = vaults.getVaults()
	for owner, vaults in pairs(allVaults) do
		for id, nestedVault in pairs(vaults) do
			if currentTimestamp >= nestedVault.endTimestamp then
				balances.increaseBalance(owner, nestedVault.balance)
				vaults[id] = nil
			end
		end
		-- update the owner vault
		allVaults[owner] = vaults
	end
	-- set the vaults to the updated vaults
	Vaults = allVaults
end

return vaults
