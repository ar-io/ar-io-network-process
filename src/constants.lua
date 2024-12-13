local constants = {}

constants.oneYearSeconds = 60 * 60 * 24 * 365
constants.thirtyDaysSeconds = 60 * 60 * 24 * 30

constants.oneHourMs = 1000 * 60 * 60
constants.oneDayMs = constants.oneHourMs * 24
constants.oneWeekMs = constants.oneDayMs * 7
constants.twoWeeksMs = constants.oneWeekMs * 2
constants.oneYearMs = 31536000 * 1000

-- EPOCHS
constants.defaultEpochDurationMs = constants.oneDayMs
constants.decayStartingRewardRate = 0.001
constants.defaultRewardRate = 0.0005
constants.rewardDecayStartEpoch = 365
constants.rewardDecayEndEpoch = 548

-- GAR
constants.DEFAULT_UNDERNAME_COUNT = 10
constants.DEADLINE_DURATION_MS = constants.oneHourMs
constants.totalTokenSupply = 1000000000 * 1000000 -- 1 billion tokens
constants.MIN_EXPEDITED_WITHDRAWAL_PENALTY_RATE = 0.10 -- the minimum penalty rate for an expedited withdrawal (10% of the amount being withdrawn)
constants.MAX_EXPEDITED_WITHDRAWAL_PENALTY_RATE = 0.50 -- the maximum penalty rate for an expedited withdrawal (50% of the amount being withdrawn)
constants.mARIOPerARIO = 1000000
constants.minimumWithdrawalAmount = constants.mARIOPerARIO -- the minimum amount that can be withdrawn from the GAR
constants.redelegationFeeResetIntervalMs = constants.defaultEpochDurationMs * 7 -- 7 epochs
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
constants.DEADLINE_DURATION_MS = constants.oneHourMs
constants.PERMABUY_LEASE_FEE_LENGTH = 20 -- 20 years
constants.ANNUAL_PERCENTAGE_FEE = 0.2 -- 20%
constants.ARNS_NAME_DOES_NOT_EXIST_MESSAGE = "Name not found in the ArNS Registry!"
constants.UNDERNAME_LEASE_FEE_PERCENTAGE = 0.001
constants.UNDERNAME_PERMABUY_FEE_PERCENTAGE = 0.005
constants.PRIMARY_NAME_REQUEST_COST = 10000000 -- 10 ARIO
constants.gracePeriodMs = constants.defaultEpochDurationMs * 14 -- 14 epochs
constants.maxLeaseLengthYears = 5
constants.returnedNamePeriod = constants.defaultEpochDurationMs * 14 -- 14 epochs
constants.returnedNameMaxMultiplier = 50 -- Freshly returned names will have a multiplier of 50x

constants.ARNS_DISCOUNT_PERCENTAGE = 0.2
constants.ARNS_DISCOUNT_TENURE_WEIGHT_ELIGIBILITY_THRESHOLD = 1
constants.ARNS_DISCOUNT_GATEWAY_PERFORMANCE_RATIO_ELIGIBILITY_THRESHOLD = 0.85
constants.ARNS_DISCOUNT_NAME = "ArNS Discount"

-- DEMAND
constants.demandSettings = {
	movingAvgPeriodCount = 7,
	periodLengthMs = 60 * 1000 * 24, -- one day
	demandFactorBaseValue = 1,
	demandFactorMin = 0.5,
	demandFactorUpAdjustment = 0.05,
	demandFactorDownAdjustment = 0.025,
	stepDownThreshold = 3,
	criteria = "revenue",
}

-- VAULTS
constants.MIN_VAULT_SIZE = 100000000 -- 100 ARIO
constants.MAX_TOKEN_LOCK_TIME_MS = 12 * 365 * 24 * 60 * 60 * 1000 -- The maximum amount of blocks tokens can be locked in a vault (12 years of blocks)
constants.MIN_TOKEN_LOCK_TIME_MS = 14 * 24 * 60 * 60 * 1000 -- The minimum amount of blocks tokens can be locked in a vault (14 days of blocks)

-- ARNS FEES
constants.genesisFees = {
	[1] = 2000000000000,
	[2] = 200000000000,
	[3] = 40000000000,
	[4] = 10000000000,
	[5] = 4000000000,
	[6] = 2000000000,
	[7] = 1000000000,
	[8] = 600000000,
	[9] = 500000000,
	[10] = 500000000,
	[11] = 500000000,
	[12] = 500000000,
	[13] = 400000000,
	[14] = 400000000,
	[15] = 400000000,
	[16] = 400000000,
	[17] = 400000000,
	[18] = 400000000,
	[19] = 400000000,
	[20] = 400000000,
	[21] = 400000000,
	[22] = 400000000,
	[23] = 400000000,
	[24] = 400000000,
	[25] = 400000000,
	[26] = 400000000,
	[27] = 400000000,
	[28] = 400000000,
	[29] = 400000000,
	[30] = 400000000,
	[31] = 400000000,
	[32] = 400000000,
	[33] = 400000000,
	[34] = 400000000,
	[35] = 400000000,
	[36] = 400000000,
	[37] = 400000000,
	[38] = 400000000,
	[39] = 400000000,
	[40] = 400000000,
	[41] = 400000000,
	[42] = 400000000,
	[43] = 400000000,
	[44] = 400000000,
	[45] = 400000000,
	[46] = 400000000,
	[47] = 400000000,
	[48] = 400000000,
	[49] = 400000000,
	[50] = 400000000,
	[51] = 400000000,
}

-- General
constants.MIN_UNSAFE_ADDRESS_LENGTH = 1
constants.MAX_UNSAFE_ADDRESS_LENGTH = 128

return constants
