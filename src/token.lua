local token = {}
local constants = require("constants")
local balances = require("balances")
local gar = require("gar")
local vaults = require("vaults")

TotalSupply = TotalSupply or constants.totalTokenSupply
LastKnownCirculatingSupply = LastKnownCirculatingSupply or 0 -- total circulating supply (e.g. balances - protocol balance)
LastKnownLockedSupply = LastKnownLockedSupply or 0 -- total vault balance across all vaults
LastKnownStakedSupply = LastKnownStakedSupply or 0 -- total operator stake across all gateways
LastKnownDelegatedSupply = LastKnownDelegatedSupply or 0 -- total delegated stake across all gateways
LastKnownWithdrawSupply = LastKnownWithdrawSupply or 0 -- total withdraw supply across all gateways (gateways and delegates)

--- @return mIO # returns the last computed total supply, this is to avoid recomputing the total supply every time, and only when requested
function token.lastKnownTotalTokenSupply()
	return LastKnownCirculatingSupply
		+ LastKnownLockedSupply
		+ LastKnownStakedSupply
		+ LastKnownDelegatedSupply
		+ LastKnownWithdrawSupply
		+ Balances[Protocol]
end

--- @class TotalSupplyDetails
--- @field totalSupply number
--- @field circulatingSupply number
--- @field lockedSupply number
--- @field stakedSupply number
--- @field delegatedSupply number
--- @field withdrawSupply number
--- @field protocolBalance number

--- Crawls the state to compute the total supply and update the last known values
--- @return TotalSupplyDetails
function token.computeTotalSupply()
	-- add all the balances
	local totalSupply = 0
	local circulatingSupply = 0
	local lockedSupply = 0
	local stakedSupply = 0
	local delegatedSupply = 0
	local withdrawSupply = 0
	local protocolBalance = balances.getBalance(Protocol)
	local userBalances = balances.getBalances()

	-- tally circulating supply
	for _, balance in pairs(userBalances) do
		circulatingSupply = circulatingSupply + balance
	end
	circulatingSupply = circulatingSupply - protocolBalance
	totalSupply = totalSupply + protocolBalance + circulatingSupply

	-- tally supply stashed in gateways and delegates
	for _, gateway in pairs(gar.getGatewaysUnsafe()) do
		totalSupply = totalSupply + gateway.operatorStake + gateway.totalDelegatedStake
		stakedSupply = stakedSupply + gateway.operatorStake
		delegatedSupply = delegatedSupply + gateway.totalDelegatedStake
		for _, delegate in pairs(gateway.delegates) do
			-- tally delegates' vaults
			for _, vault in pairs(delegate.vaults) do
				totalSupply = totalSupply + vault.balance
				withdrawSupply = withdrawSupply + vault.balance
			end
		end
		-- tally gateway's own vaults
		for _, vault in pairs(gateway.vaults) do
			totalSupply = totalSupply + vault.balance
			withdrawSupply = withdrawSupply + vault.balance
		end
	end

	-- user vaults
	local userVaults = vaults.getVaults()
	for _, vaultsForAddress in pairs(userVaults) do
		-- they may have several vaults iterate through them
		for _, vault in pairs(vaultsForAddress) do
			totalSupply = totalSupply + vault.balance
			lockedSupply = lockedSupply + vault.balance
		end
	end

	LastKnownCirculatingSupply = circulatingSupply
	LastKnownLockedSupply = lockedSupply
	LastKnownStakedSupply = stakedSupply
	LastKnownDelegatedSupply = delegatedSupply
	LastKnownWithdrawSupply = withdrawSupply
	TotalSupply = totalSupply
	return {
		totalSupply = totalSupply,
		circulatingSupply = circulatingSupply,
		lockedSupply = lockedSupply,
		stakedSupply = stakedSupply,
		delegatedSupply = delegatedSupply,
		withdrawSupply = withdrawSupply,
		protocolBalance = protocolBalance,
	}
end

return token
