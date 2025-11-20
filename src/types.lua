--- Type definitions for the AR.IO Network Process
--- This file contains all type annotations used throughout the codebase
---
--- Note: This file is automatically discovered by the Lua Language Server
--- and does not need to be required/imported in other files.
--- Types defined here are available globally for type checking and autocomplete.

--[[
  Primitive Type Aliases
]]

--- @alias WalletAddress string A wallet address
--- @alias MessageId string A message identifier
--- @alias VaultId string A vault identifier (typically a MessageId)
--- @alias Timestamp number A timestamp in milliseconds
--- @alias mARIO number Amount in mARIO (millio ARIO tokens)
--- @alias GatewayAddress string A gateway wallet address
--- @alias ObserverAddress string An observer wallet address
--- @alias DelegateAddress string A delegate wallet address
--- @alias TransactionId string A transaction identifier
--- @alias ArNSName string An ArNS name

--[[
  Core Message Types
]]

--- Raw message as it comes in from ao, before sanitization
--- All Tags are strings (or string|number|boolean if passed that way)
--- @class RawMessage
--- @field Id MessageId The message identifier
--- @field Action string The action to perform
--- @field From string The sender address (not yet formatted)
--- @field Owner string The owner address (not yet formatted)
--- @field Timestamp string|number The message timestamp (as string or number)
--- @field Tags table<string, string|number|boolean> Raw tags before sanitization
--- @field Data string|nil The message data
--- @field reply function|nil Reply function for backwards compatibility

--- Message tags after sanitization by assertAndSanitizeInputs
--- Known address tags are formatted as WalletAddress
--- Known number tags are converted to number
--- Known boolean tags are converted to boolean
--- @class MessageTags
--- @field Action string The action to perform (always present)
--- @field Recipient? WalletAddress Formatted recipient address
--- @field Initiator? WalletAddress Formatted initiator address
--- @field Target? WalletAddress Formatted target address
--- @field Source? WalletAddress Formatted source address
--- @field Address? WalletAddress Formatted address
--- @field ["Vault-Id"]? WalletAddress Formatted vault ID (is a message ID, treated as address)
--- @field ["Process-Id"]? WalletAddress Formatted process ID
--- @field ["Observer-Address"]? WalletAddress Formatted observer address
--- @field Quantity? number Parsed quantity
--- @field ["Lock-Length"]? number Parsed lock length in ms
--- @field ["Operator-Stake"]? number Parsed operator stake
--- @field ["Delegated-Stake"]? number Parsed delegated stake
--- @field ["Withdraw-Stake"]? number Parsed withdraw stake
--- @field Timestamp? Timestamp Parsed timestamp (though also on msg root)
--- @field Years? number Parsed years
--- @field ["Min-Delegated-Stake"]? number Parsed min delegated stake
--- @field Port? number Parsed port number
--- @field ["Extend-Length"]? number Parsed extension length in ms
--- @field ["Delegate-Reward-Share-Ratio"]? number Parsed delegate reward share ratio
--- @field ["Epoch-Index"]? number Parsed epoch index
--- @field ["Price-Interval-Ms"]? number Parsed price interval in ms
--- @field ["Block-Height"]? number Parsed block height
--- @field ["Allow-Unsafe-Addresses"]? boolean Allow unsafe addresses flag
--- @field ["Force-Prune"]? boolean Force prune flag
--- @field Revokable? boolean Revokable flag
--- @field Name? string ArNS name
--- @field Label? string Gateway label
--- @field Note? string Gateway note
--- @field FQDN? string Gateway FQDN
--- @field ["Purchase-Type"]? string Purchase type (lease/permabuy)
--- @field ["Fund-From"]? string Fund from strategy
--- @field Intent? string Intent type for token cost

--- Parsed message after sanitization with typed tags and added fields
--- This is what handlers receive after the 'sanitize' handler runs
--- @class ParsedMessage
--- @field Id MessageId The message identifier
--- @field Action string The action to perform
--- @field From WalletAddress The sender address (formatted)
--- @field Owner WalletAddress The owner address
--- @field Timestamp Timestamp The message timestamp (converted to number)
--- @field Tags MessageTags The sanitized message tags with proper types
--- @field Data string|nil The message data
--- @field reply function|nil Reply function for backwards compatibility
--- @field ioEvent IOEvent The event tracking object
--- @field Cast boolean|nil Whether this is a cast message

--- @class SendResponse
--- @field Target string The target address
--- @field Action? string The action
--- @field Tags? table<string, string> Tags (all values must be strings)
--- @field Data? string The data
--- @field Quantity? string The quantity (must be string)
--- @field Recipient? string The recipient address
--- @field Sender? string The sender address

--- @class IOEvent
--- @field addField fun(self: IOEvent, key: string, value: any): IOEvent Add a field to the event
--- @field addFieldsWithPrefixIfExist fun(self: IOEvent, table: table, prefix: string, excludeKeys: string[]): IOEvent Add fields with prefix
--- @field toJSON fun(self: IOEvent): string Convert to JSON

--[[
  Balance & Vault Types
]]

--- @class Vault
--- @field balance mARIO The balance of the vault
--- @field controller WalletAddress|nil The controller of a revokable vault. Nil if not revokable
--- @field startTimestamp Timestamp The start timestamp of the vault
--- @field endTimestamp Timestamp The end timestamp of the vault

--- @alias Vaults table<WalletAddress, table<VaultId, Vault>> A table of vaults indexed by owner address, then by vault id

--[[
  Gateway Types
]]

--- @class GatewayRegistrySettings
--- @field observers ObserverSettings
--- @field operators OperatorSettings
--- @field delegates DelegateSettings
--- @field expeditedWithdrawals ExpeditedWithdrawalsSettings

--- @class ObserverSettings
--- @field tenureWeightDays number
--- @field tenureWeightDurationMs number
--- @field maxTenureWeight number

--- @class OperatorSettings
--- @field minStake number
--- @field withdrawLengthMs number
--- @field leaveLengthMs number
--- @field failedEpochCountMax number
--- @field failedGatewaySlashRate number
--- @field maxDelegateRewardSharePct number

--- @class DelegateSettings
--- @field minStake number
--- @field withdrawLengthMs number

--- @class ExpeditedWithdrawalsSettings
--- @field minExpeditedWithdrawalPenaltyRate number
--- @field maxExpeditedWithdrawalPenaltyRate number
--- @field minExpeditedWithdrawalAmount number

--- @class CompactGatewaySettings
--- @field allowDelegatedStaking boolean
--- @field allowedDelegatesLookup table<WalletAddress, boolean>|nil
--- @field delegateRewardShareRatio number
--- @field autoStake boolean
--- @field minDelegatedStake number
--- @field label string
--- @field fqdn string
--- @field protocol string
--- @field port number
--- @field properties string
--- @field note string|nil

--- @class GatewaySettings : CompactGatewaySettings
--- @field allowedDelegatesLookup table<WalletAddress, boolean>|nil

--- @class JoinGatewaySettings
--- @field allowDelegatedStaking boolean|nil
--- @field allowedDelegates WalletAddress[]|nil
--- @field delegateRewardShareRatio number|nil
--- @field autoStake boolean|nil
--- @field minDelegatedStake number
--- @field label string
--- @field fqdn string
--- @field protocol string
--- @field port number
--- @field properties string
--- @field note string|nil

--- @class GatewayStats
--- @field prescribedEpochCount number
--- @field observedEpochCount number
--- @field totalEpochCount number
--- @field passedEpochCount number
--- @field failedEpochCount number
--- @field failedConsecutiveEpochs number
--- @field passedConsecutiveEpochs number

--- @class GatewayWeights
--- @field stakeWeight number
--- @field tenureWeight number
--- @field gatewayPerformanceRatio number
--- @field observerPerformanceRatio number
--- @field compositeWeight number
--- @field normalizedCompositeWeight number

--- @class GatewayService
--- @field fqdn string
--- @field port number
--- @field path string
--- @field protocol string

--- @alias GatewayServices table<'bundler', GatewayService>

--- @class CompactGateway
--- @field operatorStake number
--- @field totalDelegatedStake number
--- @field startTimestamp Timestamp
--- @field endTimestamp Timestamp|nil
--- @field stats GatewayStats
--- @field settings CompactGatewaySettings
--- @field services GatewayServices|nil
--- @field status "joined"|"leaving"
--- @field observerAddress WalletAddress
--- @field weights GatewayWeights
--- @field slashings table<Timestamp, mARIO>|nil

--- @class Gateway : CompactGateway
--- @field vaults table<WalletAddress, Vault>
--- @field delegates table<WalletAddress, Delegate>
--- @field settings GatewaySettings

--- @class Delegate
--- @field delegatedStake number
--- @field startTimestamp Timestamp
--- @field vaults table<MessageId, Vault>

--- @class Delegation
--- @field type string The type of the object. Either "stake" or "vault"
--- @field gatewayAddress string The address of the gateway the delegation is associated with
--- @field delegateStake number|nil The amount of stake delegated to the gateway if type is "stake"

--- @alias Gateways table<WalletAddress, Gateway>

--[[
  Epoch Types
]]

--- @class EpochSettings
--- @field prescribedNameCount number The number of prescribed names
--- @field rewardPercentage number The reward percentage
--- @field maxObservers number The maximum number of observers
--- @field epochZeroStartTimestamp number The start timestamp of epoch zero
--- @field durationMs number The duration of an epoch in milliseconds

--- @class DistributionSettings
--- @field observerPercentage number The percentage of rewards for observers
--- @field eligibleGatewayPercentage number The percentage of rewards for eligible gateways

--- @class ArNSStats
--- @field totalActiveNames number The total active ArNS names
--- @field totalGracePeriodNames number The total grace period ArNS names
--- @field totalReservedNames number The total reserved ArNS names
--- @field totalReturnedNames number The total returned ArNS names

--- @class Observations
--- @field failureSummaries table The failure summaries
--- @field reports Reports The reports for the epoch (indexed by observer address)

--- @alias Reports table<ObserverAddress, string>

--- @class GatewayRewards
--- @field operatorReward number The total operator reward eligible
--- @field delegateRewards table<DelegateAddress, number> The delegate rewards eligible, indexed by delegate address

--- @class PrescribedEpochRewards
--- @field eligible table<GatewayAddress, GatewayRewards> The eligible rewards

--- @class DistributedEpochRewards : PrescribedEpochRewards
--- @field distributed table<GatewayAddress | DelegateAddress, number> The distributed rewards

--- @class PrescribedEpochDistribution
--- @field totalEligibleGateways number The total eligible gateways
--- @field totalEligibleRewards number The total eligible rewards
--- @field totalEligibleGatewayReward number The total eligible gateway reward
--- @field totalEligibleObserverReward number The total eligible observer reward
--- @field rewards PrescribedEpochRewards The rewards for the epoch

--- @class DistributedEpochDistribution : PrescribedEpochDistribution
--- @field distributedTimestamp number The distributed timestamp
--- @field totalDistributedRewards number The total distributed rewards
--- @field rewards DistributedEpochRewards The rewards for the epoch

--- @class PrescribedEpoch
--- @field hashchain string The hashchain of the epoch
--- @field epochIndex number The index of the epoch
--- @field startTimestamp number The start timestamp of the epoch
--- @field endTimestamp number The end timestamp of the epoch
--- @field startHeight number The start height of the epoch
--- @field arnsStats ArNSStats The ArNS stats for the epoch
--- @field prescribedObservers table<ObserverAddress, GatewayAddress> The prescribed observers
--- @field prescribedNames string[] The prescribed names of the epoch
--- @field distributions PrescribedEpochDistribution The distributions of the epoch
--- @field observations Observations The observations of the epoch

--- @class DistributedEpoch : PrescribedEpoch
--- @field distributions DistributedEpochDistribution The rewards of the epoch

--- @class WeightedGateway
--- @field gatewayAddress string The gateway address
--- @field observerAddress string The observer address
--- @field stakeWeight number The stake weight
--- @field tenureWeight number The tenure weight
--- @field gatewayPerformanceRatio number The gateway reward ratio weight
--- @field observerPerformanceRatio number The observer reward ratio weight
--- @field compositeWeight number The composite weight
--- @field normalizedCompositeWeight number The normalized composite weight

--- @alias Epochs table<number, PrescribedEpoch>

--[[
  ArNS Types
]]

--- @class NameRegistry
--- @field reserved table<string, ReservedName> The reserved names
--- @field records table<string, Record> The records
--- @field returned table<string, ReturnedName> The returned records

--- @class StoredRecord
--- @field processId string The process id of the record
--- @field startTimestamp number The start timestamp of the record
--- @field type 'lease' | 'permabuy' The type of the record
--- @field undernameLimit number The undername limit of the record
--- @field purchasePrice number The purchase price of the record
--- @field endTimestamp number|nil The end timestamp of the record

--- @class Record : StoredRecord
--- @field name string The name of the record

--- @class ReservedName
--- @field name string The name of the reserved record
--- @field target string|nil The address of the target of the reserved record
--- @field endTimestamp number|nil The time at which the record is no longer reserved

--- @class ReturnedName
--- @field name string The name of the returned record
--- @field initiator WalletAddress
--- @field startTimestamp Timestamp The timestamp of when the record was returned

--- @class ReturnedNameData : ReturnedName
--- @field endTimestamp Timestamp The timestamp of when the record will no longer be in the returned period
--- @field premiumMultiplier number The current multiplier for the returned name

--- @class ReturnedNameBuyRecordResult
--- @field initiator WalletAddress
--- @field rewardForProtocol mARIO The reward for the protocol from the returned name purchase
--- @field rewardForInitiator mARIO The reward for the initiator from the returned name purchase

--[[
  Funding & Token Cost Types
]]

--- @class FundingPlan
--- @field balance number The balance to use
--- @field stakes table<GatewayAddress, StakeSpendingPlan> The stakes to use
--- @field shortfall number The shortfall amount

--- @class StakeSpendingPlan
--- @field delegatedStake number The delegated stake amount
--- @field vaults table<VaultId, number> The vaults to use

--- @class FundingResult
--- @field newWithdrawVaults table<GatewayAddress, table<VaultId, Vault>> New withdraw vaults created

--- @class Discount
--- @field name string The name of the discount
--- @field discountTotal number The discounted cost
--- @field multiplier number The multiplier for the discount

--- @class TokenCostResult
--- @field tokenCost number The token cost in mARIO of the intended action
--- @field discounts table|nil The discounts applied to the token cost
--- @field returnedNameDetails table|nil The details of anything returned name in the token cost result

--- @class TokenCostAndFundingPlan
--- @field tokenCost number The token cost in mARIO of the intended action
--- @field discounts table|nil The discounts applied to the token cost
--- @field fundingPlan table|nil The funding plan for the intended action

--- @class RecordInteractionResult
--- @field record Record The updated record
--- @field baseRegistrationFee number The base registration fee
--- @field remainingBalance number The remaining balance
--- @field protocolBalance number The protocol balance
--- @field df table The demand factor info
--- @field fundingPlan FundingPlan The funding plan
--- @field fundingResult table The funding result
--- @field totalFee mARIO The total fee for the name-related operation

--- @class BuyNameResult : RecordInteractionResult
--- @field recordsCount number The total number of records
--- @field reservedRecordsCount number The total number of reserved records
--- @field returnedName nil|ReturnedNameBuyRecordResult The initiator and reward details if returned name was purchased

--[[
  Primary Names Types
]]

--- @class PrimaryNames
--- @field owners table<WalletAddress, PrimaryName> Map indexed by owner address
--- @field names table<ArNSName, WalletAddress> Map indexed by primary name
--- @field requests table<WalletAddress, PrimaryNameRequest> Map indexed by owner address

--- @class PrimaryName
--- @field name ArNSName
--- @field startTimestamp number

--- @class PrimaryNameWithOwner
--- @field name ArNSName
--- @field owner WalletAddress
--- @field startTimestamp number

--- @class PrimaryNameInfo
--- @field name ArNSName
--- @field owner WalletAddress
--- @field startTimestamp number
--- @field processId WalletAddress

--- @class PrimaryNameRequest
--- @field name ArNSName The name being requested
--- @field startTimestamp number The timestamp of the request
--- @field endTimestamp number The timestamp of the request expiration

--- @class CreatePrimaryNameResult
--- @field request PrimaryNameRequest|nil
--- @field newPrimaryName PrimaryNameWithOwner|nil
--- @field baseNameOwner WalletAddress
--- @field fundingPlan table
--- @field fundingResult table
--- @field demandFactor table

--- @class PrimaryNameRequestApproval
--- @field newPrimaryName PrimaryNameWithOwner
--- @field baseNameOwner WalletAddress
--- @field fundingPlan FundingPlan|nil
--- @field fundingResult table|nil

--[[
  Demand Factor Types
]]

--- @class DemandFactor
--- @field currentPeriod number The current period
--- @field trailingPeriodPurchases number[] The trailing period purchases
--- @field trailingPeriodRevenues number[] The trailing period revenues
--- @field purchasesThisPeriod number The current period purchases
--- @field revenueThisPeriod number The current period revenue
--- @field currentDemandFactor number The current demand factor
--- @field consecutivePeriodsWithMinDemandFactor number The number of consecutive periods with the minimum demand factor
--- @field fees table<number, number> The fees for each name length

--- @class DemandFactorSettings
--- @field periodZeroStartTimestamp number The timestamp of the start of period zero
--- @field movingAvgPeriodCount number The number of periods to use for the moving average
--- @field periodLengthMs number The length of a period in milliseconds
--- @field demandFactorBaseValue number The base demand factor value
--- @field demandFactorMin number The minimum demand factor value
--- @field demandFactorUpAdjustmentRate number The adjustment when demand is increasing
--- @field demandFactorDownAdjustmentRate number The adjustment when demand is decreasing
--- @field maxPeriodsAtMinDemandFactor number The threshold for consecutive periods at min
--- @field criteria 'revenue' | 'purchases' The criteria for determining demand

--[[
  Prune Types
]]

--- @class PruneStateResult
--- @field prunedRecords table<string, Record>
--- @field newGracePeriodRecords table<string, Record>
--- @field prunedReturnedNames table<string, ReturnedName>
--- @field prunedReserved table<string, ReservedName>
--- @field prunedVaults table<WalletAddress, table<VaultId, Vault>>
--- @field prunedPrimaryNameRequests table<WalletAddress, PrimaryNameRequest>

--- @class PruneGatewaysResult
--- @field prunedGateways table<GatewayAddress, Gateway>
--- @field slashedGateways table<GatewayAddress, mARIO>

return {}
