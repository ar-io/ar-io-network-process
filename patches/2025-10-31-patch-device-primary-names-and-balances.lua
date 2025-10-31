--[[
	1. Set up HyperbeamSync table
	2. copy balances in the prune handler and store in the HyperbeamSync table
	3. Record primary names changes in primary names module and send patch message for them
	4. Sends one single patch message instead of multiple

	Reviewers: Dylan, Ariel, Atticus
]]
--

--[[
	HyperbeamSync is a table that is used to track changes to our lua state that need to be synced to the Hyperbeam.
	the principle of using it is to set the key:value pairs that need to be synced, then
	the patch function will pull that from the global state to build the patch message.
	After, the HyperbeamSync table is cleared and the next message run will start fresh.
]]
HyperbeamSync = HyperbeamSync
	or {
		balances = {},
		primaryNames = {
			---@type table<string, boolean> addresses that have had name changes
			names = {},
			---@type table<string, boolean> addresses that have had owner changes
			owners = {},
			---@type table<string, boolean> addresses that have had request changes
			requests = {},
		},
	}

-- module: ".src.hb"
local function _loaded_mod_src_hb()
	-- hb.lua needs to be in its own file and not in balances.lua to avoid circular dependencies
	local hb = {}

	---@return table<string, string>|nil affectedBalancesAddresses table of addresses and their balance values as strings
	function hb.createBalancesPatch()
		local affectedBalancesAddresses = {}
		for address, _ in pairs(Balances) do
			if HyperbeamSync.balances[address] ~= Balances[address] then
				affectedBalancesAddresses[address] = true
			end
		end

		for address, _ in pairs(HyperbeamSync.balances) do
			if Balances[address] ~= HyperbeamSync.balances[address] then
				affectedBalancesAddresses[address] = true
			end
		end

		--- For simplicity we always include the protocol balance in the patch message
		--- this also prevents us from sending an empty patch message and deleting the entire hyperbeam balances table
		affectedBalancesAddresses[ao.id] = true

		-- Convert all affected addresses from boolean flags to actual balance values
		local balancesPatch = {}
		for address, _ in pairs(affectedBalancesAddresses) do
			balancesPatch[address] = tostring(Balances[address] or 0)
		end

		if next(balancesPatch) == nil then
			return nil
		end

		return balancesPatch
	end

	---@return PrimaryNames|nil affectedPrimaryNamesAddresses
	function hb.createPrimaryNamesPatch()
		---@type PrimaryNames
		local affectedPrimaryNamesAddresses = {
			names = {},
			owners = {},
			requests = {},
		}

		-- if no changes, return early. This will allow downstream code to not send the patch state for this key ('primary-names')
		if
			next(_G.HyperbeamSync.primaryNames.names) == nil
			and next(_G.HyperbeamSync.primaryNames.owners) == nil
			and next(_G.HyperbeamSync.primaryNames.requests) == nil
		then
			return nil
		end

		-- build the affected primary names addresses table for the patch message
		for name, _ in pairs(_G.HyperbeamSync.primaryNames.names) do
			-- we need to send an empty string to remove the name
			affectedPrimaryNamesAddresses.names[name] = PrimaryNames.names[name] or ""
		end
		for owner, _ in pairs(_G.HyperbeamSync.primaryNames.owners) do
			-- we need to send an empty table to remove the owner primary name data
			affectedPrimaryNamesAddresses.owners[owner] = PrimaryNames.owners[owner] or {}
		end
		for address, _ in pairs(_G.HyperbeamSync.primaryNames.requests) do
			-- we need to send an empty table to remove the request
			affectedPrimaryNamesAddresses.requests[address] = PrimaryNames.requests[address] or {}
		end

		-- Setting the property to {} will nuke the entire table from patch device state
		-- We do this because we want to remove the entire table from patch device state if it's empty
		if next(PrimaryNames.names) == nil then
			affectedPrimaryNamesAddresses.names = {}
		-- setting the property to nil will remove it from the patch message entirely to avoid sending an empty table and nuking patch device state
		-- We do this to AVOID sending an empty table and nuking patch device state if our lua state is not empty.
		elseif next(affectedPrimaryNamesAddresses.names) == nil then
			affectedPrimaryNamesAddresses.names = nil
		end

		if next(PrimaryNames.owners) == nil then
			affectedPrimaryNamesAddresses.owners = {}
		elseif next(affectedPrimaryNamesAddresses.owners) == nil then
			affectedPrimaryNamesAddresses.owners = nil
		end

		if next(PrimaryNames.requests) == nil then
			affectedPrimaryNamesAddresses.requests = {}
		elseif next(affectedPrimaryNamesAddresses.requests) == nil then
			affectedPrimaryNamesAddresses.requests = nil
		end

		-- if we're not sending any data, return nil which will allow downstream code to not send the patch message
		-- We do this to AVOID sending an empty table and nuking patch device state if our lua state is not empty.
		if next(affectedPrimaryNamesAddresses) == nil then
			return nil
		end

		return affectedPrimaryNamesAddresses
	end

	function hb.resetHyperbeamSync()
		HyperbeamSync = {
			balances = {},
			primaryNames = {
				names = {},
				owners = {},
				requests = {},
			},
		}
	end

	--[[
	1. Create the data patches
	2. Send the patch message if there are any data patches
	3. Reset the hyperbeam sync
]]
	function hb.patchHyperbeamState()
		local patchMessageFields = {}

		-- Only add patches that have data
		local primaryNamesPatch = hb.createPrimaryNamesPatch()
		if primaryNamesPatch then
			patchMessageFields["primary-names"] = primaryNamesPatch
		end

		local balancesPatch = hb.createBalancesPatch()
		if balancesPatch then
			patchMessageFields["balances"] = balancesPatch
		end

		--- Send patch message if there are any patches
		if next(patchMessageFields) ~= nil then
			patchMessageFields.device = "patch@1.0"
			ao.send(patchMessageFields)
		end

		hb.resetHyperbeamSync()
	end

	return hb
end

_G.package.loaded[".src.hb"] = _loaded_mod_src_hb()

-- module: ".src.primary_names"
local function _loaded_mod_src_primary_names()
	local arns = require(".src.arns")
	local balances = require(".src.balances")
	local utils = require(".src.utils")
	local gar = require(".src.gar")
	local constants = require(".src.constants")
	local demand = require(".src.demand")
	local primaryNames = {}

	--- @alias WalletAddress string
	--- @alias ArNSName string

	--- @class PrimaryNames
	--- @field owners table<WalletAddress, PrimaryName> - map indexed by owner address containing the primary name and all metadata, used for reverse lookups
	--- @field names table<ArNSName, WalletAddress> - map indexed by primary name containing the owner address, used for reverse lookups
	--- @field requests table<WalletAddress, PrimaryNameRequest> - map indexed by owner address containing the request, used for pruning expired requests

	--- @class PrimaryName
	--- @field name ArNSName
	--- @field startTimestamp number

	--- @class PrimaryNameWithOwner
	--- @field name ArNSName
	--- @field owner WalletAddress
	--- @field startTimestamp number

	--- @class PrimaryNameInfo
	--- @field name ArNSName
	--- @field owner WalletAddress
	--- @field startTimestamp number
	--- @field processId WalletAddress

	--- @class PrimaryNameRequest
	--- @field name ArNSName -- the name being requested
	--- @field startTimestamp number -- the timestamp of the request
	--- @field endTimestamp number -- the timestamp of the request expiration

	--- @class CreatePrimaryNameResult
	--- @field request PrimaryNameRequest|nil
	--- @field newPrimaryName PrimaryNameWithOwner|nil
	--- @field baseNameOwner WalletAddress
	--- @field fundingPlan table
	--- @field fundingResult table
	--- @field demandFactor table
	---
	-- NOTE: lua 5.3 has limited regex support, particularly for lookaheads and negative lookaheads or use of {n}
	---@param name string
	---@description Asserts that the provided name is a valid undername
	---@example
	---```lua
	---utils.assertValidateUndername("my-undername")
	---```
	function primaryNames.assertValidUndername(name)
		--- RULES FOR UNDERNAMES
		--- min 1 char
		--- max 61 chars
		--- no starting dashes or underscores
		--- alphanumeric, dashes, underscores OR one '@' sign

		local validLength = #name <= constants.MAX_UNDERNAME_LENGTH
		assert(validLength, "Undername is too long, recieved length of " .. tostring(#name))
		local validRegex = string.match(name, constants.ARNS_NAME_SINGLE_CHAR_REGEX) ~= nil
			or string.match(name, constants.UNDERNAME_REGEX) ~= nil
		local valid = validLength and validRegex
		assert(valid, "Invalid undername " .. name)
	end

	--- Asserts that a name is a valid Primary name
	--- Validates the undername and base name
	--- @param name string The name to check
	function primaryNames.assertValidPrimaryName(name)
		assert(name and type(name) == "string", "Name is required and must be a string.")

		assert(
			#name <= constants.MAX_PRIMARY_NAME_LENGTH,
			"Primary Name with length "
				.. #name
				.. " exceeds maximum allowable length of "
				.. constants.MAX_PRIMARY_NAME_LENGTH
		)

		local baseName = utils.baseNameForName(name)
		arns.assertValidArNSName(baseName)
		local undername = utils.undernameForName(name)
		if undername then
			primaryNames.assertValidUndername(undername)
		end
	end

	--- Creates a transient request for a primary name. This is done by a user and must be approved by the name owner of the base name.
	--- @param name string -- the name being requested, this could be an undername and should always be lower case
	--- @param initiator WalletAddress -- the address that is creating the primary name request, e.g. the ANT process id
	--- @param timestamp number -- the timestamp of the request
	--- @param msgId string -- the message id of the request
	--- @param fundFrom "balance"|"stakes"|"any"|nil -- the address to fund the request from. Default is "balance"
	--- @return CreatePrimaryNameResult # the request created, or the primary name with owner data if the request is approved
	function primaryNames.createPrimaryNameRequest(name, initiator, timestamp, msgId, fundFrom)
		fundFrom = fundFrom or "balance"

		primaryNames.assertValidPrimaryName(name)

		name = string.lower(name)
		local baseName = utils.baseNameForName(name)

		--- check the primary name request for the initiator does not already exist for the same name
		--- this allows the caller to create a new request and pay the fee again, so long as it is for a different name
		local existingRequest = primaryNames.getPrimaryNameRequest(initiator)
		assert(
			not existingRequest or existingRequest.name ~= name,
			"Primary name request by '" .. initiator .. "' for '" .. name .. "' already exists"
		)

		--- check the primary name is not already owned
		local primaryNameOwner = primaryNames.getAddressForPrimaryName(name)
		assert(not primaryNameOwner, "Primary name is already owned")

		local record = arns.getRecord(baseName)
		assert(record, "ArNS record '" .. baseName .. "' does not exist")
		assert(arns.recordIsActive(record, timestamp), "ArNS record '" .. baseName .. "' is not active")

		local requestCost = arns.getTokenCost({
			intent = "Primary-Name-Request",
			name = name,
			currentTimestamp = timestamp,
			record = record,
		})

		local fundingPlan = gar.getFundingPlan(initiator, requestCost.tokenCost, fundFrom)
		assert(fundingPlan and fundingPlan.shortfall == 0, "Insufficient balances")
		local fundingResult = gar.applyFundingPlan(fundingPlan, msgId, timestamp)
		assert(fundingResult.totalFunded == requestCost.tokenCost, "Funding plan application failed")

		--- transfer the primary name cost from the initiator to the protocol balance
		balances.increaseBalance(ao.id, requestCost.tokenCost)
		demand.tallyNamePurchase(requestCost.tokenCost)

		local request = {
			name = name,
			startTimestamp = timestamp,
			endTimestamp = timestamp + constants.PRIMARY_NAME_REQUEST_DURATION_MS,
		}

		--- if the initiator is base name owner, then just set the primary name and return
		local newPrimaryName
		if record.processId == initiator then
			newPrimaryName = primaryNames.setPrimaryNameFromRequest(initiator, request, timestamp)
		else
			-- otherwise store the request for asynchronous approval
			PrimaryNames.requests[initiator] = request
			-- track the changes in the hyperbeam sync
			HyperbeamSync.primaryNames.requests[initiator] = true
			primaryNames.scheduleNextPrimaryNamesPruning(request.endTimestamp)
		end

		return {
			request = request,
			newPrimaryName = newPrimaryName,
			baseNameOwner = record.processId,
			fundingPlan = fundingPlan,
			fundingResult = fundingResult,
			demandFactor = demand.getDemandFactorInfo(),
		}
	end

	--- Get a primary name request, safely deep copying the request
	--- @param address WalletAddress
	--- @return PrimaryNameRequest|nil primaryNameClaim - the request found, or nil if it does not exist
	function primaryNames.getPrimaryNameRequest(address)
		return utils.deepCopy(primaryNames.getUnsafePrimaryNameRequests()[address])
	end

	--- Unsafe access to the primary name requests
	--- @return table<WalletAddress, PrimaryNameRequest> primaryNameClaims - the primary name requests
	function primaryNames.getUnsafePrimaryNameRequests()
		return PrimaryNames.requests or {}
	end

	function primaryNames.getUnsafePrimaryNames()
		return PrimaryNames.names or {}
	end

	--- Unsafe access to the primary name owners
	--- @return table<WalletAddress, PrimaryName> primaryNames - the primary names
	function primaryNames.getUnsafePrimaryNameOwners()
		return PrimaryNames.owners or {}
	end

	--- @class PrimaryNameRequestApproval
	--- @field newPrimaryName PrimaryNameWithOwner
	--- @field request PrimaryNameRequest

	--- Action taken by the owner of a primary name. This is who pays for the primary name.
	--- @param recipient string -- the address that is requesting the primary name
	--- @param from string -- the process id that is requesting the primary name for the owner
	--- @param timestamp number -- the timestamp of the request
	--- @return PrimaryNameRequestApproval # the primary name with owner data and original request
	function primaryNames.approvePrimaryNameRequest(recipient, name, from, timestamp)
		local request = primaryNames.getPrimaryNameRequest(recipient)
		assert(request, "Primary name request not found")
		assert(request.endTimestamp > timestamp, "Primary name request has expired")
		assert(name == request.name, "Provided name does not match the primary name request")

		-- assert the process id in the initial request still owns the name
		local baseName = utils.baseNameForName(request.name)
		local record = arns.getRecord(baseName)
		assert(record, "ArNS record '" .. baseName .. "' does not exist")
		assert(record.processId == from, "Primary name request must be approved by the owner of the base name")

		-- set the primary name
		local newPrimaryName = primaryNames.setPrimaryNameFromRequest(recipient, request, timestamp)

		return {
			newPrimaryName = newPrimaryName,
			request = request,
		}
	end

	--- Update the primary name maps and return the primary name. Removes the request from the requests map.
	--- @param recipient string -- the address that is requesting the primary name
	--- @param request PrimaryNameRequest
	--- @param startTimestamp number
	--- @return PrimaryNameWithOwner # the primary name with owner data
	function primaryNames.setPrimaryNameFromRequest(recipient, request, startTimestamp)
		--- if the owner has an existing primary name, make sure we remove it from the maps before setting the new one
		local existingPrimaryName = primaryNames.getPrimaryNameDataWithOwnerFromAddress(recipient)
		if existingPrimaryName then
			primaryNames.removePrimaryName(existingPrimaryName.name, recipient)
		end
		PrimaryNames.names[request.name] = recipient
		PrimaryNames.owners[recipient] = {
			name = request.name,
			startTimestamp = startTimestamp,
		}
		PrimaryNames.requests[recipient] = nil

		-- track the changes in the hyperbeam sync
		HyperbeamSync.primaryNames.names[request.name] = true
		HyperbeamSync.primaryNames.owners[recipient] = true
		HyperbeamSync.primaryNames.requests[recipient] = true

		return {
			name = request.name,
			owner = recipient,
			startTimestamp = startTimestamp,
		}
	end

	--- @class RemovedPrimaryNameResult
	--- @field name string
	--- @field owner WalletAddress

	--- Remove primary names, returning the results of the name removals
	--- @param names string[]
	--- @param from string
	--- @return RemovedPrimaryNameResult[] removedPrimaryNameResults - the results of the name removals
	function primaryNames.removePrimaryNames(names, from)
		local removedPrimaryNamesAndOwners = {}
		for _, name in pairs(names) do
			local removedPrimaryNameAndOwner = primaryNames.removePrimaryName(name, from)
			-- track the changes in the hyperbeam sync
			HyperbeamSync.primaryNames.names[name] = true
			HyperbeamSync.primaryNames.owners[removedPrimaryNameAndOwner.owner] = true

			table.insert(removedPrimaryNamesAndOwners, removedPrimaryNameAndOwner)
		end
		return removedPrimaryNamesAndOwners
	end

	--- Release a primary name
	--- @param name ArNSName -- the name being released
	--- @param from WalletAddress -- the address that is releasing the primary name, or the owner of the base name
	--- @return RemovedPrimaryNameResult
	function primaryNames.removePrimaryName(name, from)
		--- assert the from is the current owner of the name
		local primaryName = primaryNames.getPrimaryNameDataWithOwnerFromName(name)
		assert(primaryName, "Primary name '" .. name .. "' does not exist")
		local baseName = utils.baseNameForName(name)
		local record = arns.getRecord(baseName)
		assert(
			primaryName.owner == from or (record and record.processId == from),
			"Caller is not the owner of the primary name, or the owner of the " .. baseName .. " record"
		)

		PrimaryNames.names[name] = nil
		PrimaryNames.owners[primaryName.owner] = nil
		if PrimaryNames.requests[primaryName.owner] and PrimaryNames.requests[primaryName.owner].name == name then
			PrimaryNames.requests[primaryName.owner] = nil
		end

		-- track the changes in the hyperbeam sync
		HyperbeamSync.primaryNames.names[name] = true
		HyperbeamSync.primaryNames.owners[primaryName.owner] = true
		HyperbeamSync.primaryNames.requests[primaryName.owner] = true

		return {
			name = name,
			owner = primaryName.owner,
		}
	end

	--- Get the address for a primary name, allowing for forward lookups (e.g. "foo.bar" -> "0x123")
	--- @param name string
	--- @return WalletAddress|nil address -- the address for the primary name, or nil if it does not exist
	function primaryNames.getAddressForPrimaryName(name)
		return PrimaryNames.names[name]
	end

	--- Get the name data for an address, allowing for reverse lookups (e.g. "0x123" -> "foo.bar")
	--- @param address string
	--- @return PrimaryNameInfo|nil -- the primary name with owner data, or nil if it does not exist
	function primaryNames.getPrimaryNameDataWithOwnerFromAddress(address)
		local nameData = PrimaryNames.owners[address]

		if not nameData then
			return nil
		end
		return {

			owner = address,
			name = nameData.name,
			startTimestamp = nameData.startTimestamp,
			processId = arns.getProcessIdForRecord(utils.baseNameForName(nameData.name)),
		}
	end

	--- Complete name resolution, returning the owner and name data for a name
	--- @param name string
	--- @return PrimaryNameInfo|nil - the primary name with owner data and processId, or nil if it does not exist
	function primaryNames.getPrimaryNameDataWithOwnerFromName(name)
		local owner = primaryNames.getAddressForPrimaryName(name)
		if not owner then
			return nil
		end
		local nameData = primaryNames.getPrimaryNameDataWithOwnerFromAddress(owner)
		if not nameData then
			return nil
		end
		return nameData
	end

	---Finds all primary names with a given base  name
	--- @param baseName string -- the base name to find primary names for (e.g. "test" to find "undername_test")
	--- @return PrimaryNameWithOwner[] primaryNamesForArNSName - the primary names with owner data
	function primaryNames.getPrimaryNamesForBaseName(baseName)
		local primaryNamesForArNSName = {}
		for name, _ in pairs(primaryNames.getUnsafePrimaryNames()) do
			local nameData = primaryNames.getPrimaryNameDataWithOwnerFromName(name)
			if nameData and utils.baseNameForName(name) == baseName then
				table.insert(primaryNamesForArNSName, nameData)
			end
		end
		-- sort by name length
		table.sort(primaryNamesForArNSName, function(a, b)
			return #a.name < #b.name
		end)
		return primaryNamesForArNSName
	end

	--- @class RemovedPrimaryName
	--- @field owner WalletAddress
	--- @field name ArNSName

	--- Remove all primary names with a given base name
	--- @param baseName string
	--- @return RemovedPrimaryName[] removedPrimaryNames - the results of the name removals
	function primaryNames.removePrimaryNamesForBaseName(baseName)
		local removedNames = {}
		local primaryNamesForBaseName = primaryNames.getPrimaryNamesForBaseName(baseName)
		for _, nameData in pairs(primaryNamesForBaseName) do
			local removedName = primaryNames.removePrimaryName(nameData.name, nameData.owner)
			-- track the changes in the hyperbeam sync
			HyperbeamSync.primaryNames.names[nameData.name] = true
			HyperbeamSync.primaryNames.owners[nameData.owner] = true
			table.insert(removedNames, removedName)
		end
		return removedNames
	end

	--- Get paginated primary names
	--- @param cursor string|nil
	--- @param limit number
	--- @param sortBy string
	--- @param sortOrder string
	--- @return PaginatedTable<PrimaryNameWithOwner> paginatedPrimaryNames - the paginated primary names
	function primaryNames.getPaginatedPrimaryNames(cursor, limit, sortBy, sortOrder)
		local primaryNamesArray = {}
		local cursorField = "name"
		for owner, primaryName in pairs(primaryNames.getUnsafePrimaryNameOwners()) do
			table.insert(primaryNamesArray, {
				name = primaryName.name,
				owner = owner,
				startTimestamp = primaryName.startTimestamp,
				processId = arns.getProcessIdForRecord(utils.baseNameForName(primaryName.name)),
			})
		end
		return utils.paginateTableWithCursor(primaryNamesArray, cursor, cursorField, limit, sortBy, sortOrder)
	end

	--- Get paginated primary name requests
	--- @param cursor string|nil
	--- @param limit number
	--- @param sortBy string
	--- @param sortOrder string
	--- @return PaginatedTable<PrimaryNameRequest> paginatedPrimaryNameRequests - the paginated primary name requests
	function primaryNames.getPaginatedPrimaryNameRequests(cursor, limit, sortBy, sortOrder)
		local primaryNameRequestsArray = {}
		local cursorField = "initiator"
		for initiator, request in pairs(primaryNames.getUnsafePrimaryNameRequests()) do
			table.insert(primaryNameRequestsArray, {
				name = request.name,
				startTimestamp = request.startTimestamp,
				endTimestamp = request.endTimestamp,
				initiator = initiator,
			})
		end
		return utils.paginateTableWithCursor(primaryNameRequestsArray, cursor, cursorField, limit, sortBy, sortOrder)
	end

	--- Prune expired primary name requests
	--- @param timestamp number
	--- @return table<string, PrimaryNameRequest> prunedNameClaims - the names of the requests that were pruned
	function primaryNames.prunePrimaryNameRequests(timestamp)
		local prunedNameRequests = {}
		if not NextPrimaryNamesPruneTimestamp or timestamp < NextPrimaryNamesPruneTimestamp then
			-- No known requests to prune
			return prunedNameRequests
		end

		-- reset the next prune timestamp, below will populate it with the next prune timestamp minimum
		NextPrimaryNamesPruneTimestamp = nil

		for initiator, request in pairs(primaryNames.getUnsafePrimaryNameRequests()) do
			if request.endTimestamp <= timestamp then
				PrimaryNames.requests[initiator] = nil
				prunedNameRequests[initiator] = request

				-- track the changes in the hyperbeam sync
				HyperbeamSync.primaryNames.requests[initiator] = true
			else
				primaryNames.scheduleNextPrimaryNamesPruning(request.endTimestamp)
			end
		end
		return prunedNameRequests
	end

	--- @param timestamp Timestamp
	function primaryNames.scheduleNextPrimaryNamesPruning(timestamp)
		NextPrimaryNamesPruneTimestamp = math.min(NextPrimaryNamesPruneTimestamp or timestamp, timestamp)
	end

	function primaryNames.nextPrimaryNamesPruneTimestamp()
		return NextPrimaryNamesPruneTimestamp
	end

	return primaryNames
end

_G.package.loaded[".src.primary_names"] = _loaded_mod_src_primary_names()

-- module: ".src.main"
local function _loaded_mod_src_main()
	local main = {}
	local constants = require(".src.constants")
	local token = require(".src.token")
	local utils = require(".src.utils")
	local json = require(".src.json")
	local balances = require(".src.balances")
	local hb = require(".src.hb")
	local arns = require(".src.arns")
	local gar = require(".src.gar")
	local demand = require(".src.demand")
	local epochs = require(".src.epochs")
	local vaults = require(".src.vaults")
	local prune = require(".src.prune")
	local tick = require(".src.tick")
	local primaryNames = require(".src.primary_names")
	local ARIOEvent = require(".src.ario_event")

	-- handlers that are critical should discard the memory on error (see prune for an example)
	local CRITICAL = true

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

	--- @param msg ParsedMessage
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
	--- @param rewardForInitiator number|nil only applies in buy record for returned names
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

	--- @param ioEvent ARIOEvent
	--- @param result BuyNameResult|RecordInteractionResult|CreatePrimaryNameResult|PrimaryNameRequestApproval
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
		adjustSuppliesForFundingPlan(result.fundingPlan, result.returnedName and result.returnedName.rewardForInitiator)
	end

	--- @param ioEvent ARIOEvent
	---@param result RecordInteractionResult|BuyNameResult
	local function addRecordResultFields(ioEvent, result)
		ioEvent:addFieldsIfExist(result, {
			"baseRegistrationFee",
			"remainingBalance",
			"protocolBalance",
			"recordsCount",
			"reservedRecordsCount",
			"totalFee",
		})
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

	local function addReturnedNameResultFields(ioEvent, result)
		ioEvent:addFieldsIfExist(result, {
			"rewardForInitiator",
			"rewardForProtocol",
			"type",
			"years",
		})
		ioEvent:addFieldsIfExist(result.record, { "startTimestamp", "endTimestamp", "undernameLimit", "purchasePrice" })
		ioEvent:addFieldsIfExist(result.returnedName, {
			"name",
			"initiator",
			"startTimestamp",
		})
		-- TODO: add removedPrimaryNamesAndOwners to ioEvent
		addResultFundingPlanFields(ioEvent, result)
	end

	--- @class SupplyData
	--- @field circulatingSupply number|nil
	--- @field lockedSupply number|nil
	--- @field stakedSupply number|nil
	--- @field delegatedSupply number|nil
	--- @field withdrawSupply number|nil
	--- @field totalTokenSupply number|nil
	--- @field protocolBalance number|nil

	--- @param ioEvent ARIOEvent
	--- @param supplyData SupplyData|nil
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

	--- @param ioEvent ARIOEvent
	--- @param talliesData StateObjectTallies|GatewayObjectTallies|nil
	local function addTalliesData(ioEvent, talliesData)
		ioEvent:addFieldsIfExist(talliesData, {
			"numAddressesVaulting",
			"numBalanceVaults",
			"numBalances",
			"numDelegateVaults",
			"numDelegatesVaulting",
			"numDelegates",
			"numDelegations",
			"numExitingDelegations",
			"numGatewayVaults",
			"numGatewaysVaulting",
			"numGateways",
			"numExitingGateways",
		})
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

	--- @param ioEvent ARIOEvent
	--- @param pruneGatewaysResult PruneGatewaysResult
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

		addTalliesData(ioEvent, pruneGatewaysResult.gatewayObjectTallies)
	end

	--- @param ioEvent ARIOEvent
	local function addNextPruneTimestampsData(ioEvent)
		ioEvent:addField("Next-Returned-Names-Prune-Timestamp", arns.nextReturnedNamesPruneTimestamp())
		ioEvent:addField("Next-Records-Prune-Timestamp", arns.nextRecordsPruneTimestamp())
		ioEvent:addField("Next-Vaults-Prune-Timestamp", vaults.nextVaultsPruneTimestamp())
		ioEvent:addField("Next-Gateways-Prune-Timestamp", gar.nextGatewaysPruneTimestamp())
		ioEvent:addField("Next-Redelegations-Prune-Timestamp", gar.nextRedelegationsPruneTimestamp())
		ioEvent:addField("Next-Primary-Names-Prune-Timestamp", primaryNames.nextPrimaryNamesPruneTimestamp())
	end

	--- @param ioEvent ARIOEvent
	--- @param prunedStateResult PruneStateResult
	local function addNextPruneTimestampsResults(ioEvent, prunedStateResult)
		--- @type PruneGatewaysResult
		local pruneGatewaysResult = prunedStateResult.pruneGatewaysResult

		-- If anything meaningful was pruned, collect the next prune timestamps
		if
			next(prunedStateResult.prunedReturnedNames)
			or next(prunedStateResult.prunedPrimaryNameRequests)
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
			addNextPruneTimestampsData(ioEvent)
		end
	end

	local function assertValidFundFrom(fundFrom)
		if fundFrom == nil then
			return
		end
		local validFundFrom = utils.createLookupTable({ "any", "balance", "stakes" })
		assert(validFundFrom[fundFrom], "Invalid fund from type. Must be one of: any, balance, stakes")
	end

	--- @param ioEvent ARIOEvent
	local function addPrimaryNameCounts(ioEvent)
		ioEvent:addField("Total-Primary-Names", utils.lengthOfTable(primaryNames.getUnsafePrimaryNames()))
		ioEvent:addField(
			"Total-Primary-Name-Requests",
			utils.lengthOfTable(primaryNames.getUnsafePrimaryNameRequests())
		)
	end

	--- @param ioEvent ARIOEvent
	--- @param primaryNameResult CreatePrimaryNameResult|PrimaryNameRequestApproval
	local function addPrimaryNameRequestData(ioEvent, primaryNameResult)
		ioEvent:addFieldsIfExist(primaryNameResult, { "baseNameOwner" })
		ioEvent:addFieldsIfExist(primaryNameResult.newPrimaryName, { "owner", "startTimestamp" })
		ioEvent:addFieldsWithPrefixIfExist(primaryNameResult.request, "Request-", { "startTimestamp", "endTimestamp" })
		addResultFundingPlanFields(ioEvent, primaryNameResult)
		addPrimaryNameCounts(ioEvent)

		-- demand factor data
		if primaryNameResult.demandFactor and type(primaryNameResult.demandFactor) == "table" then
			ioEvent:addField(
				"DF-Trailing-Period-Purchases",
				(primaryNameResult.demandFactor.trailingPeriodPurchases or {})
			)
			ioEvent:addField(
				"DF-Trailing-Period-Revenues",
				(primaryNameResult.demandFactor.trailingPeriodRevenues or {})
			)
			ioEvent:addFieldsWithPrefixIfExist(primaryNameResult.demandFactor, "DF-", {
				"currentPeriod",
				"currentDemandFactor",
				"consecutivePeriodsWithMinDemandFactor",
				"revenueThisPeriod",
				"purchasesThisPeriod",
			})
		end
	end

	local function assertValueBytesLowerThan(value, remainingBytes, tablesSeen)
		tablesSeen = tablesSeen or {}

		local t = type(value)
		if t == "string" then
			remainingBytes = remainingBytes - #value
		elseif t == "number" or t == "boolean" then
			remainingBytes = remainingBytes - 8 -- Approximate size for numbers/booleans
		elseif t == "table" and not tablesSeen[value] then
			tablesSeen[value] = true
			for k, v in pairs(value) do
				remainingBytes = assertValueBytesLowerThan(k, remainingBytes, tablesSeen)
				remainingBytes = assertValueBytesLowerThan(v, remainingBytes, tablesSeen)
			end
		end

		if remainingBytes <= 0 then
			error("Data size is too large")
		end
		return remainingBytes
	end

	-- Sanitize inputs before every interaction
	local function assertAndSanitizeInputs(msg)
		if msg.Tags.Action ~= "Eval" and msg.Data then
			assertValueBytesLowerThan(msg.Data, 100)
		end

		assert(
			-- TODO: replace this with LastKnownMessageTimestamp after node release 23.0.0
			msg.Timestamp and tonumber(msg.Timestamp) >= 0,
			"Timestamp must be greater than or equal to the last known message timestamp of "
				.. LastKnownMessageTimestamp
				.. " but was "
				.. msg.Timestamp
		)
		assert(msg.From, "From is required")
		assert(msg.Tags and type(msg.Tags) == "table", "Tags are required")

		msg.Tags = utils.validateAndSanitizeInputs(msg.Tags)
		msg.From = utils.formatAddress(msg.From)
		msg.Timestamp = msg.Timestamp and tonumber(msg.Timestamp) -- Timestamp should always be provided by the CU
	end

	local function updateLastKnownMessage(msg)
		if msg.Timestamp >= LastKnownMessageTimestamp then
			LastKnownMessageTimestamp = msg.Timestamp
			LastKnownMessageId = msg.Id
		end
	end

	--- @class ParsedMessage
	--- @field Id string
	--- @field Action string
	--- @field From string
	--- @field Timestamp Timestamp
	--- @field Tags table<string, any>
	--- @field ioEvent ARIOEvent
	--- @field Cast boolean?
	--- @field reply? fun(response: any)

	--- @param handlerName string
	--- @param pattern fun(msg: ParsedMessage):'continue'|boolean
	--- @param handleFn fun(msg: ParsedMessage)
	--- @param critical boolean?
	--- @param printEvent boolean?
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

	addEventingHandler("sanitize", function()
		return "continue"
	end, function(msg)
		assertAndSanitizeInputs(msg)
		updateLastKnownMessage(msg)
	end, CRITICAL, false)

	-- NOTE: THIS IS A CRITICAL HANDLER AND WILL DISCARD THE MEMORY ON ERROR
	addEventingHandler("prune", function()
		return "continue" -- continue is a pattern that matches every message and continues to the next handler that matches the tags
	end, function(msg)
		HyperbeamSync.balances = utils.deepCopy(Balances)

		local epochIndex = epochs.getEpochIndexForTimestamp(msg.Timestamp)
		msg.ioEvent:addField("Epoch-Index", epochIndex)

		local previousStateSupplies = {
			protocolBalance = Balances[ao.id],
			lastKnownCirculatingSupply = LastKnownCirculatingSupply,
			lastKnownLockedSupply = LastKnownLockedSupply,
			lastKnownStakedSupply = LastKnownStakedSupply,
			lastKnownDelegatedSupply = LastKnownDelegatedSupply,
			lastKnownWithdrawSupply = LastKnownWithdrawSupply,
			lastKnownTotalSupply = token.lastKnownTotalTokenSupply(),
		}

		if msg.Tags["Force-Prune"] then
			print("Force prune provided, resetting all prune timestamps")
			gar.scheduleNextGatewaysPruning(0)
			gar.scheduleNextRedelegationsPruning(0)
			arns.scheduleNextReturnedNamesPrune(0)
			arns.scheduleNextRecordsPrune(0)
			primaryNames.scheduleNextPrimaryNamesPruning(0)
			vaults.scheduleNextVaultsPruning(0)
		end

		print("Pruning state at timestamp: " .. msg.Timestamp)
		local prunedStateResult = prune.pruneState(msg.Timestamp, msg.Id, LastGracePeriodEntryEndTimestamp)
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
			local prunedReturnedNames = prunedStateResult.prunedReturnedNames or {}
			local prunedReturnedNamesCount = utils.lengthOfTable(prunedReturnedNames)
			if prunedReturnedNamesCount > 0 then
				msg.ioEvent:addField("Pruned-Returned-Names", prunedReturnedNames)
				msg.ioEvent:addField("Pruned-Returned-Name-Count", prunedReturnedNamesCount)
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

			local pruneGatewaysResult = prunedStateResult.pruneGatewaysResult or {}
			addPruneGatewaysResult(msg.ioEvent, pruneGatewaysResult)

			local prunedPrimaryNameRequests = prunedStateResult.prunedPrimaryNameRequests or {}
			local prunedRequestsCount = utils.lengthOfTable(prunedPrimaryNameRequests)
			if prunedRequestsCount > 0 then
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
			or Balances[ao.id] ~= previousStateSupplies.protocolBalance
			or token.lastKnownTotalTokenSupply() ~= previousStateSupplies.lastKnownTotalSupply
		then
			addSupplyData(msg.ioEvent)
		end
	end, CRITICAL, false)

	-- Write handlers
	addEventingHandler(ActionMap.Transfer, utils.hasMatchingTag("Action", ActionMap.Transfer), function(msg)
		-- assert recipient is a valid arweave address
		local recipient = msg.Tags.Recipient
		local quantity = msg.Tags.Quantity
		local allowUnsafeAddresses = msg.Tags["Allow-Unsafe-Addresses"] or false
		assert(utils.isValidAddress(recipient, allowUnsafeAddresses), "Invalid recipient")
		assert(
			quantity and quantity > 0 and utils.isInteger(quantity),
			"Invalid quantity. Must be integer greater than 0"
		)
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

		-- if the sender is the protocol, then we need to update the circulating supply as tokens are now in circulation
		if msg.From == ao.id then
			LastKnownCirculatingSupply = LastKnownCirculatingSupply + quantity
			addSupplyData(msg.ioEvent)
		end

		-- Casting implies that the sender does not want a response - Reference: https://elixirforum.com/t/what-is-the-etymology-of-genserver-cast/33610/3
		if not msg.Cast then
			-- Debit-Notice message template, that is sent to the Sender of the transfer
			local debitNotice = {
				Target = msg.From,
				Action = "Debit-Notice",
				Recipient = recipient,
				Quantity = tostring(quantity),
				["Allow-Unsafe-Addresses"] = tostring(allowUnsafeAddresses),
				Data = "You transferred " .. msg.Tags.Quantity .. " to " .. recipient,
			}
			-- Credit-Notice message template, that is sent to the Recipient of the transfer
			local creditNotice = {
				Target = recipient,
				Action = "Credit-Notice",
				Sender = msg.From,
				Quantity = tostring(quantity),
				["Allow-Unsafe-Addresses"] = tostring(allowUnsafeAddresses),
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
		local msgId = msg.Id
		assert(
			lockLengthMs and lockLengthMs > 0 and utils.isInteger(lockLengthMs),
			"Invalid lock length. Must be integer greater than 0"
		)
		assert(
			quantity and utils.isInteger(quantity) and quantity >= constants.MIN_VAULT_SIZE,
			"Invalid quantity. Must be integer greater than or equal to " .. constants.MIN_VAULT_SIZE .. " mARIO"
		)
		local vault = vaults.createVault(msg.From, quantity, lockLengthMs, msg.Timestamp, msgId)

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

	addEventingHandler(
		ActionMap.VaultedTransfer,
		utils.hasMatchingTag("Action", ActionMap.VaultedTransfer),
		function(msg)
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
				Quantity = quantity,
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
				Quantity = quantity,
				Sender = msg.From,
				Tags = {
					Action = ActionMap.CreateVault .. "-Notice",
					["Vault-Id"] = msgId,
					["Allow-Unsafe-Addresses"] = tostring(allowUnsafeAddresses),
				},
				Data = json.encode(vault),
			})
		end
	)

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
			Quantity = vault.balance,
			Tags = { Action = "Credit-Notice", ["Vault-Id"] = vaultId },
			Data = json.encode(vault),
		})

		-- to the receiver, they get a revoke vault notice
		Send(msg, {
			Target = recipient,
			Quantity = vault.balance,
			Sender = msg.From,
			Tags = { Action = ActionMap.RevokeVault .. "-Notice", ["Vault-Id"] = vaultId },
			Data = json.encode(vault),
		})
	end)

	addEventingHandler(ActionMap.ExtendVault, utils.hasMatchingTag("Action", ActionMap.ExtendVault), function(msg)
		local vaultId = msg.Tags["Vault-Id"]
		local extendLengthMs = msg.Tags["Extend-Length"]
		assert(utils.isValidAddress(vaultId, true), "Invalid vault id")
		assert(
			extendLengthMs and extendLengthMs > 0 and utils.isInteger(extendLengthMs),
			"Invalid extension length. Must be integer greater than 0"
		)

		local vault = vaults.extendVault(msg.From, extendLengthMs, msg.Timestamp, vaultId)

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
		assert(
			quantity and quantity > 0 and utils.isInteger(quantity),
			"Invalid quantity. Must be integer greater than 0"
		)

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

	addEventingHandler(ActionMap.BuyName, utils.hasMatchingTag("Action", ActionMap.BuyName), function(msg)
		local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
		local purchaseType = msg.Tags["Purchase-Type"] and string.lower(msg.Tags["Purchase-Type"]) or "lease"
		local years = msg.Tags.Years or nil
		local processId = msg.Tags["Process-Id"]
		local fundFrom = msg.Tags["Fund-From"]
		local allowUnsafeProcessId = msg.Tags["Allow-Unsafe-Addresses"]
		assert(
			type(purchaseType) == "string" and purchaseType == "lease" or purchaseType == "permabuy",
			"Invalid purchase type"
		)
		arns.assertValidArNSName(name)
		assert(utils.isValidAddress(processId, true), "Process Id must be a valid address.")
		if years then
			assert(
				years >= 1 and years <= 5 and utils.isInteger(years),
				"Invalid years. Must be integer between 1 and 5"
			)
		end
		assertValidFundFrom(fundFrom)

		msg.ioEvent:addField("Name-Length", #name)

		local result = arns.buyRecord(
			name,
			purchaseType,
			years,
			msg.From,
			msg.Timestamp,
			processId,
			msg.Id,
			fundFrom,
			allowUnsafeProcessId
		)
		local record = result.record
		addRecordResultFields(msg.ioEvent, result)
		addSupplyData(msg.ioEvent)

		msg.ioEvent:addField("Records-Count", utils.lengthOfTable(NameRegistry.records))

		Send(msg, {
			Target = msg.From,
			Tags = { Action = ActionMap.BuyName .. "-Notice", Name = name },
			Data = json.encode({
				name = name,
				startTimestamp = record.startTimestamp,
				endTimestamp = record.endTimestamp,
				undernameLimit = record.undernameLimit,
				type = record.type,
				purchasePrice = record.purchasePrice,
				processId = record.processId,
				fundingResult = fundFrom and result.fundingResult or nil,
				fundingPlan = fundFrom and result.fundingPlan or nil,
				baseRegistrationFee = result.baseRegistrationFee,
				remainingBalance = result.remainingBalance,
				returnedName = result.returnedName,
			}),
		})

		-- If was returned name, send a credit notice to the initiator
		if result.returnedName ~= nil then
			Send(msg, {
				Target = result.returnedName.initiator,
				Action = "Credit-Notice",
				Quantity = tostring(result.returnedName.rewardForInitiator),
				Data = json.encode({
					name = name,
					buyer = msg.From,
					rewardForInitiator = result.returnedName.rewardForInitiator,
					rewardForProtocol = result.returnedName.rewardForProtocol,
					record = result.record,
				}),
			})
		end
	end)

	addEventingHandler("upgradeName", utils.hasMatchingTag("Action", ActionMap.UpgradeName), function(msg)
		local fundFrom = msg.Tags["Fund-From"]
		local name = string.lower(msg.Tags.Name)
		assert(type(name) == "string", "Invalid name")
		assertValidFundFrom(fundFrom)

		local result = arns.upgradeRecord(msg.From, name, msg.Timestamp, msg.Id, fundFrom)

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
		assert(type(name) == "string", "Invalid name")
		assert(
			years and years > 0 and years < 5 and utils.isInteger(years),
			"Invalid years. Must be integer between 1 and 5"
		)
		assertValidFundFrom(fundFrom)
		local result = arns.extendLease(msg.From, name, years, msg.Timestamp, msg.Id, fundFrom)
		local recordResult = {}
		if result ~= nil then
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
			assert(type(name) == "string", "Invalid name")
			assert(
				quantity and quantity > 0 and utils.isInteger(quantity),
				"Invalid quantity. Must be an integer value greater than 0"
			)
			assertValidFundFrom(fundFrom)

			local result = arns.increaseUndernameLimit(msg.From, name, quantity, msg.Timestamp, msg.Id, fundFrom)
			local recordResult = {}
			if result ~= nil then
				recordResult = result.record
				addRecordResultFields(msg.ioEvent, result)
				msg.ioEvent:addField("Previous-Undername-Limit", recordResult.undernameLimit - msg.Tags.Quantity)
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
			ActionMap.BuyName,
			ActionMap.ExtendLease,
			ActionMap.IncreaseUndernameLimit,
			ActionMap.UpgradeName,
			ActionMap.PrimaryNameRequest,
		})
		assert(
			intentType and type(intentType) == "string" and validIntents[intentType],
			"Intent must be valid registry interaction (e.g. Buy-Name, Extend-Lease, Increase-Undername-Limit, Upgrade-Name, Primary-Name-Request). Provided intent: "
				.. (intentType or "nil")
		)
		if intentType == ActionMap.PrimaryNameRequest then
			primaryNames.assertValidPrimaryName(msg.Tags.Name)
		else
			arns.assertValidArNSName(msg.Tags.Name)
		end

		-- if years is provided, assert it is a number and integer between 1 and 5
		if msg.Tags.Years then
			assert(utils.isInteger(msg.Tags.Years), "Invalid years. Must be integer")
			assert(msg.Tags.Years > 0 and msg.Tags.Years < 6, "Invalid years. Must be between 1 and 5")
		end

		-- if quantity provided must be a number and integer greater than 0
		if msg.Tags.Quantity then
			assert(utils.isInteger(msg.Tags.Quantity), "Invalid quantity. Must be integer")
			assert(msg.Tags.Quantity > 0, "Invalid quantity. Must be greater than 0")
		end
	end

	addEventingHandler(ActionMap.TokenCost, utils.hasMatchingTag("Action", ActionMap.TokenCost), function(msg)
		assertTokenCostTags(msg)
		local intent = msg.Tags.Intent
		local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
		local years = msg.Tags.Years or nil
		local quantity = msg.Tags.Quantity or nil
		local purchaseType = msg.Tags["Purchase-Type"] or "lease"

		local intendedAction = {
			intent = intent,
			name = name,
			years = years,
			quantity = quantity,
			purchaseType = purchaseType,
			currentTimestamp = msg.Timestamp,
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
		assertTokenCostTags(msg)
		assertValidFundFrom(fundFrom)

		local tokenCostAndFundingPlan = arns.getTokenCostAndFundingPlanForIntent(
			msg.Tags.Intent,
			name,
			years,
			quantity,
			purchaseType,
			msg.Timestamp,
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
		ActionMap.RegistrationFees,
		utils.hasMatchingTag("Action", ActionMap.RegistrationFees),
		function(msg)
			local priceList = arns.getRegistrationFees()

			Send(msg, {
				Target = msg.From,
				Tags = { Action = ActionMap.RegistrationFees .. "-Notice" },
				Data = json.encode(priceList),
			})
		end
	)

	addEventingHandler(ActionMap.JoinNetwork, utils.hasMatchingTag("Action", ActionMap.JoinNetwork), function(msg)
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

		assert(not msg.Tags.Services or updatedServices, "Services must be a valid JSON string")

		msg.ioEvent:addField("Resolved-Observer-Address", observerAddress)
		msg.ioEvent:addField("Sender-Previous-Balance", Balances[fromAddress] or 0)

		local gateway =
			gar.joinNetwork(fromAddress, stake, updatedSettings, updatedServices, observerAddress, msg.Timestamp)
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
		local unsafeGatewayBeforeLeaving = gar.getGatewayUnsafe(msg.From)
		local gwPrevTotalDelegatedStake = 0
		local gwPrevStake = 0
		if unsafeGatewayBeforeLeaving ~= nil then
			gwPrevTotalDelegatedStake = unsafeGatewayBeforeLeaving.totalDelegatedStake
			gwPrevStake = unsafeGatewayBeforeLeaving.operatorStake
		end

		assert(unsafeGatewayBeforeLeaving, "Gateway not found")

		local gateway = gar.leaveNetwork(msg.From, msg.Timestamp, msg.Id)

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
			assert(
				quantity and utils.isInteger(quantity) and quantity > constants.MIN_WITHDRAWAL_AMOUNT,
				"Invalid quantity. Must be integer greater than " .. constants.MIN_WITHDRAWAL_AMOUNT
			)
			assert(
				msg.Tags.Instant == nil or (msg.Tags.Instant == "true" or msg.Tags.Instant == "false"),
				"Instant must be a string with value 'true' or 'false'"
			)

			msg.ioEvent:addField("Sender-Previous-Balance", Balances[msg.From])

			local result = gar.decreaseOperatorStake(msg.From, quantity, msg.Timestamp, msg.Id, instantWithdraw)
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
			if instantWithdraw then
				LastKnownCirculatingSupply = LastKnownCirculatingSupply + decreaseOperatorStakeResult.amountWithdrawn
			else
				LastKnownWithdrawSupply = LastKnownWithdrawSupply + quantity
			end

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
		assert(utils.isValidAddress(gatewayTarget, true), "Invalid gateway address")
		assert(
			msg.Tags.Quantity and msg.Tags.Quantity > 0 and utils.isInteger(msg.Tags.Quantity),
			"Invalid quantity. Must be integer greater than 0"
		)

		msg.ioEvent:addField("Target-Formatted", gatewayTarget)

		local gateway = gar.delegateStake(msg.From, gatewayTarget, quantity, msg.Timestamp)
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

	addEventingHandler(
		ActionMap.CancelWithdrawal,
		utils.hasMatchingTag("Action", ActionMap.CancelWithdrawal),
		function(msg)
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
		end
	)

	addEventingHandler(
		ActionMap.InstantWithdrawal,
		utils.hasMatchingTag("Action", ActionMap.InstantWithdrawal),
		function(msg)
			local target = msg.Tags.Target or msg.Tags.Address or msg.From -- if not provided, use sender
			local vaultId = msg.Tags["Vault-Id"]
			msg.ioEvent:addField("Target-Formatted", target)
			assert(utils.isValidAddress(target, true), "Invalid gateway address")
			assert(utils.isValidAddress(vaultId, true), "Invalid vault id")

			local result = gar.instantGatewayWithdrawal(msg.From, target, vaultId, msg.Timestamp)
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
				LastKnownWithdrawSupply = LastKnownWithdrawSupply
					- result.amountWithdrawn
					- result.expeditedWithdrawalFee
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
					Quantity = quantity,
					["Penalty-Rate"] = tostring(decreaseDelegateStakeResult.penaltyRate),
					["Expedited-Withdrawal-Fee"] = tostring(decreaseDelegateStakeResult.expeditedWithdrawalFee),
					["Amount-Withdrawn"] = tostring(decreaseDelegateStakeResult.amountWithdrawn),
				},
				Data = json.encode(result and result.updatedDelegate or {}),
			})
		end
	)

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

			local observerAddress = msg.Tags["Observer-Address"] or unsafeGateway.observerAddress
			local result = gar.updateGatewaySettings(
				msg.From,
				updatedSettings,
				updatedServices,
				observerAddress,
				msg.Timestamp,
				msg.Id
			)
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
		local allowUnsafeProcessId = msg.Tags["Allow-Unsafe-Addresses"]
		assert(name and #name > 0, "Name is required")
		assert(utils.isValidAddress(newProcessId, true), "Process Id must be a valid address.")
		if initiator ~= nil then
			assert(utils.isValidAddress(initiator, true), "Invalid initiator address.")
		end

		local reassignment = arns.reassignName(name, msg.From, msg.Timestamp, newProcessId, allowUnsafeProcessId)

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

	addEventingHandler(
		ActionMap.SaveObservations,
		utils.hasMatchingTag("Action", ActionMap.SaveObservations),
		function(msg)
			local reportTxId = msg.Tags["Report-Tx-Id"]
			local failedGateways = utils.splitAndTrimString(msg.Tags["Failed-Gateways"], ",")
			-- observers provide AR-IO-Epoch-Index, so check both
			local epochIndex = msg.Tags["Epoch-Index"] and tonumber(msg.Tags["Epoch-Index"])
				or msg.Tags["AR-IO-Epoch-Index"] and tonumber(msg.Tags["AR-IO-Epoch-Index"])
			assert(
				epochIndex and epochIndex >= 0 and utils.isInteger(epochIndex),
				"Epoch index is required. Must be a number greater than 0."
			)
			assert(utils.isValidArweaveAddress(reportTxId), "Invalid report tx id. Must be a valid Arweave address.")
			for _, gateway in ipairs(failedGateways) do
				assert(utils.isValidAddress(gateway, true), "Invalid failed gateway address: " .. gateway)
			end

			local observations =
				epochs.saveObservations(msg.From, reportTxId, failedGateways, epochIndex, msg.Timestamp)
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
		end
	)

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
		addTalliesData(msg.ioEvent, totalSupplyDetails.stateObjectTallies)
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
		addTalliesData(msg.ioEvent, totalSupplyDetails.stateObjectTallies)
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
				-- NOTE: json.lua supports up to stringified numbers with 20 significant digits - numbers should always be stringified
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
	addEventingHandler("distribute", function(msg)
		return msg.Action == "Tick" or msg.Action == "Distribute"
	end, function(msg)
		local msgId = msg.Id
		local blockHeight = tonumber(msg["Block-Height"])
		local hashchain = msg["Hash-Chain"]
		local lastCreatedEpochIndex = LastCreatedEpochIndex
		local lastDistributedEpochIndex = LastDistributedEpochIndex
		local targetCurrentEpochIndex = epochs.getEpochIndexForTimestamp(msg.Timestamp)

		assert(blockHeight, "Block height is required")
		assert(hashchain, "Hash chain is required")

		msg.ioEvent:addField("Last-Created-Epoch-Index", lastCreatedEpochIndex)
		msg.ioEvent:addField("Last-Distributed-Epoch-Index", lastDistributedEpochIndex)
		msg.ioEvent:addField("Target-Current-Epoch-Index", targetCurrentEpochIndex)

		-- tick and distribute rewards for every index between the last ticked epoch and the current epoch
		local distributedEpochIndexes = {}
		local newEpochIndexes = {}
		local newPruneGatewaysResults = {}
		local tickedRewardDistributions = {}
		local totalTickedRewardsDistributed = 0

		-- tick the demand factor all the way to the current period
		local latestDemandFactor, newDemandFactors = demand.updateDemandFactor(msg.Timestamp)
		if latestDemandFactor ~= nil then
			Send(msg, {
				Target = msg.From,
				Action = "Demand-Factor-Updated-Notice",
				Data = tostring(latestDemandFactor),
			})
		end

		--[[
		Tick up to the target epoch index, this will create new epochs and distribute rewards for existing epochs
		This should never fall behind, but in the case it does, it will create the epochs and distribute rewards for the epochs
		accordingly. It should finish at the target epoch index - which is computed based on the message timestamp
	]]
		--
		print("Ticking from " .. lastCreatedEpochIndex .. " to " .. targetCurrentEpochIndex)
		for epochIndexToTick = lastCreatedEpochIndex, targetCurrentEpochIndex do
			local tickResult = tick.tickEpoch(msg.Timestamp, blockHeight, hashchain, msgId, epochIndexToTick)
			if tickResult.pruneGatewaysResult ~= nil then
				table.insert(newPruneGatewaysResults, tickResult.pruneGatewaysResult)
			end
			if tickResult.maybeNewEpoch ~= nil then
				print("Created epoch " .. tickResult.maybeNewEpoch.epochIndex)
				LastCreatedEpochIndex = tickResult.maybeNewEpoch.epochIndex
				table.insert(newEpochIndexes, tickResult.maybeNewEpoch.epochIndex)
				Send(msg, {
					Target = msg.From,
					Action = "Epoch-Created-Notice",
					["Epoch-Index"] = tostring(tickResult.maybeNewEpoch.epochIndex),
					Data = json.encode(tickResult.maybeNewEpoch),
				})
			end
			if tickResult.maybeDistributedEpoch ~= nil then
				print("Distributed rewards for epoch " .. tickResult.maybeDistributedEpoch.epochIndex)
				LastDistributedEpochIndex = tickResult.maybeDistributedEpoch.epochIndex
				tickedRewardDistributions[tostring(tickResult.maybeDistributedEpoch.epochIndex)] =
					tickResult.maybeDistributedEpoch.distributions.totalDistributedRewards
				totalTickedRewardsDistributed = totalTickedRewardsDistributed
					+ tickResult.maybeDistributedEpoch.distributions.totalDistributedRewards
				table.insert(distributedEpochIndexes, tickResult.maybeDistributedEpoch.epochIndex)
				Send(msg, {
					Target = msg.From,
					Action = "Epoch-Distribution-Notice",
					["Epoch-Index"] = tostring(tickResult.maybeDistributedEpoch.epochIndex),
					Data = json.encode(tickResult.maybeDistributedEpoch),
				})
			end
		end
		if #distributedEpochIndexes > 0 then
			msg.ioEvent:addField("Distributed-Epoch-Indexes", distributedEpochIndexes)
		end
		if #newEpochIndexes > 0 then
			msg.ioEvent:addField("New-Epoch-Indexes", newEpochIndexes)
			-- Only print the prescribed observers of the newest epoch
			local newestEpoch = epochs.getEpoch(math.max(table.unpack(newEpochIndexes)))
			local prescribedObserverAddresses = {}
			local prescribedObserverGatewayAddresses = {}
			if newestEpoch ~= nil and newestEpoch.prescribedObservers ~= nil then
				for observerAddress, gatewayAddress in pairs(newestEpoch.prescribedObservers) do
					table.insert(prescribedObserverAddresses, observerAddress)
					table.insert(prescribedObserverGatewayAddresses, gatewayAddress)
				end
			end
			msg.ioEvent:addField("Prescribed-Observer-Addresses", prescribedObserverAddresses)
			msg.ioEvent:addField("Prescribed-Observer-Gateway-Addresses", prescribedObserverGatewayAddresses)
		end
		local updatedDemandFactorCount = utils.lengthOfTable(newDemandFactors)
		if updatedDemandFactorCount > 0 then
			local updatedDemandFactorPeriods = {}
			local updatedDemandFactorValues = {}
			for _, df in ipairs(newDemandFactors) do
				table.insert(updatedDemandFactorPeriods, df.period)
				table.insert(updatedDemandFactorValues, df.demandFactor)
			end
			msg.ioEvent:addField("New-Demand-Factor-Periods", updatedDemandFactorPeriods)
			msg.ioEvent:addField("New-Demand-Factor-Values", updatedDemandFactorValues)
			msg.ioEvent:addField("New-Demand-Factor-Count", updatedDemandFactorCount)
		end
		if #newPruneGatewaysResults > 0 then
			-- Reduce the prune gateways results and then track changes
			--- @type PruneGatewaysResult
			local aggregatedPruneGatewaysResult = utils.reduce(
				newPruneGatewaysResults,
				--- @param acc PruneGatewaysResult
				--- @param _ any
				--- @param pruneGatewaysResult PruneGatewaysResult
				function(acc, _, pruneGatewaysResult)
					for _, address in pairs(pruneGatewaysResult.prunedGateways) do
						table.insert(acc.prunedGateways, address)
					end
					for address, slashAmount in pairs(pruneGatewaysResult.slashedGateways) do
						acc.slashedGateways[address] = (acc.slashedGateways[address] or 0) + slashAmount
					end
					acc.gatewayStakeReturned = acc.gatewayStakeReturned + pruneGatewaysResult.gatewayStakeReturned
					acc.delegateStakeReturned = acc.delegateStakeReturned + pruneGatewaysResult.delegateStakeReturned
					acc.gatewayStakeWithdrawing = acc.gatewayStakeWithdrawing
						+ pruneGatewaysResult.gatewayStakeWithdrawing
					acc.delegateStakeWithdrawing = acc.delegateStakeWithdrawing
						+ pruneGatewaysResult.delegateStakeWithdrawing
					acc.stakeSlashed = acc.stakeSlashed + pruneGatewaysResult.stakeSlashed
					-- Upsert to the latest tallies if available
					acc.gatewayObjectTallies = pruneGatewaysResult.gatewayObjectTallies or acc.gatewayObjectTallies
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

		-- Send a single tick notice to the sender after all epochs have been ticked
		Send(msg, {
			Target = msg.From,
			Action = "Tick-Notice",
			Data = json.encode({
				distributedEpochIndexes = distributedEpochIndexes,
				newEpochIndexes = newEpochIndexes,
				newDemandFactors = newDemandFactors,
				newPruneGatewaysResults = newPruneGatewaysResults,
				tickedRewardDistributions = tickedRewardDistributions,
				totalTickedRewardsDistributed = totalTickedRewardsDistributed,
			}),
		})
	end, CRITICAL)

	-- READ HANDLERS

	addEventingHandler(ActionMap.Info, Handlers.utils.hasMatchingTag("Action", ActionMap.Info), function(msg)
		local handlers = Handlers.list
		local handlerNames = {}

		for _, handler in ipairs(handlers) do
			table.insert(handlerNames, handler.name)
		end

		local memoryKiBUsed = collectgarbage("count")

		Send(msg, {
			Target = msg.From,
			Action = "Info-Notice",
			Tags = {
				Name = Name,
				Ticker = Ticker,
				Logo = Logo,
				Owner = Owner,
				Denomination = tostring(Denomination),
				LastCreatedEpochIndex = tostring(LastCreatedEpochIndex),
				LastDistributedEpochIndex = tostring(LastDistributedEpochIndex),
				Handlers = json.encode(handlerNames),
				["Memory-KiB-Used"] = tostring(memoryKiBUsed),
			},
			Data = json.encode({
				Name = Name,
				Ticker = Ticker,
				Logo = Logo,
				Owner = Owner,
				Denomination = Denomination,
				LastCreatedEpochIndex = LastCreatedEpochIndex,
				LastDistributedEpochIndex = LastDistributedEpochIndex,
				Handlers = handlerNames,
				["Memory-KiB-Used"] = memoryKiBUsed,
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

	--- NOTE: this handler does not scale well, but various ecosystem apps rely on it (arconnect, ao.link, etc.)
	addEventingHandler(ActionMap.Balances, Handlers.utils.hasMatchingTag("Action", ActionMap.Balances), function(msg)
		Send(msg, {
			Target = msg.From,
			Action = "Balances-Notice",
			Data = json.encode(Balances),
		})
	end)

	addEventingHandler(ActionMap.Balance, Handlers.utils.hasMatchingTag("Action", ActionMap.Balance), function(msg)
		local target = msg.Tags.Target or msg.Tags.Address or msg.Tags.Recipient or msg.From
		local balance = balances.getBalance(target)

		-- must adhere to token.lua spec defined by https://github.com/permaweb/aos/blob/15dd81ee596518e2f44521e973b8ad1ce3ee9945/blueprints/token.lua
		Send(msg, {
			Target = msg.From,
			Action = "Balance-Notice",
			Account = target,
			Data = tostring(balance),
			Balance = tostring(balance),
			Ticker = Ticker,
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

	addEventingHandler(
		ActionMap.DemandFactorInfo,
		utils.hasMatchingTag("Action", ActionMap.DemandFactorInfo),
		function(msg)
			local result = demand.getDemandFactorInfo()
			Send(msg, { Target = msg.From, Action = "Demand-Factor-Info-Notice", Data = json.encode(result) })
		end
	)

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
		local epochIndex = msg.Tags["Epoch-Index"] and tonumber(msg.Tags["Epoch-Index"])
			or epochs.getEpochIndexForTimestamp(msg.Timestamp)
		local epoch = epochs.getEpoch(epochIndex)
		if epoch then
			-- populate the prescribed observers with weights for the epoch, this helps improve DX of downstream apps
			epoch.prescribedObservers = epochs.getPrescribedObserversWithWeightsForEpoch(epochIndex)
		end
		if epoch and epoch.distributions then
			-- remove the distributions data from the epoch to avoid unbounded response payloads
			epoch.distributions.rewards = nil
		end
		Send(msg, { Target = msg.From, Action = "Epoch-Notice", Data = json.encode(epoch) })
	end)

	addEventingHandler(
		ActionMap.PrescribedObservers,
		utils.hasMatchingTag("Action", ActionMap.PrescribedObservers),
		function(msg)
			local epochIndex = msg.Tags["Epoch-Index"] and tonumber(msg.Tags["Epoch-Index"])
				or epochs.getEpochIndexForTimestamp(msg.Timestamp)
			local prescribedObserversWithWeights = epochs.getPrescribedObserversWithWeightsForEpoch(epochIndex)
			Send(msg, {
				Target = msg.From,
				Action = "Prescribed-Observers-Notice",
				Data = json.encode(prescribedObserversWithWeights),
			})
		end
	)

	addEventingHandler(ActionMap.Observations, utils.hasMatchingTag("Action", ActionMap.Observations), function(msg)
		local epochIndex = msg.Tags["Epoch-Index"] and tonumber(msg.Tags["Epoch-Index"])
			or epochs.getEpochIndexForTimestamp(msg.Timestamp)
		local observations = epochs.getObservationsForEpoch(epochIndex)
		Send(msg, {
			Target = msg.From,
			Action = "Observations-Notice",
			EpochIndex = tostring(epochIndex),
			Data = json.encode(observations),
		})
	end)

	addEventingHandler(
		ActionMap.PrescribedNames,
		utils.hasMatchingTag("Action", ActionMap.PrescribedNames),
		function(msg)
			-- check if the epoch number is provided, if not get the epoch number from the timestamp
			local epochIndex = msg.Tags["Epoch-Index"] and tonumber(msg.Tags["Epoch-Index"])
				or epochs.getEpochIndexForTimestamp(msg.Timestamp)
			local prescribedNames = epochs.getPrescribedNamesForEpoch(epochIndex)
			Send(msg, {
				Target = msg.From,
				Action = "Prescribed-Names-Notice",
				Data = json.encode(prescribedNames),
			})
		end
	)

	addEventingHandler(ActionMap.Distributions, utils.hasMatchingTag("Action", ActionMap.Distributions), function(msg)
		-- check if the epoch number is provided, if not get the epoch number from the timestamp
		local epochIndex = msg.Tags["Epoch-Index"] and tonumber(msg.Tags["Epoch-Index"])
			or epochs.getEpochIndexForTimestamp(msg.Timestamp)
		local distributions = epochs.getDistributionsForEpoch(epochIndex)
		Send(msg, {
			Target = msg.From,
			Action = "Distributions-Notice",
			Data = json.encode(distributions),
		})
	end)

	addEventingHandler("epochRewards", utils.hasMatchingTag("Action", ActionMap.EpochRewards), function(msg)
		local page = utils.parsePaginationTags(msg)

		local epochRewards = epochs.getEligibleRewardsForEpoch(
			msg.Timestamp,
			page.cursor,
			page.limit,
			page.sortBy or "cursorId",
			page.sortOrder
		)

		Send(msg, {
			Target = msg.From,
			Action = "Epoch-Eligible-Rewards-Notice",
			Data = json.encode(epochRewards),
		})
	end)

	addEventingHandler("paginatedReservedNames", utils.hasMatchingTag("Action", ActionMap.ReservedNames), function(msg)
		local page = utils.parsePaginationTags(msg)
		local reservedNames =
			arns.getPaginatedReservedNames(page.cursor, page.limit, page.sortBy or "name", page.sortOrder)
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
		local result = arns.getPaginatedRecords(
			page.cursor,
			page.limit,
			page.sortBy or "startTimestamp",
			page.sortOrder,
			page.filters
		)
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

	addEventingHandler("releaseName", utils.hasMatchingTag("Action", ActionMap.ReleaseName), function(msg)
		-- validate the name and process id exist, then create the returned name
		local name = msg.Tags.Name and string.lower(msg.Tags.Name)
		local processId = msg.From
		local initiator = msg.Tags.Initiator or msg.From

		assert(name and #name > 0, "Name is required") -- this could be an undername, so we don't want to assertValidArNSName
		assert(processId and utils.isValidAddress(processId, true), "Process-Id must be a valid address")
		assert(initiator and utils.isValidAddress(initiator, true), "Initiator is required")
		local record = arns.getRecord(name)
		assert(record, "Record not found")
		assert(record.type == "permabuy", "Only permabuy names can be released")
		assert(record.processId == processId, "Process-Id mismatch")
		assert(
			#primaryNames.getPrimaryNamesForBaseName(name) == 0,
			"Primary names are associated with this name. They must be removed before releasing the name."
		)

		-- we should be able to create the returned name here
		local removedRecord = arns.removeRecord(name)
		local removedPrimaryNamesAndOwners = primaryNames.removePrimaryNamesForBaseName(name) -- NOTE: this should be empty if there are no primary names allowed before release
		local returnedName = arns.createReturnedName(name, msg.Timestamp, initiator)
		local returnedNameData = {
			removedRecord = removedRecord,
			removedPrimaryNamesAndOwners = removedPrimaryNamesAndOwners,
			returnedName = returnedName,
		}

		addReturnedNameResultFields(msg.ioEvent, {
			name = name,
			returnedName = returnedNameData.returnedName,
			removedRecord = returnedNameData.removedRecord,
			removedPrimaryNamesAndOwners = returnedNameData.removedPrimaryNamesAndOwners,
		})

		-- note: no change to token supply here - only on buy record of returned name
		msg.ioEvent:addField("Returned-Name-Count", utils.lengthOfTable(NameRegistry.returned))
		msg.ioEvent:addField("Records-Count", utils.lengthOfTable(NameRegistry.records))

		local releaseNameData = {
			name = name,
			startTimestamp = returnedName.startTimestamp,
			endTimestamp = returnedName.startTimestamp + constants.RETURNED_NAME_DURATION_MS,
			initiator = returnedName.initiator,
		}

		-- send to the initiator and the process that released the name
		Send(msg, {
			Target = initiator,
			Action = "Returned-Name-Notice",
			Name = name,
			Data = json.encode(releaseNameData),
		})
		Send(msg, {
			Target = processId,
			Action = "Returned-Name-Notice",
			Name = name,
			Data = json.encode(releaseNameData),
		})
	end)

	addEventingHandler(ActionMap.ReturnedNames, utils.hasMatchingTag("Action", ActionMap.ReturnedNames), function(msg)
		local page = utils.parsePaginationTags(msg)
		local returnedNames = arns.getReturnedNamesUnsafe()

		--- @type ReturnedNameData[] -- Returned Names with End Timestamp and Premium Multiplier
		local returnedNameDataArray = {}

		for _, v in pairs(returnedNames) do
			table.insert(returnedNameDataArray, {
				name = v.name,
				startTimestamp = v.startTimestamp,
				endTimestamp = v.startTimestamp + constants.RETURNED_NAME_DURATION_MS,
				initiator = v.initiator,
				premiumMultiplier = arns.getReturnedNamePremiumMultiplier(v.startTimestamp, msg.Timestamp),
			})
		end

		-- paginate the returnedNames by name, showing returnedNames nearest to the endTimestamp first
		local paginatedReturnedNames = utils.paginateTableWithCursor(
			returnedNameDataArray,
			page.cursor,
			"name",
			page.limit,
			page.sortBy or "endTimestamp",
			page.sortOrder or "asc"
		)
		Send(msg, {
			Target = msg.From,
			Action = ActionMap.ReturnedNames .. "-Notice",
			Data = json.encode(paginatedReturnedNames),
		})
	end)

	addEventingHandler(ActionMap.ReturnedName, utils.hasMatchingTag("Action", ActionMap.ReturnedName), function(msg)
		local name = string.lower(msg.Tags.Name)
		local returnedName = arns.getReturnedNameUnsafe(name)

		assert(returnedName, "Returned name not found")

		Send(msg, {
			Target = msg.From,
			Action = ActionMap.ReturnedName .. "-Notice",
			Data = json.encode({
				name = returnedName.name,
				startTimestamp = returnedName.startTimestamp,
				endTimestamp = returnedName.startTimestamp + constants.RETURNED_NAME_DURATION_MS,
				initiator = returnedName.initiator,
				premiumMultiplier = arns.getReturnedNamePremiumMultiplier(returnedName.startTimestamp, msg.Timestamp),
			}),
		})
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
		local disallowedDelegates = msg.Tags["Disallowed-Delegates"]
			and utils.splitAndTrimString(msg.Tags["Disallowed-Delegates"], ",")
		assert(disallowedDelegates and #disallowedDelegates > 0, "Disallowed-Delegates is required")
		msg.ioEvent:addField("Input-Disallowed-Delegates-Count", utils.lengthOfTable(disallowedDelegates))
		local result = gar.disallowDelegates(disallowedDelegates, msg.From, msg.Id, msg.Timestamp)
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

	addEventingHandler(
		ActionMap.RedelegateStake,
		utils.hasMatchingTag("Action", ActionMap.RedelegateStake),
		function(msg)
			local sourceAddress = msg.Tags.Source
			local targetAddress = msg.Tags.Target
			local delegateAddress = msg.From
			local quantity = msg.Tags.Quantity or nil
			local vaultId = msg.Tags["Vault-Id"]

			assert(utils.isValidAddress(sourceAddress, true), "Invalid source gateway address")
			assert(utils.isValidAddress(targetAddress, true), "Invalid target gateway address")
			assert(utils.isValidAddress(delegateAddress, true), "Invalid delegator address")
			if vaultId then
				assert(utils.isValidAddress(vaultId, true), "Invalid vault id")
			end

			assert(
				quantity and quantity > 0 and utils.isInteger(quantity),
				"Invalid quantity. Must be integer greater than 0"
			)
			local redelegationResult = gar.redelegateStake({
				sourceAddress = sourceAddress,
				targetAddress = targetAddress,
				delegateAddress = delegateAddress,
				qty = quantity,
				currentTimestamp = msg.Timestamp,
				vaultId = vaultId,
			})

			local redelegationFee = redelegationResult.redelegationFee
			local stakeMoved = quantity - redelegationFee

			local isStakeMovingFromDelegateToOperator = delegateAddress == targetAddress
			local isStakeMovingFromOperatorToDelegate = delegateAddress == sourceAddress
			local isStakeMovingFromWithdrawal = vaultId ~= nil

			--- Stake Direction Codings:
			--- dw2o = Delegate Withdrawal to Operator Stake
			--- d2o = Delegate Stake to Operator Stake
			--- ow2d = Operator Withdrawal to Delegate Stake
			--- o2d = Operator Stake to Delegate Stake
			--- dw2d = Delegate Withdrawal to Other Delegate Stake
			--- d2d = Delegate Stake to Other Delegate Stake
			msg.ioEvent:addField(
				"Stake-Direction",
				isStakeMovingFromDelegateToOperator and (isStakeMovingFromWithdrawal and "dw2o" or "d2o")
					or (
						isStakeMovingFromOperatorToDelegate and (isStakeMovingFromWithdrawal and "ow2d" or "o2d")
						or (isStakeMovingFromWithdrawal and "dw2d" or "d2d")
					)
			)

			if isStakeMovingFromWithdrawal then
				LastKnownWithdrawSupply = LastKnownWithdrawSupply - quantity
			end

			if isStakeMovingFromDelegateToOperator then
				if not isStakeMovingFromWithdrawal then
					LastKnownDelegatedSupply = LastKnownDelegatedSupply - quantity
				end
				LastKnownStakedSupply = LastKnownStakedSupply + stakeMoved
			elseif isStakeMovingFromOperatorToDelegate then
				if not isStakeMovingFromWithdrawal then
					LastKnownStakedSupply = LastKnownStakedSupply - quantity
				end
				LastKnownDelegatedSupply = LastKnownDelegatedSupply + stakeMoved
			elseif isStakeMovingFromWithdrawal then
				LastKnownStakedSupply = LastKnownStakedSupply + stakeMoved
			else
				LastKnownStakedSupply = LastKnownStakedSupply - redelegationFee
			end

			if redelegationFee > 0 then
				msg.ioEvent:addField("Redelegation-Fee", redelegationFee)
			end
			addSupplyData(msg.ioEvent)

			Send(msg, {
				Target = msg.From,
				Tags = {
					Action = ActionMap.RedelegateStake .. "-Notice",
				},
				Data = json.encode(redelegationResult),
			})
		end
	)

	addEventingHandler(
		ActionMap.RedelegationFee,
		utils.hasMatchingTag("Action", ActionMap.RedelegationFee),
		function(msg)
			local delegateAddress = msg.Tags.Address or msg.From
			assert(utils.isValidAddress(delegateAddress, true), "Invalid delegator address")
			local feeResult = gar.getRedelegationFee(delegateAddress)
			Send(msg, {
				Target = msg.From,
				Tags = { Action = ActionMap.RedelegationFee .. "-Notice" },
				Data = json.encode(feeResult),
			})
		end
	)

	--- PRIMARY NAMES
	addEventingHandler("removePrimaryName", utils.hasMatchingTag("Action", ActionMap.RemovePrimaryNames), function(msg)
		local names = utils.splitAndTrimString(msg.Tags.Names, ",")
		assert(names and #names > 0, "Names are required")
		assert(msg.From, "From is required")
		local notifyOwners = msg.Tags["Notify-Owners"] and msg.Tags["Notify-Owners"] == "true" or false

		local removedPrimaryNamesAndOwners = primaryNames.removePrimaryNames(names, msg.From)
		local removedPrimaryNamesCount = utils.lengthOfTable(removedPrimaryNamesAndOwners)
		msg.ioEvent:addField("Num-Removed-Primary-Names", removedPrimaryNamesCount)
		if removedPrimaryNamesCount > 0 then
			msg.ioEvent:addField(
				"Removed-Primary-Names",
				utils.map(removedPrimaryNamesAndOwners, function(_, v)
					return v.name
				end)
			)
			msg.ioEvent:addField(
				"Removed-Primary-Name-Owners",
				utils.map(removedPrimaryNamesAndOwners, function(_, v)
					return v.owner
				end)
			)
		end
		addPrimaryNameCounts(msg.ioEvent)

		Send(msg, {
			Target = msg.From,
			Action = ActionMap.RemovePrimaryNames .. "-Notice",
			Data = json.encode(removedPrimaryNamesAndOwners),
		})

		-- Send messages to the owners of the removed primary names if the notifyOwners flag is true
		if notifyOwners then
			for _, removedPrimaryNameAndOwner in pairs(removedPrimaryNamesAndOwners) do
				Send(msg, {
					Target = removedPrimaryNameAndOwner.owner,
					Action = ActionMap.RemovePrimaryNames .. "-Notice",
					Tags = { Name = removedPrimaryNameAndOwner.name },
					Data = json.encode(removedPrimaryNameAndOwner),
				})
			end
		end
	end)

	addEventingHandler("requestPrimaryName", utils.hasMatchingTag("Action", ActionMap.RequestPrimaryName), function(msg)
		local fundFrom = msg.Tags["Fund-From"]
		local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
		local initiator = msg.From
		assert(name, "Name is required")
		assert(initiator, "Initiator is required")
		assertValidFundFrom(fundFrom)

		local primaryNameResult =
			primaryNames.createPrimaryNameRequest(name, initiator, msg.Timestamp, msg.Id, fundFrom)

		addPrimaryNameRequestData(msg.ioEvent, primaryNameResult)

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

			assert(name, "Name is required")
			assert(recipient, "Recipient is required")
			assert(msg.From, "From is required")

			local approvedPrimaryNameResult =
				primaryNames.approvePrimaryNameRequest(recipient, name, msg.From, msg.Timestamp)
			addPrimaryNameRequestData(msg.ioEvent, approvedPrimaryNameResult)

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

	addEventingHandler(
		"getPrimaryNameRequest",
		utils.hasMatchingTag("Action", ActionMap.PrimaryNameRequest),
		function(msg)
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
		end
	)

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
		local result = primaryNames.getPaginatedPrimaryNames(
			page.cursor,
			page.limit,
			page.sortBy or "name",
			page.sortOrder or "asc"
		)

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

	addEventingHandler("getPruningTimestamps", utils.hasMatchingTag("Action", "Pruning-Timestamps"), function(msg)
		addNextPruneTimestampsData(msg.ioEvent)
		return Send(msg, {
			Target = msg.From,
			Action = "Pruning-Timestamps-Notice",
			Data = json.encode({
				returnedNames = arns.nextReturnedNamesPruneTimestamp(),
				gateways = gar.nextGatewaysPruneTimestamp(),
				primaryNames = primaryNames.nextPrimaryNamesPruneTimestamp(),
				records = arns.nextRecordsPruneTimestamp(),
				redelegations = gar.nextRedelegationsPruneTimestamp(),
				vaults = vaults.nextVaultsPruneTimestamp(),
			}),
		})
	end)

	addEventingHandler("allPaginatedDelegates", utils.hasMatchingTag("Action", "All-Paginated-Delegates"), function(msg)
		local page = utils.parsePaginationTags(msg)
		local result = gar.getPaginatedDelegatesFromAllGateways(page.cursor, page.limit, page.sortBy, page.sortOrder)
		Send(msg, { Target = msg.From, Action = "All-Delegates-Notice", Data = json.encode(result) })
	end)

	addEventingHandler("allPaginatedGatewayVaults", utils.hasMatchingTag("Action", "All-Gateway-Vaults"), function(msg)
		local page = utils.parsePaginationTags(msg)
		local result = gar.getPaginatedVaultsFromAllGateways(page.cursor, page.limit, page.sortBy, page.sortOrder)
		Send(msg, { Target = msg.From, Action = "All-Gateway-Vaults-Notice", Data = json.encode(result) })
	end)

	addEventingHandler(ActionMap.PatchHyperbeamBalances, function(msg)
		if msg.Tags.Action == ActionMap.PatchHyperbeamBalances then
			return "continue"
		end
		return false
	end, function(msg)
		assert(msg.From == Owner, "Only the owner can trigger " .. ActionMap.PatchHyperbeamBalances)

		local patchBalances = {}
		for address, balance in pairs(Balances) do
			patchBalances[address] = tostring(balance)
		end

		local patchMessage = { device = "patch@1.0", balances = patchBalances }
		ao.send(patchMessage)

		return Send(msg, {
			Target = msg.From,
			Action = ActionMap.PatchHyperbeamBalances .. "-Notice",
		})
	end)

	return main
end

_G.package.loaded[".src.main"] = _loaded_mod_src_main()

--------------------------------
-------- HYPERBEAM SYNC --------
--- Sends a sync patch to hyperbeam with the current balances and primary names state
--------------------------------

-- For balances we need to send the balance as a string due to trie device requirements
local patchBalances = {}
for address, balance in pairs(Balances) do
	patchBalances[address] = tostring(balance)
end

ao.send({
	device = "patch@1.0",
	balances = patchBalances,
	-- primary names don't need to be sent as a string
	["primary-names"] = PrimaryNames,
})
