local constants = require("constants")
local demand = require("demand")
local utils = require("utils")
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
			fees = constants.DEFAULT_GENESIS_FEES,
		}
		_G.DemandFactorSettings = {
			periodZeroStartTimestamp = 0,
			movingAvgPeriodCount = 7,
			periodLengthMs = 60 * 1000 * 24, -- one day
			demandFactorBaseValue = 1,
			demandFactorMin = 0.5,

			demandFactorUpAdjustment = 0.05,
			demandFactorDownAdjustment = 0.015,
			maxPeriodsAtMinDemandFactor = 3,
			criteria = "revenue",
		}
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
				local resultingDemandFactor = demand.updateDemandFactor(startNextPeriodTimestamp)
				assert.are.equal(0.985, resultingDemandFactor)
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
			"updateDemandFactor() adjust fees and reset demand factor parameters when consecutive periods at minimum threshold is hit",
			function()
				local currentPeriod = 15
				_G.DemandFactor.currentPeriod = currentPeriod -- 15 % 7 = 1 = 2 index of the trailing period array
				_G.DemandFactor.currentDemandFactor = _G.DemandFactorSettings.demandFactorMin - 0.1
				_G.DemandFactor.consecutivePeriodsWithMinDemandFactor =
					_G.DemandFactorSettings.maxPeriodsAtMinDemandFactor
				_G.DemandFactor.revenueThisPeriod = 0
				_G.DemandFactor.trailingPeriodRevenues = { 0, 10, 10, 10, 10, 10, 0 }
				local expectedFees = {}
				local startNextPeriodTimestamp = _G.DemandFactorSettings.periodLengthMs * currentPeriod + 1
				-- use pairs as fees is a map
				for nameLength, fee in pairs(_G.DemandFactor.fees) do
					expectedFees[nameLength] = fee * _G.DemandFactorSettings.demandFactorMin
				end
				demand.updateDemandFactor(startNextPeriodTimestamp)
				assert.are.equal(1, _G.DemandFactor.currentDemandFactor)
				assert.are.equal(0, _G.DemandFactor.consecutivePeriodsWithMinDemandFactor)
				assert.are.same(expectedFees, _G.DemandFactor.fees)
				assert.are.same({ 0, 0, 10, 10, 10, 10, 0 }, _G.DemandFactor.trailingPeriodRevenues)
			end
		)

		it("cuts fees in half after hitting the minimum demand factor period threshold", function()
			--[[
				We want to validate that the demand factor steps down to the minimum and resets fees 5 times.
				With a step down of 0.015 per period, the demand factor will reduce to 0.5 after 46 periods (log(0.5) / log(1 - 0.015)).
				We run this process multiple times to verify that fees continue to be reduced after the demand factor
				reaches the minimum, with final fees being initial * 0.5 ^ 3. We also validate that the demand factor
				reaches the minimum and is reset to the base value (1) when fees reset.
			]]
			--
			local currentTimestamp = 0
			local numPeriodsToHitMinimum = math.ceil(
				math.log(_G.DemandFactorSettings.demandFactorMin)
					/ math.log(1 - _G.DemandFactorSettings.demandFactorDownAdjustment)
			)
			local periodAtWhichFeesReset = numPeriodsToHitMinimum + _G.DemandFactorSettings.maxPeriodsAtMinDemandFactor
			local totalStepDownCycles = 5
			for _ = 1, totalStepDownCycles do
				local initialFees = utils.deepCopy(_G.DemandFactor.fees)
				for i = 1, periodAtWhichFeesReset do
					-- Advance time past one period so that updateDemandFactor triggers.
					currentTimestamp = currentTimestamp + _G.DemandFactorSettings.periodLengthMs + 1
					local demandBeforeUpdate = _G.DemandFactor.currentDemandFactor
					local maybeNewDemandFactor = demand.updateDemandFactor(currentTimestamp)
					-- make sure the demand factor is dropping for every period in between
					if i < periodAtWhichFeesReset then
						local expectedDemandFactor = math.max(
							utils.roundToPrecision(
								demandBeforeUpdate * (1 - _G.DemandFactorSettings.demandFactorDownAdjustment),
								5
							),
							_G.DemandFactorSettings.demandFactorMin
						)
						assert.are.equal(expectedDemandFactor, maybeNewDemandFactor)
						assert.is_true(maybeNewDemandFactor >= 0.5)
					end
				end
				-- after 46 periods, the fees should be cut in half
				for nameLength, fee in pairs(_G.DemandFactor.fees) do
					local expectedFee = initialFees[nameLength] * _G.DemandFactorSettings.demandFactorMin -- fees are reduced by the demand factor minimum every time they are reset
					assert.are.equal(expectedFee, fee)
				end
				-- assert the demand factor is returned the the base value
				assert.are.equal(_G.DemandFactorSettings.demandFactorBaseValue, _G.DemandFactor.currentDemandFactor)
			end
		end)
	end)

	describe("purchase count criteria", function()
		before_each(function()
			_G.DemandFactorSettings = {
				periodZeroStartTimestamp = 0,
				movingAvgPeriodCount = 7,
				periodLengthMs = 60 * 1000 * 24, -- one day
				demandFactorStartingValue = 1,
				demandFactorBaseValue = 1,
				demandFactorMin = 0.5,
				demandFactorUpAdjustment = 0.05,
				demandFactorDownAdjustment = 0.025,
				maxPeriodsAtMinDemandFactor = 3,
				criteria = "purchases",
			}
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
