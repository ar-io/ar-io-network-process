--[[
	Adds demand factor data to the ioEvent for the requestPrimaryName handler.

	Reviewers: Dylan, Ariel, Atticus, Jon, Phil, Derek
]]
--
local utils = require(".src.utils")
local primaryNames = require(".src.primary_names")
local arns = require(".src.arns")
local gar = require(".src.gar")
local balances = require(".src.balances")
local demand = require(".src.demand")
local constants = require(".src.constants")

-- Update the primaryNames global function to return the demand factor data
primaryNames.createPrimaryNameRequest = function(name, initiator, timestamp, msgId, fundFrom)
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

-- Now update main.lua to use the new function and add the demand factor data
local createPrimaryNameRequestHandlerIndex = utils.findInArray(Handlers.list, function(handler)
	return handler.name == "requestPrimaryName"
end)

if not createPrimaryNameRequestHandlerIndex then
	error("Failed to find requestPrimaryName handler")
end

local createPrimaryNameRequestHandler = Handlers.list[createPrimaryNameRequestHandlerIndex]
if not createPrimaryNameRequestHandler then
	error("Failed to find requestPrimaryName handler")
end

local function Send(msg, response)
	if msg.reply then
		--- Reference: https://github.com/permaweb/aos/blob/main/blueprints/patch-legacy-reply.lua
		msg.reply(response)
	else
		ao.send(response)
	end
end

local function assertValidFundFrom(fundFrom)
	if fundFrom == nil then
		return
	end
	local validFundFrom = utils.createLookupTable({ "any", "balance", "stakes" })
	assert(validFundFrom[fundFrom], "Invalid fund from type. Must be one of: any, balance, stakes")
end

local function addPrimaryNameCounts(ioEvent)
	ioEvent:addField("Total-Primary-Names", utils.lengthOfTable(primaryNames.getUnsafePrimaryNames()))
	ioEvent:addField("Total-Primary-Name-Requests", utils.lengthOfTable(primaryNames.getUnsafePrimaryNameRequests()))
end

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
--- @param primaryNameResult CreatePrimaryNameResult|PrimaryNameRequestApproval
local function addPrimaryNameRequestData(ioEvent, primaryNameResult)
	ioEvent:addFieldsIfExist(primaryNameResult, { "baseNameOwner" })
	ioEvent:addFieldsIfExist(primaryNameResult.newPrimaryName, { "owner", "startTimestamp" })
	ioEvent:addFieldsWithPrefixIfExist(primaryNameResult.request, "Request-", { "startTimestamp", "endTimestamp" })
	addResultFundingPlanFields(ioEvent, primaryNameResult)
	addPrimaryNameCounts(ioEvent)

	-- add the demand factor data to the ioEvent
	if primaryNameResult.demandFactor and type(primaryNameResult.demandFactor) == "table" then
		ioEvent:addField("DF-Trailing-Period-Purchases", (primaryNameResult.demandFactor.trailingPeriodPurchases or {}))
		ioEvent:addField("DF-Trailing-Period-Revenues", (primaryNameResult.demandFactor.trailingPeriodRevenues or {}))
		ioEvent:addFieldsWithPrefixIfExist(primaryNameResult.demandFactor, "DF-", {
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
end
