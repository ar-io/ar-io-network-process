local constants = require("constants")
local demand = require("demand")

describe("demand", function()
	before_each(function()
		_G.DemandFactor = {
			startTimestamp = 0,
			currentPeriod = 1,
			trailingPeriodPurchases = { 0, 0, 0, 0, 0, 0, 0 },
			trailingPeriodRevenues = { 0, 0, 0, 0, 0, 0 },
			purchasesThisPeriod = 0,
			revenueThisPeriod = 0,
			currentDemandFactor = 1,
			consecutivePeriodsWithMinDemandFactor = 0,
			fees = constants.genesisFees,
		}
		demand.updateSettings({
			periodZeroStartTimestamp = 0,
			movingAvgPeriodCount = 7,
			periodLengthMs = 60 * 1000 * 24, -- one day
			demandFactorBaseValue = 1,
			demandFactorMin = 0.5,
			demandFactorUpAdjustment = 0.05,
			demandFactorDownAdjustment = 0.025,
			stepDownThreshold = 3,
			criteria = "revenue",
		})
	end)

	it("should tally name purchase", function()
		demand.tallyNamePurchase(100)
		assert.are.equal(1, demand.getCurrentPeriodPurchases())
		assert.are.equal(100, demand.getCurrentPeriodRevenue())
	end)

	describe("revenue based criteria", function()
		it("mvgAvgTrailingPurchaseCounts() should calculate moving average of trailing purchase counts", function()
			_G.DemandFactor.trailingPeriodPurchases = { 1, 2, 3, 4, 5, 6, 7 }
			assert.are.equal(4, demand.mvgAvgTrailingPurchaseCounts())
		end)

		it("mvgAvgTrailingRevenues() should calculate moving average of trailing revenues", function()
			_G.DemandFactor.trailingPeriodRevenues = { 1, 2, 3, 4, 5, 6 }
			assert.are.equal(3.5, demand.mvgAvgTrailingRevenues())
		end)

		it("isDemandIncreasing() should return false when demand is is not increasing based on revenue", function()
			_G.DemandFactor.revenueThisPeriod = 0
			_G.DemandFactor.trailingPeriodRevenues = { 0, 10, 10, 10, 10, 10 }
			assert.is_false(demand.isDemandIncreasing())
		end)

		it("isDemandIncreasing() should return true when demand is increasing based on revenue", function()
			_G.DemandFactor.revenueThisPeriod = 10
			_G.DemandFactor.trailingPeriodRevenues = { 10, 0, 0, 0, 0, 0, 0 }
			assert.is_true(demand.isDemandIncreasing())
		end)

		it(
			"updateDemandFactor() should update demand factor if demand is increasing and a new period has started",
			function()
				local currentPeriod = 3
				_G.DemandFactor.currentPeriod = currentPeriod
				_G.DemandFactor.revenueThisPeriod = 10
				_G.DemandFactor.trailingPeriodRevenues = { 5, 0, 0, 5, 0, 0, 0 }
				local startNextPeriodTimestamp = _G.DemandFactorSettings.periodLengthMs * currentPeriod + 1
				demand.updateDemandFactor(startNextPeriodTimestamp)
				assert.are.equal(1.05, _G.DemandFactor.currentDemandFactor)
				assert.are.same({ 5, 0, 0, 10, 0, 0, 0 }, _G.DemandFactor.trailingPeriodRevenues)
				assert.are.equal(currentPeriod + 1, _G.DemandFactor.currentPeriod)
			end
		)

		it(
			"updateDemandFactor() should update demand factor if demand is decreasing and a new period has started",
			function()
				local currentPeriod = 5
				_G.DemandFactor.currentPeriod = currentPeriod
				_G.DemandFactor.revenueThisPeriod = 0
				_G.DemandFactor.trailingPeriodRevenues = { 0, 10, 0, 0, 5, 10, 0 }
				local startNextPeriodTimestamp = _G.DemandFactorSettings.periodLengthMs * currentPeriod + 1
				demand.updateDemandFactor(startNextPeriodTimestamp)
				assert.are.equal(0.9749999999999999778, _G.DemandFactor.currentDemandFactor)
				-- update the 6th spot in the pervious period revenues for the 5th period
				assert.are.same({ 0, 10, 0, 0, 5, 0, 0 }, _G.DemandFactor.trailingPeriodRevenues)
				assert.are.equal(currentPeriod + 1, _G.DemandFactor.currentPeriod)
			end
		)

		it(
			"updateDemandFactor() should increment consecutive periods at minimum and not lower demand factor if demand factor is already at minimum",
			function()
				local currentPeriod = 12
				_G.DemandFactor.currentPeriod = currentPeriod
				_G.DemandFactor.currentDemandFactor = 0.5
				_G.DemandFactor.revenueThisPeriod = 0
				_G.DemandFactor.trailingPeriodRevenues = { 0, 10, 10, 10, 10, 10, 0 }
				local currentTimestamp = _G.DemandFactorSettings.periodLengthMs * currentPeriod + 1
				demand.updateDemandFactor(currentTimestamp)
				assert.are.equal(0.5, _G.DemandFactor.currentDemandFactor)
				-- update the 12 % 7 = 5th spot in the pervious period revenues
				assert.are.same({ 0, 10, 10, 10, 10, 0, 0 }, _G.DemandFactor.trailingPeriodRevenues)
				-- increments the period by one
				assert.are.equal(currentPeriod + 1, _G.DemandFactor.currentPeriod)
			end
		)

		it(
			"updateDemandFactor() adjust fees and reset demend factor parameters when consecutive periods at minimum threshold is hit",
			function()
				local currentPeriod = 15
				_G.DemandFactor.currentPeriod = currentPeriod -- 15 % 7 = 1 = 2 index of the trailing period array
				_G.DemandFactor.currentDemandFactor = _G.DemandFactorSettings.demandFactorMin - 0.1
				_G.DemandFactor.consecutivePeriodsWithMinDemandFactor = _G.DemandFactorSettings.stepDownThreshold
				_G.DemandFactor.revenueThisPeriod = 0
				_G.DemandFactor.trailingPeriodRevenues = { 0, 10, 10, 10, 10, 10, 0 }
				local expectedFees = {}
				local startNextPeriodTimestamp = _G.DemandFactorSettings.periodLengthMs * currentPeriod + 1
				-- use pairs as fees is a map
				for nameLength, fee in pairs(constants.genesisFees) do
					expectedFees[nameLength] = fee * _G.DemandFactorSettings.demandFactorMin
				end
				demand.updateDemandFactor(startNextPeriodTimestamp)
				assert.are.equal(1, _G.DemandFactor.currentDemandFactor)
				assert.are.equal(0, _G.DemandFactor.consecutivePeriodsWithMinDemandFactor)
				assert.are.same(expectedFees, _G.DemandFactor.fees)
				assert.are.same({ 0, 0, 10, 10, 10, 10, 0 }, _G.DemandFactor.trailingPeriodRevenues)
			end
		)
	end)

	describe("purchase count criteria", function()
		before_each(function()
			demand.updateSettings({
				periodZeroStartTimestamp = 0,
				movingAvgPeriodCount = 7,
				periodLengthMs = 60 * 1000 * 24, -- one day
				demandFactorBaseValue = 1,
				demandFactorMin = 0.5,
				demandFactorUpAdjustment = 0.05,
				demandFactorDownAdjustment = 0.025,
				stepDownThreshold = 3,
				criteria = "purchases",
			})
		end)

		it("isDemandIncreasing() should return true when demand is increasing for purchases based criteria", function()
			_G.DemandFactor.purchasesThisPeriod = 10
			_G.DemandFactor.trailingPeriodPurchases = { 10, 0, 0, 0, 0, 0, 0 }
			assert.is_true(demand.isDemandIncreasing())
		end)

		it(
			"isDemandIncreasing() should return false when demand is not increasing for purchases based criteria",
			function()
				_G.DemandFactor.purchasesThisPeriod = 0
				_G.DemandFactor.trailingPeriodPurchases = { 0, 10, 10, 10, 10, 10, 10 }
				assert.is_false(demand.isDemandIncreasing())
			end
		)

		it(
			"updateDemandFactor() should update demand factor if demand is increasing and a new period has started",
			function()
				local currentPeriod = 3
				_G.DemandFactor.currentPeriod = currentPeriod
				_G.DemandFactor.purchasesThisPeriod = 10
				_G.DemandFactor.trailingPeriodPurchases = { 10, 0, 0, 0, 0, 0, 0 }
				local startNextPeriodTimestamp = _G.DemandFactorSettings.periodLengthMs * currentPeriod + 1
				demand.updateDemandFactor(startNextPeriodTimestamp)
				assert.are.equal(1.05, _G.DemandFactor.currentDemandFactor)
				assert.are.same({ 10, 0, 0, 10, 0, 0, 0 }, _G.DemandFactor.trailingPeriodPurchases)
				assert.are.equal(currentPeriod + 1, _G.DemandFactor.currentPeriod)
			end
		)

		it(
			"updateDemandFactor() should update demand factor if demand is decreasing and a new period has started",
			function()
				local currentPeriod = 5
				_G.DemandFactor.currentPeriod = currentPeriod
				_G.DemandFactor.purchasesThisPeriod = 0
				_G.DemandFactor.trailingPeriodPurchases = { 0, 10, 0, 0, 0, 0, 0 }
				local startNextPeriodTimestamp = _G.DemandFactorSettings.periodLengthMs * currentPeriod + 1
				demand.updateDemandFactor(startNextPeriodTimestamp)
				assert.are.equal(0.9749999999999999778, _G.DemandFactor.currentDemandFactor)
				assert.are.same({ 0, 10, 0, 0, 0, 0, 0 }, _G.DemandFactor.trailingPeriodPurchases)
				assert.are.equal(currentPeriod + 1, _G.DemandFactor.currentPeriod)
			end
		)
	end)
end)
