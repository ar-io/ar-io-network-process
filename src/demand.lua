local constants = require("constants")
local utils = require("utils")
local demand = {}

--- @class DemandFactor
--- @field currentPeriod number The current period
--- @field trailingPeriodPurchases number[] The trailing period purchases
--- @field trailingPeriodRevenues number[] The trailing period revenues
--- @field purchasesThisPeriod number The current period purchases
--- @field revenueThisPeriod number The current period revenue
--- @field currentDemandFactor number The current demand factor
--- @field consecutivePeriodsWithMinDemandFactor number The number of consecutive periods with the minimum demand factor
--- @field fees table<number, number> The fees for each name length
DemandFactor = DemandFactor
	or {
		currentPeriod = 1, -- one based index of the current period
		trailingPeriodPurchases = { 0, 0, 0, 0, 0, 0, 0 }, -- Acts as a ring buffer of trailing period purchase counts
		trailingPeriodRevenues = { 0, 0, 0, 0, 0, 0 }, -- Acts as a ring buffer of trailing period revenues
		purchasesThisPeriod = 0,
		revenueThisPeriod = 0,
		currentDemandFactor = 1,
		consecutivePeriodsWithMinDemandFactor = 0,
		fees = constants.genesisFees,
	}

--- @class DemandFactorSettings
--- @field periodZeroStartTimestamp number The timestamp of the start of period zero
--- @field movingAvgPeriodCount number The number of periods to use for the moving average
--- @field periodLengthMs number The length of a period in milliseconds
--- @field demandFactorBaseValue number The base demand factor value
--- @field demandFactorMin number The minimum demand factor value
--- @field demandFactorUpAdjustment number The adjustment to the demand factor when it is increasing
--- @field demandFactorDownAdjustment number The adjustment to the demand factor when it is decreasing
--- @field stepDownThreshold number The threshold for the number of consecutive periods with the minimum demand factor before adjusting the demand factor
--- @field criteria 'revenue' | 'purchases' The criteria to use for determining if the demand is increasing
DemandFactorSettings = DemandFactorSettings
	or {
		periodZeroStartTimestamp = 1722837600000, -- 08/05/2024 @ 12:00am (UTC)
		movingAvgPeriodCount = 7,
		periodLengthMs = 60 * 60 * 1000 * 24, -- one day in milliseconds
		demandFactorBaseValue = 1,
		demandFactorMin = 0.5,
		demandFactorUpAdjustment = 0.05, -- 5%
		demandFactorDownAdjustment = 0.015, -- 1.5%
		stepDownThreshold = 3,
		criteria = "revenue",
	}

--- Tally a name purchase
--- @param qty number The quantity of the purchase
function demand.tallyNamePurchase(qty)
	demand.incrementPurchasesThisPeriodRevenue(1)
	demand.incrementRevenueThisPeriod(qty)
end

--- Gets the base fee for a given name length
--- @param nameLength number The length of the name
--- @return number #The base fee for the name length
function demand.baseFeeForNameLength(nameLength)
	assert(utils.isInteger(nameLength) and nameLength > 0, "nameLength must be a positive integer")
	return demand.getFees()[nameLength]
end

--- Gets the moving average of trailing purchase counts
--- @return number # The moving average of trailing purchase counts
function demand.mvgAvgTrailingPurchaseCounts()
	local sum = 0
	local trailingPeriodPurchases = demand.getTrailingPeriodPurchases()
	for i = 1, #trailingPeriodPurchases do
		sum = sum + trailingPeriodPurchases[i]
	end
	return sum / #trailingPeriodPurchases
end

--- Gets the moving average of trailing revenues
--- @return number 	# The moving average of trailing revenues
function demand.mvgAvgTrailingRevenues()
	local sum = 0
	local trailingPeriodRevenues = demand.getTrailingPeriodRevenues()
	for i = 1, #trailingPeriodRevenues do
		sum = sum + trailingPeriodRevenues[i]
	end
	return sum / #trailingPeriodRevenues
end

--- Checks if the demand is increasing
--- @return boolean # true if the demand is increasing, false otherwise
function demand.isDemandIncreasing()
	local settings = demand.getSettings()

	-- check that we have settings
	if not settings then
		print("No settings found")
		return false
	end

	local purchasesInCurrentPeriod = demand.getCurrentPeriodPurchases()
	local revenueInCurrentPeriod = demand.getCurrentPeriodRevenue()
	local mvgAvgOfTrailingNamePurchases = demand.mvgAvgTrailingPurchaseCounts()
	local mvgAvgOfTrailingRevenue = demand.mvgAvgTrailingRevenues()

	if settings.criteria == "revenue" then
		return revenueInCurrentPeriod > 0 and (revenueInCurrentPeriod > mvgAvgOfTrailingRevenue)
	else
		return purchasesInCurrentPeriod > 0 and (purchasesInCurrentPeriod > mvgAvgOfTrailingNamePurchases)
	end
end

--- Checks if the demand should update the demand factor
--- @param currentTimestamp number The current timestamp
--- @return boolean # True if the demand should update the demand factor, false otherwise
function demand.shouldUpdateDemandFactor(currentTimestamp)
	local settings = demand.getSettings()

	if not settings or not settings.periodZeroStartTimestamp then
		return false
	end

	local calculatedPeriod = math.floor(
		(currentTimestamp - settings.periodZeroStartTimestamp) / settings.periodLengthMs
	) + 1
	return calculatedPeriod > demand.getCurrentPeriod()
end

--- Gets the demand factor info
--- @return DemandFactor # The demand factor info
function demand.getDemandFactorInfo()
	return utils.deepCopy(DemandFactor)
end

--- Updates the demand factor and returns the updated demand factor
--- @param timestamp number The current timestamp
--- @return number # The demand factor, updated if necessary
function demand.updateDemandFactor(timestamp)
	if not demand.shouldUpdateDemandFactor(timestamp) then
		print("Not updating demand factor")
		return demand.getDemandFactor()
	end

	local settings = demand.getSettings()

	-- check that we have settings
	if not demand.shouldUpdateDemandFactor(timestamp) or not settings then
		print("No settings found")
		return demand.getDemandFactor()
	end

	if demand.isDemandIncreasing() then
		local upAdjustment = settings.demandFactorUpAdjustment
		demand.setDemandFactor(demand.getDemandFactor() * (1 + upAdjustment))
	else
		if demand.getDemandFactor() > settings.demandFactorMin then
			local downAdjustment = settings.demandFactorDownAdjustment
			local updatedDemandFactor =
				math.max(demand.getDemandFactor() * (1 - downAdjustment), settings.demandFactorMin)
			-- increment consecutive periods with min demand factor
			demand.setDemandFactor(updatedDemandFactor)
		end
	end

	if demand.getDemandFactor() <= settings.demandFactorMin then
		if demand.getConsecutivePeriodsWithMinDemandFactor() >= settings.stepDownThreshold then
			demand.updateFees(settings.demandFactorMin)
			demand.setDemandFactor(settings.demandFactorBaseValue)
			demand.resetConsecutivePeriodsWithMinimumDemandFactor()
		else
			demand.incrementConsecutivePeriodsWithMinDemandFactor(1)
		end
	end

	-- update the current period values in the ring buffer for previous periods
	demand.updateTrailingPeriodPurchases()
	demand.updateTrailingPeriodRevenues()
	demand.resetPurchasesThisPeriod()
	demand.resetRevenueThisPeriod()
	demand.incrementCurrentPeriod(1)

	return demand.getDemandFactor()
end

--- Updates the fees
--- @param multiplier number The multiplier for the fees
--- @return table # The updated fees
function demand.updateFees(multiplier)
	local currentFees = demand.getFees()
	-- update all fees multiply them by the demand factor minimum
	for nameLength, fee in pairs(currentFees) do
		local updatedFee = fee * multiplier
		DemandFactor.fees[nameLength] = updatedFee
	end
	return demand.getFees()
end

--- Gets the demand factor
--- @return number # The demand factor
function demand.getDemandFactor()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.currentDemandFactor or 1
end

--- Gets the current period revenue
--- @return number # The current period revenue
function demand.getCurrentPeriodRevenue()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.revenueThisPeriod or 0
end

--- Gets the current period purchases
--- @return number # The current period purchases
function demand.getCurrentPeriodPurchases()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.purchasesThisPeriod or 0
end

--- Gets the trailing period purchases
--- @return table # The trailing period purchases
function demand.getTrailingPeriodPurchases()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.trailingPeriodPurchases or { 0, 0, 0, 0, 0, 0, 0 }
end

--- Gets the trailing period revenues
--- @return table # The trailing period revenues
function demand.getTrailingPeriodRevenues()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.trailingPeriodRevenues or { 0, 0, 0, 0, 0, 0, 0 }
end

--- Gets the fees
--- @return table # The fees
function demand.getFees()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.fees or {}
end

--- Gets the settings
--- @return DemandFactorSettings # The settings
function demand.getSettings()
	return utils.deepCopy(DemandFactorSettings)
end

--- Gets the consecutive periods with minimum demand factor
--- @return number # The consecutive periods with minimum demand factor
function demand.getConsecutivePeriodsWithMinDemandFactor()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.consecutivePeriodsWithMinDemandFactor or 0
end

--- Gets the current period
--- @return number # The current period
function demand.getCurrentPeriod()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.currentPeriod or 1
end

--- Sets the demand factor
--- @param demandFactor number # The demand factor
function demand.setDemandFactor(demandFactor)
	DemandFactor.currentDemandFactor = demandFactor
end

--- Gets the period index
--- @return number # The period index
function demand.getPeriodIndex()
	local currentPeriod = demand.getCurrentPeriod()
	local settings = demand.getSettings()
	if not settings then
		return 0
	end
	-- current period is one based index of the current period
	return (currentPeriod % settings.movingAvgPeriodCount) + 1 -- has to be + 1 to avoid zero index
end

--- Updates the trailing period purchases
function demand.updateTrailingPeriodPurchases()
	local periodIndex = demand.getPeriodIndex()
	DemandFactor.trailingPeriodPurchases[periodIndex] = demand.getCurrentPeriodPurchases()
end

--- Updates the trailing period revenues
function demand.updateTrailingPeriodRevenues()
	local periodIndex = demand.getPeriodIndex()
	DemandFactor.trailingPeriodRevenues[periodIndex] = demand.getCurrentPeriodRevenue()
end

--- Resets the purchases this period
function demand.resetPurchasesThisPeriod()
	DemandFactor.purchasesThisPeriod = 0
end

--- Resets the revenue this period
function demand.resetRevenueThisPeriod()
	DemandFactor.revenueThisPeriod = 0
end

--- Increments the purchases this period
--- @param count number The count to increment
function demand.incrementPurchasesThisPeriodRevenue(count)
	DemandFactor.purchasesThisPeriod = DemandFactor.purchasesThisPeriod + count
end

--- Increments the revenue this period
--- @param revenue number The revenue to increment
function demand.incrementRevenueThisPeriod(revenue)
	DemandFactor.revenueThisPeriod = DemandFactor.revenueThisPeriod + revenue
end

--- Increments the current period
--- @param count number The count to increment
function demand.incrementCurrentPeriod(count)
	DemandFactor.currentPeriod = DemandFactor.currentPeriod + count
end

--- Resets the consecutive periods with minimum demand factor
function demand.resetConsecutivePeriodsWithMinimumDemandFactor()
	DemandFactor.consecutivePeriodsWithMinDemandFactor = 0
end

--- Increments the consecutive periods with minimum demand factor
--- @param count number The count to increment
function demand.incrementConsecutivePeriodsWithMinDemandFactor(count)
	DemandFactor.consecutivePeriodsWithMinDemandFactor = DemandFactor.consecutivePeriodsWithMinDemandFactor + count
end

return demand
