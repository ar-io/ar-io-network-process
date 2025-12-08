--[[
	Adds Filters tag support to all paginated handlers.

	This extends the pagination filters feature (added in 2025-06-16-pagination-filters.lua)
	to support filtering on all paginated endpoints.

	Reviewers: Dylan, Ariel, Atticus
]]
--
local gar = require(".src.gar")
local primaryNames = require(".src.primary_names")
local vaults = require(".src.vaults")
local balances = require(".src.balances")
local arns = require(".src.arns")
local utils = require(".src.utils")
local json = require(".src.json")
local ARIOEvent = require(".src.ario_event")

-- gar.lua - add filters parameter to getPaginatedGateways
function gar.getPaginatedGateways(cursor, limit, sortBy, sortOrder, filters)
	local gateways = gar.getGateways()
	local gatewaysArray = {}
	local cursorField = "gatewayAddress" -- the cursor will be the gateway address
	for address, gateway in pairs(gateways) do
		--- @diagnostic disable-next-line: inject-field
		gateway.gatewayAddress = address
		-- remove delegates and vaults to avoid sending unbounded arrays, they can be fetched via getPaginatedDelegates and getPaginatedVaults
		gateway.delegates = nil
		gateway.vaults = nil
		table.insert(gatewaysArray, gateway)
	end

	return utils.paginateTableWithCursor(gatewaysArray, cursor, cursorField, limit, sortBy, sortOrder, filters)
end

-- primary_names.lua - add filters parameter to getPaginatedPrimaryNames
function primaryNames.getPaginatedPrimaryNames(cursor, limit, sortBy, sortOrder, filters)
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
	return utils.paginateTableWithCursor(primaryNamesArray, cursor, cursorField, limit, sortBy, sortOrder, filters)
end

-- vaults.lua - add filters parameter to getPaginatedVaults
function vaults.getPaginatedVaults(cursor, limit, sortOrder, sortBy, filters)
	local allVaults = vaults.getVaultsUnsafe()
	local cursorField = "vaultId"

	local vaultsArray = utils.reduce(allVaults, function(acc, address, vaultsForAddress)
		for vaultId, vault in pairs(vaultsForAddress) do
			table.insert(acc, {
				address = address,
				controller = vault.controller,
				vaultId = vaultId,
				balance = vault.balance,
				startTimestamp = vault.startTimestamp,
				endTimestamp = vault.endTimestamp,
			})
		end
		return acc
	end, {})

	return utils.paginateTableWithCursor(
		vaultsArray,
		cursor,
		cursorField,
		limit,
		sortBy or "address",
		sortOrder,
		filters
	)
end

-- balances.lua - add filters parameter to getPaginatedBalances
function balances.getPaginatedBalances(cursor, limit, sortBy, sortOrder, filters)
	local allBalances = balances.getBalances()
	local balancesArray = {}
	local cursorField = "address" -- the cursor will be the wallet address
	for address, balance in pairs(allBalances) do
		table.insert(balancesArray, {
			address = address,
			balance = balance,
		})
	end

	return utils.paginateTableWithCursor(balancesArray, cursor, cursorField, limit, sortBy, sortOrder, filters)
end

-- arns.lua - add filters parameter to getPaginatedReservedNames
function arns.getPaginatedReservedNames(cursor, limit, sortBy, sortOrder, filters)
	--- @type ReservedName[]
	local reservedArray = {}
	local cursorField = "name" -- the cursor will be the name
	for name, reservedName in pairs(arns.getReservedNamesUnsafe()) do
		local reservedNameCopy = utils.deepCopy(reservedName)
		reservedNameCopy.name = name
		table.insert(reservedArray, reservedNameCopy)
	end
	return utils.paginateTableWithCursor(reservedArray, cursor, cursorField, limit, sortBy, sortOrder, filters)
end

-- gar.lua - add filters parameter to getPaginatedDelegates
function gar.getPaginatedDelegates(address, cursor, limit, sortBy, sortOrder, filters)
	local gateway = gar.getGateway(address)
	assert(gateway, "Gateway not found")
	local delegatesArray = {}
	local cursorField = "address"
	for delegateAddress, delegate in pairs(gateway.delegates) do
		--- @diagnostic disable-next-line: inject-field
		delegate.address = delegateAddress
		delegate.vaults = nil -- remove vaults to avoid sending an unbounded array, we can fetch them if needed via getPaginatedDelegations
		table.insert(delegatesArray, delegate)
	end

	return utils.paginateTableWithCursor(delegatesArray, cursor, cursorField, limit, sortBy, sortOrder, filters)
end

-- gar.lua - add filters parameter to getPaginatedAllowedDelegates
function gar.getPaginatedAllowedDelegates(address, cursor, limit, sortOrder, filters)
	local gateway = gar.getGateway(address)
	assert(gateway, "Gateway not found")
	local allowedDelegatesArray = {}

	if gateway.settings.allowedDelegatesLookup then
		for delegateAddress, _ in pairs(gateway.settings.allowedDelegatesLookup) do
			table.insert(allowedDelegatesArray, delegateAddress)
		end
		for delegateAddress, delegate in pairs(gateway.delegates) do
			if delegate.delegatedStake > 0 then
				table.insert(allowedDelegatesArray, delegateAddress)
			end
		end
	end

	local cursorField = nil
	local sortBy = nil
	return utils.paginateTableWithCursor(allowedDelegatesArray, cursor, cursorField, limit, sortBy, sortOrder, filters)
end

-- gar.lua - add filters parameter to getPaginatedDelegations
function gar.getPaginatedDelegations(address, cursor, limit, sortBy, sortOrder, filters)
	local delegationsArray = gar.getFlattenedDelegations(address)
	return utils.paginateTableWithCursor(
		delegationsArray,
		cursor,
		"delegationId",
		limit,
		sortBy or "startTimestamp",
		sortOrder or "asc",
		filters
	)
end

-- primary_names.lua - add filters parameter to getPaginatedPrimaryNameRequests
function primaryNames.getPaginatedPrimaryNameRequests(cursor, limit, sortBy, sortOrder, filters)
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
	return utils.paginateTableWithCursor(primaryNameRequestsArray, cursor, cursorField, limit, sortBy, sortOrder, filters)
end

-- gar.lua - add filters parameter to getPaginatedVaultsForGateway
function gar.getPaginatedVaultsForGateway(gatewayAddress, cursor, limit, sortBy, sortOrder, filters)
	local unsafeGateway = gar.getGatewayUnsafe(gatewayAddress)
	assert(unsafeGateway, "Gateway not found")

	local gatewayVaults = utils.reduce(unsafeGateway.vaults, function(acc, vaultId, vault)
		table.insert(acc, {
			vaultId = vaultId,
			cursorId = vaultId .. "_" .. vault.startTimestamp,
			balance = vault.balance,
			startTimestamp = vault.startTimestamp,
			endTimestamp = vault.endTimestamp,
		})
		return acc
	end, {})

	return utils.paginateTableWithCursor(
		gatewayVaults,
		cursor,
		"cursorId",
		limit,
		sortBy or "startTimestamp",
		sortOrder or "asc",
		filters
	)
end

-- gar.lua - add filters parameter to getPaginatedDelegatesFromAllGateways
function gar.getPaginatedDelegatesFromAllGateways(cursor, limit, sortBy, sortOrder, filters)
	--- @type DelegatesFromAllGateways[]
	local allDelegations = {}

	for gatewayAddress, gateway in pairs(gar.getGatewaysUnsafe()) do
		for delegateAddress, delegate in pairs(gateway.delegates) do
			table.insert(allDelegations, {
				cursorId = delegateAddress .. "_" .. gatewayAddress,
				address = delegateAddress,
				gatewayAddress = gatewayAddress,
				startTimestamp = delegate.startTimestamp,
				delegatedStake = delegate.delegatedStake,
				vaultedStake = utils.reduce(delegate.vaults, function(acc, _, vault)
					return acc + vault.balance
				end, 0),
			})
		end
	end

	return utils.paginateTableWithCursor(
		allDelegations,
		cursor,
		"cursorId",
		limit,
		sortBy or "delegatedStake",
		sortOrder or "desc",
		filters
	)
end

-- gar.lua - add filters parameter to getPaginatedVaultsFromAllGateways
function gar.getPaginatedVaultsFromAllGateways(cursor, limit, sortBy, sortOrder, filters)
	--- @type VaultsFromAllGateways[]
	local allVaults = {}

	local gateways = gar.getGatewaysUnsafe()
	for gatewayAddress, gateway in pairs(gateways) do
		for vaultId, vault in pairs(gateway.vaults) do
			table.insert(allVaults, {
				cursorId = gatewayAddress .. "_" .. vaultId,
				vaultId = vaultId,
				gatewayAddress = gatewayAddress,
				balance = vault.balance,
				startTimestamp = vault.startTimestamp,
				endTimestamp = vault.endTimestamp,
			})
		end
	end

	return utils.paginateTableWithCursor(
		allVaults,
		cursor,
		"cursorId",
		limit,
		sortBy or "startTimestamp",
		sortOrder or "asc",
		filters
	)
end

-- main.lua - update handlers to pass filters
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

		msg.ioEvent:addField("Handler-Memory-KiB-Used", collectgarbage("count"), false)
		collectgarbage("collect")
		msg.ioEvent:addField("Final-Memory-KiB-Used", collectgarbage("count"), false)

		if printEvent then
			msg.ioEvent:printEvent()
		end
	end)
end

-- Paginated-Gateways handler with filters support
addEventingHandler("paginatedGateways", function(msg)
	return msg.Action == "Paginated-Gateways" or msg.Action == "Gateways"
end, function(msg)
	local page = utils.parsePaginationTags(msg)
	local result = gar.getPaginatedGateways(
		page.cursor,
		page.limit,
		page.sortBy or "startTimestamp",
		page.sortOrder or "desc",
		page.filters
	)
	Send(msg, { Target = msg.From, Action = "Gateways-Notice", Data = json.encode(result) })
end)

-- Paginated-Vaults handler with filters support
addEventingHandler("paginatedVaults", function(msg)
	return msg.Action == "Paginated-Vaults" or msg.Action == "Vaults"
end, function(msg)
	local page = utils.parsePaginationTags(msg)
	local pageVaults = vaults.getPaginatedVaults(page.cursor, page.limit, page.sortOrder, page.sortBy, page.filters)
	Send(msg, { Target = msg.From, Action = "Vaults-Notice", Data = json.encode(pageVaults) })
end)

-- Primary-Names handler with filters support
addEventingHandler("getPaginatedPrimaryNames", utils.hasMatchingTag("Action", "Primary-Names"), function(msg)
	local page = utils.parsePaginationTags(msg)
	local result = primaryNames.getPaginatedPrimaryNames(
		page.cursor,
		page.limit,
		page.sortBy or "name",
		page.sortOrder or "asc",
		page.filters
	)

	return Send(msg, {
		Target = msg.From,
		Action = "Primary-Names-Notice",
		Data = json.encode(result),
	})
end)

-- Paginated-Balances handler with filters support
addEventingHandler("paginatedBalances", utils.hasMatchingTag("Action", "Paginated-Balances"), function(msg)
	local page = utils.parsePaginationTags(msg)
	local walletBalances =
		balances.getPaginatedBalances(page.cursor, page.limit, page.sortBy or "balance", page.sortOrder, page.filters)
	Send(msg, { Target = msg.From, Action = "Balances-Notice", Data = json.encode(walletBalances) })
end)

-- Paginated-Reserved-Names handler with filters support
addEventingHandler("paginatedReservedNames", utils.hasMatchingTag("Action", "Reserved-Names"), function(msg)
	local page = utils.parsePaginationTags(msg)
	local reservedNames =
		arns.getPaginatedReservedNames(page.cursor, page.limit, page.sortBy or "name", page.sortOrder, page.filters)
	Send(msg, { Target = msg.From, Action = "Reserved-Names-Notice", Data = json.encode(reservedNames) })
end)

-- Paginated-Delegates handler with filters support
addEventingHandler("paginatedDelegates", function(msg)
	return msg.Action == "Paginated-Delegates" or msg.Action == "Delegates"
end, function(msg)
	local page = utils.parsePaginationTags(msg)
	local result = gar.getPaginatedDelegates(
		msg.Tags.Address or msg.From,
		page.cursor,
		page.limit,
		page.sortBy or "startTimestamp",
		page.sortOrder,
		page.filters
	)
	Send(msg, { Target = msg.From, Action = "Delegates-Notice", Data = json.encode(result) })
end)

-- Paginated-Allowed-Delegates handler with filters support
addEventingHandler(
	"paginatedAllowedDelegates",
	utils.hasMatchingTag("Action", "Paginated-Allowed-Delegates"),
	function(msg)
		local page = utils.parsePaginationTags(msg)
		local result = gar.getPaginatedAllowedDelegates(
			msg.Tags.Address or msg.From,
			page.cursor,
			page.limit,
			page.sortOrder,
			page.filters
		)
		Send(msg, { Target = msg.From, Action = "Allowed-Delegates-Notice", Data = json.encode(result) })
	end
)

-- Paginated-Delegations handler with filters support
addEventingHandler("paginatedDelegations", utils.hasMatchingTag("Action", "Paginated-Delegations"), function(msg)
	local address = msg.Tags.Address or msg.From
	local page = utils.parsePaginationTags(msg)

	assert(utils.isValidAddress(address, true), "Invalid address.")

	local result =
		gar.getPaginatedDelegations(address, page.cursor, page.limit, page.sortBy, page.sortOrder, page.filters)
	Send(msg, {
		Target = msg.From,
		Tags = { Action = "Delegations-Notice" },
		Data = json.encode(result),
	})
end)

-- Paginated-Primary-Name-Requests handler with filters support
addEventingHandler(
	"getPaginatedPrimaryNameRequests",
	utils.hasMatchingTag("Action", "Primary-Name-Requests"),
	function(msg)
		local page = utils.parsePaginationTags(msg)
		local result = primaryNames.getPaginatedPrimaryNameRequests(
			page.cursor,
			page.limit,
			page.sortBy or "startTimestamp",
			page.sortOrder or "asc",
			page.filters
		)
		return Send(msg, {
			Target = msg.From,
			Action = "Primary-Name-Requests-Notice",
			Data = json.encode(result),
		})
	end
)

-- Paginated-Gateway-Vaults handler with filters support
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
			page.sortOrder or "desc",
			page.filters
		)
		return Send(msg, {
			Target = msg.From,
			Action = "Gateway-Vaults-Notice",
			Data = json.encode(result),
		})
	end
)

-- All-Paginated-Delegates handler with filters support
addEventingHandler("allPaginatedDelegates", utils.hasMatchingTag("Action", "All-Paginated-Delegates"), function(msg)
	local page = utils.parsePaginationTags(msg)
	local result =
		gar.getPaginatedDelegatesFromAllGateways(page.cursor, page.limit, page.sortBy, page.sortOrder, page.filters)
	Send(msg, { Target = msg.From, Action = "All-Delegates-Notice", Data = json.encode(result) })
end)

-- All-Paginated-Gateway-Vaults handler with filters support
addEventingHandler("allPaginatedGatewayVaults", utils.hasMatchingTag("Action", "All-Gateway-Vaults"), function(msg)
	local page = utils.parsePaginationTags(msg)
	local result =
		gar.getPaginatedVaultsFromAllGateways(page.cursor, page.limit, page.sortBy, page.sortOrder, page.filters)
	Send(msg, { Target = msg.From, Action = "All-Gateway-Vaults-Notice", Data = json.encode(result) })
end)
