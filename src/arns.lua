-- arns.lua
local utils = require("utils")
local constants = require("constants")
local balances = require("balances")
local demand = require("demand")
local arns = {}
local Auction = require("auctions")

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

	local baseRegistrationFee = demand.baseFeeForNameLength(#name)

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

	if arns.getAuction(name) then
		error("Name is in auction")
	end

	local newRecord = {
		processId = processId,
		startTimestamp = timestamp,
		type = purchaseType,
		undernameLimit = constants.DEFAULT_UNDERNAME_COUNT,
		purchasePrice = totalRegistrationFee,
		endTimestamp = purchaseType == "lease" and timestamp + constants.oneYearMs * years or nil,
	}

	-- Register the leased or permanently owned name
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
	local baseRegistrationFee = demand.baseFeeForNameLength(#name)
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

	if not record then
		error("Name is not registered")
	end

	-- throws errors on invalid requests
	arns.assertValidIncreaseUndername(record, qty, currentTimestamp)

	local yearsRemaining = constants.PERMABUY_LEASE_FEE_LENGTH
	if record.type == "lease" then
		yearsRemaining = arns.calculateYearsBetweenTimestamps(currentTimestamp, record.endTimestamp)
	end

	local baseRegistrationFee = demand.baseFeeForNameLength(#name)
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

--- Asserts that a buy record is valid
--- @param name string The name of the record
--- @param years number|nil The number of years to check
--- @param purchaseType string|nil The purchase type to check
--- @param processId string|nil The processId of the record
function arns.assertValidBuyRecord(name, years, purchaseType, processId)
	-- assert name is valid pattern
	assert(type(name) == "string", "Name is required and must be a string.")
	assert(#name >= 1 and #name <= 51, "Name pattern is invalid.")
	assert(name:match("^%w") and name:match("%w$") and name:match("^[%w-]+$"), "Name pattern is invalid.")
	assert(not utils.isValidAOAddress(name), "Name cannot be a wallet address.")

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
	assert(type(processId) == "string", "Process id is required and must be a string.")
	assert(utils.isValidAOAddress(processId), "Process Id must be a valid AO signer address..")
end

--- Asserts that a record is valid for extending the lease
--- @param record table|nil The record to check
--- @param currentTimestamp number|nil The current timestamp
--- @param years number|nil The number of years to check
function arns.assertValidExtendLease(record, currentTimestamp, years)
	assert(record, "Name is not registered")
	assert(currentTimestamp, "Timestamp is required")
	assert(years, "Years is required")

	assert(record.type ~= "permabuy", "Name is permanently owned and cannot be extended")
	assert(not arns.recordExpired(record, currentTimestamp), "Name is expired")

	local maxAllowedYears = arns.getMaxAllowedYearsExtensionForRecord(record, currentTimestamp)
	assert(years <= maxAllowedYears, "Cannot extend lease beyond 5 years")
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

--- Gets the token cost for an intended action
--- @param intendedAction table The intended action
--- @return number The token cost in mIO of the intended action
function arns.getTokenCost(intendedAction)
	local tokenCost = 0
	local purchaseType = intendedAction.purchaseType
	local years = tonumber(intendedAction.years)
	local name = intendedAction.name
	local baseFee = demand.baseFeeForNameLength(#name)
	local intent = intendedAction.intent
	local qty = tonumber(intendedAction.quantity)
	local record = arns.getRecord(name)
	local currentTimestamp = tonumber(intendedAction.currentTimestamp)

	assert(type(intent) == "string", "Intent is required and must be a string.")
	assert(type(name) == "string", "Name is required and must be a string.")
	if intent == "Buy-Record" then
		-- stub the process id as it is not required for this intent
		local processId = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
		arns.assertValidBuyRecord(name, years, purchaseType, processId)
		tokenCost = arns.calculateRegistrationFee(purchaseType, baseFee, years, demand.getDemandFactor())
	elseif intent == "Extend-Lease" then
		arns.assertValidExtendLease(record, currentTimestamp, years)
		tokenCost = arns.calculateExtensionFee(baseFee, years, demand.getDemandFactor())
	elseif intent == "Increase-Undername-Limit" then
		arns.assertValidIncreaseUndername(record, qty, currentTimestamp)
		assert(record, "Name is not registered")
		local yearsRemaining = constants.PERMABUY_LEASE_FEE_LENGTH
		if record.type == "lease" then
			yearsRemaining = arns.calculateYearsBetweenTimestamps(currentTimestamp, record.endTimestamp)
		end
		tokenCost = arns.calculateUndernameCost(baseFee, qty, record.type, yearsRemaining, demand.getDemandFactor())
	elseif intent == "Upgrade-Name" then
		arns.assertValidUpgradeName(record, currentTimestamp)
		tokenCost = arns.calculatePermabuyFee(baseFee, demand.getDemandFactor())
	end
	-- if token Cost is less than 0, throw an error
	if tokenCost < 0 then
		error("Invalid token cost for " .. intendedAction.intent)
	end
	return tokenCost
end

--- Asserts that a name is valid for upgrading
--- @param record table|nil The record to check
--- @param currentTimestamp number|nil The current timestamp
function arns.assertValidUpgradeName(record, currentTimestamp)
	assert(record, "Name is not registered")
	assert(currentTimestamp, "Timestamp is required")
	assert(record.type ~= "permabuy", "Name is permanently owned")
	assert(
		arns.recordIsActive(record, currentTimestamp) or arns.recordInGracePeriod(record, currentTimestamp),
		"Name is expired"
	)
end

--- Upgrades a leased record to permanently owned
--- @param from string The address of the sender
--- @param name string The name of the record
--- @param currentTimestamp number The current timestamp
--- @return table The upgraded record with name and record fields
function arns.upgradeRecord(from, name, currentTimestamp)
	local record = arns.getRecord(name)
	arns.assertValidUpgradeName(record, currentTimestamp)

	local baseFee = demand.baseFeeForNameLength(#name)
	local demandFactor = demand.getDemandFactor()
	local upgradeCost = arns.calculatePermabuyFee(baseFee, demandFactor)

	if not balances.walletHasSufficientBalance(from, upgradeCost) then
		error("Insufficient balance")
	end

	record.endTimestamp = nil
	record.type = "permabuy"
	record.purchasePrice = upgradeCost

	balances.transfer(ao.id, from, upgradeCost)
	demand.tallyNamePurchase(upgradeCost)

	NameRegistry.records[name] = record
	return {
		name = name,
		record = record,
		totalUpgradeFee = upgradeCost,
		baseRegistrationFee = baseFee,
		remainingBalance = balances.getBalance(from),
		protocolBalance = balances.getBalance(ao.id),
		df = demand.getDemandFactorInfo(),
	}
end

--- Checks if a record is in the grace period
--- @param record table The record to check
--- @param currentTimestamp number The current timestamp
--- @return boolean True if the record is in the grace period, false otherwise (active or expired)
function arns.recordInGracePeriod(record, currentTimestamp)
	return record.endTimestamp
		and record.endTimestamp < currentTimestamp
		and record.endTimestamp + constants.gracePeriodMs > currentTimestamp
end

--- Checks if a record is expired
--- @param record table The record to check
--- @param currentTimestamp number The current timestamp
--- @return boolean True if the record is expired, false otherwise (active or in grace period)
function arns.recordExpired(record, currentTimestamp)
	if record.type == "permabuy" then
		return false
	end
	local isActive = arns.recordIsActive(record, currentTimestamp)
	local inGracePeriod = arns.recordInGracePeriod(record, currentTimestamp)
	local expired = not isActive and not inGracePeriod
	return expired
end

--- Checks if a record is active
--- @param record table The record to check
--- @param currentTimestamp number The current timestamp
--- @return boolean True if the record is active, false otherwise (expired or in grace period)
function arns.recordIsActive(record, currentTimestamp)
	if record.type == "permabuy" then
		return true
	end

	return record.endTimestamp and record.endTimestamp >= currentTimestamp
end

--- Asserts that a record is valid for increasing the undername limit
--- @param record table|nil The record to check
--- @param qty number|nil The quantity to check
--- @param currentTimestamp number|nil The current timestamp
function arns.assertValidIncreaseUndername(record, qty, currentTimestamp)
	assert(record, "Name is not registered")
	assert(currentTimestamp, "Timestamp is required")
	assert(arns.recordIsActive(record, currentTimestamp), "Name must be active to increase undername limit")
	assert(qty > 0 and utils.isInteger(qty), "Qty is invalid")
end

-- AUCTIONS

--- Creates an auction for a given name
--- @param name string The name of the auction
--- @param timestamp number The timestamp to start the auction
--- @param initiator string The address of the initiator of the auction
--- @return Auction|nil The auction instance
function arns.createAuction(name, timestamp, initiator)
	if not arns.getRecord(name) then
		error("Name is not registered. Auctions must be created for registered names.")
	end
	if arns.getAuction(name) then
		error("Auction already exists for name")
	end

	local baseFee = demand.baseFeeForNameLength(#name)
	local demandFactor = demand.getDemandFactor()
	local auction = Auction:new(name, timestamp, demandFactor, baseFee, initiator, arns.calculateRegistrationFee)
	NameRegistry.auctions[name] = auction
	-- ensure the name is removed from the registry
	arns.removeRecord(name)
	return auction
end

--- Gets an auction by name
--- @param name string The name of the auction
--- @return Auction|nil The auction instance
function arns.getAuction(name)
	return NameRegistry.auctions[name]
end

--- Gets all auctions
--- @return table The auctions
function arns.getAuctions()
	return NameRegistry.auctions or {}
end

--- Submits a bid to an auction
--- @param name string The name of the auction
--- @param bidAmount number The amount of the bid
--- @param bidder string The address of the bidder
--- @param timestamp number The timestamp of the bid
--- @param processId string The processId of the bid
--- @param type string The type of the bid
--- @param years number The number of years for the bid
--- @return table The result of the bid including the auction, bidder, bid amount, reward for initiator, reward for protocol, and record
function arns.submitAuctionBid(name, bidAmount, bidder, timestamp, processId, type, years)
	local auction = arns.getAuction(name)
	if not auction then
		error("Auction not found")
	end

	-- assert the bid is between auction start and end timestamps
	if timestamp < auction.startTimestamp or timestamp > auction.endTimestamp then
		-- TODO: we should likely clean up the auction if it is outside of the time range
		error("Bid timestamp is outside of auction start and end timestamps")
	end
	local requiredBid = auction:getPriceForAuctionAtTimestamp(timestamp, type, years)
	local floorPrice = auction:floorPrice(type, years) -- useful for analytics, used by getPriceForAuctionAtTimestamp
	local startPrice = auction:startPrice(type, years) -- useful for analytics, used by getPriceForAuctionAtTimestamp
	local requiredOrBidAmount = bidAmount or requiredBid
	if requiredOrBidAmount < requiredBid then
		error("Bid amount is less than the required bid of " .. requiredBid)
	end

	local finalBidAmount = math.min(requiredOrBidAmount, requiredBid)

	-- check the balance of the bidder
	if not balances.walletHasSufficientBalance(bidder, finalBidAmount) then
		error("Insufficient balance")
	end

	local record = {
		processId = processId,
		startTimestamp = timestamp,
		endTimestamp = type == "lease" and timestamp + constants.oneYearMs * years or nil,
		undernameLimit = constants.DEFAULT_UNDERNAME_COUNT,
		purchasePrice = finalBidAmount,
		type = type,
	}

	-- if the initiator is the protocol, all funds go to the protocol
	local rewardForInitiator = auction.initiator ~= ao.id and math.floor(finalBidAmount * 0.5) or 0
	local rewardForProtocol = auction.initiator ~= ao.id and finalBidAmount - rewardForInitiator or finalBidAmount
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
		floorPrice = floorPrice,
		startPrice = startPrice,
		type = type,
		years = years,
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
			-- psych! create an auction for the name instantiated by protocol - it will get pruned out if the auction expires with no bids
			prunedRecords[name] = record
			arns.createAuction(name, currentTimestamp, ao.id)
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

function arns.assertValidReassignName(record, currentTimestamp, from, newProcessId)
	if not record then
		error("Name is not registered")
	end

	assert(utils.isValidAOAddress(newProcessId), "Invalid Process-Id")

	if record.processId ~= from then
		error("Not authorized to reassign this name")
	end

	if record.endTimestamp then
		local isWithinGracePeriod = record.endTimestamp < currentTimestamp
			and record.endTimestamp + constants.gracePeriodMs > currentTimestamp
		local isExpired = record.endTimestamp + constants.gracePeriodMs < currentTimestamp

		if isWithinGracePeriod then
			error("Name must be extended before it can be reassigned")
		elseif isExpired then
			error("Name is expired")
		end
	end

	return true
end

function arns.reassignName(name, from, currentTimestamp, newProcessId)
	local record = arns.getRecord(name)

	arns.assertValidReassignName(record, currentTimestamp, from, newProcessId)

	NameRegistry.records[name].processId = newProcessId

	return arns.getRecord(name)
end

return arns
