local gar = require("gar")
local crypto = require("crypto.init")
local utils = require("utils")
local balances = require("balances")
local arns = require("arns")
local epochs = {}

Epochs = Epochs or {}
EpochSettings = EpochSettings
	or {
		prescribedNameCount = 5,
		rewardPercentage = 0.0005, -- 0.05%
		maxObservers = 50,
		epochZeroStartTimestamp = 1719900000000, -- July 9th, 00:00:00 UTC
		durationMs = 60 * 1000 * 60 * 24, -- 24 hours
		distributionDelayMs = 60 * 1000 * 30, -- 15 blocks / 30 minutes
	}

function epochs.getEpochs()
	local epochs = utils.deepCopy(Epochs) or {}
	return epochs
end

function epochs.getEpoch(epochIndex)
	local epoch = utils.deepCopy(Epochs[epochIndex]) or {}
	return epoch
end

function epochs.getObservers()
	return epochs.getCurrentEpoch().prescribedObservers or {}
end

function epochs.getSettings()
	return utils.deepCopy(EpochSettings)
end

function epochs.getObservations()
	return epochs.getCurrentEpoch().observations or {}
end

function epochs.getReports()
	return epochs.getObservations().reports or {}
end

function epochs.getDistribution()
	return epochs.getCurrentEpoch().distributions or {}
end

function epochs.getPrescribedObserversForEpoch(epochIndex)
	return epochs.getEpoch(epochIndex).prescribedObservers or {}
end

function epochs.getEligibleRewardsForEpoch(epochIndex)
	return epochs.getEpoch(epochIndex).distributions.rewards.eligible or {}
end

function epochs.getDistributedRewardsForEpoch(epochIndex)
	return epochs.getEpoch(epochIndex).distributions.rewards.distributed or {}
end

function epochs.getObservationsForEpoch(epochIndex)
	return epochs.getEpoch(epochIndex).observations or {}
end

function epochs.getDistributionsForEpoch(epochIndex)
	return epochs.getEpoch(epochIndex).distributions or {}
end

function epochs.getPrescribedNamesForEpoch(epochIndex)
	return epochs.getEpoch(epochIndex).prescribedNames or {}
end

function epochs.getReportsForEpoch(epochIndex)
	return epochs.getEpoch(epochIndex).observations.reports or {}
end

function epochs.getDistributionForEpoch(epochIndex)
	return epochs.getEpoch(epochIndex).distributions or {}
end

function epochs.getEpochFromTimestamp(timestamp)
	local epochIndex = epochs.getEpochIndexForTimestamp(timestamp)
	return epochs.getEpoch(epochIndex)
end
function epochs.setPrescribedObserversForEpoch(epochIndex, hashchain)
	local prescribedObservers = epochs.computePrescribedObserversForEpoch(epochIndex, hashchain)
	local epoch = epochs.getEpoch(epochIndex)
	-- assign the prescribed observers and update the epoch
	epoch.prescribedObservers = prescribedObservers
	Epochs[epochIndex] = epoch
end

function epochs.setPrescribedNamesForEpoch(epochIndex, hashchain)
	local prescribedNames = epochs.computePrescribedNamesForEpoch(epochIndex, hashchain)
	local epoch = epochs.getEpoch(epochIndex)
	-- assign the prescribed names and update the epoch
	epoch.prescribedNames = prescribedNames
	Epochs[epochIndex] = epoch
end

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

	if #activeArNSNames < epochs.getSettings().prescribedNameCount then
		return activeArNSNames
	end

	local epochHash = utils.getHashFromBase64URL(hashchain)
	local prescribedNames = {}
	local hash = epochHash
	while #prescribedNames < epochs.getSettings().prescribedNameCount do
		local hashString = crypto.utils.array.toString(hash)
		local random = crypto.random(nil, nil, hashString) % #activeArNSNames

		for i = 0, #activeArNSNames do
			local index = (random + i) % #activeArNSNames
			local alreadyPrescribed = utils.findInArray(prescribedNames, function(name)
				return name == activeArNSNames[index]
			end)
			if not alreadyPrescribed then
				table.insert(prescribedNames, activeArNSNames[index])
				break
			end
		end

		-- hash the hash to get a new hash
		local newHash = crypto.utils.stream.fromArray(hash)
		hash = crypto.digest.sha2_256(newHash).asBytes()
	end

	-- sort them by name
	table.sort(prescribedNames, function(a, b)
		return a < b
	end)
	return prescribedNames
end

function epochs.computePrescribedObserversForEpoch(epochIndex, hashchain)
	assert(epochIndex >= 0, "Epoch index must be greater than or equal to 0")
	assert(type(hashchain) == "string", "Hashchain must be a string")

	local epochStartTimestamp, epochEndTimestamp = epochs.getEpochTimestampsForIndex(epochIndex)
	local activeGatewayAddresses = gar.getActiveGatewaysBetweenTimestamps(epochStartTimestamp, epochEndTimestamp)
	local weightedGateways = gar.getGatewayWeightsAtTimestamp(activeGatewayAddresses, epochStartTimestamp)

	-- Filter out any observers that could have a normalized composite weight of 0
	local filteredObservers = {}
	-- use ipairs as weightedObservers in array
	for _, observer in ipairs(weightedGateways) do
		if observer.normalizedCompositeWeight > 0 then
			table.insert(filteredObservers, observer)
		end
	end
	if #filteredObservers <= epochs.getSettings().maxObservers then
		return filteredObservers, weightedGateways
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
	local prescribedObserversAddresses = {}
	while #prescribedObserversAddresses < epochs.getSettings().maxObservers do
		local hashString = crypto.utils.array.toString(hash)
		local random = crypto.random(nil, nil, hashString) / 0xffffffff
		local cumulativeNormalizedCompositeWeight = 0
		for i = 1, #filteredObservers do
			local observer = filteredObservers[i]
			local alreadyPrescribed = utils.findInArray(prescribedObserversAddresses, function(address)
				return address == observer.gatewayAddress
			end)

			-- add only if observer has not already been prescribed
			if not alreadyPrescribed then
				-- add the observers normalized composite weight to the cumulative weight
				cumulativeNormalizedCompositeWeight = cumulativeNormalizedCompositeWeight
					+ observer.normalizedCompositeWeight
				-- if the random value is less than the cumulative weight, we have found our observer
				if random <= cumulativeNormalizedCompositeWeight then
					table.insert(prescribedObserversAddresses, observer.gatewayAddress)
					break
				end
			end
		end
		-- hash the hash to get a new hash
		local newHash = crypto.utils.stream.fromArray(hash)
		hash = crypto.digest.sha2_256(newHash).asBytes()
	end
	local prescribedObservers = {}
	-- use ipairs as prescribedObserversAddresses is an array
	for _, address in ipairs(prescribedObserversAddresses) do
		local index = utils.findInArray(filteredObservers, function(observer)
			return observer.gatewayAddress == address
		end)
		table.insert(prescribedObservers, filteredObservers[index])
		table.sort(prescribedObservers, function(a, b)
			return a.normalizedCompositeWeight > b.normalizedCompositeWeight
		end)
	end

	-- sort them in place
	table.sort(prescribedObservers, function(a, b)
		return a.normalizedCompositeWeight > b.normalizedCompositeWeight -- sort by descending weight
	end)

	-- return the prescribed observers and the weighted observers
	return prescribedObservers, weightedGateways
end

function epochs.getEpochTimestampsForIndex(epochIndex)
	local epochStartTimestamp = epochs.getSettings().epochZeroStartTimestamp
		+ epochs.getSettings().durationMs * epochIndex
	local epochEndTimestamp = epochStartTimestamp + epochs.getSettings().durationMs
	local epochDistributionTimestamp = epochEndTimestamp + epochs.getSettings().distributionDelayMs
	return epochStartTimestamp, epochEndTimestamp, epochDistributionTimestamp
end

function epochs.getEpochIndexForTimestamp(timestamp)
	local timestampInMS = utils.checkAndConvertTimestamptoMs(timestamp)
	local epochZeroStartTimestamp = epochs.getSettings().epochZeroStartTimestamp
	local epochLengthMs = epochs.getSettings().durationMs
	local epochIndex = math.floor((timestampInMS - epochZeroStartTimestamp) / epochLengthMs)
	return epochIndex
end

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

	-- TODO: we may not want to create the epoch until after rewards are distributed and weights are updated
	local prevEpochIndex = epochIndex - 1
	local prevEpoch = epochs.getEpoch(prevEpochIndex)
	if prevEpochIndex >= 0 and timestamp < prevEpoch.distributions.distributedTimestamp then
		-- silently return
		print(
			"Distributions have not occured for the previous epoch. A new epoch will not be created until those are complete: "
				.. prevEpochIndex
		)
		return
	end

	local epochStartTimestamp, epochEndTimestamp, epochDistributionTimestamp =
		epochs.getEpochTimestampsForIndex(epochIndex)
	local prescribedObservers, weightedGateways = epochs.computePrescribedObserversForEpoch(epochIndex, hashchain)
	local prescribedNames = epochs.computePrescribedNamesForEpoch(epochIndex, hashchain)
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
	return epoch
end

function epochs.saveObservations(observerAddress, reportTxId, failedGatewayAddresses, timestamp)
	-- assert report tx id is valid arweave address
	assert(utils.isValidArweaveAddress(reportTxId), "Report transaction ID is not a valid Arweave address")
	-- assert observer address is valid arweave address
	assert(utils.isValidArweaveAddress(observerAddress), "Observer address is not a valid Arweave address")
	assert(type(failedGatewayAddresses) == "table", "Failed gateway addresses is required")
	-- assert each address in failedGatewayAddresses is a valid arweave address
	for _, address in ipairs(failedGatewayAddresses) do
		assert(utils.isValidArweaveAddress(address), "Failed gateway address is not a valid Arweave address")
	end
	assert(type(timestamp) == "number", "Timestamp is required")

	local epochIndex = epochs.getEpochIndexForTimestamp(timestamp)
	local epochStartTimestamp, epochEndTimestamp, epochDistributionTimestamp =
		epochs.getEpochTimestampsForIndex(epochIndex)

	-- avoid observations before the previous epoch distribution has occurred, as distributions affect weights of the current epoch
	if timestamp < epochStartTimestamp + epochs.getSettings().distributionDelayMs then
		error("Observations for the current epoch cannot be submitted before: " .. epochDistributionTimestamp)
	end

	local prescribedObservers = epochs.getPrescribedObserversForEpoch(epochIndex)
	if #prescribedObservers == 0 then
		error("No prescribed observers for the current epoch.")
	end

	local observerIndex = utils.findInArray(prescribedObservers, function(prescribedObserver)
		return prescribedObserver.observerAddress == observerAddress
	end)

	local observer = prescribedObservers[observerIndex]

	if observer == nil then
		error("Caller is not a prescribed observer for the current epoch.")
	end

	local observingGateway = gar.getGateway(observer.gatewayAddress)
	if observingGateway == nil then
		error("The associated gateway does not exist in the registry.")
	end

	local epoch = epochs.getEpoch(epochIndex)

	-- check if this is the first report filed in this epoch (TODO: use start or end?)
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
			local gatewayPresentDuringEpoch =
				gar.isGatewayActiveBetweenTimestamps(epochStartTimestamp, epochEndTimestamp, gateway)
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

-- for testing purposes
function epochs.updateEpochSettings(newSettings)
	EpochSettings = newSettings
end

function epochs.computeTotalEligibleRewardsForEpoch(epochIndex, prescribedObservers)
	local epochStartTimestamp, epochEndTimestamp = epochs.getEpochTimestampsForIndex(epochIndex)
	local activeGatewayAddresses = gar.getActiveGatewaysBetweenTimestamps(epochStartTimestamp, epochEndTimestamp)
	local totalEligibleRewards = math.floor(balances.getBalance(ao.id) * epochs.getSettings().rewardPercentage)
	local eligibleGatewayReward = math.floor(totalEligibleRewards * 0.90 / #activeGatewayAddresses) -- TODO: make these setting variables
	local eligibleObserverReward = math.floor(totalEligibleRewards * 0.10 / #prescribedObservers) -- TODO: make these setting variables
	-- compute for each gateway what their potential rewards are and for their delegates
	local potentialRewards = {}
	-- use ipairs as activeGatewayAddresses is an array
	for _, gatewayAddress in ipairs(activeGatewayAddresses) do
		local gateway = gar.getGateway(gatewayAddress)
		if gateway ~= nil then
			local potentialReward = eligibleGatewayReward -- start with the gateway reward
			-- it it is a prescribed observer for the epoch, it is eligible for the observer reward
			local observerIndex = utils.findInArray(prescribedObservers, function(prescribedObserver)
				return prescribedObserver.observerAddress == gateway.observerAddress
			end)
			if observerIndex then
				potentialReward = potentialReward + eligibleObserverReward -- add observer reward if it is a prescribed observer
			end
			-- if any delegates are present, distribute the rewards to the delegates
			local eligbibleDelegateRewards =
				math.floor(potentialReward * (gateway.settings.delegateRewardShareRatio / 100))
			-- set the potential reward for the gateway
			local eligibleOperatorRewards = potentialReward - eligbibleDelegateRewards
			local eligibleRewardsForGateway = {
				operatorReward = eligibleOperatorRewards,
				delegateRewards = {},
			}
			-- use pairs as gateway.delegates is map
			for delegateAddress, delegate in pairs(gateway.delegates) do
				if gateway.totalDelegatedStake > 0 then
					local delegateReward =
						math.floor((delegate.delegatedStake / gateway.totalDelegatedStake) * eligbibleDelegateRewards)
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
-- Steps
-- 1. Get gateways participated in full epoch based on start and end timestamp
-- 2. Get the prescribed observers for the relevant epoch
-- 3. Calcualte the rewards for the epoch based on protocol balance
-- 4. Allocate 95% of the rewards for passed gateways, 5% for observers - based on total gateways during the epoch and # of prescribed observers
-- 5. Distribute the rewards to the gateways and observers
-- 6. Increment the epoch stats for the gateways
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

	-- TODO: look at the potential rewards recorded in the epoch and compare against the behavior of the gateway
	-- check if already distributed rewards for epoch
	if epoch.distributions.distributedTimestamp then
		print("Rewards already distributed for epoch: " .. epochIndex)
		return -- silently return
	end

	-- NOTE: these should match what was computed at the beginning of the epoch - use that instead of this
	local activeGatewayAddresses = epochs.getEligibleRewardsForEpoch(epochIndex)
	local prescribedObservers = epochs.getPrescribedObserversForEpoch(epochIndex)
	local totalObservationsSubmitted = utils.lengthOfTable(epoch.observations.reports) or 0

	-- get the eligible rewards for the epoch
	local totalElgibleObserverReward = epoch.distributions.totalEligibleObserverReward
	local totalEligibleGatewayReward = epoch.distributions.totalEligibleGatewayReward
	local distributed = {}
	local totalDistributed = 0
	for gatewayAddress, totalEligibleRewardsForGateway in pairs(activeGatewayAddresses) do
		local gateway = gar.getGateway(gatewayAddress)
		-- only operate if the gateway is found (it should be )
		if gateway and totalEligibleRewardsForGateway then
			-- check the observations to see if gateway passed, if 50% or more of the observers marked the gateway as failed, it is considered failed
			local observersMarkedFailed = epoch.observations.failureSummaries
					and epoch.observations.failureSummaries[gatewayAddress]
				or {}
			local failed = #observersMarkedFailed > (totalObservationsSubmitted / 2) -- more than 50% of observerations submitted marked gateway as failed

			-- if prescribed, we'll update the prescribed stats as well - find if the observer address is in prescribed observers
			local observerIndex = utils.findInArray(prescribedObservers, function(prescribedObserver)
				return prescribedObserver.observerAddress == gateway.observerAddress
			end)

			local observationSubmitted = observerIndex and epoch.observations.reports[gateway.observerAddress] ~= nil

			local updatedStats = {
				totalEpochCount = gateway.stats.totalEpochCount + 1,
				failedEpochCount = failed and gateway.stats.failedEpochCount + 1 or gateway.stats.failedEpochCount,
				failedConsecutiveEpochs = failed and gateway.stats.failedConsecutiveEpochs + 1 or 0,
				passedConsecutiveEpochs = failed and 0 or gateway.stats.passedConsecutiveEpochs + 1,
				passedEpochCount = failed and gateway.stats.passedEpochCount or gateway.stats.passedEpochCount + 1,
				prescribedEpochCount = observerIndex and gateway.stats.prescribedEpochCount + 1
					or gateway.stats.prescribedEpochCount,
				observedEpochCount = observationSubmitted and gateway.stats.observedEpochCount + 1
					or gateway.stats.observedEpochCount,
			}

			-- update the gateway stats
			gar.updateGatewayStats(gatewayAddress, updatedStats)

			-- scenarioes
			-- 1. Gateway passed and was prescribed and submittied an observation - it gets full gateway reward
			-- 2. Gateway passed and was prescribed and did not submit an observation - it gets only the gateway reward, docked by 25%
			-- 2. Gateway passed and was not prescribed -- it gets full operator reward
			-- 3. Gateway failed and was prescribed and did not submit observation -- it gets no reward
			-- 3. Gateway failed and was prescribed and did submit observation -- it gets the observer reward
			-- 4. Gateway failed and was not prescribed -- it gets no reward
			local earnedRewardForGatewayAndDelegates = 0
			if not failed then
				if observerIndex then
					if observationSubmitted then
						-- 1. gateway passed and was prescribed and submittied an observation - it gets full reward
						earnedRewardForGatewayAndDelegates = totalEligibleGatewayReward + totalElgibleObserverReward
					else
						-- 2. gateway passed and was prescribed and did not submit an observation - it gets only the gateway reward, docked by 25%
						earnedRewardForGatewayAndDelegates = math.floor(totalEligibleGatewayReward * 0.75)
					end
				else
					-- 3. gateway passed and was not prescribed -- it gets full gateway reward
					earnedRewardForGatewayAndDelegates = totalEligibleGatewayReward
				end
			else
				if observerIndex then
					if observationSubmitted then
						-- 3. gateway failed and was prescribed and did submit an observation -- it gets the observer reward
						earnedRewardForGatewayAndDelegates = totalElgibleObserverReward
					end
				end
			end

			if earnedRewardForGatewayAndDelegates > 0 then
				local percentOfEligibleEarned = earnedRewardForGatewayAndDelegates
					/ totalEligibleRewardsForGateway.operatorReward
				-- optimally this is 1, but if the gateway did not do what it was supposed to do, it will be less than 1 and thus all payouts will be less
				local totalDistributedToDelegates = 0
				-- distribute all the predetermined rewards to the delegates
				for delegateAddress, eligibleDelegateReward in pairs(totalEligibleRewardsForGateway.delegateRewards) do
					local actualDelegateReward = math.floor(eligibleDelegateReward * percentOfEligibleEarned)
					-- distribute the rewards to the delegate
					balances.transfer(delegateAddress, ao.id, actualDelegateReward)
					-- increment the total distributed
					totalDistributed = math.floor(totalDistributed + actualDelegateReward)
					-- update the distributed rewards for the delegate
					distributed[delegateAddress] = (distributed[delegateAddress] or 0) + actualDelegateReward
					-- increment the total distributed for the epoch
					totalDistributedToDelegates = totalDistributedToDelegates + actualDelegateReward
				end
				-- transfer the remaining rewards to the gateway
				local actualOperatorReward = earnedRewardForGatewayAndDelegates - totalDistributedToDelegates
				-- distribute the rewards to the gateway
				balances.transfer(gatewayAddress, ao.id, actualOperatorReward)
				-- update the distributed rewards for the gateway
				distributed[gatewayAddress] = (distributed[gatewayAddress] or 0) + actualOperatorReward
				-- increment the total distributed for the epoch
				totalDistributed = math.floor(totalDistributed + actualOperatorReward)
			else
				-- if the gateway did not earn any rewards, we still need to update the distributed rewards
				distributed[gatewayAddress] = 0
			end
		end
	end

	-- set the distributions for the epoch
	epoch.distributions.totalDistributedRewards = totalDistributed
	epoch.distributions.distributedTimestamp = currentTimestamp
	epoch.distributions.rewards.distributed = distributed

	-- update the epoch
	Epochs[epochIndex] = epoch
end

return epochs
