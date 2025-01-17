local gar = require("gar")
local crypto = require("crypto.init")
local utils = require("utils")
local balances = require("balances")
local arns = require("arns")
local constants = require("constants")
local epochs = {}

--- @class Epoch
--- @field epochIndex number The index of the epoch
--- @field startTimestamp number The start timestamp of the epoch
--- @field endTimestamp number The end timestamp of the epoch
--- @field startHeight number The start height of the epoch
--- @field distributionTimestamp number The distribution timestamp of the epoch
--- @field prescribedObservers table The prescribed observers of the epoch
--- @field prescribedNames table The prescribed names of the epoch
--- @field observations Observations The observations of the epoch
--- @field distributions Distribution The distributions of the epoch

--- @class EpochSettings
--- @field pruneEpochsCount number The number of epochs to prune
--- @field prescribedNameCount number The number of prescribed names
--- @field rewardPercentage number The reward percentage
--- @field maxObservers number The maximum number of observers
--- @field epochZeroStartTimestamp number The start timestamp of epoch zero
--- @field durationMs number The duration of an epoch in milliseconds
--- @field distributionDelayMs number The distribution delay in milliseconds

--- @class WeightedGateway
--- @field gatewayAddress string The gateway address
--- @field observerAddress string The observer address
--- @field stakeWeight number The stake weight
--- @field tenureWeight number The tenure weight
--- @field gatewayRewardRatioWeight number The gateway reward ratio weight
--- @field observerRewardRatioWeight number The observer reward ratio weight
--- @field compositeWeight number The composite weight
--- @field normalizedCompositeWeight number The normalized composite weight

--- @class Observations
--- @field failureSummaries table The failure summaries
--- @field reports Reports The reports for the epoch (indexed by observer address)

--- @class Reports: table<string, string>

--- @class GatewayRewards
--- @field operatorReward number The total operator reward eligible
--- @field delegateRewards table<string, number> The delegate rewards eligible, indexed by delegate address

--- @class Rewards
--- @field eligible table<string, GatewayRewards> A table representing the eligible operator and delegate rewards for a gateway
--- @field distributed table<string, number> A table representing the distributed rewards, only set if rewards have been distributed

--- @class Distribution
--- @field totalEligibleGateways number The total eligible gateways
--- @field totalEligibleRewards number The total eligible rewards
--- @field totalEligibleGatewayReward number The total eligible gateway reward
--- @field totalEligibleObserverReward number The total eligible observer reward
--- @field distributedTimestamp number|nil The distributed timestamp, only set if rewards have been distributed
--- @field totalDistributedRewards number|nil The total distributed rewards, only set if rewards have been distributed
--- @field rewards Rewards The rewards

Epochs = Epochs or {}
EpochSettings = EpochSettings
	or {
		pruneEpochsCount = 14, -- prune epochs older than 14 days
		prescribedNameCount = 2,
		maxObservers = 50,
		epochZeroStartTimestamp = 1719900000000, -- July 9th, 00:00:00 UTC
		durationMs = constants.defaultEpochDurationMs, -- 24 hours
		distributionDelayMs = 60 * 1000 * 40, -- 40 minutes (~ 20 arweave blocks)
	}

--- @type Timestamp|nil
NextEpochsPruneTimestamp = NextEpochsPruneTimestamp or 0

--- Gets a deep copy of all the epochs
--- @return table<number, Epoch> # A deep copy of the epochs indexed by their epoch index
function epochs.getEpochs()
	return utils.deepCopy(Epochs) or {}
end

--- Gets all the epochs
--- @return table<number, Epoch> # The epochs indexed by their epoch index
function epochs.getEpochsUnsafe()
	return Epochs or {}
end

--- Gets an epoch by index
--- @param epochIndex number The epoch index
--- @return Epoch # The epoch
function epochs.getEpoch(epochIndex)
	local epoch = utils.deepCopy(Epochs[epochIndex]) or {}
	return epoch
end

--- Gets the current epoch
--- @return Epoch # The current epoch
function epochs.getCurrentEpoch()
	return epochs.getEpoch(epochs.getEpochIndexForTimestamp(os.time()))
end

--- Gets the epoch settings
--- @return EpochSettings|nil # The epoch settings
function epochs.getSettings()
	return utils.deepCopy(EpochSettings)
end

--- Gets the prescribed observers for an epoch
--- @param epochIndex number The epoch index
--- @return table<WalletAddress, WalletAddress> # The prescribed observers for the epoch
function epochs.getPrescribedObserversForEpoch(epochIndex)
	return epochs.getEpoch(epochIndex).prescribedObservers or {}
end

--- Get prescribed observers with weights for epoch
--- @param epochIndex number The epoch index
--- @return WeightedGateway[] # The prescribed observers with weights for the epoch
function epochs.getPrescribedObserversWithWeightsForEpoch(epochIndex)
	local prescribedObservers = epochs.getPrescribedObserversForEpoch(epochIndex)
	-- Iterate over prescribed observers and add gateway details
	local prescribedObserversWithWeights = {}
	for _, gatewayAddress in pairs(prescribedObservers) do
		local gateway = gar.getGateway(gatewayAddress)
		if gateway then
			table.insert(prescribedObserversWithWeights, {
				observerAddress = gateway.observerAddress,
				gatewayAddress = gatewayAddress,
				normalizedCompositeWeight = gateway.weights.normalizedCompositeWeight,
				stakeWeight = gateway.weights.stakeWeight,
				tenureWeight = gateway.weights.tenureWeight,
				gatewayRewardRatioWeight = gateway.weights.gatewayRewardRatioWeight,
				observerRewardRatioWeight = gateway.weights.observerRewardRatioWeight,
				compositeWeight = gateway.weights.compositeWeight,
				stake = gateway.operatorStake,
				startTimestamp = gateway.startTimestamp,
			})
		end
	end

	-- sort by normalizedCompositeWeight
	table.sort(prescribedObserversWithWeights, function(a, b)
		return a.normalizedCompositeWeight > b.normalizedCompositeWeight
	end)
	return prescribedObserversWithWeights
end

--- Gets the eligible rewards for an epoch
--- @param epochIndex number The epoch index
--- @return Rewards # T	he eligible rewards for the epoch
function epochs.getEligibleRewardsForEpoch(epochIndex)
	local epoch = epochs.getEpoch(epochIndex)
	local eligible = epoch
			and epoch.distributions
			and epoch.distributions.rewards
			and epoch.distributions.rewards.eligible
		or {}
	return eligible
end

--- Gets the distributed rewards for an epoch
--- @param epochIndex number The epoch index
--- @return Rewards # The distributed rewards for the epoch
function epochs.getDistributedRewardsForEpoch(epochIndex)
	local epoch = epochs.getEpoch(epochIndex)
	local distributed = epoch
			and epoch.distributions
			and epoch.distributions.rewards
			and epoch.distributions.rewards.distributed
		or {}
	return distributed
end

--- Gets the observations for an epoch
--- @param epochIndex number The epoch index
--- @return Observations # The observations for the epoch
function epochs.getObservationsForEpoch(epochIndex)
	return epochs.getEpoch(epochIndex).observations or {}
end

--- Gets the distributions for an epoch
--- @param epochIndex number The epoch index
--- @return Distribution # The distributions for the epoch
function epochs.getDistributionsForEpoch(epochIndex)
	return epochs.getEpoch(epochIndex).distributions or {}
end

--- Gets the prescribed names for an epoch
--- @param epochIndex number The epoch index
--- @return string[] # 	The prescribed names for the epoch
function epochs.getPrescribedNamesForEpoch(epochIndex)
	return epochs.getEpoch(epochIndex).prescribedNames or {}
end

--- Gets the reports for an epoch
--- @param epochIndex number The epoch index
--- @return table<string, Report> # The reports for the epoch
function epochs.getReportsForEpoch(epochIndex)
	return epochs.getEpoch(epochIndex).observations.reports or {}
end

--- Gets the distribution for an epoch
--- @param epochIndex number The epoch index
--- @return Distribution # The distribution for the epoch
function epochs.getDistributionForEpoch(epochIndex)
	return epochs.getEpoch(epochIndex).distributions or {}
end

--- Computes the prescribed names for an epoch
--- @param epochIndex number The epoch index
--- @param hashchain string The hashchain
--- @return string[] # The prescribed names for the epoch
function epochs.computePrescribedNamesForEpoch(epochIndex, hashchain)
	local epochStartTimestamp, epochEndTimestamp = epochs.getEpochTimestampsForIndex(epochIndex)
	local activeArNSNames = arns.getActiveArNSNamesBetweenTimestamps(epochStartTimestamp, epochEndTimestamp)

	-- sort active records by name and hashchain
	table.sort(activeArNSNames, function(nameA, nameB)
		local nameAHash = utils.getHashFromBase64URL(nameA)
		local nameBHash = utils.getHashFromBase64URL(nameB)
		local nameAString = crypto.utils.array.toString(nameAHash)
		local nameBString = crypto.utils.array.toString(nameBHash)
		return nameAString < nameBString
	end)

	if #activeArNSNames <= epochs.getSettings().prescribedNameCount then
		return activeArNSNames
	end

	local epochHash = utils.getHashFromBase64URL(hashchain)
	local prescribedNamesLookup = {}
	local hash = epochHash
	while utils.lengthOfTable(prescribedNamesLookup) < epochs.getSettings().prescribedNameCount do
		local hashString = crypto.utils.array.toString(hash)
		local random = crypto.random(nil, nil, hashString) % #activeArNSNames

		for i = 0, #activeArNSNames do
			local index = (random + i) % #activeArNSNames + 1
			local alreadyPrescribed = prescribedNamesLookup[activeArNSNames[index]] ~= nil
			if not alreadyPrescribed then
				prescribedNamesLookup[activeArNSNames[index]] = true
				break
			end
		end

		-- hash the hash to get a new hash
		local newHash = crypto.utils.stream.fromArray(hash)
		hash = crypto.digest.sha2_256(newHash).asBytes()
	end

	local prescribedNames = utils.getTableKeys(prescribedNamesLookup)

	-- sort them by name
	table.sort(prescribedNames, function(a, b)
		return a < b
	end)
	return prescribedNames
end

--- Computes the prescribed observers for an epoch
--- @param epochIndex number The epoch index
--- @param hashchain string The hashchain
--- @return table<WalletAddress, WalletAddress>, WeightedGateway[] # The prescribed observers for the epoch, and all the gateways with weights
function epochs.computePrescribedObserversForEpoch(epochIndex, hashchain)
	assert(epochIndex >= 0, "Epoch index must be greater than or equal to 0")
	assert(type(hashchain) == "string", "Hashchain must be a string")

	local epochStartTimestamp = epochs.getEpochTimestampsForIndex(epochIndex)
	local activeGatewayAddresses = gar.getActiveGatewaysBeforeTimestamp(epochStartTimestamp)
	local weightedGateways = gar.getGatewayWeightsAtTimestamp(activeGatewayAddresses, epochStartTimestamp)

	-- Filter out any observers that could have a normalized composite weight of 0
	local filteredObservers = {}
	local prescribedObserversLookup = {}
	-- use ipairs as weightedObservers in array
	for _, observer in ipairs(weightedGateways) do
		if observer.normalizedCompositeWeight > 0 then
			table.insert(filteredObservers, observer)
		end
	end
	if #filteredObservers <= epochs.getSettings().maxObservers then
		for _, observer in ipairs(filteredObservers) do
			prescribedObserversLookup[observer.observerAddress] = observer.gatewayAddress
		end
		return prescribedObserversLookup, weightedGateways
	end

	-- the hash we will use to create entropy for prescribed observers
	local epochHash = utils.getHashFromBase64URL(hashchain)

	-- sort the observers using entropy from the hash chain, this will ensure that the same observers are selected for the same epoch
	table.sort(filteredObservers, function(observerA, observerB)
		local addressAHash = utils.getHashFromBase64URL(observerA.gatewayAddress .. hashchain)
		local addressBHash = utils.getHashFromBase64URL(observerB.gatewayAddress .. hashchain)
		local addressAString = crypto.utils.array.toString(addressAHash)
		local addressBString = crypto.utils.array.toString(addressBHash)
		return addressAString < addressBString
	end)

	-- get our prescribed observers, using the hashchain as entropy
	local hash = epochHash
	while utils.lengthOfTable(prescribedObserversLookup) < epochs.getSettings().maxObservers do
		local hashString = crypto.utils.array.toString(hash)
		local random = crypto.random(nil, nil, hashString) / 0xffffffff
		local cumulativeNormalizedCompositeWeight = 0
		for _, observer in ipairs(filteredObservers) do
			local alreadyPrescribed = prescribedObserversLookup[observer.observerAddress]
			-- add only if observer has not already been prescribed
			if not alreadyPrescribed then
				-- add the observers normalized composite weight to the cumulative weight
				cumulativeNormalizedCompositeWeight = cumulativeNormalizedCompositeWeight
					+ observer.normalizedCompositeWeight
				-- if the random value is less than the cumulative weight, we have found our observer
				if random <= cumulativeNormalizedCompositeWeight then
					prescribedObserversLookup[observer.observerAddress] = observer.gatewayAddress
					break
				end
			end
		end
		-- hash the hash to get a new hash
		local newHash = crypto.utils.stream.fromArray(hash)
		hash = crypto.digest.sha2_256(newHash).asBytes()
	end
	-- return the prescribed observers and the weighted observers
	return prescribedObserversLookup, weightedGateways
end

--- Gets the epoch timestamps for an epoch index
--- @param epochIndex number The epoch index
--- @return number, number, number # 	The epoch start timestamp, epoch end timestamp, and epoch distribution timestamp
function epochs.getEpochTimestampsForIndex(epochIndex)
	local epochStartTimestamp = epochs.getSettings().epochZeroStartTimestamp
		+ epochs.getSettings().durationMs * epochIndex
	local epochEndTimestamp = epochStartTimestamp + epochs.getSettings().durationMs
	local epochDistributionTimestamp = epochEndTimestamp + epochs.getSettings().distributionDelayMs
	return epochStartTimestamp, epochEndTimestamp, epochDistributionTimestamp
end

--- Gets the epoch index for a given timestamp
--- @param timestamp number The timestamp
--- @return number # 	The epoch index
function epochs.getEpochIndexForTimestamp(timestamp)
	local timestampInMS = utils.checkAndConvertTimestampToMs(timestamp)
	local epochZeroStartTimestamp = epochs.getSettings().epochZeroStartTimestamp
	local epochLengthMs = epochs.getSettings().durationMs
	local epochIndex = math.floor((timestampInMS - epochZeroStartTimestamp) / epochLengthMs)
	return epochIndex
end

--- Creates a new epoch and updates the gateway weights
--- @param timestamp number The timestamp in milliseconds
--- @param blockHeight number The block height
--- @param hashchain string The hashchain
--- @return Epoch|nil # The created epoch, or nil if an epoch already exists for the index
function epochs.createEpoch(timestamp, blockHeight, hashchain)
	assert(type(timestamp) == "number", "Timestamp must be a number")
	assert(type(blockHeight) == "number", "Block height must be a number")
	assert(type(hashchain) == "string", "Hashchain must be a string")

	local epochIndex = epochs.getEpochIndexForTimestamp(timestamp)
	if next(epochs.getEpoch(epochIndex)) then
		-- silently return
		print("Epoch already exists for index: " .. epochIndex)
		return
	end

	local prevEpochIndex = epochIndex - 1
	local prevEpoch = epochs.getEpoch(prevEpochIndex)
	-- if the previous epoch is not the genesis epoch and we have not distributed rewards, we cannot create a new epoch
	if
		prevEpochIndex > 0 -- only validate distributions occurred if previous epoch is not the genesis epoch
		and (
			prevEpoch.distributions == nil
			or prevEpoch.distributions.distributedTimestamp == nil
			or timestamp < prevEpoch.distributions.distributedTimestamp
		)
	then
		-- silently return
		print(
			"Distributions have not occurred for the previous epoch. A new epoch will not be created until those are complete: "
				.. prevEpochIndex
		)
		return
	end

	local epochStartTimestamp, epochEndTimestamp, epochDistributionTimestamp =
		epochs.getEpochTimestampsForIndex(epochIndex)
	local prescribedObservers, weightedGateways = epochs.computePrescribedObserversForEpoch(epochIndex, hashchain)
	local prescribedNames = epochs.computePrescribedNamesForEpoch(epochIndex, hashchain)
	local activeGateways = gar.getActiveGatewaysBeforeTimestamp(epochStartTimestamp)
	-- get the max rewards for each participant eligible for the epoch
	local eligibleEpochRewards = epochs.computeTotalEligibleRewardsForEpoch(epochIndex, prescribedObservers)
	-- create the epoch
	local epoch = {
		epochIndex = epochIndex,
		startTimestamp = epochStartTimestamp,
		endTimestamp = epochEndTimestamp,
		startHeight = blockHeight,
		distributionTimestamp = epochDistributionTimestamp,
		prescribedObservers = prescribedObservers,
		prescribedNames = prescribedNames,
		observations = {
			failureSummaries = {},
			reports = {},
		},
		distributions = {
			totalEligibleGateways = utils.lengthOfTable(activeGateways),
			totalEligibleRewards = eligibleEpochRewards.totalEligibleRewards,
			totalEligibleGatewayReward = eligibleEpochRewards.perGatewayReward,
			totalEligibleObserverReward = eligibleEpochRewards.perObserverReward,
			rewards = {
				eligible = eligibleEpochRewards.potentialRewards,
			},
		},
	}
	Epochs[epochIndex] = epoch
	-- update the gateway weights
	if weightedGateways then
		for _, weightedGateway in ipairs(weightedGateways) do
			gar.updateGatewayWeights(weightedGateway)
		end
	end

	-- Force schedule a pruning JIC
	NextEpochsPruneTimestamp = NextEpochsPruneTimestamp or 0

	return epoch
end

--- Saves the observations for an epoch
--- @param observerAddress string The observer address
--- @param reportTxId string The report transaction ID
--- @param failedGatewayAddresses string[] The failed gateway addresses
--- @param timestamp number The timestamp
--- @return Observations # The updated observations for the epoch
function epochs.saveObservations(observerAddress, reportTxId, failedGatewayAddresses, timestamp)
	-- Note: one of the only places we use arweave addresses, as the protocol requires the report to be stored on arweave. This would be a significant change to OIP if changed.
	assert(utils.isValidArweaveAddress(reportTxId), "Report transaction ID is not a valid address")
	assert(utils.isValidAddress(observerAddress, true), "Observer address is not a valid address") -- allow unsafe addresses for observer address
	assert(type(failedGatewayAddresses) == "table", "Failed gateway addresses is required")
	for _, address in ipairs(failedGatewayAddresses) do
		assert(utils.isValidAddress(address, true), "Failed gateway address is not a valid address") -- allow unsafe addresses for failed gateway addresses
	end
	assert(type(timestamp) == "number", "Timestamp is required")

	local epochIndex = epochs.getEpochIndexForTimestamp(timestamp)
	local epochStartTimestamp, _, epochDistributionTimestamp = epochs.getEpochTimestampsForIndex(epochIndex)

	-- avoid observations before the previous epoch distribution has occurred, as distributions affect weights of the current epoch
	assert(
		timestamp >= epochStartTimestamp + epochs.getSettings().distributionDelayMs,
		"Observations for the current epoch cannot be submitted before: " .. epochDistributionTimestamp
	)

	local prescribedObserversLookup = epochs.getPrescribedObserversForEpoch(epochIndex)
	assert(utils.lengthOfTable(prescribedObserversLookup) > 0, "No prescribed observers for the current epoch.")

	local gatewayAddressForObserver = prescribedObserversLookup[observerAddress]
	assert(gatewayAddressForObserver, "Caller is not a prescribed observer for the current epoch.")

	local observingGateway = gar.getGateway(gatewayAddressForObserver)
	assert(observingGateway, "The associated gateway not found in the registry.")

	local epoch = epochs.getEpoch(epochIndex)

	-- check if this is the first report filed in this epoch
	if epoch.observations == nil then
		epoch.observations = {
			failureSummaries = {},
			reports = {},
		}
	end

	-- use ipairs as failedGatewayAddresses is an array
	for _, failedGatewayAddress in ipairs(failedGatewayAddresses) do
		local gateway = gar.getGateway(failedGatewayAddress)

		if gateway then
			local gatewayPresentDuringEpoch = gar.isGatewayActiveBeforeTimestamp(epochStartTimestamp, gateway)
			if gatewayPresentDuringEpoch then
				-- if there are none, create an array
				if epoch.observations.failureSummaries == nil then
					epoch.observations.failureSummaries = {}
				end
				-- Get the existing set of failed gateways for this observer
				local observersMarkedFailed = epoch.observations.failureSummaries[failedGatewayAddress] or {}

				-- if list of observers who marked failed does not continue current observer than add it
				local alreadyObservedIndex = utils.findInArray(observersMarkedFailed, function(address)
					return address == observingGateway.observerAddress
				end)

				if not alreadyObservedIndex then
					table.insert(observersMarkedFailed, observingGateway.observerAddress)
				end

				epoch.observations.failureSummaries[failedGatewayAddress] = observersMarkedFailed
			end
		end
	end

	-- if reports are not already present, create an array
	if epoch.observations.reports == nil then
		epoch.observations.reports = {}
	end

	epoch.observations.reports[observingGateway.observerAddress] = reportTxId
	-- update the epoch
	Epochs[epochIndex] = epoch
	return epoch.observations
end

--- @class ComputedRewards
--- @field totalEligibleRewards number The total eligible rewards
--- @field perGatewayReward number The per gateway reward
--- @field perObserverReward number The per observer reward
--- @field potentialRewards table<string, GatewayRewards> The potential rewards for each gateway

--- Computes the total eligible rewards for an epoch based on the protocol balance and the reward percentage and prescribed observers
--- @param epochIndex number The epoch index
--- @param prescribedObserversLookup table<WalletAddress, WalletAddress> The prescribed observers for the epoch
--- @return ComputedRewards # The total eligible rewards
function epochs.computeTotalEligibleRewardsForEpoch(epochIndex, prescribedObserversLookup)
	local epochStartTimestamp = epochs.getEpochTimestampsForIndex(epochIndex)
	local activeGatewayAddresses = gar.getActiveGatewaysBeforeTimestamp(epochStartTimestamp)
	local protocolBalance = balances.getBalance(ao.id)
	local rewardRate = epochs.getRewardRateForEpoch(epochIndex)
	local totalEligibleRewards = math.floor(protocolBalance * rewardRate)
	local eligibleGatewayReward = #activeGatewayAddresses > 0
			and math.floor(totalEligibleRewards * constants.gatewayOperatorRewardRatio / #activeGatewayAddresses)
		or 0
	local eligibleObserverReward = utils.lengthOfTable(prescribedObserversLookup) > 0
			and math.floor(
				totalEligibleRewards * constants.observerRewardRatio / utils.lengthOfTable(prescribedObserversLookup)
			)
		or 0
	-- compute for each gateway what their potential rewards are and for their delegates
	local potentialRewards = {}
	-- use ipairs as activeGatewayAddresses is an array
	for _, gatewayAddress in ipairs(activeGatewayAddresses) do
		local gateway = gar.getGateway(gatewayAddress)
		if gateway ~= nil then
			local potentialReward = eligibleGatewayReward -- start with the gateway reward
			-- it it is a prescribed observer for the epoch, it is eligible for the observer reward
			if prescribedObserversLookup[gateway.observerAddress] then
				potentialReward = potentialReward + eligibleObserverReward -- add observer reward if it is a prescribed observer
			end
			-- if any delegates are present, distribute the rewards to the delegates
			local eligibleDelegateRewards = gateway.totalDelegatedStake > 0
					and math.floor(potentialReward * (gateway.settings.delegateRewardShareRatio / 100))
				or 0
			-- set the potential reward for the gateway
			local eligibleOperatorRewards = potentialReward - eligibleDelegateRewards
			local eligibleRewardsForGateway = {
				operatorReward = eligibleOperatorRewards,
				delegateRewards = {},
			}
			-- use pairs as gateway.delegates is map
			for delegateAddress, delegate in pairs(gateway.delegates) do
				if gateway.totalDelegatedStake > 0 then
					local delegateReward =
						math.floor((delegate.delegatedStake / gateway.totalDelegatedStake) * eligibleDelegateRewards)
					if delegateReward > 0 then
						eligibleRewardsForGateway.delegateRewards[delegateAddress] = delegateReward
					end
				end
			end
			-- set the potential rewards for the gateway
			potentialRewards[gatewayAddress] = eligibleRewardsForGateway
		end
	end
	return {
		totalEligibleRewards = totalEligibleRewards,
		perGatewayReward = eligibleGatewayReward,
		perObserverReward = eligibleObserverReward,
		potentialRewards = potentialRewards,
	}
end
--- Distributes the rewards for an epoch
--- 1. Get gateways participated in full epoch based on start and end timestamp
--- 2. Get the prescribed observers for the relevant epoch
--- 3. Calculate the rewards for the epoch based on protocol balance
--- 4. Allocate 95% of the rewards for passed gateways, 5% for observers - based on total gateways during the epoch and # of prescribed observers
--- 5. Distribute the rewards to the gateways and observers
--- 6. Increment the epoch stats for the gateways
--- @param currentTimestamp number The current timestamp
--- @return Epoch|nil # The updated epoch with the distributed rewards, or nil if no rewards were distributed
function epochs.distributeRewardsForEpoch(currentTimestamp)
	local epochIndex = epochs.getEpochIndexForTimestamp(currentTimestamp - epochs.getSettings().durationMs) -- go back to previous epoch
	local epoch = epochs.getEpoch(epochIndex)
	if not next(epoch) then
		-- silently return
		print("Not distributing rewards for last epoch.")
		return
	end

	if currentTimestamp < epoch.distributionTimestamp then
		-- silently ignore - Distribution can only occur after the epoch has ended
		print("Distribution can only occur after the epoch has ended")
		return
	end

	-- check if already distributed rewards for epoch
	if epoch.distributions.distributedTimestamp then
		print("Rewards already distributed for epoch: " .. epochIndex)
		return -- silently return
	end

	local eligibleGatewaysForEpoch = epochs.getEligibleRewardsForEpoch(epochIndex)
	local prescribedObserversLookup = epochs.getPrescribedObserversForEpoch(epochIndex)
	local totalObservationsSubmitted = utils.lengthOfTable(epoch.observations.reports) or 0

	-- get the eligible rewards for the epoch
	local totalEligibleObserverReward = epoch.distributions.totalEligibleObserverReward
	local totalEligibleGatewayReward = epoch.distributions.totalEligibleGatewayReward
	--- @type table<string, number>
	local distributed = {}
	for gatewayAddress, totalEligibleRewardsForGateway in pairs(eligibleGatewaysForEpoch) do
		local gateway = gar.getGateway(gatewayAddress)
		-- only distribute rewards if the gateway is found and not leaving
		if gateway and totalEligibleRewardsForGateway and gateway.status ~= "leaving" then
			-- check the observations to see if gateway passed, if 50% or more of the observers marked the gateway as failed, it is considered failed
			local observersMarkedFailed = epoch.observations.failureSummaries
					and epoch.observations.failureSummaries[gatewayAddress]
				or {}
			local failed = #observersMarkedFailed > (totalObservationsSubmitted / 2) -- more than 50% of observations submitted marked gateway as failed

			-- if prescribed, we'll update the prescribed stats as well - find if the observer address is in prescribed observers
			local isPrescribed = prescribedObserversLookup[gateway.observerAddress]

			local observationSubmitted = isPrescribed and epoch.observations.reports[gateway.observerAddress] ~= nil

			local updatedStats = {
				totalEpochCount = gateway.stats.totalEpochCount + 1,
				failedEpochCount = failed and gateway.stats.failedEpochCount + 1 or gateway.stats.failedEpochCount,
				failedConsecutiveEpochs = failed and gateway.stats.failedConsecutiveEpochs + 1 or 0,
				passedConsecutiveEpochs = failed and 0 or gateway.stats.passedConsecutiveEpochs + 1,
				passedEpochCount = failed and gateway.stats.passedEpochCount or gateway.stats.passedEpochCount + 1,
				prescribedEpochCount = isPrescribed and gateway.stats.prescribedEpochCount + 1
					or gateway.stats.prescribedEpochCount,
				observedEpochCount = observationSubmitted and gateway.stats.observedEpochCount + 1
					or gateway.stats.observedEpochCount,
			}

			-- update the gateway stats, returns the updated gateway
			gateway = gar.updateGatewayStats(gatewayAddress, gateway, updatedStats)

			-- Scenarios
			-- 1. Gateway passed and was prescribed and submitted an observation - it gets full gateway reward
			-- 2. Gateway passed and was prescribed and did not submit an observation - it gets only the gateway reward, docked by 25%
			-- 2. Gateway passed and was not prescribed -- it gets full operator reward
			-- 3. Gateway failed and was prescribed and did not submit observation -- it gets no reward
			-- 3. Gateway failed and was prescribed and did submit observation -- it gets the observer reward
			-- 4. Gateway failed and was not prescribed -- it gets no reward
			local earnedRewardForGatewayAndDelegates = 0
			if not failed then
				if isPrescribed then
					if observationSubmitted then
						-- 1. gateway passed and was prescribed and submitted an observation - it gets full reward
						earnedRewardForGatewayAndDelegates =
							math.floor(totalEligibleGatewayReward + totalEligibleObserverReward)
					else
						-- 2. gateway passed and was prescribed and did not submit an observation - it gets only the gateway reward, docked by 25%
						earnedRewardForGatewayAndDelegates = math.floor(totalEligibleGatewayReward * 0.75)
					end
				else
					-- 3. gateway passed and was not prescribed -- it gets full gateway reward
					earnedRewardForGatewayAndDelegates = math.floor(totalEligibleGatewayReward)
				end
			else
				if isPrescribed then
					if observationSubmitted then
						-- 3. gateway failed and was prescribed and did submit an observation -- it gets the observer reward
						earnedRewardForGatewayAndDelegates = math.floor(totalEligibleObserverReward)
					end
				end
			end

			local totalEligibleRewardsForGatewayAndDelegates = totalEligibleRewardsForGateway.operatorReward
				+ utils.sumTableValues(totalEligibleRewardsForGateway.delegateRewards)

			if earnedRewardForGatewayAndDelegates > 0 and totalEligibleRewardsForGatewayAndDelegates > 0 then
				local percentOfEligibleEarned = earnedRewardForGatewayAndDelegates
					/ totalEligibleRewardsForGatewayAndDelegates -- percent of what was earned vs what was eligible
				-- optimally this is 1, but if the gateway did not do what it was supposed to do, it will be less than 1 and thus all payouts will be less
				local totalDistributedToDelegates = 0
				local totalRewardsForMissingDelegates = 0
				-- distribute all the predetermined rewards to the delegates
				for delegateAddress, eligibleDelegateReward in pairs(totalEligibleRewardsForGateway.delegateRewards) do
					local actualDelegateReward = math.floor(eligibleDelegateReward * percentOfEligibleEarned)
					-- distribute the rewards to the delegate if greater than 0 and the delegate still exists on the gateway and has a stake greater than 0
					if actualDelegateReward > 0 then
						if gar.isDelegateEligibleForDistributions(gateway, delegateAddress) then
							-- increase the stake and decrease the protocol balance, returns the updated gateway
							gateway = gar.increaseExistingDelegateStake(
								gatewayAddress,
								gateway,
								delegateAddress,
								actualDelegateReward
							)
							balances.reduceBalance(ao.id, actualDelegateReward)
							-- update the distributed rewards for the delegate
							distributed[delegateAddress] = (distributed[delegateAddress] or 0) + actualDelegateReward
							totalDistributedToDelegates = totalDistributedToDelegates + actualDelegateReward
						else
							totalRewardsForMissingDelegates = totalRewardsForMissingDelegates + actualDelegateReward
						end
					end
				end
				-- transfer the remaining rewards to the gateway
				local actualOperatorReward = math.floor(
					earnedRewardForGatewayAndDelegates - totalDistributedToDelegates - totalRewardsForMissingDelegates
				)
				if actualOperatorReward > 0 then
					-- distribute the rewards to the gateway
					balances.transfer(gatewayAddress, ao.id, actualOperatorReward)
					-- move that balance to the gateway if auto-staking is on
					if gateway.settings.autoStake then
						-- only increase stake if the gateway is joined, otherwise it is leaving and cannot accept additional stake so distribute rewards to the operator directly
						gar.increaseOperatorStake(gatewayAddress, actualOperatorReward)
					end
				end
				-- update the distributed rewards for the gateway
				distributed[gatewayAddress] = (distributed[gatewayAddress] or 0) + actualOperatorReward
			end
		end
	end

	-- get the total distributed rewards for the epoch
	local totalDistributedForEpoch = utils.sumTableValues(distributed)

	-- set the distributions for the epoch
	epoch.distributions.totalDistributedRewards = totalDistributedForEpoch
	epoch.distributions.distributedTimestamp = currentTimestamp
	epoch.distributions.rewards = epoch.distributions.rewards or {
		eligible = {},
	}
	epoch.distributions.rewards.distributed = distributed

	-- update the epoch
	Epochs[epochIndex] = epoch
	return epochs.getEpoch(epochIndex)
end

--- Prunes epochs older than the cutoff epoch index
--- @param timestamp number The timestamp to prune epochs older than
--- @return Epoch[] # The pruned epochs
function epochs.pruneEpochs(timestamp)
	local prunedEpochIndexes = {}
	if not NextEpochsPruneTimestamp or timestamp < NextEpochsPruneTimestamp then
		-- No known pruning work to do
		return prunedEpochIndexes
	end

	--- Reset the next pruning timestamp
	NextEpochsPruneTimestamp = nil
	local currentEpochIndex = epochs.getEpochIndexForTimestamp(timestamp)
	local cutoffEpochIndex = currentEpochIndex - epochs.getSettings().pruneEpochsCount
	local unsafeEpochs = epochs.getEpochsUnsafe()
	local nextEpochIndex = next(unsafeEpochs)
	while nextEpochIndex do
		if nextEpochIndex <= cutoffEpochIndex then
			table.insert(prunedEpochIndexes, nextEpochIndex)
			-- Safe to assign to nil during next() iteration
			Epochs[nextEpochIndex] = nil
		else
			local _, endTimestamp = epochs.getEpochTimestampsForIndex(nextEpochIndex)
			if endTimestamp >= timestamp then
				NextEpochsPruneTimestamp = math.min(NextEpochsPruneTimestamp or endTimestamp, endTimestamp)
			end
		end
		nextEpochIndex = next(unsafeEpochs, nextEpochIndex)
	end
	return prunedEpochIndexes
end

function epochs.nextEpochsPruneTimestamp()
	return NextEpochsPruneTimestamp
end

---@param epochIndex number
---@returns number
function epochs.getRewardRateForEpoch(epochIndex)
	if epochIndex <= constants.rewardDecayStartEpoch then
		return constants.minimumRewardRate
	elseif epochIndex <= constants.rewardDecayLastEpoch then
		local totalDecayPeriod = (constants.rewardDecayLastEpoch - constants.rewardDecayStartEpoch) + 1
		local epochsAlreadyDecayed = (epochIndex - constants.rewardDecayStartEpoch)
		local decayRatePerEpoch = (constants.maximumRewardRate - constants.minimumRewardRate) / totalDecayPeriod
		return constants.maximumRewardRate - (decayRatePerEpoch * epochsAlreadyDecayed)
	else
		return constants.minimumRewardRate
	end
end

return epochs
