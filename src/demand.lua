local constants = require("constants")
local utils = require("utils")
local demand = {}

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

DemandFactorSettings = DemandFactorSettings
	or {
		periodZeroStartTimestamp = 1722837600000, -- 08/05/2024 @ 12:00am (UTC)
		movingAvgPeriodCount = 7,
		periodLengthMs = 60 * 60 * 1000 * 24, -- one day in milseconds
		demandFactorBaseValue = 1,
		demandFactorMin = 0.5,
		demandFactorUpAdjustment = 0.05, -- 5%
		demandFactorDownAdjustment = 0.015, -- 1.5%
		stepDownThreshold = 3,
		criteria = "revenue",
	}

function demand.tallyNamePurchase(qty)
	demand.incrementPurchasesThisPeriodRevenue(1)
	demand.incrementRevenueThisPeriod(qty)
end

--- Gets the base fee for a given name length
--- @param nameLength number The length of the name
--- @return number The base fee for the name length
function demand.baseFeeForNameLength(nameLength)
	return demand.getFees()[nameLength]
end

function demand.mvgAvgTrailingPurchaseCounts()
	local sum = 0
	local trailingPeriodPurchases = demand.getTrailingPeriodPurchases()
	for i = 1, #trailingPeriodPurchases do
		sum = sum + trailingPeriodPurchases[i]
	end
	return sum / #trailingPeriodPurchases
end

function demand.mvgAvgTrailingRevenues()
	local sum = 0
	local trailingPeriodRevenues = demand.getTrailingPeriodRevenues()
	for i = 1, #trailingPeriodRevenues do
		sum = sum + trailingPeriodRevenues[i]
	end
	return sum / #trailingPeriodRevenues
end

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

-- update at the end of the demand if the current timestamp results in a period greater than our current state
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

function demand.getDemandFactorInfo()
	return utils.deepCopy(DemandFactor)
end

function demand.updateDemandFactor(timestamp)
	if not demand.shouldUpdateDemandFactor(timestamp) then
		print("Not updating demand factor")
		return -- silently return
	end

	local settings = demand.getSettings()

	-- check that we have settings
	if not settings then
		print("No settings found")
		return
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

function demand.updateFees(multiplier)
	local currentFees = demand.getFees()
	-- update all fees multiply them by the demand factor minimim
	for nameLength, fee in pairs(currentFees) do
		local updatedFee = fee * multiplier
		DemandFactor.fees[nameLength] = updatedFee
	end
end

function demand.getDemandFactor()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.currentDemandFactor or 1
end

function demand.getCurrentPeriodRevenue()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.revenueThisPeriod or 0
end

function demand.getCurrentPeriodPurchases()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.purchasesThisPeriod or 0
end

function demand.getTrailingPeriodPurchases()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.trailingPeriodPurchases or { 0, 0, 0, 0, 0, 0, 0 }
end

function demand.getTrailingPeriodRevenues()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.trailingPeriodRevenues or { 0, 0, 0, 0, 0, 0, 0 }
end

function demand.getFees()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.fees or {}
end

function demand.getSettings()
	return utils.deepCopy(DemandFactorSettings)
end

function demand.getConsecutivePeriodsWithMinDemandFactor()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.consecutivePeriodsWithMinDemandFactor or 0
end

function demand.getCurrentPeriod()
	local demandFactor = utils.deepCopy(DemandFactor)
	return demandFactor and demandFactor.currentPeriod or 1
end

function demand.updateSettings(settings)
	if not settings then
		return
	end
	DemandFactorSettings = settings
end

function demand.updateStartTimestamp(timestamp)
	DemandFactorSettings.periodZeroStartTimestamp = timestamp
end

function demand.updateCurrentPeriod(period)
	DemandFactor.currentPeriod = period
end

function demand.setDemandFactor(demandFactor)
	DemandFactor.currentDemandFactor = demandFactor
end

function demand.getPeriodIndex()
	local currentPeriod = demand.getCurrentPeriod()
	local settings = demand.getSettings()
	if not settings then
		return 0
	end
	-- current period is one based index of the current period
	return (currentPeriod % settings.movingAvgPeriodCount) + 1 -- has to be + 1 to avoid zero index
end

function demand.updateTrailingPeriodPurchases()
	local periodIndex = demand.getPeriodIndex()
	DemandFactor.trailingPeriodPurchases[periodIndex] = demand.getCurrentPeriodPurchases()
end

function demand.updateTrailingPeriodRevenues()
	local periodIndex = demand.getPeriodIndex()
	DemandFactor.trailingPeriodRevenues[periodIndex] = demand.getCurrentPeriodRevenue()
end

function demand.resetPurchasesThisPeriod()
	DemandFactor.purchasesThisPeriod = 0
end

function demand.resetRevenueThisPeriod()
	DemandFactor.revenueThisPeriod = 0
end

function demand.incrementPurchasesThisPeriodRevenue(count)
	DemandFactor.purchasesThisPeriod = DemandFactor.purchasesThisPeriod + count
end

function demand.incrementRevenueThisPeriod(revenue)
	DemandFactor.revenueThisPeriod = DemandFactor.revenueThisPeriod + revenue
end

function demand.updateRevenueThisPeriod(revenue)
	DemandFactor.revenueThisPeriod = revenue
end

function demand.incrementCurrentPeriod(count)
	DemandFactor.currentPeriod = DemandFactor.currentPeriod + count
end

function demand.resetConsecutivePeriodsWithMinimumDemandFactor()
	DemandFactor.consecutivePeriodsWithMinDemandFactor = 0
end

function demand.incrementConsecutivePeriodsWithMinDemandFactor(count)
	DemandFactor.consecutivePeriodsWithMinDemandFactor = DemandFactor.consecutivePeriodsWithMinDemandFactor + count
end

return demand
