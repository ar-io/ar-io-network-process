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
constants.DEFAULT_PROTOCOL_BALANCE = constants.ARIOToMARIO(50000000) -- 50M ARIO (TODO: may change to 65M on mainnet)
constants.MIN_UNSAFE_ADDRESS_LENGTH = 1
constants.MAX_UNSAFE_ADDRESS_LENGTH = 128

-- EPOCHS
constants.DEFAULT_EPOCH_SETTINGS = {
	prescribedNameCount = 2, -- observers choose 8 names per epoch
	maxObservers = 50,
	epochZeroStartTimestamp = 1719900000000, -- July 9th,2024 00:00:00 UTC (TODO: set this on mainnet process, likely two weeks after TGE)
	durationMs = constants.daysToMs(1), -- 1 day
}

-- DISTRIBUTIONS
--[[
	Distribution rewards will be 0.1% of the protocol balance for the first year,
	then decay linearly to 0.05% of the protocol balance after the first year until 1.5 years.
	After 1.5 years, the reward rate will be 0.05% of the protocol balance.

	TODO: ensure this is enabled on mainnet
]]
--
constants.DEFAULT_DISTRIBUTION_SETTINGS = {
	maximumRewardRate = 0.001, -- 0.1% of the protocol balance for the first year
	minimumRewardRate = 0.0005, -- 0.05% of the protocol balance after the first year
	rewardDecayStartEpoch = 365, -- one year of epochs before it kicks in
	rewardDecayLastEpoch = 547, -- 1.5 years of epochs before it stops
	gatewayOperatorRewardRatio = 0.9, -- 90% of the rewards go to the gateway operators
	observerRewardRatio = 0.1, -- 10% of the rewards go to the observers
}

-- GAR
constants.DEFAULT_GAR_SETTINGS = {
	observers = {
		maxPerEpoch = 50, -- remove this reference, it is above and defined by the epoch settings
		tenureWeightDaysDenominator = 180, -- tenure weight is computed by tenure / 6-months
		tenureWeightPeriod = constants.daysToMs(180), -- 180 days in ms
		maxTenureWeight = 4, -- i.e. an operator has been running for 2 years or more
	},
	operators = {
		minStake = constants.ARIOToMARIO(10000), -- 10,000 ARIO
		withdrawLengthMs = constants.daysToMs(90), -- 90 days to lower operator stake
		leaveLengthMs = constants.daysToMs(90), -- 90 days that balance will be vaulted
		failedEpochCountMax = 30, -- number of epochs failed before marked as leaving
		failedEpochSlashRate = 1, -- 100% of the minimum operator stake is returned to protocol balance, rest is vaulted
		maxDelegateRewardShareRatio = 95, -- 95% of rewards can be shared with delegates, intended to promote competition between gateways
	},
	delegates = {
		minStake = constants.ARIOToMARIO(10), -- 10 ARIO
		withdrawLengthMs = constants.daysToMs(90), -- 90 days once withdraw is requested, subject to redelegation rules and penalties for early withdrawal
	},
	redelegations = {
		-- TODO: verify the logic uses these variables
		minRedelegationPenaltyRate = 0.10, -- the minimum penalty rate for a redelegation (10% of the amount being redelegated)
		maxRedelegationPenaltyRate = 0.60, -- the maximum penalty rate for a redelegation (50% of the amount being redelegated)
		minRedelegationAmount = constants.ARIOToMARIO(1), -- the minimum amount that can be redelegated
		redelegationFeeResetIntervalMs = constants.daysToMs(7), -- 7 days
	},
	expeditedWithdrawals = {
		minExpeditedWithdrawalPenaltyRate = 0.10, -- the minimum penalty rate for an expedited withdrawal (10% of the amount being withdrawn)
		maxExpeditedWithdrawalPenaltyRate = 0.50, -- the maximum penalty rate for an expedited withdrawal (50% of the amount being withdrawn)
		minExpeditedWithdrawalAmount = constants.ARIOToMARIO(1), -- the minimum amount that can be expedited
	},
}

-- DEMAND FACTOR
--- TODO: validate the demand factor down behavior on mainnet
constants.DEFAULT_DEMAND_FACTOR_SETTINGS = {
	periodZeroStartTimestamp = 1722837600000, -- 08/05/2024 @ 12:00am (UTC) (TODO: set this on mainnet process, it could start whenever the process is created)
	movingAvgPeriodCount = 7, -- the number of periods to use for the moving average
	periodLengthMs = constants.daysToMs(1), -- one day in milliseconds
	demandFactorBaseValue = 1, -- the base demand factor
	demandFactorMin = 0.5, -- the minimum demand factor
	demandFactorUpAdjustment = 0.05, -- 5%
	demandFactorDownAdjustment = 0.015, -- 1.5%
	stepDownThreshold = 3, -- three consecutive periods with the minimum demand factor (TODO: mainnet this should be 14)
	criteria = "revenue", -- "revenue" or "purchases"
	-- NOTE: we may manually set the demand factor to 2 on mainnet, would be a separate variable here
}

-- VAULTS
constants.MIN_VAULT_SIZE = constants.ARIOToMARIO(100) -- 100 ARIO
constants.MAX_TOKEN_LOCK_TIME_MS = constants.yearsToMs(12) -- The maximum amount of blocks tokens can be locked in a vault (12 years) (TODO: make this 50 years or larger?)
constants.MIN_TOKEN_LOCK_TIME_MS = constants.daysToMs(14) -- The minimum amount of blocks tokens can be locked in a vault (14 days)

-- ARNS
constants.DEFAULT_UNDERNAME_COUNT = 10
constants.MAX_NAME_LENGTH = 51 -- protects against invalid URLs when resolving arns names on gateways
constants.MIN_NAME_LENGTH = 1
-- Regex pattern to validate ARNS names:
-- - Starts with an alphanumeric character (%w)
-- - Can contain alphanumeric characters and hyphens (%w-)
-- - Ends with an alphanumeric character (%w)
-- - Does not allow names to start or end with a hyphen
constants.ARNS_NAME_REGEX = "^%w[%w-]*%w?$" -- TODO: validate tests around this
constants.PERMABUY_LEASE_FEE_LENGTH = 20 -- buying a permabuy record is equal to leasing the name for 20 years
constants.ANNUAL_PERCENTAGE_FEE = 0.2 -- the fee applied for leases against the base name
constants.UNDERNAME_LEASE_FEE_PERCENTAGE = 0.001 -- for leased names the undername fee is 0.1% for one undername
constants.UNDERNAME_PERMABUY_FEE_PERCENTAGE = 0.005 -- for permabuy names the undername fee is 0.5% for one undername
constants.GRACE_PERIOD_MS = constants.daysToMs(14) -- the grace period for expired names (TODO: verify in addition to extending, it can be upgraded)
constants.MAX_LEASE_LENGTH_YEARS = 5 -- the maximum number of years a name can be leased for
constants.RETURNED_NAME_DURATION_MS = constants.daysToMs(14) -- the returned period for names that have expired beyond their grace period or manually returned, where a multiplier is applied for purchasing
constants.RETURNED_NAME_MAX_MULTIPLIER = 50 -- Freshly returned names will have a multiplier of 50x
constants.PRIMARY_NAME_REQUEST_DEFAULT_NAME_LENGTH = 51 -- primary name requests cost the same as a single undername on a 51 character name
constants.GATEWAY_OPERATOR_ARNS_DISCOUNT_PERCENTAGE = 0.2 -- operator discount applied to arns requests
constants.GATEWAY_OPERATOR_ARNS_DISCOUNT_TENURE_WEIGHT_ELIGIBILITY_THRESHOLD = 1 -- the tenure weight threshold for eligibility for the arns discount (you need to be an operator for 3 months to qualify) TODO: consider bumping this to 1 implying you must run a gateway for 6 months before qualifying
constants.GATEWAY_OPERATOR_ARNS_DISCOUNT_GATEWAY_PERFORMANCE_RATIO_ELIGIBILITY_THRESHOLD = 0.85 -- the gateway performance ratio threshold for eligibility for the arns discount (you need to have a 85% performance ratio to qualify)
constants.GATEWAY_OPERATOR_ARNS_DISCOUNT_NAME = "Gateway Operator ArNS Discount" -- the name of the discount applied to arns requests
-- TODO: these will likely be adjusted for mainnet
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
