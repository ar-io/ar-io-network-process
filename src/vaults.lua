Vaults = Vaults or {}

-- Utility functions that modify global Vaults object
local vaults = {}
local balances = require("balances")
local utils = require("utils")
local constants = require("constants")

--- @type Timestamp|nil
NextBalanceVaultsPruneTimestamp = NextBalanceVaultsPruneTimestamp or 0

--- @class Vault
--- @field balance number The balance of the vault
--- @field startTimestamp number The start timestamp of the vault
--- @field endTimestamp number The end timestamp of the vault

--- @class Vaults: table<string, Vault> A table of vaults indexed by owner address

--- Creates a vault
--- @param from string The address of the owner
--- @param qty number The quantity of tokens to vault
--- @param lockLengthMs number The lock length in milliseconds
--- @param currentTimestamp number The current timestamp
--- @param vaultId string The vault id
--- @return Vault The created vault
function vaults.createVault(from, qty, lockLengthMs, currentTimestamp, vaultId)
	assert(qty > 0, "Quantity must be greater than 0")
	assert(not vaults.getVault(from, vaultId), "Vault with id " .. vaultId .. " already exists")
	assert(balances.walletHasSufficientBalance(from, qty), "Insufficient balance")
	assert(
		lockLengthMs >= constants.MIN_TOKEN_LOCK_TIME_MS and lockLengthMs <= constants.MAX_TOKEN_LOCK_TIME_MS,
		"Invalid lock length. Must be between "
			.. constants.MIN_TOKEN_LOCK_TIME_MS
			.. " - "
			.. constants.MAX_TOKEN_LOCK_TIME_MS
			.. " ms"
	)
	balances.reduceBalance(from, qty)
	local newVault = vaults.setVault(from, vaultId, {
		balance = qty,
		startTimestamp = currentTimestamp,
		endTimestamp = currentTimestamp + lockLengthMs,
	})
	vaults.scheduleNextVaultsPruning(newVault.endTimestamp)
	return newVault
end

--- Vaults a transfer
--- @param from string The address of the owner
--- @param recipient string The address of the recipient
--- @param qty number The quantity of tokens to vault
--- @param lockLengthMs number The lock length in milliseconds
--- @param currentTimestamp number The current timestamp
--- @param vaultId string The vault id
--- @param allowUnsafeAddresses boolean|nil Whether to allow unsafe addresses, since this results in funds eventually being sent to an invalid address
--- @return Vault The created vault
function vaults.vaultedTransfer(from, recipient, qty, lockLengthMs, currentTimestamp, vaultId, allowUnsafeAddresses)
	assert(utils.isValidAddress(recipient, allowUnsafeAddresses), "Invalid recipient")
	assert(qty > 0, "Quantity must be greater than 0")
	assert(recipient ~= from, "Cannot transfer to self")
	assert(balances.walletHasSufficientBalance(from, qty), "Insufficient balance")
	assert(not vaults.getVault(recipient, vaultId), "Vault with id " .. vaultId .. " already exists")
	assert(
		lockLengthMs >= constants.MIN_TOKEN_LOCK_TIME_MS and lockLengthMs <= constants.MAX_TOKEN_LOCK_TIME_MS,
		"Invalid lock length. Must be between "
			.. constants.MIN_TOKEN_LOCK_TIME_MS
			.. " - "
			.. constants.MAX_TOKEN_LOCK_TIME_MS
			.. " ms"
	)

	balances.reduceBalance(from, qty)
	local newVault = vaults.setVault(recipient, vaultId, {
		balance = qty,
		startTimestamp = currentTimestamp,
		endTimestamp = currentTimestamp + lockLengthMs,
	})
	return newVault
end

--- Extends a vault
--- @param from string The address of the owner
--- @param extendLengthMs number The extension length in milliseconds
--- @param currentTimestamp number The current timestamp
--- @param vaultId string The vault id
--- @return Vault The extended vault
function vaults.extendVault(from, extendLengthMs, currentTimestamp, vaultId)
	local vault = vaults.getVault(from, vaultId)
	assert(vault, "Vault not found.")
	assert(currentTimestamp <= vault.endTimestamp, "Vault has ended.")
	assert(extendLengthMs > 0, "Invalid extend length. Must be a positive number.")

	local totalTimeRemaining = vault.endTimestamp - currentTimestamp
	local totalTimeRemainingWithExtension = totalTimeRemaining + extendLengthMs
	assert(
		totalTimeRemainingWithExtension <= constants.MAX_TOKEN_LOCK_TIME_MS,
		"Invalid vault extension. Total lock time cannot be greater than " .. constants.MAX_TOKEN_LOCK_TIME_MS .. " ms"
	)

	vault.endTimestamp = vault.endTimestamp + extendLengthMs
	Vaults[from][vaultId] = vault

	--- The NextPruneTimestamp might have been from this vault, but figuring out which one
	--- comes next is a linear walk of the vaults anyway, so just leave it as is and the next
	--- prune will figure it out.
	return vault
end

--- Increases a vault
--- @param from string The address of the owner
--- @param qty number The quantity of tokens to increase the vault by
--- @param vaultId string The vault id
--- @param currentTimestamp number The current timestamp
--- @return Vault The increased vault
function vaults.increaseVault(from, qty, vaultId, currentTimestamp)
	assert(qty > 0, "Quantity must be greater than 0")
	assert(balances.walletHasSufficientBalance(from, qty), "Insufficient balance")

	local vault = vaults.getVault(from, vaultId)
	assert(vault, "Vault not found.")
	assert(currentTimestamp <= vault.endTimestamp, "Vault has ended.")

	balances.reduceBalance(from, qty)
	vault.balance = vault.balance + qty
	Vaults[from][vaultId] = vault
	return vault
end

--- Gets all vaults
--- @return Vaults The vaults
function vaults.getVaults()
	return utils.deepCopy(Vaults) or {}
end

function vaults.getVaultsUnsafe()
	return Vaults or {}
end

--- @class WalletVault
--- @field address string - the wallet address that owns the vault
--- @field vaultId string - the unique id of the vault
--- @field startTimestamp number - the timestamp in ms of the vault started
--- @field endTimestamp number - the ending timestamp of the vault
--- @field balance number - the number of mARIO stored in the vault

--- Gets all paginated vaults
--- @param cursor string|nil The address to start from
--- @param limit number Max number of results to return
--- @param sortOrder string "asc" or "desc" sort direction
--- @param sortBy string|nil "address", "vaultId", "balance", "startTimestamp", "endTimestamp" field to sort by
--- @return WalletVault[] - array of wallet vaults indexed by address and vault id
function vaults.getPaginatedVaults(cursor, limit, sortOrder, sortBy)
	local allVaults = vaults.getVaultsUnsafe()
	local cursorField = "address" -- the cursor will be the wallet address

	local vaultsArray = utils.reduce(allVaults, function(acc, address, vaultsForAddress)
		for vaultId, vault in pairs(vaultsForAddress) do
			table.insert(acc, {
				address = address,
				vaultId = vaultId,
				balance = vault.balance,
				startTimestamp = vault.startTimestamp,
				endTimestamp = vault.endTimestamp,
			})
		end
		return acc
	end, {})

	return utils.paginateTableWithCursor(vaultsArray, cursor, cursorField, limit, sortBy or "address", sortOrder)
end

--- Gets a vault
--- @param target string The address of the owner
--- @param id string The vault id
--- @return Vault| nil The vault
function vaults.getVault(target, id)
	return Vaults[target] and Vaults[target][id]
end

--- Sets a vault
--- @param target string The address of the owner
--- @param id string The vault id
--- @param vault Vault The vault
--- @return Vault The vault
function vaults.setVault(target, id, vault)
	-- create the top key first if not exists
	if not Vaults[target] then
		Vaults[target] = {}
	end
	-- set the vault
	Vaults[target][id] = vault
	return vault
end

--- Prunes expired vaults
--- @param currentTimestamp number The current timestamp
--- @return Vault[] The pruned vaults
function vaults.pruneVaults(currentTimestamp)
	if not NextBalanceVaultsPruneTimestamp or currentTimestamp < NextBalanceVaultsPruneTimestamp then
		-- No known pruning work to do
		return {}
	end

	local allVaults = vaults.getVaults()
	local prunedVaults = {}
	--- @type Timestamp|nil
	local minNextEndTimestamp
	for owner, ownersVaults in pairs(allVaults) do
		for id, nestedVault in pairs(ownersVaults) do
			if currentTimestamp >= nestedVault.endTimestamp then
				balances.increaseBalance(owner, nestedVault.balance)
				ownersVaults[id] = nil
				prunedVaults[id] = nestedVault
			else
				--- find the next prune timestamp
				minNextEndTimestamp =
					math.min(minNextEndTimestamp or nestedVault.endTimestamp, nestedVault.endTimestamp)
			end
		end
	end

	-- Reset the pruning timestamp
	NextBalanceVaultsPruneTimestamp = nil
	if minNextEndTimestamp then
		vaults.scheduleNextVaultsPruning(minNextEndTimestamp)
	end

	-- set the vaults to the updated vaults
	Vaults = allVaults
	return prunedVaults
end

--- @param timestamp Timestamp
function vaults.scheduleNextVaultsPruning(timestamp)
	-- A nil NextPruneTimestamp means we're not expecting anything to prune, so set it if necessary
	-- Otherwise, this new endTimestamp might be earlier than the next known for pruning. If so, set it.
	NextBalanceVaultsPruneTimestamp = math.min(NextBalanceVaultsPruneTimestamp or timestamp, timestamp)
end

function vaults.nextVaultsPruneTimestamp()
	return NextBalanceVaultsPruneTimestamp
end

return vaults
