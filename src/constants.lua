local constants = {}

-- GAR
constants.DEFAULT_UNDERNAME_COUNT = 10
constants.DEADLINE_DURATION_MS = 60 * 60 * 1000 -- One hour of miliseconds
constants.oneYearSeconds = 60 * 60 * 24 * 365
constants.thirtyDaysSeconds = 60 * 60 * 24 * 30
constants.defaultundernameLimit = 10
constants.totalTokenSupply = 1000000000 * 1000000 -- 1 billion tokens

-- ARNS
constants.DEFAULT_UNDERNAME_COUNT = 10
constants.DEADLINE_DURATION_MS = 60 * 60 * 1000 -- One hour of miliseconds
constants.PERMABUY_LEASE_FEE_LENGTH = 20
constants.ANNUAL_PERCENTAGE_FEE = 0.2
constants.ARNS_NAME_DOES_NOT_EXIST_MESSAGE = "Name does not exist in the ArNS Registry!"
constants.ARNS_MAX_UNDERNAME_MESSAGE = "Name has reached undername limit of 10000"
constants.MAX_ALLOWED_UNDERNAMES = 10000
constants.UNDERNAME_LEASE_FEE_PERCENTAGE = 0.001
constants.UNDERNAME_PERMABUY_FEE_PERCENTAGE = 0.005
constants.oneYearMs = 31536000 * 1000
constants.gracePeriodMs = 3 * 14 * 24 * 60 * 60 * 1000
constants.maxLeaseLengthYears = 5

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

-- BALANCES
constants.MAX_TOKEN_LOCK_TIME = 12 * 365 * 24 * 60 * 60 * 1000 -- The maximum amount of blocks tokens can be locked in a vault (12 years of blocks)
constants.MIN_TOKEN_LOCK_TIME = 14 * 24 * 60 * 60 * 1000 -- The minimum amount of blocks tokens can be locked in a vault (14 days of blocks)

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

return constants
