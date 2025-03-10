--[[
	Adds demand factor data to the ioEvent for the requestPrimaryName handler.

	Reviewers: Dylan, Ariel, Atticus, Jon, Phil, Derek
]]
--

local demand = require(".src.demand")
local utils = require(".src.utils")
local json = require(".src.json")
local primaryNames = require(".src.primary_names")

-- TODO: confirm Send and Handlers are available in the global scope

local createPrimaryNameRequestHandlerIndex = utils.findInArray(Handlers.list, function(handler)
	return handler.name == "requestPrimaryName"
end)

if not createPrimaryNameRequestHandlerIndex then
	error("Failed to find requestPrimaryName handler")
end

local createPrimaryNameRequestHandler = Handlers.list[createPrimaryNameRequestHandlerIndex]

--- @param ioEvent ARIOEvent
--- @param primaryNameResult CreatePrimaryNameResult|PrimaryNameRequestApproval
local function addPrimaryNameRequestData(ioEvent, primaryNameResult)
	ioEvent:addFieldsIfExist(primaryNameResult, { "baseNameOwner" })
	ioEvent:addFieldsIfExist(primaryNameResult.newPrimaryName, { "owner", "startTimestamp" })
	ioEvent:addFieldsWithPrefixIfExist(primaryNameResult.request, "Request-", { "startTimestamp", "endTimestamp" })
	addResultFundingPlanFields(ioEvent, primaryNameResult)
	addPrimaryNameCounts(ioEvent)

	-- demand factor data
	if primaryNameResult.df and type(primaryNameResult.df) == "table" then
		ioEvent:addField("DF-Trailing-Period-Purchases", (primaryNameResult.df.trailingPeriodPurchases or {}))
		ioEvent:addField("DF-Trailing-Period-Revenues", (primaryNameResult.df.trailingPeriodRevenues or {}))
		ioEvent:addFieldsWithPrefixIfExist(primaryNameResult.df, "DF-", {
			"currentPeriod",
			"currentDemandFactor",
			"consecutivePeriodsWithMinDemandFactor",
			"revenueThisPeriod",
			"purchasesThisPeriod",
		})
	end
end

-- Update the handler to use the new function and add the demand factor data
createPrimaryNameRequestHandler.handler = function(msg)
	local fundFrom = msg.Tags["Fund-From"]
	local name = msg.Tags.Name and string.lower(msg.Tags.Name) or nil
	local initiator = msg.From
	assert(name, "Name is required")
	assert(initiator, "Initiator is required")
	assertValidFundFrom(fundFrom)

	local primaryNameResult = primaryNames.createPrimaryNameRequest(name, initiator, msg.Timestamp, msg.Id, fundFrom)

	addPrimaryNameRequestData(msg.ioEvent, primaryNameResult)

	--- if the from is the new owner, then send an approved notice to the from
	if primaryNameResult.newPrimaryName then
		Send(msg, {
			Target = msg.From,
			Action = "Approve-Primary-Name-Request-Notice",
			Data = json.encode(primaryNameResult),
		})
		return
	end

	if primaryNameResult.request then
		--- send a notice to the msg.From, and the base name owner
		Send(msg, {
			Target = msg.From,
			Action = "Primary-Name-Request-Notice",
			Data = json.encode(primaryNameResult),
		})
		Send(msg, {
			Target = primaryNameResult.baseNameOwner,
			Action = "Primary-Name-Request-Notice",
			Data = json.encode(primaryNameResult),
		})
	end
end
