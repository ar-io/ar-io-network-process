--[[
	NOTE: constants is used throughout the codebase, so avoid imports of any modules in this file to prevent circular dependencies
]]
--
local constants = {}

--- CONVERSION HELPERS
constants.DENOMINATION = 6
-- @alias mARIO number
-- intentionally not exposed so all callers use ARIOToMARIO for consistency
local mARIO_PER_ARIO = 10 ^ constants.DENOMINATION -- 1 million mARIO per ARIO

--- @param ARIO number
--- @return mARIO mARIO the amount of mario for the given ARIO
function constants.ARIOToMARIO(ARIO)
	return ARIO * mARIO_PER_ARIO
end

--- @param days number
--- @return number milliseconds the number of days in milliseconds
function constants.daysToMs(days)
	return days * constants.hoursToMs(24)
end

--- @param minutes number
--- @return number milliseconds the number of minutes in milliseconds
function constants.minutesToMs(minutes)
	return minutes * constants.secondsToMs(60)
end

function constants.secondsToMs(seconds)
	return seconds * 1000
end

--- @param years number
--- @return number milliseconds the number of years in milliseconds
function constants.yearsToMs(years)
	return years * constants.daysToMs(365)
end

function constants.hoursToMs(hours)
	return hours * constants.minutesToMs(60)
end

-- TOKEN SUPPLY
constants.TOTAL_TOKEN_SUPPLY = constants.ARIOToMARIO(1000000000) -- 1 billion tokens
constants.DEFAULT_PROTOCOL_BALANCE = constants.ARIOToMARIO(50000000) -- 50M ARIO
constants.MIN_UNSAFE_ADDRESS_LENGTH = 1
constants.MAX_UNSAFE_ADDRESS_LENGTH = 128

-- EPOCHS
constants.DEFAULT_EPOCH_SETTINGS = {
	prescribedNameCount = 2,
	maxObservers = 50,
	epochZeroStartTimestamp = 1719900000000, -- July 9th,2024 00:00:00 UTC (TODO: set this on mainnet process)
	durationMs = constants.DEFAULT_EPOCH_DURATION_MS, -- 24 hours
	distributionDelayMs = constants.minutesToMs(40), -- 40 minutes (~ 20 arweave blocks)
}

-- DISTRIBUTIONS
constants.DEFAULT_DISTRIBUTION_SETTINGS = {
	maximumRewardRate = 0.001, -- 0.1% of the rewards for the first year
	minimumRewardRate = 0.0005, -- 0.05% of the rewards after the first year
	rewardDecayStartEpoch = 365, -- one year of epochs before it kicks in
	rewardDecayLastEpoch = 547, -- 1.5 years of epochs before it stops
	observerRewardRatio = 0.1, -- 10% of the rewards go to the observers
	gatewayOperatorRewardRatio = 0.9, -- 90% of the rewards go to the gateway operators
}

-- GAR
constants.DEFAULT_GAR_SETTINGS = {
	observers = {
		maxPerEpoch = 50,
		tenureWeightDays = 180,
		tenureWeightPeriod = constants.daysToMs(180), -- 180 days in ms
		maxTenureWeight = 4,
	},
	operators = {
		minStake = constants.ARIOToMARIO(10000), -- 10,000 ARIO
		withdrawLengthMs = constants.daysToMs(90), -- 90 days to lower operator stake
		leaveLengthMs = constants.daysToMs(90), -- 90 days that balance will be vaulted
		failedEpochCountMax = 30, -- number of epochs failed before marked as leaving
		failedEpochSlashRate = 1, -- 100% of the minimum operator stake is returned to protocol balance, rest is vaulted
		maxDelegateRewardShareRatio = 95, -- 95% of rewards can be shared with delegates
	},
	delegates = {
		minStake = constants.ARIOToMARIO(10), -- 10 ARIO
		withdrawLengthMs = constants.daysToMs(90), -- 90 days
	},
	redelegations = {
		minExpeditedWithdrawalPenaltyRate = 0.10, -- the minimum penalty rate for an expedited withdrawal (10% of the amount being withdrawn)
		maxExpeditedWithdrawalPenaltyRate = 0.50, -- the maximum penalty rate for an expedited withdrawal (50% of the amount being withdrawn)
		minWithdrawalAmount = constants.ARIOToMARIO(1), -- the minimum amount that can be withdrawn from the GAR
		redelegationFeeResetIntervalMs = constants.daysToMs(7), -- 7 days
	},
}

-- DEMAND FACTOR
constants.DEFAULT_DEMAND_FACTOR_SETTINGS = {
	periodZeroStartTimestamp = 1722837600000, -- 08/05/2024 @ 12:00am (UTC) (TODO: set this on mainnet process)
	movingAvgPeriodCount = 7, -- the number of periods to use for the moving average
	periodLengthMs = constants.daysToMs(1), -- one day in milliseconds
	demandFactorBaseValue = 1, -- the base demand factor
	demandFactorMin = 0.5, -- the minimum demand factor
	demandFactorUpAdjustment = 0.05, -- 5%
	demandFactorDownAdjustment = 0.015, -- 1.5%
	stepDownThreshold = 3, -- three consecutive periods with the minimum demand factor
	criteria = "revenue", -- "revenue" or "purchases"
}

-- VAULTS
constants.MIN_VAULT_SIZE = constants.ARIOToMARIO(100) -- 100 ARIO
constants.MAX_TOKEN_LOCK_TIME_MS = constants.yearsToMs(12) -- The maximum amount of blocks tokens can be locked in a vault (12 years of blocks)
constants.MIN_TOKEN_LOCK_TIME_MS = constants.daysToMs(14) -- The minimum amount of blocks tokens can be locked in a vault (14 days of blocks)

-- ARNS
constants.DEFAULT_UNDERNAME_COUNT = 10
constants.MAX_NAME_LENGTH = 51
constants.MIN_NAME_LENGTH = 1
-- Regex pattern to validate ARNS names:
-- - Starts with an alphanumeric character (%w)
-- - Can contain alphanumeric characters and hyphens (%w-)
-- - Ends with an alphanumeric character (%w)
-- - Does not allow names to start or end with a hyphen
constants.ARNS_NAME_REGEX = "^%w[%w-]*%w?$"
constants.PERMABUY_LEASE_FEE_LENGTH = 20 -- 20 years
constants.ANNUAL_PERCENTAGE_FEE = 0.2 -- 20%
constants.UNDERNAME_LEASE_FEE_PERCENTAGE = 0.001
constants.UNDERNAME_PERMABUY_FEE_PERCENTAGE = 0.005
constants.GRACE_PERIOD_MS = constants.daysToMs(14)
constants.MAX_LEASE_LENGTH_YEARS = 5
constants.RETURNED_NAME_PERIOD = constants.daysToMs(14)
constants.RETURNED_NAME_MAX_MULTIPLIER = 50 -- Freshly returned names will have a multiplier of 50x
constants.PRIMARY_NAME_REQUEST_DEFAULT_NAME_LENGTH = 51 -- primary name requests cost the same as a single undername on a 51 character name
constants.ARNS_DISCOUNT_PERCENTAGE = 0.2
constants.ARNS_DISCOUNT_TENURE_WEIGHT_ELIGIBILITY_THRESHOLD = 0.5
constants.ARNS_DISCOUNT_GATEWAY_PERFORMANCE_RATIO_ELIGIBILITY_THRESHOLD = 0.85
constants.ARNS_DISCOUNT_NAME = "ArNS Discount"
constants.DEFAULT_GENESIS_FEES = {
	[1] = constants.ARIOToMARIO(2000000),
	[2] = constants.ARIOToMARIO(200000),
	[3] = constants.ARIOToMARIO(40000),
	[4] = constants.ARIOToMARIO(10000),
	[5] = constants.ARIOToMARIO(4000),
	[6] = constants.ARIOToMARIO(2000),
	[7] = constants.ARIOToMARIO(1000),
	[8] = constants.ARIOToMARIO(600),
	[9] = constants.ARIOToMARIO(500),
	[10] = constants.ARIOToMARIO(500),
	[11] = constants.ARIOToMARIO(500),
	[12] = constants.ARIOToMARIO(500),
	[13] = constants.ARIOToMARIO(400),
	[14] = constants.ARIOToMARIO(400),
	[15] = constants.ARIOToMARIO(400),
	[16] = constants.ARIOToMARIO(400),
	[17] = constants.ARIOToMARIO(400),
	[18] = constants.ARIOToMARIO(400),
	[19] = constants.ARIOToMARIO(400),
	[20] = constants.ARIOToMARIO(400),
	[21] = constants.ARIOToMARIO(400),
	[22] = constants.ARIOToMARIO(400),
	[23] = constants.ARIOToMARIO(400),
	[24] = constants.ARIOToMARIO(400),
	[25] = constants.ARIOToMARIO(400),
	[26] = constants.ARIOToMARIO(400),
	[27] = constants.ARIOToMARIO(400),
	[28] = constants.ARIOToMARIO(400),
	[29] = constants.ARIOToMARIO(400),
	[30] = constants.ARIOToMARIO(400),
	[31] = constants.ARIOToMARIO(400),
	[32] = constants.ARIOToMARIO(400),
	[33] = constants.ARIOToMARIO(400),
	[34] = constants.ARIOToMARIO(400),
	[35] = constants.ARIOToMARIO(400),
	[36] = constants.ARIOToMARIO(400),
	[37] = constants.ARIOToMARIO(400),
	[38] = constants.ARIOToMARIO(400),
	[39] = constants.ARIOToMARIO(400),
	[40] = constants.ARIOToMARIO(400),
	[41] = constants.ARIOToMARIO(400),
	[42] = constants.ARIOToMARIO(400),
	[43] = constants.ARIOToMARIO(400),
	[44] = constants.ARIOToMARIO(400),
	[45] = constants.ARIOToMARIO(400),
	[46] = constants.ARIOToMARIO(400),
	[47] = constants.ARIOToMARIO(400),
	[48] = constants.ARIOToMARIO(400),
	[49] = constants.ARIOToMARIO(400),
	[50] = constants.ARIOToMARIO(400),
	[51] = constants.ARIOToMARIO(400),
}

return constants
