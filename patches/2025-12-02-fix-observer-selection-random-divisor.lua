--[[
	Fixes a bug in observer selection where the random divisor was incorrect.

	The crypto.random function returns values in [0, 2^31-1], but we were dividing
	by 0xffffffff (2^32-1), which meant the random value could never exceed ~0.5.
	This biased selection toward observers at the front of the sorted list.

	This patch updates epochs.computePrescribedObserversForEpoch to divide by
	(2^31-1) instead, producing properly distributed random values in [0, 1].

	Reviewers: Dylan, Ariel, Atticus
]]
--

local epochs = require(".src.epochs")
local gar = require(".src.gar")
local utils = require(".src.utils")
local crypto = require(".crypto.init")

--- Computes the prescribed observers for an epoch
--- @param epochIndex number The epoch index
--- @param hashchain string The hashchain
--- @return table<WalletAddress, WalletAddress>, WeightedGateway[] # The prescribed observers for the epoch, and all the gateways with weights
function epochs.computePrescribedObserversForEpoch(epochIndex, hashchain)
	assert(epochIndex >= 0, "Epoch index must be greater than or equal to 0")
	assert(type(hashchain) == "string", "Hashchain must be a string")

	local epochStartTimestamp = epochs.getEpochTimestampsForIndex(epochIndex)
	local activeGatewayAddresses = gar.getActiveGatewayAddressesBeforeTimestamp(epochStartTimestamp)
	local weightedGateways = gar.getGatewayWeightsAtTimestamp(activeGatewayAddresses, epochStartTimestamp)

	-- Filter out any observers that could have a normalized composite weight of 0
	local filteredObservers = {}
	local prescribedObserversLookup = {}
	-- use ipairs as weightedObservers in array
	for _, observer in ipairs(weightedGateways) do
		-- for the first epoch, we need to include all observers as there are no weights yet
		if epochIndex == 0 or observer.normalizedCompositeWeight > 0 then
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
		-- crypto.random returns values in [0, 2^31-1], so divide by max to get [0, 1]
		local random = crypto.random(nil, nil, hashString) / (2 ^ 31 - 1)
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
