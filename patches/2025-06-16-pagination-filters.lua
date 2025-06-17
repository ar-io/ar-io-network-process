--[[
	Adds support for providing JSON filters for pagination.

	Note: This patch only supports filters for the records handler. It does not support filters for the other handlers. Additional patches will be needed to support filters for the other handlers.

	Reviewers: Dylan, Ariel, Jonathon, Phil
]]
--
local arns = require(".src.arns")
local utils = require(".src.utils")
local json = require(".src.json")
local ARIOEvent = require(".src.ario_event")

--- utils.lua - add createFilterFunction function and patch paginateTableWithCursor to support filters
_G.package.loaded[".src.utils"].parsePaginationTags = function(msg)
	local cursor = msg.Tags.Cursor
	local limit = tonumber(msg.Tags["Limit"]) or 100
	assert(limit <= 1000, "Limit must be less than or equal to 1000")
	local sortOrder = msg.Tags["Sort-Order"] and string.lower(msg.Tags["Sort-Order"]) or "desc"
	assert(sortOrder == "asc" or sortOrder == "desc", "Invalid sortOrder: expected 'asc' or 'desc'")
	local sortBy = msg.Tags["Sort-By"]
	local filters = utils.safeDecodeJson(msg.Tags.Filters)
	assert(msg.Tags.Filters == nil or filters ~= nil, "Invalid JSON supplied in Filters tag")
	return {
		cursor = cursor,
		limit = limit,
		sortBy = sortBy,
		sortOrder = sortOrder,
		filters = filters,
	}
end

_G.package.loaded[".src.utils"].createFilterFunction = function(filters)
	if type(filters) ~= "table" then
		return nil
	end

	-- Precompute lookup maps for array values so repeated checks are O(1)
	local lookups = {}
	for field, value in pairs(filters) do
		if type(value) == "table" then
			lookups[field] = utils.createLookupTable(value)
		else
			lookups[field] = value
		end
	end

	return function(item)
		for field, expected in pairs(lookups) do
			local itemValue = type(item) == "table" and item[field] or nil
			if type(expected) == "table" then
				if not expected[itemValue] then
					return false
				end
			else
				if itemValue ~= expected then
					return false
				end
			end
		end
		return true
	end
end

_G.package.loaded[".src.utils"].paginateTableWithCursor = function(
	tableArray,
	cursor,
	cursorField,
	limit,
	sortBy,
	sortOrder,
	filters
)
	local filterFn = nil
	if type(filters) == "table" then
		filterFn = utils.createFilterFunction(filters)
	end

	local filteredArray = filterFn
			and utils.filterArray(tableArray, function(_, value)
				return filterFn(value)
			end)
		or tableArray

	assert(sortOrder == "asc" or sortOrder == "desc", "Invalid sortOrder: expected 'asc' or 'desc'")
	local sortFields = { { order = sortOrder, field = sortBy } }
	if cursorField ~= nil and cursorField ~= sortBy then
		-- Tie-breaker to guarantee deterministic pagination
		table.insert(sortFields, { order = "asc", field = cursorField })
	end
	local sortedArray = utils.sortTableByFields(filteredArray, sortFields)

	if not sortedArray or #sortedArray == 0 then
		return {
			items = {},
			limit = limit,
			totalItems = 0,
			sortBy = sortBy,
			sortOrder = sortOrder,
			nextCursor = nil,
			hasMore = false,
		}
	end

	local startIndex = 1

	if cursor then
		for i, obj in ipairs(sortedArray) do
			if cursorField and obj[cursorField] == cursor or cursor == obj then
				startIndex = i + 1
				break
			end
		end
	end

	local items = {}
	local endIndex = math.min(startIndex + limit - 1, #sortedArray)

	for i = startIndex, endIndex do
		table.insert(items, sortedArray[i])
	end

	local nextCursor = nil
	if endIndex < #sortedArray then
		nextCursor = cursorField and sortedArray[endIndex][cursorField] or sortedArray[endIndex]
	end

	return {
		items = items,
		limit = limit,
		totalItems = #sortedArray,
		sortBy = sortBy,
		sortOrder = sortOrder,
		nextCursor = nextCursor, -- the last item in the current page
		hasMore = nextCursor ~= nil,
	}
end

-- arns.lua - pass the filters to the paginateTableWithCursor function
_G.package.loaded[".src.arns"].getPaginatedRecords = function(cursor, limit, sortBy, sortOrder, filters)
	--- @type Record[]
	local recordsArray = {}
	local cursorField = "name" -- the cursor will be the name
	for name, record in pairs(arns.getRecordsUnsafe()) do
		local recordCopy = utils.deepCopy(record)
		--- @diagnostic disable-next-line: inject-field
		recordCopy.name = name
		table.insert(recordsArray, recordCopy)
	end

	return utils.paginateTableWithCursor(recordsArray, cursor, cursorField, limit, sortBy, sortOrder, filters)
end

-- main.lua - allow providing filters in the pagination tags for records handler ONLY in this patch
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

addEventingHandler("paginatedRecords", function(msg)
	return msg.Action == "Paginated-Records" or msg.Action == "Records"
end, function(msg)
	local page = utils.parsePaginationTags(msg)
	local result =
		arns.getPaginatedRecords(page.cursor, page.limit, page.sortBy or "startTimestamp", page.sortOrder, page.filters)
	Send(msg, { Target = msg.From, Action = "Records-Notice", Data = json.encode(result) })
end)
