--[[
	Adds Filters tag support to Paginated-Gateways, Primary-Names, and Paginated-Vaults handlers.

	This extends the pagination filters feature (added in 2025-06-16-pagination-filters.lua)
	to also support filtering on gateways, primary names, and vaults endpoints.

	Reviewers: [PLACEHOLDER FOR REVIEWERS]
]]
--
local gar = require(".src.gar")
local primaryNames = require(".src.primary_names")
local vaults = require(".src.vaults")
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

	return utils.paginateTableWithCursor(vaultsArray, cursor, cursorField, limit, sortBy or "address", sortOrder, filters)
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
