local constants = {}

-- @alias mARIO number
-- intentionally not exposed so all callers use ARIOToMARIO for consistency
local mARIO_PER_ARIO = 1000000

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

-- EPOCHS
constants.defaultEpochDurationMs = constants.daysToMs(1)
constants.distributionDelayMs = constants.minutesToMs(40) -- 40 minutes
constants.maximumRewardRate = 0.001
constants.minimumRewardRate = 0.0005
constants.rewardDecayStartEpoch = 365
constants.rewardDecayLastEpoch = 547
constants.observerRewardRatio = 0.1
constants.gatewayOperatorRewardRatio = 0.9

-- GAR
constants.DEFAULT_UNDERNAME_COUNT = 10
constants.totalTokenSupply = constants.ARIOToMARIO(1000000000) -- 1 billion tokens
constants.MIN_EXPEDITED_WITHDRAWAL_PENALTY_RATE = 0.10 -- the minimum penalty rate for an expedited withdrawal (10% of the amount being withdrawn)
constants.MAX_EXPEDITED_WITHDRAWAL_PENALTY_RATE = 0.50 -- the maximum penalty rate for an expedited withdrawal (50% of the amount being withdrawn)
constants.minimumWithdrawalAmount = constants.ARIOToMARIO(1) -- the minimum amount that can be withdrawn from the GAR
constants.redelegationFeeResetIntervalMs = constants.daysToMs(7) -- 7 days
constants.maxDelegateRewardShareRatio = 95 -- 95% of rewards can be shared with delegates

-- ARNS
constants.MAX_NAME_LENGTH = 51
constants.MIN_NAME_LENGTH = 1
-- Regex pattern to validate ARNS names:
-- - Starts with an alphanumeric character (%w)
-- - Can contain alphanumeric characters and hyphens (%w-)
-- - Ends with an alphanumeric character (%w)
-- - Does not allow names to start or end with a hyphen
constants.ARNS_NAME_REGEX = "^%w[%w-]*%w?$"
constants.DEFAULT_UNDERNAME_COUNT = 10
constants.PERMABUY_LEASE_FEE_LENGTH = 20 -- 20 years
constants.ANNUAL_PERCENTAGE_FEE = 0.2 -- 20%
constants.ARNS_NAME_DOES_NOT_EXIST_MESSAGE = "Name not found in the ArNS Registry!"
constants.UNDERNAME_LEASE_FEE_PERCENTAGE = 0.001
constants.UNDERNAME_PERMABUY_FEE_PERCENTAGE = 0.005
constants.PRIMARY_NAME_REQUEST_COST = constants.ARIOToMARIO(10) -- 10 ARIO
constants.gracePeriodMs = constants.daysToMs(14)
constants.maxLeaseLengthYears = 5
constants.returnedNamePeriod = constants.daysToMs(14)
constants.returnedNameMaxMultiplier = 50 -- Freshly returned names will have a multiplier of 50x

constants.ARNS_DISCOUNT_PERCENTAGE = 0.2
constants.ARNS_DISCOUNT_TENURE_WEIGHT_ELIGIBILITY_THRESHOLD = 0.5
constants.ARNS_DISCOUNT_GATEWAY_PERFORMANCE_RATIO_ELIGIBILITY_THRESHOLD = 0.85
constants.ARNS_DISCOUNT_NAME = "ArNS Discount"

-- DEMAND
constants.demandSettings = {
	movingAvgPeriodCount = 7,
	periodLengthMs = constants.daysToMs(1), -- one day
	demandFactorBaseValue = 1,
	demandFactorMin = 0.5,
	demandFactorUpAdjustment = 0.05,
	demandFactorDownAdjustment = 0.025,
	stepDownThreshold = 3,
	criteria = "revenue",
}

-- VAULTS
constants.MIN_VAULT_SIZE = constants.ARIOToMARIO(100) -- 100 ARIO
constants.MAX_TOKEN_LOCK_TIME_MS = constants.yearsToMs(12) -- The maximum amount of blocks tokens can be locked in a vault (12 years of blocks)
constants.MIN_TOKEN_LOCK_TIME_MS = constants.daysToMs(14) -- The minimum amount of blocks tokens can be locked in a vault (14 days of blocks)

-- ARNS FEES
constants.genesisFees = {
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

-- General
constants.MIN_UNSAFE_ADDRESS_LENGTH = 1
constants.MAX_UNSAFE_ADDRESS_LENGTH = 128

return constants
