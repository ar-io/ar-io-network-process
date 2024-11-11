-- arns.lua
local utils = require("utils")
local constants = require("constants")
local balances = require("balances")
local demand = require("demand")
local arns = {}
local Auction = require("auctions")
local gar = require("gar")

NameRegistry = NameRegistry or {
	reserved = {},
	records = {},
	auctions = {},
}

--- Buys a record
--- @param name string The name of the record
--- @param purchaseType string The purchase type (lease/permabuy)
--- @param years number|nil The number of years
--- @param from string The address of the sender
--- @param timestamp number The current timestamp
--- @param processId string The process id
--- @param msgId string The current message id
--- @param fundFrom string|nil The intended payment sources; one of "any", "balance", or "stakes". Default "balance"
--- @return table The updated record
function arns.buyRecord(name, purchaseType, years, from, timestamp, processId, msgId, fundFrom)
	fundFrom = fundFrom or "balance"
	arns.assertValidBuyRecord(name, years, purchaseType, processId)
	if purchaseType == nil then
		purchaseType = "lease" -- set to lease by default
	end

	if not years and purchaseType == "lease" then
		years = 1 -- set to 1 year by default
	end
	local numYears = purchaseType == "lease" and (years or 1) or 0

	local baseRegistrationFee = demand.baseFeeForNameLength(#name)

	local tokenCostResult = arns.getTokenCost({
		currentTimestamp = timestamp,
		intent = "Buy-Record",
		name = name,
		purchaseType = purchaseType,
		years = numYears,
		from = from,
	})

	local totalRegistrationFee = tokenCostResult.tokenCost

	local fundingPlan = gar.getFundingPlan(from, totalRegistrationFee, fundFrom)
	assert(fundingPlan and fundingPlan.shortfall == 0 or false, "Insufficient balances")

	local record = arns.getRecord(name)
	local isPermabuy = record ~= nil and record.type == "permabuy"
	local isActiveLease = record ~= nil and (record.endTimestamp or 0) + constants.gracePeriodMs > timestamp

	assert(not isPermabuy and not isActiveLease, "Name is already registered")

	assert(not arns.getReservedName(name) or arns.getReservedName(name).target == from, "Name is reserved")
	assert(not arns.getAuction(name), "Name is in auction")

	local newRecord = {
		processId = processId,
		startTimestamp = timestamp,
		type = purchaseType,
		undernameLimit = constants.DEFAULT_UNDERNAME_COUNT,
		purchasePrice = totalRegistrationFee,
		endTimestamp = purchaseType == "lease" and timestamp + constants.oneYearMs * years or nil,
	}

	-- Register the leased or permanently owned name
	local fundingResult = gar.applyFundingPlan(fundingPlan, msgId, timestamp)
	assert(fundingResult.totalFunded == totalRegistrationFee, "Funding plan application failed")
	-- Transfer tokens to the protocol balance
	balances.increaseBalance(ao.id, totalRegistrationFee)
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
		fundingPlan = fundingPlan,
		fundingResult = fundingResult,
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

---@param from string The address of the sender
---@param name string The name of the record
---@param years number The number of years to extend the lease
---@param currentTimestamp number The current timestamp
---@param msgId string The current message id
---@param fundFrom string|nil The intended payment sources; one of "any", "balance", or "stakes". Default "balance"
function arns.extendLease(from, name, years, currentTimestamp, msgId, fundFrom)
	fundFrom = fundFrom or "balance"
	local record = arns.getRecord(name)
	assert(record, "Name is not registered")
	-- throw error if invalid
	arns.assertValidExtendLease(record, currentTimestamp, years)
	local baseRegistrationFee = demand.baseFeeForNameLength(#name)
	local tokenCostResult = arns.getTokenCost({
		currentTimestamp = currentTimestamp,
		intent = "Extend-Lease",
		name = name,
		years = years,
		from = from,
	})
	local totalExtensionFee = tokenCostResult.tokenCost

	local fundingPlan = gar.getFundingPlan(from, totalExtensionFee, fundFrom)
	assert(fundingPlan and fundingPlan.shortfall == 0 or false, "Insufficient balances")
	local fundingResult = gar.applyFundingPlan(fundingPlan, msgId, currentTimestamp)
	assert(fundingResult.totalFunded == totalExtensionFee, "Funding plan application failed")

	-- modify the record with the new end timestamp
	arns.modifyRecordEndTimestamp(name, record.endTimestamp + constants.oneYearMs * years)

	-- Transfer tokens to the protocol balance
	balances.increaseBalance(ao.id, totalExtensionFee)
	demand.tallyNamePurchase(totalExtensionFee)
	return {
		record = arns.getRecord(name),
		totalExtensionFee = totalExtensionFee,
		baseRegistrationFee = baseRegistrationFee,
		remainingBalance = balances.getBalance(from),
		protocolBalance = balances.getBalance(ao.id),
		df = demand.getDemandFactorInfo(),
		fundingPlan = fundingPlan,
		fundingResult = fundingResult,
	}
end

function arns.calculateExtensionFee(baseFee, years, demandFactor)
	local extensionFee = arns.calculateAnnualRenewalFee(baseFee, years)
	return math.floor(demandFactor * extensionFee)
end

function arns.increaseundernameLimit(from, name, qty, currentTimestamp, msgId, fundFrom)
	fundFrom = fundFrom or "balance"

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

	-- if the address is eligible for the ArNS discount, apply the discount
	if gar.isEligibleForArNSDiscount(from) then
		local discount = math.floor(additionalUndernameCost * constants.ARNS_DISCOUNT_PERCENTAGE)
		additionalUndernameCost = additionalUndernameCost - discount
	end

	if additionalUndernameCost < 0 then
		error("Invalid undername cost")
	end

	local fundingPlan = gar.getFundingPlan(from, additionalUndernameCost, fundFrom)
	assert(fundingPlan and fundingPlan.shortfall == 0 or false, "Insufficient balances")
	local fundingResult = gar.applyFundingPlan(fundingPlan, msgId, currentTimestamp)

	-- update the record with the new undername count
	arns.modifyRecordundernameLimit(name, qty)

	-- Transfer tokens to the protocol balance
	balances.increaseBalance(ao.id, additionalUndernameCost)
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
		fundingPlan = fundingPlan,
		fundingResult = fundingResult,
	}
end

--- Gets a record
--- @param name string The name of the record
--- @return table|nil The a deep copy of the record or nil if it does not exist
function arns.getRecord(name)
	return utils.deepCopy(NameRegistry.records[name])
end

--- Gets the active ARNS names between two timestamps
--- @param startTimestamp number The start timestamp
--- @param endTimestamp number The end timestamp
--- @return table The active ARNS names between the two timestamps
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

--- Gets all records
--- @return table The a deep copy of the records table
function arns.getRecords()
	local records = utils.deepCopy(NameRegistry.records)
	return records or {}
end

--- Gets all reserved names
--- @return table The a deep copy of the reserved names table
function arns.getReservedNames()
	local reserved = utils.deepCopy(NameRegistry.reserved)
	return reserved or {}
end

--- Gets a reserved name
--- @param name string The name of the reserved record
--- @return table|nil The a deep copy of the reserved name or nil if it does not exist
function arns.getReservedName(name)
	return utils.deepCopy(NameRegistry.reserved[name])
end

--- Modifies the undername limit for a record
--- @param name string The name of the record
--- @param qty number The quantity to increase the undername limit by
--- @return table The updated record
function arns.modifyRecordundernameLimit(name, qty)
	local record = arns.getRecord(name)
	assert(record, "Name is not registered")
	NameRegistry.records[name].undernameLimit = record.undernameLimit + qty
	return arns.getRecord(name)
end

--- Modifies the process id for a record
--- @param name string The name of the record
--- @param processId string The new process id
--- @return table The updated record
function arns.modifyProcessId(name, processId)
	local record = arns.getRecord(name)
	assert(record, "Name is not registered")
	NameRegistry.records[name].processId = processId
	return arns.getRecord(name)
end

--- Modifies the end timestamp for a record
--- @param name string The name of the record
--- @param newEndTimestamp number The new end timestamp
--- @return table The updated record
function arns.modifyRecordEndTimestamp(name, newEndTimestamp)
	local record = arns.getRecord(name)
	assert(record, "Name is not registered")
	local maxLeaseLength = constants.maxLeaseLengthYears * constants.oneYearMs
	local maxEndTimestamp = record.startTimestamp + maxLeaseLength
	assert(newEndTimestamp <= maxEndTimestamp, "Cannot extend lease beyond 5 years")
	NameRegistry.records[name].endTimestamp = newEndTimestamp
	return arns.getRecord(name)
end

---Calculates the lease fee for a given base fee, years, and demand factor
--- @param baseFee number The base fee for the name
--- @param years number The number of years
--- @param demandFactor number The demand factor
--- @return number The lease fee
function arns.calculateLeaseFee(baseFee, years, demandFactor)
	local annualRegistrationFee = arns.calculateAnnualRenewalFee(baseFee, years)
	local totalLeaseCost = baseFee + annualRegistrationFee
	return math.floor(demandFactor * totalLeaseCost)
end

---Calculates the annual renewal fee for a given base fee and years
--- @param baseFee number The base fee for the name
--- @param years number The number of years
--- @return number The annual renewal fee
function arns.calculateAnnualRenewalFee(baseFee, years)
	local totalAnnualRenewalCost = baseFee * constants.ANNUAL_PERCENTAGE_FEE * years
	return math.floor(totalAnnualRenewalCost)
end

---Calculates the permabuy fee for a given base fee and demand factor
--- @param baseFee number The base fee for the name
--- @param demandFactor number The demand factor
--- @return number The permabuy fee
function arns.calculatePermabuyFee(baseFee, demandFactor)
	local permabuyPrice = baseFee + arns.calculateAnnualRenewalFee(baseFee, constants.PERMABUY_LEASE_FEE_LENGTH)
	return math.floor(demandFactor * permabuyPrice)
end

---Calculates the registration fee for a given purchase type, base fee, years, and demand factor
--- @param purchaseType string The purchase type (lease/permabuy)
--- @param baseFee number The base fee for the name
--- @param years number The number of years, may be empty for permabuy
--- @param demandFactor number The demand factor
--- @return number The registration fee
function arns.calculateRegistrationFee(purchaseType, baseFee, years, demandFactor)
	assert(purchaseType == "lease" or purchaseType == "permabuy", "Invalid purchase type")
	local registrationFee = purchaseType == "lease" and arns.calculateLeaseFee(baseFee, years, demandFactor)
		or arns.calculatePermabuyFee(baseFee, demandFactor)

	return registrationFee
end

---Calculates the undername cost for a given base fee, increase quantity, registration type, years, and demand factor
--- @param baseFee number The base fee for the name
--- @param increaseQty number The increase quantity
--- @param registrationType string The registration type (lease/permabuy)
--- @param years number The number of years
--- @param demandFactor number The demand factor
--- @return number The undername cost
function arns.calculateUndernameCost(baseFee, increaseQty, registrationType, years, demandFactor)
	assert(registrationType == "lease" or registrationType == "permabuy", "Invalid registration type")
	local undernamePercentageFee = registrationType == "lease" and constants.UNDERNAME_LEASE_FEE_PERCENTAGE
		or constants.UNDERNAME_PERMABUY_FEE_PERCENTAGE
	local totalFeeForQtyAndYears = baseFee * undernamePercentageFee * increaseQty * years
	return math.floor(demandFactor * totalFeeForQtyAndYears)
end

--- Calculates the number of years between two timestamps
--- @param startTimestamp number The start timestamp
--- @param endTimestamp number The end timestamp
--- @return number The number of years between the two timestamps
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
--- @param record table The record to check
--- @param currentTimestamp number The current timestamp
--- @param years number The number of years to check
function arns.assertValidExtendLease(record, currentTimestamp, years)
	assert(record.type ~= "permabuy", "Name is permanently owned and cannot be extended")
	assert(not arns.recordExpired(record, currentTimestamp), "Name is expired")

	local maxAllowedYears = arns.getMaxAllowedYearsExtensionForRecord(record, currentTimestamp)
	assert(years <= maxAllowedYears, "Cannot extend lease beyond 5 years")
end

--- Calculates the maximum allowed years extension for a record
--- @param record table The record to check
--- @param currentTimestamp number The current timestamp
--- @return number The maximum allowed years extension for the record
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

--- Gets the registration fees for all name lengths and years
--- @return table A table containing registration fees for each name length, with the following structure:
---   - [nameLength]: table The fees for names of this length
---     - lease: table Lease fees by year
---       - ["1"]: number Cost for 1 year lease
---       - ["2"]: number Cost for 2 year lease
---       - ["3"]: number Cost for 3 year lease
---       - ["4"]: number Cost for 4 year lease
---       - ["5"]: number Cost for 5 year lease
---     - permabuy: number Cost for permanent purchase
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

---@class IntendedAction
---@field purchaseType string|nil The type of purchase (lease/permabuy)
---@field years number|nil The number of years for lease
---@field quantity number|nil The quantity for increasing undername limit
---@field name string The name of the record
---@field intent string The intended action type (Buy-Record/Extend-Lease/Increase-Undername-Limit/Upgrade-Name)
---@field currentTimestamp number The current timestamp
---@field from string|nil The target address of the intended action

---@class Discount
---@field name string The name of the discount
---@field discountedCost number The discounted cost
---@field multiplier number The multiplier for the discount

---@class TokenCostResult
---@field tokenCost number The token cost in mIO of the intended action
---@field discounts table The discounts applied to the token cost

--- Gets the token cost for an intended action
--- @param intendedAction IntendedAction The intended action with fields:
---   - purchaseType string|nil The type of purchase (lease/permabuy)
---   - years number|nil The number of years for lease
---   - quantity number|nil The quantity for increasing undername limit
---   - name string The name of the record
---   - intent string The intended action type (Buy-Record/Extend-Lease/Increase-Undername-Limit/Upgrade-Name)
---   - currentTimestamp number The current timestamp
---   - from string|nil The target address of the intended action
--- @return TokenCostResult The token cost in mIO of the intended action
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
		assert(record, "Name is not registered")
		assert(currentTimestamp, "Timestamp is required")
		assert(years, "Years is required")
		arns.assertValidExtendLease(record, currentTimestamp, years)
		tokenCost = arns.calculateExtensionFee(baseFee, years, demand.getDemandFactor())
	elseif intent == "Increase-Undername-Limit" then
		assert(record, "Name is not registered")
		assert(currentTimestamp, "Timestamp is required")
		assert(qty, "Quantity is required for increasing undername limit")
		arns.assertValidIncreaseUndername(record, qty, currentTimestamp)
		local yearsRemaining = constants.PERMABUY_LEASE_FEE_LENGTH
		if record.type == "lease" then
			yearsRemaining = arns.calculateYearsBetweenTimestamps(currentTimestamp, record.endTimestamp)
		end
		tokenCost = arns.calculateUndernameCost(baseFee, qty, record.type, yearsRemaining, demand.getDemandFactor())
	elseif intent == "Upgrade-Name" then
		assert(record, "Name is not registered")
		assert(currentTimestamp, "Timestamp is required")
		arns.assertValidUpgradeName(record, currentTimestamp)
		tokenCost = arns.calculatePermabuyFee(baseFee, demand.getDemandFactor())
	end

	local discounts = {}

	-- if the address is eligible for the ArNS discount, apply the discount
	if gar.isEligibleForArNSDiscount(intendedAction.from) then
		local discountedCost = math.floor(tokenCost * constants.ARNS_DISCOUNT_PERCENTAGE)
		local discount = {
			name = "ArNS Discount",
			discountedCost = discountedCost,
			multiplier = constants.ARNS_DISCOUNT_PERCENTAGE,
		}
		table.insert(discounts, discount)
		tokenCost = tokenCost - discountedCost
	end

	-- if token Cost is less than 0, throw an error
	if tokenCost < 0 then
		error("Invalid token cost for " .. intendedAction.intent)
	end

	return { tokenCost = tokenCost, discounts = discounts }
end

--- Asserts that a name is valid for upgrading
--- @param record table The record to check
--- @param currentTimestamp number The current timestamp
function arns.assertValidUpgradeName(record, currentTimestamp)
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
	assert(record, "Name is not registered")
	assert(currentTimestamp, "Timestamp is required")
	arns.assertValidUpgradeName(record, currentTimestamp)

	local baseFee = demand.baseFeeForNameLength(#name)
	local tokenCostResult = arns.getTokenCost({
		currentTimestamp = currentTimestamp,
		intent = "Upgrade-Name",
		name = name,
		from = from,
	})
	local tokenCost = tokenCostResult.tokenCost

	assert(balances.walletHasSufficientBalance(from, tokenCost), "Insufficient balance")

	record.endTimestamp = nil
	record.type = "permabuy"
	record.purchasePrice = tokenCost

	balances.transfer(ao.id, from, tokenCost)
	demand.tallyNamePurchase(tokenCost)

	NameRegistry.records[name] = record
	return {
		name = name,
		record = record,
		totalUpgradeFee = tokenCost,
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
--- @param record table The record to check
--- @param qty number The quantity to check
--- @param currentTimestamp number The current timestamp
function arns.assertValidIncreaseUndername(record, qty, currentTimestamp)
	assert(arns.recordIsActive(record, currentTimestamp), "Name must be active to increase undername limit")
	assert(qty > 0 and utils.isInteger(qty), "Qty is invalid")
end

--- Creates an auction for a given name
--- @param name string The name of the auction
--- @param timestamp number The timestamp to start the auction
--- @param initiator string The address of the initiator of the auction
--- @return Auction|nil The auction instance
function arns.createAuction(name, timestamp, initiator)
	assert(arns.getRecord(name), "Name is not registered. Auctions can only be created for registered names.")
	assert(not arns.getAuction(name), "Auction already exists for name")
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
	assert(auction, "Auction not found")
	assert(
		timestamp >= auction.startTimestamp and timestamp <= auction.endTimestamp,
		"Bid timestamp is outside of auction start and end timestamps"
	)
	local requiredBid = auction:getPriceForAuctionAtTimestamp(timestamp, type, years)
	local floorPrice = auction:floorPrice(type, years) -- useful for analytics, used by getPriceForAuctionAtTimestamp
	local startPrice = auction:startPrice(type, years) -- useful for analytics, used by getPriceForAuctionAtTimestamp
	local requiredOrBidAmount = bidAmount or requiredBid
	assert(requiredOrBidAmount >= requiredBid, "Bid amount is less than the required bid of " .. requiredBid)

	local finalBidAmount = math.min(requiredOrBidAmount, requiredBid)

	-- check if bidder is eligible for ArNS discount
	if gar.isEligibleForArNSDiscount(bidder) then
		local discount = math.floor(finalBidAmount * constants.ARNS_DISCOUNT_PERCENTAGE)
		finalBidAmount = finalBidAmount - discount
	end

	-- check the balance of the bidder
	assert(balances.walletHasSufficientBalance(bidder, finalBidAmount), "Insufficient balance")

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

--- Removes an auction by name
--- @param name string The name of the auction
--- @return Auction|nil The auction instance
function arns.removeAuction(name)
	local auction = arns.getAuction(name)
	NameRegistry.auctions[name] = nil
	return auction
end

--- Removes a record by name
--- @param name string The name of the record
--- @return table|nil The record instance
function arns.removeRecord(name)
	local record = NameRegistry.records[name]
	NameRegistry.records[name] = nil
	return record
end

--- Removes a reserved name by name
--- @param name string The name of the reserved name
--- @return table|nil The reserved name instance
function arns.removeReservedName(name)
	local reserved = NameRegistry.reserved[name]
	NameRegistry.reserved[name] = nil
	return reserved
end

--- Prunes records that have expired
--- @param currentTimestamp number The current timestamp
--- @param lastGracePeriodEntryEndTimestamp number The end timestamp of the last known record to have entered its grace period
--- @return table # The pruned records
--- @return number # The end timestamp of the last known record to have entered its grace period
function arns.pruneRecords(currentTimestamp, lastGracePeriodEntryEndTimestamp)
	lastGracePeriodEntryEndTimestamp = lastGracePeriodEntryEndTimestamp or 0
	local prunedRecords = {}
	local newGracePeriodRecords = {}
	-- identify any records that are leases and that have expired, account for a one week grace period in seconds
	for name, record in pairs(arns.getRecords()) do
		if record.type == "lease" and currentTimestamp > record.endTimestamp then
			if currentTimestamp >= record.endTimestamp + constants.gracePeriodMs then
				-- lease is outside the grade period. start a dutch auction. it will get pruned out if it expires with no bids
				prunedRecords[name] = record
				arns.createAuction(name, currentTimestamp, ao.id)
			elseif record.endTimestamp > lastGracePeriodEntryEndTimestamp then
				-- lease is newly recognized as being within the grace period
				newGracePeriodRecords[name] = record
			end
		end
	end
	return prunedRecords, newGracePeriodRecords
end

--- Prunes auctions that have expired
--- @param currentTimestamp number The current timestamp
--- @return table The pruned auctions
function arns.pruneAuctions(currentTimestamp)
	local prunedAuctions = {}
	for name, auction in pairs(arns.getAuctions()) do
		if auction.endTimestamp <= currentTimestamp then
			prunedAuctions[name] = arns.removeAuction(name)
		end
	end
	return prunedAuctions
end

--- Prunes reserved names that have expired
--- @param currentTimestamp number The current timestamp
--- @return table The pruned reserved names
function arns.pruneReservedNames(currentTimestamp)
	local prunedReserved = {}
	for name, details in pairs(arns.getReservedNames()) do
		if details.endTimestamp and details.endTimestamp <= currentTimestamp then
			prunedReserved[name] = arns.removeReservedName(name)
		end
	end
	return prunedReserved
end

--- Asserts that a name can be reassigned
--- @param record table The record to check
--- @param currentTimestamp number The current timestamp
--- @param from string The address of the sender
--- @param newProcessId string The new process id
function arns.assertValidReassignName(record, currentTimestamp, from, newProcessId)
	assert(record, "Name is not registered")
	assert(currentTimestamp, "Timestamp is required")
	assert(utils.isValidAOAddress(newProcessId), "Invalid Process-Id")
	assert(record.processId == from, "Not authorized to reassign this name")

	if record.endTimestamp then
		local isWithinGracePeriod = record.endTimestamp < currentTimestamp
			and record.endTimestamp + constants.gracePeriodMs > currentTimestamp
		local isExpired = record.endTimestamp + constants.gracePeriodMs < currentTimestamp
		assert(not isWithinGracePeriod, "Name must be extended before it can be reassigned")
		assert(not isExpired, "Name is expired")
	end

	return true
end

--- Reassigns a name
--- @param name string The name of the record
--- @param from string The address of the sender
--- @param currentTimestamp number The current timestamp
--- @param newProcessId string The new process id
--- @return table The updated record
function arns.reassignName(name, from, currentTimestamp, newProcessId)
	local record = arns.getRecord(name)
	assert(record, "Name is not registered")
	arns.assertValidReassignName(record, currentTimestamp, from, newProcessId)
	local updatedRecord = arns.modifyProcessId(name, newProcessId)
	return updatedRecord
end

return arns
