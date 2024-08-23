local utils = require("utils")
local json = require("json")
local ao = require("ao")

-- create index pool class that accepts parameters for the index pool
local IndexPool = {}
local paritionModuleId = "example-tx-id"
local defaultFilter = '{ "tags": [{ "name": "App-Name", "value": "ArDrive"}]}'
IndexPool = IndexPool or {} -- essentially, self here

-- TODO: this global state of pools will exist in the registry, but use it here to simulate how to manage pools or where to callback to the registry
RegistryIndexPools = RegistryIndexPools or {}
RegistryBalances = RegistryBalances or {}

--#
Handlers.add("createPool", utils.hasMatchingTag("Action", "Create-Index-Pool"), function(msg)
	-- TODO: do some checks on the filter or parameters provided
	local pool = IndexPool:new(msg.From, msg.Id, defaultFilter, paritionModuleId)
	-- create the partitions for the pool (this is essentially a bunch of coroutnes, so likely not want to do it on instantiation of the pool)
	pool:createPartitions(tonumber(msg["Block-Height"]))
	IndexPool = pool
	-- TODO: add the pool to the global state (replace with callback to registry?)
	RegistryIndexPools[pool.id] = pool

	ao.send({
		Target = msg.From,
		Action = "Pool-Created",
		["Pool-Id"] = pool.id,
		Data = json.encode(pool),
	})
end)

Handlers.add("info", utils.hasMatchingTag("Action", "Info"), function(msg)
	ao.send({
		Target = msg.From,
		Action = "Info-Notice",
		Data = "Hello",
	})
end)

Handlers.add("hello", utils.hasMatchingTag("Action", "Hello"), function(msg)
	print("Hello, world!")
	ao.send({
		Target = msg.From,
		Action = "Hello-Notice",
		Data = "Hello, world!",
	})
end)

-- simulate the registry balance function here
Handlers.add("fundPool", utils.hasMatchingTag("Action", "Fund-Index-Pool"), function(msg)
	-- TODO: do some checks on the filter or parameters provided
	-- withdraw balance from registry balance and vault it in the fungs
	-- parse out the pool id, the quantity, the timestamp
	-- check the balance in registry balance
	local poolId = msg.Tags["Pool-Id"]
	local quantity = tonumber(msg.Tags.Quantity)
	local timestamp = tonumber(msg.Timestamp)

	-- Check if the pool exists
	if not RegistryIndexPools[poolId] then
		ao.send({
			Target = msg.From,
			Action = "Fund-Pool-Error",
			Error = "Pool-Not-Found",
			Data = "The specified pool does not exist.",
		})
		return
	end

	-- Check if the sender has sufficient balance
	if not RegistryBalances[msg.From] or RegistryBalances[msg.From] < quantity then
		ao.send({
			Target = msg.From,
			Action = "Fund-Pool-Error",
			Error = "Insufficient-Balance",
			Data = "You do not have sufficient balance to fund this amount.",
		})
		return
	end

	-- Withdraw the balance from the registry (assume this is then a credit-notice )
	RegistryBalances[msg.From] = RegistryBalances[msg.From] - quantity

	-- Add the funds to the pool
	local pool = RegistryIndexPools[poolId]
	if not pool.funds[msg.From] then
		pool.funds[msg.From] = {}
	end
	table.insert(pool.funds[msg.From], { amount = quantity, timestamp = timestamp })

	-- Send a credit notice to the pool process
	ao.send({
		Target = poolId,
		Action = "Credit-Notice",
		Sender = msg.From,
		Quantity = tostring(quantity),
		Timestamp = timestamp,
		Data = "Received " .. quantity .. " from " .. msg.From,
	})

	-- Send a confirmation to the sender
	ao.send({
		Target = msg.From,
		Action = "Fund-Pool-Success",
		["Pool-Id"] = poolId,
		Quantity = tostring(quantity),
		Data = "Successfully funded " .. quantity .. " to pool " .. poolId,
	})
end)

Handlers.add("creditNotice", utils.hasMatchingTag("Action", "Credit-Notice"), function(msg)
	-- add to the pool funds
	-- check that the sender is only the registry contract

	-- TODO: check that the sender is only the registry contract
	local quantity = tonumber(msg.Quantity)
	local funder = msg["Funder"] -- TODO: what tag do we forward from the registry
	local messageId = msg.Id
	IndexPool:addFunds(messageId, funder, quantity)
	-- send credit notice success back
	ao.send({
		Target = msg.From,
		Action = "Credit-Notice-Success",
		Data = "Successfully added " .. quantity .. " to the pool from " .. funder,
	})
end)

-- TODO: assume that an index pool is it's own process, this is a class representation of what that state of the process would like
local timestampComparator = function(a, b)
	return a.timestamp < b.timestamp
end
function IndexPool:new(initiator, id, config, partitionModuleId)
	local self = setmetatable({}, { __index = IndexPool })
	self.id = id
	self.initiator = initiator
	self.funds = PriorityDeque:new(timestampComparator) -- priority queue based on timestamp
	self.withdrawls = {}
	self.trustedProvers = {} -- unique list of wallets that have been trusted to provide fraud proofs for the index pool
	self.config = {
		filter = config.filter,
		-- TODO: block range handling somehwere in here
		partitionSize = config.partitionSize or 10000, -- number of blocks per partition
		targetSegmentSize = config.targetSegmentSize or 5000, -- number of ideal data items per parquet segment - this will be used to calaculate the potential bid returned to indexers based on how optimal their offered segments are
		maxAcceptableBid = config.maxAcceptableBid or 10, -- max amount of funds to allocate to a partition
		minProverCollateral = config.minProverCollateral or 10, -- number of tIO required for a prover collator to be active
		bidStakeRate = config.bidStakeRate or 0.1, -- amound per data item required to be staked for a bid
		-- epoch informaiton, in length and period
		epoch = config.epoch or {
			epochDurationMs = 86400000, -- one day in milliseconds
			bidPeriodMs = 7200000, -- two hours in milliseconds
			fraudProofPeriodMs = 7200000, -- two hours in milliseconds to submit a fraud proof - TODO: this may be
		},
		-- auto-accept the first bid received
		autoAcceptFirstBid = config.autoAcceptFirstBid or false,
	}
	self.partitions = {} -- as indexers request parittions to be me made, track all the epoch partitions here
	self.partitionModuleId = partitionModuleId or paritionModuleId
	-- other state we want to store for the pools
	return self
end

-- create distribution for index pool
function IndexPool:createPartitions(currentBlockHeight)
	-- distribute the funds to the partitions
	-- number of partitions to create up to the current block height
	local numPartitions = math.ceil(currentBlockHeight / self.config.partitionSize)
	-- Spawn processes and add their IDs to partition state
	for i = 1, numPartitions do
		-- find the funds necessary to fund the partition
		local requiredAllocatedFunds = self.config.maxAcceptableBid
		local totalAllocatedFunds = 0
		local allocatedFundObjs = PriorityDeque:new(timestampComparator)
		-- get those funds from our funds queue
		while totalAllocatedFunds < requiredAllocatedFunds do
			local fund = self.funds:dequeue()
			-- if the fund is more than enough, split it and update the existing fund and create a new one to refrence to the parittion
			local fundAmount = fund.quantity
			if fundAmount > requiredAllocatedFunds then
				local remainingFundAmount = fundAmount - requiredAllocatedFunds
				totalAllocatedFunds = totalAllocatedFunds + requiredAllocatedFunds
				-- update the fund quantity
				fund.quantity = remainingFundAmount
				self.funds:enqueue(fund)
				-- enqueue to the partitioned funds
				allocatedFundObjs:enqueue({
					timestamp = fund.timestamp,
					quantity = requiredAllocatedFunds,
					address = fund.sender,
					id = fund.id,
				})
			else
				allocatedFundObjs:enqueue(fund)
			end
		end
		-- TODO: on the creation of the partition we give it all these things to the partition, i.e. what it needs to accept bids and determine stakes
		local createdParition = {
			Id = "example-tx-id-" .. i,
			PartitionModuleId = self.partitionModuleId,
			IndexPoolId = self.id,
			Funds = allocatedFundObjs,
			TargetSegmentSize = self.config.targetSegmentSize,
			MaxAcceptableBid = self.config.maxAcceptableBid,
			MinProverCollateral = self.config.minProverCollateral,
			BidStakeRate = self.config.bidStakeRate,
			Epoch = self.config.epoch,
			AutoAcceptFirstBid = self.config.autoAcceptFirstBid,
			Filter = self.config.filter,
			BlockStart = i * self.config.partitionSize,
			BlockEnd = (i + 1) * self.config.partitionSize,
			TrustedProvers = self.trustedProvers,
			PartitionIndex = i,
		}
		-- TODO: spawn the partition process with the above data
		-- local txId = ao.spawn(ao.env.Module.Id, {}).receive() -- TODO: how do we protect against this just not returning or erroring
		self.partitions[i] = createdParition
	end
	print("Created " .. numPartitions .. " partitions")
end

function IndexPool:addFunds(id, sender, quantity, timestamp)
	-- add to the funds queue
	self.funds:enqueue({
		id,
		sender,
		quantity,
		timestamp,
	})
end

function IndexPool:initiateWithdraw(id, address, quantity)
	-- remove from the funds up to an amount equally the desired quantitty and add to withdraws
	local totalAvailable = 0
	local totalWithdrawn = 0
	local fundsToRemove = {}

	-- Iterate through the funds queue to find funds for the given address
	for i = 1, self.funds:size() do
		local fund = self.funds:dequeue()
		if fund.sender == address then
			totalAvailable = totalAvailable + fund.quantity
			table.insert(fundsToRemove, fund)

			if totalAvailable >= quantity then
				break
			end
		end
		self.funds:enqueue(fund)
	end

	-- If we have enough funds, process the withdrawal
	if totalAvailable >= quantity then
		totalWithdrawn = quantity
		local remainingToWithdraw = quantity

		-- Remove the used funds from the queue and add to withdrawals
		for _, fund in ipairs(fundsToRemove) do
			self.funds:remove(function(item)
				return item.id == fund.id
			end)

			local amountFromThisFund = math.min(remainingToWithdraw, fund.quantity)
			remainingToWithdraw = remainingToWithdraw - amountFromThisFund

			-- Add to withdrawals
			self.withdrawals[address] = (self.withdrawals[address] or 0) + amountFromThisFund

			-- If there's remaining balance in this fund, re-add it to the queue
			if fund.quantity > amountFromThisFund then
				self.funds:enqueue({
					id = fund.id,
					sender = fund.sender,
					quantity = fund.quantity - amountFromThisFund,
					timestamp = fund.timestamp,
				})
			end

			if remainingToWithdraw <= 0 then
				break
			end
		end
	else
		print("Insufficient funds for withdrawal")
	end
	return totalWithdrawn
end

-- distribute all the withdraws and reset withdraws object
function IndexPool:distributeWithdrawals()
	for address, withdrawQty in pairs(self.withdrawals) do
		-- TODO: send to registry balance
		RegistryBalances[address] = (RegistryBalances[address] or 0) + withdrawQty
	end

	-- Reset the withdrawals object after distribution
	self.withdrawals = {}
end

return IndexPool
