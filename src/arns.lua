-- arns.lua
local utils = require("utils")
local constants = require("constants")
local balances = require("balances")
local demand = require("demand")
local arns = {}

NameRegistry = NameRegistry or {
	reserved = {},
	records = {},
	auctions = {},
}

function arns.buyRecord(name, purchaseType, years, from, timestamp, processId)
	-- don't catch, let the caller handle the error
	arns.assertValidBuyRecord(name, years, purchaseType, processId)
	if purchaseType == nil then
		purchaseType = "lease" -- set to lease by default
	end

	if years == nil and purchaseType == "lease" then
		years = 1 -- set to 1 year by default
	end

	local baseRegistrationFee = demand.getFees()[#name]

	local totalRegistrationFee =
		arns.calculateRegistrationFee(purchaseType, baseRegistrationFee, years, demand.getDemandFactor())

	if balances.getBalance(from) < totalRegistrationFee then
		error("Insufficient balance")
	end

	local record = arns.getRecord(name)
	local isPermabuy = record ~= nil and record.type == "permabuy"
	local isActiveLease = record ~= nil and (record.endTimestamp or 0) + constants.gracePeriodMs > timestamp

	if isPermabuy or isActiveLease then
		error("Name is already registered")
	end

	if arns.getReservedName(name) and arns.getReservedName(name).target ~= from then
		error("Name is reserved")
	end

	local newRecord = {
		processId = processId,
		startTimestamp = timestamp,
		type = purchaseType,
		undernameLimit = constants.DEFAULT_UNDERNAME_COUNT,
		purchasePrice = totalRegistrationFee,
		endTimestamp = purchaseType == "lease" and timestamp + constants.oneYearMs * years or nil,
	}

	-- Register the leased or permabought name
	-- Transfer tokens to the protocol balance
	balances.transfer(ao.id, from, totalRegistrationFee)
	arns.addRecord(name, newRecord)
	demand.tallyNamePurchase(totalRegistrationFee)
	return {
		record = arns.getRecord(name),
		totalRegistrationFee = totalRegistrationFee,
		baseRegistrationFee = baseRegistrationFee,
		remainingBalance = balances.getBalance(from),
		protocolBalance = balances.getBalance(ao.id),
		recordsCount = utils.lengthOfTable(NameRegistry.records),
		reservedRecordsCount = utils.lengthOfTable(NameRegistry.reserved),
		df = demand.getDemandFactorInfo(),
	}
end

function arns.addRecord(name, record)
	NameRegistry.records[name] = record

	-- remove reserved name if it exists in reserved
	if arns.getReservedName(record.name) then
		NameRegistry.reserved[name] = nil
	end
end

function arns.getPaginatedRecords(cursor, limit, sortBy, sortOrder)
	local records = arns.getRecords()
	local recordsArray = {}
	local cursorField = "name" -- the cursor will be the name
	for name, record in pairs(records) do
		record.name = name
		table.insert(recordsArray, record)
	end

	return utils.paginateTableWithCursor(recordsArray, cursor, cursorField, limit, sortBy, sortOrder)
end

function arns.extendLease(from, name, years, currentTimestamp)
	local record = arns.getRecord(name)
	-- throw error if invalid
	arns.assertValidExtendLease(record, currentTimestamp, years)
	local baseRegistrationFee = demand.getFees()[#name]
	local totalExtensionFee = arns.calculateExtensionFee(baseRegistrationFee, years, demand.getDemandFactor())

	if balances.getBalance(from) < totalExtensionFee then
		error("Insufficient balance")
	end

	-- modify the record with the new end timestamp
	arns.modifyRecordEndTimestamp(name, record.endTimestamp + constants.oneYearMs * years)

	-- Transfer tokens to the protocol balance
	balances.transfer(ao.id, from, totalExtensionFee)
	demand.tallyNamePurchase(totalExtensionFee)
	return {
		record = arns.getRecord(name),
		totalExtensionFee = totalExtensionFee,
		baseRegistrationFee = baseRegistrationFee,
		remainingBalance = balances.getBalance(from),
		protocolBalance = balances.getBalance(ao.id),
		df = demand.getDemandFactorInfo(),
	}
end

function arns.calculateExtensionFee(baseFee, years, demandFactor)
	local extensionFee = arns.calculateAnnualRenewalFee(baseFee, years)
	return math.floor(demandFactor * extensionFee)
end

function arns.increaseundernameLimit(from, name, qty, currentTimestamp)
	-- validate record can increase undernames
	local record = arns.getRecord(name)

	-- throws errors on invalid requests
	arns.assertValidIncreaseUndername(record, qty, currentTimestamp)

	local yearsRemaining = constants.PERMABUY_LEASE_FEE_LENGTH
	if record.type == "lease" then
		yearsRemaining = arns.calculateYearsBetweenTimestamps(currentTimestamp, record.endTimestamp)
	end

	local baseRegistrationFee = demand.getFees()[#name]
	local additionalUndernameCost =
		arns.calculateUndernameCost(baseRegistrationFee, qty, record.type, yearsRemaining, demand.getDemandFactor())

	if additionalUndernameCost < 0 then
		error("Invalid undername cost")
	end

	if balances.getBalance(from) < additionalUndernameCost then
		error("Insufficient balance")
	end

	-- update the record with the new undername count
	arns.modifyRecordundernameLimit(name, qty)

	-- Transfer tokens to the protocol balance
	balances.transfer(ao.id, from, additionalUndernameCost)
	demand.tallyNamePurchase(additionalUndernameCost)
	return {
		record = arns.getRecord(name),
		additionalUndernameCost = additionalUndernameCost,
		baseRegistrationFee = baseRegistrationFee,
		remainingBalance = balances.getBalance(from),
		protocolBalance = balances.getBalance(ao.id),
		recordsCount = utils.lengthOfTable(NameRegistry.records),
		reservedRecordsCount = utils.lengthOfTable(NameRegistry.reserved),
		df = demand.getDemandFactorInfo(),
	}
end

function arns.getRecord(name)
	return utils.deepCopy(NameRegistry.records[name])
end

function arns.getActiveArNSNamesBetweenTimestamps(startTimestamp, endTimestamp)
	local records = arns.getRecords()
	local activeNames = {}
	for name, record in pairs(records) do
		if
			record.type == "permabuy"
			or (
				record.type == "lease"
				and record.endTimestamp
				and record.startTimestamp
				and record.startTimestamp <= startTimestamp
				and record.endTimestamp >= endTimestamp
			)
		then
			table.insert(activeNames, name)
		end
	end
	return activeNames
end

function arns.getRecords()
	local records = utils.deepCopy(NameRegistry.records)
	return records or {}
end

function arns.getReservedNames()
	local reserved = utils.deepCopy(NameRegistry.reserved)
	return reserved or {}
end

function arns.getReservedName(name)
	return utils.deepCopy(NameRegistry.reserved[name])
end

function arns.modifyRecordundernameLimit(name, qty)
	local record = arns.getRecord(name)
	if not record then
		error("Name is not registered")
	end

	NameRegistry.records[name].undernameLimit = record.undernameLimit + qty
	return arns.getRecord(name)
end

function arns.modifyRecordEndTimestamp(name, newEndTimestamp)
	local record = arns.getRecord(name)
	if not record then
		error("Name is not registered")
	end

	-- if new end timestamp + existing timetamp is > 5 years throw error
	if newEndTimestamp > record.startTimestamp + constants.maxLeaseLengthYears * constants.oneYearMs then
		error("Cannot extend lease beyond 5 years")
	end

	NameRegistry.records[name].endTimestamp = newEndTimestamp
end

-- internal functions
function arns.calculateLeaseFee(baseFee, years, demandFactor)
	local annualRegistrationFee = arns.calculateAnnualRenewalFee(baseFee, years)
	local totalLeaseCost = baseFee + annualRegistrationFee
	return math.floor(demandFactor * totalLeaseCost)
end

function arns.calculateAnnualRenewalFee(baseFee, years)
	local totalAnnualRenewalCost = baseFee * constants.ANNUAL_PERCENTAGE_FEE * years
	return math.floor(totalAnnualRenewalCost)
end

function arns.calculatePermabuyFee(baseFee, demandFactor)
	local permabuyPrice = baseFee + arns.calculateAnnualRenewalFee(baseFee, constants.PERMABUY_LEASE_FEE_LENGTH)
	return math.floor(demandFactor * permabuyPrice)
end

function arns.calculateRegistrationFee(purchaseType, baseFee, years, demandFactor)
	if purchaseType == "lease" then
		return arns.calculateLeaseFee(baseFee, years, demandFactor)
	elseif purchaseType == "permabuy" then
		return arns.calculatePermabuyFee(baseFee, demandFactor)
	end
end

function arns.calculateUndernameCost(baseFee, increaseQty, registrationType, years, demandFactor)
	local undernamePercentageFee = 0
	if registrationType == "lease" then
		undernamePercentageFee = constants.UNDERNAME_LEASE_FEE_PERCENTAGE
	elseif registrationType == "permabuy" then
		undernamePercentageFee = constants.UNDERNAME_PERMABUY_FEE_PERCENTAGE
	else
		error("Invalid registration type")
	end

	local totalFeeForQtyAndYears = baseFee * undernamePercentageFee * increaseQty * years
	return math.floor(demandFactor * totalFeeForQtyAndYears)
end

-- this is intended to be a float point number - TODO: protect against large decimals
function arns.calculateYearsBetweenTimestamps(startTimestamp, endTimestamp)
	local yearsRemainingFloat = (endTimestamp - startTimestamp) / constants.oneYearMs
	return yearsRemainingFloat
end

function arns.assertValidBuyRecord(name, years, purchaseType, processId)
	-- assert name is valid pattern
	assert(type(name) == "string", "Name is required and must be a string.")
	assert(#name >= 1 and #name <= 51, "Name pattern is invalid.")
	assert(name:match("^%w") and name:match("%w$") and name:match("^[%w-]+$"), "Name pattern is invalid.")

	-- assert purchase type if present is lease or permabuy
	assert(purchaseType == nil or purchaseType == "lease" or purchaseType == "permabuy", "Purchase-Type is invalid.")

	if purchaseType == "lease" or purchaseType == nil then
		-- only check on leases (nil is set to lease)
		-- If 'years' is present, validate it as an integer between 1 and 5
		assert(
			years == nil or (type(years) == "number" and years % 1 == 0 and years >= 1 and years <= 5),
			"Years is invalid. Must be an integer between 1 and 5"
		)
	end

	-- assert processId is valid pattern
	assert(type(processId) == "string", "ProcessId is required and must be a string.")
	assert(utils.isValidBase64Url(processId), "ProcessId pattern is invalid.")
end

function arns.assertValidExtendLease(record, currentTimestamp, years)
	if not record then
		error("Name is not registered")
	end

	if record.type == "permabuy" then
		error("Name is permabought and cannot be extended")
	end

	if record.endTimestamp and record.endTimestamp + constants.gracePeriodMs < currentTimestamp then
		error("Name is expired")
	end

	local maxAllowedYears = arns.getMaxAllowedYearsExtensionForRecord(record, currentTimestamp)
	if years > maxAllowedYears then
		error("Cannot extend lease beyond 5 years")
	end
end

function arns.getMaxAllowedYearsExtensionForRecord(record, currentTimestamp)
	if not record.endTimestamp then
		return 0
	end

	if currentTimestamp > record.endTimestamp and currentTimestamp < record.endTimestamp + constants.gracePeriodMs then
		return constants.maxLeaseLengthYears
	end

	-- TODO: should we put this as the ceiling? or should we allow people to extend as soon as it is purchased
	local yearsRemainingOnLease = math.ceil((record.endTimestamp - currentTimestamp) / constants.oneYearMs)

	-- a number between 0 and 5 (MAX_YEARS)
	return constants.maxLeaseLengthYears - yearsRemainingOnLease
end

function arns.getRegistrationFees()
	local fees = {}
	local demandFactor = demand.getDemandFactor()

	for nameLength, baseFee in pairs(demand.getFees()) do
		local feesForNameLength = {
			lease = {},
			permabuy = 0,
		}
		for years = 1, constants.maxLeaseLengthYears do
			feesForNameLength.lease[tostring(years)] = arns.calculateLeaseFee(baseFee, years, demandFactor)
		end
		feesForNameLength.permabuy = arns.calculatePermabuyFee(baseFee, demandFactor)
		fees[tostring(nameLength)] = feesForNameLength
	end
	return fees
end

function arns.getTokenCost(intendedAction)
	local tokenCost = 0
	if intendedAction.intent == "Buy-Record" then
		local purchaseType = intendedAction.purchaseType
		local years = intendedAction.years
		local name = intendedAction.name
		assert(type(name) == "string", "Name is required and must be a string.")
		assert(purchaseType == "lease" or purchaseType == "permabuy", "PurchaseType is invalid.")
		if purchaseType == "lease" then
			assert(years >= 1 and years <= 5, "Years is invalid. Must be an integer between 1 and 5")
		end
		local baseFee = demand.getFees()[#name]
		tokenCost = arns.calculateRegistrationFee(purchaseType, baseFee, years, demand.getDemandFactor())
	elseif intendedAction.intent == "Extend-Lease" then
		local name = intendedAction.name
		local years = intendedAction.years
		assert(type(name) == "string", "Name is required and must be a string.")
		assert(years >= 1 and years <= 5, "Years is invalid. Must be an integer between 1 and 5")
		local record = arns.getRecord(name)
		if not record then
			error("Name is not registered")
		end
		if record.type == "permabuy" then
			error("Name is permabought and cannot be extended")
		end
		local years = intendedAction.years
		local baseFee = demand.getFees()[#intendedAction.name]
		tokenCost = arns.calculateExtensionFee(baseFee, years, demand.getDemandFactor())
	elseif intendedAction.intent == "Increase-Undername-Limit" then
		local name = intendedAction.name
		local qty = tonumber(intendedAction.quantity)
		local currentTimestamp = intendedAction.currentTimestamp
		assert(type(name) == "string", "Name is required and must be a string.")
		assert(
			qty >= 1 and qty <= 9990 and utils.isInteger(qty),
			"Quantity is invalid, must be an integer between 1 and 9990"
		)
		assert(type(currentTimestamp) == "number" and currentTimestamp > 0, "Timestamp is required")
		local record = arns.getRecord(intendedAction.name)
		if not record then
			error("Name is not registered")
		end
		local yearsRemaining = constants.PERMABUY_LEASE_FEE_LENGTH
		if record.type == "lease" then
			yearsRemaining = arns.calculateYearsBetweenTimestamps(currentTimestamp, record.endTimestamp)
		end
		local baseFee = demand.getFees()[#intendedAction.name]
		tokenCost = arns.calculateUndernameCost(baseFee, qty, record.type, yearsRemaining, demand.getDemandFactor())
	end
	return tokenCost
end

function arns.assertValidIncreaseUndername(record, qty, currentTimestamp)
	if not record then
		error("Name is not registered")
	end

	if
		record.endTimestamp
		and record.endTimestamp < currentTimestamp
		and record.endTimestamp + constants.gracePeriodMs > currentTimestamp
	then
		error("Name must be extended before additional unernames can be purchased")
	end

	if record.endTimestamp and record.endTimestamp + constants.gracePeriodMs < currentTimestamp then
		error("Name is expired")
	end

	if qty < 1 or not utils.isInteger(qty) then
		error("Qty is invalid")
	end

	return true
end

-- AUCTIONS
function arns.createAuction(name, timestamp, initiator)
	if not arns.getRecord(name) then
		error("Name is not registered. Auctions must be created for registered names.")
	end
	if arns.getAuction(name) then
		error("Auction already exists for name")
	end
	local record = arns.getRecord(name)
	local auctionDurationMs = 60 * 1000 * 60 * 24 * 14 -- 14 days in milliseconds
	local decayRate = 0.020379 / auctionDurationMs
	local scalingExponent = 190
	local endTimestamp = timestamp + auctionDurationMs
	local baseFee = demand.getFees()[#name]
	local demandFactor = demand.getDemandFactor()
	local floorPrice = arns.calculateRegistrationFee(record.type, baseFee, 1, demandFactor)
	local startPriceMultiplier = 50
	local startPrice = floorPrice * startPriceMultiplier
	local auction = {
		name = name,
		type = record.type, -- prices are dynamically based on the requested bid time (e.g. years - 5)
		startTimestamp = timestamp,
		endTimestamp = endTimestamp,
		startPrice = startPrice,
		floorPrice = floorPrice,
		initiator = initiator,
		settings = {
			durationMs = auctionDurationMs,
			demandFactor = demand.getDemandFactor(),
			baseFee = baseFee,
			decayRate = decayRate,
			scalingExponent = scalingExponent,
		},
	}
	NameRegistry.auctions[name] = auction
	-- ensure the name is removed from the registry
	arns.removeRecord(name)
	return auction
end

function arns.getAuction(name)
	return utils.deepCopy(NameRegistry.auctions[name])
end

function arns.getAuctions()
	local auctions = utils.deepCopy(NameRegistry.auctions)
	return auctions or {}
end

function arns.computePricesForAuction(auction, intervalMs)
	local prices = {}
	intervalMs = intervalMs or 1000 * 60 * 5 -- default to 5 minute price intervals
	for timestampAtInterval = auction.startTimestamp, auction.endTimestamp, intervalMs do
		local priceAtTimestamp = arns.getCurrentBidPriceForAuction(auction, timestampAtInterval)
		prices[timestampAtInterval] = priceAtTimestamp
	end
	return prices
end

function arns.getCurrentBidPriceForAuction(auction, timestamp)
	local decayRate = auction.settings.decayRate
	local scalingExponent = auction.settings.scalingExponent
	if timestamp < auction.startTimestamp or timestamp > auction.endTimestamp then
		error("Timestamp is outside of auction start and end timestamps")
	end
	local timeSinceStart = timestamp - auction.startTimestamp
	local decayFactor = math.max(1 - timeSinceStart * decayRate, 0) ^ scalingExponent
	local currentAuctionPrice = auction.startPrice * decayFactor
	return math.floor(math.max(currentAuctionPrice, auction.floorPrice))
end

function arns.submitAuctionBid(name, bidAmount, bidder, timestamp, processId, years)
	local auction = arns.getAuction(name)
	if not auction then
		error("Auction does not exist")
	end

	-- assert the bid is between auction start and end timestamps
	if timestamp < auction.startTimestamp or timestamp > auction.endTimestamp then
		-- TODO: we should likely clean up the auction if it is outside of the time range
		error("Bid timestamp is outside of auction start and end timestamps")
	end

	local requiredBid = arns.getCurrentBidPriceForAuction(auction, timestamp)
	local requiredOrBidAmount = bidAmount or requiredBid
	if requiredOrBidAmount < requiredBid then
		error("Bid amount is less than the required bid of " .. requiredBid)
	end

	local finalBidAmount = math.min(requiredOrBidAmount, requiredBid)

	-- check the balance of the bidder
	if not utils.walletHasSufficientBalance(bidder, finalBidAmount) then
		error("Insufficient balance")
	end

	local record = {
		processId = processId,
		startTimestamp = timestamp,
		endTimestamp = auction.type == "lease" and timestamp + constants.oneYearMs * auction.years or nil,
		type = auction.type,
		undernameLimit = constants.DEFAULT_UNDERNAME_COUNT,
		purchasePrice = finalBidAmount,
	}
	local rewardForInitiator = math.floor(finalBidAmount * 0.5)
	local rewardForProtocol = finalBidAmount - rewardForInitiator
	-- reduce bidder balance by the final bid amount
	balances.transfer(auction.initiator, bidder, rewardForInitiator)
	balances.transfer(ao.id, bidder, rewardForProtocol)
	arns.removeAuction(name)
	arns.addRecord(name, record)
	-- make sure we tally name purchase given, even though only half goes to protocol
	-- TODO: DO WE WANT TO TALLY THE ENTIRE AMOUNT OR JUST THE REWARD FOR THE PROTOCOL?
	demand.tallyNamePurchase(finalBidAmount)
	return {
		auction = auction,
		bidder = bidder,
		bidAmount = finalBidAmount,
		rewardForInitiator = rewardForInitiator,
		rewardForProtocol = rewardForProtocol,
		record = record,
	}
end

function arns.removeAuction(name)
	local auction = arns.getAuction(name)
	NameRegistry.auctions[name] = nil
	return auction
end

function arns.removeRecord(name)
	local record = NameRegistry.records[name]
	NameRegistry.records[name] = nil
	return record
end

function arns.removeReservedName(name)
	local reserved = NameRegistry.reserved[name]
	NameRegistry.reserved[name] = nil
	return reserved
end

-- prune records that have expired
function arns.pruneRecords(currentTimestamp)
	local prunedRecords = {}
	-- identify any records that are leases and that have expired, account for a one week grace period in seconds
	for name, record in pairs(arns.getRecords()) do
		if record.type == "lease" and record.endTimestamp + constants.gracePeriodMs <= currentTimestamp then
			prunedRecords[name] = arns.removeRecord(name)
		end
	end
	return prunedRecords
end

-- prune auctions that have expired
function arns.pruneAuctions(currentTimestamp)
	local prunedAuctions = {}
	for name, auction in pairs(arns.getAuctions()) do
		if auction.endTimestamp <= currentTimestamp then
			prunedAuctions[name] = arns.removeAuction(name)
		end
	end
	return prunedAuctions
end

-- identify any reserved names that have expired, account for a one week grace period in seconds
function arns.pruneReservedNames(currentTimestamp)
	local prunedReserved = {}
	for name, details in pairs(arns.getReservedNames()) do
		if details.endTimestamp and details.endTimestamp <= currentTimestamp then
			prunedReserved[name] = arns.removeReservedName(name)
		end
	end
	return prunedReserved
end

return arns
