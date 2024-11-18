local Auction = {}

-- Default Auction Settings
--- @type AuctionSettings
AuctionSettings = {
	durationMs = 60 * 1000 * 60 * 24 * 14, -- 14 days in milliseconds
	decayRate = 0.000000000016847809193121693, -- 0.02037911 / durationMs
	scalingExponent = 190, -- steepness of the curve
	startPriceMultiplier = 50, -- multiplier for the starting price
}

--- @class AuctionSettings
--- @field durationMs number The duration of the auction in milliseconds
--- @field decayRate number The decay rate for the auction
--- @field scalingExponent number The scaling exponent for the auction
--- @field startPriceMultiplier number The start price multiplier for the auction

--- Represents an Auction.
--- @class Auction
--- @field name string The name of the auction
--- @field demandFactor number The demand factor for pricing
--- @field baseFee number The base fee for the auction
--- @field initiator string The address of the initiator of the auction
--- @field settings AuctionSettings The settings for the auction
--- @field startTimestamp number The starting timestamp for the auction
--- @field endTimestamp function Computes the ending timestamp for the auction
--- @field registrationFeeCalculator function Function to calculate registration fee
--- @field computePricesForAuction function Function to compute prices for the auction
--- @field getPriceForAuctionAtTimestamp function Function to get the price for the auction at a given timestamp
--- @field startPrice function Function to get the start price for the auction
--- @field floorPrice function Function to get the floor price for the auction

--- Creates a new Auction instance
--- @param name string The name of the auction
--- @param startTimestamp number The starting timestamp for the auction
--- @param demandFactor number The demand factor for pricing
--- @param baseFee number The base fee for the auction
--- @param initiator string The address of the initiator of the auction
--- @param registrationFeeCalculator function Function to calculate registration fee that supports type, baseFee, years, demandFactor
--- @return Auction The new Auction instance
function Auction:new(name, startTimestamp, demandFactor, baseFee, initiator, registrationFeeCalculator)
	local auction = {
		name = name,
		initiator = initiator,
		startTimestamp = startTimestamp,
		registrationFeeCalculator = registrationFeeCalculator,
		baseFee = baseFee,
		demandFactor = demandFactor,
		settings = {
			durationMs = AuctionSettings.durationMs,
			decayRate = AuctionSettings.decayRate,
			scalingExponent = AuctionSettings.scalingExponent,
			startPriceMultiplier = AuctionSettings.startPriceMultiplier,
		},
	}
	setmetatable(auction, self)
	self.__index = self
	return auction
end

--- Computes the prices for the auction.
--- @param type string The type of auction
--- @param years number The number of years for calculation
--- @param intervalMs number The interval in milliseconds, must be at least 15 minutes
--- @return table A table of prices indexed by timestamp
function Auction:computePricesForAuction(type, years, intervalMs)
	local prices = {}
	for i = self.startTimestamp, Auction.endTimestampForAuction(self), intervalMs do
		local priceAtTimestamp = self:getPriceForAuctionAtTimestamp(i, type, years)
		prices[i] = priceAtTimestamp
	end
	return prices
end

--- Returns the current price for the auction at a given timestamp
--- @param timestamp number The timestamp to get the price for
--- @param type string The type of auction
--- @param years number The number of years for the auction
--- @return number The current price for the auction at the given timestamp
function Auction:getPriceForAuctionAtTimestamp(timestamp, type, years)
	local startPrice = self:startPrice(type, years)
	local floorPrice = self:floorPrice(type, years)
	local timeSinceStart = timestamp - self.startTimestamp
	local totalDecaySinceStart = self.settings.decayRate * timeSinceStart
	local currentPrice = math.floor(startPrice * ((1 - totalDecaySinceStart) ^ self.settings.scalingExponent))
	return math.max(currentPrice, floorPrice)
end

--- Returns the start price for the auction
--- @param type string The type of auction
--- @param years number The number of years for the auction
--- @return number The start price for the auction
function Auction:startPrice(type, years)
	return self:floorPrice(type, years) * self.settings.startPriceMultiplier
end

--- Returns the floor price for the auction
--- @param type string The type of auction
--- @param years number The number of years for the auction
--- @return number The floor price for the auction
function Auction:floorPrice(type, years)
	return self.registrationFeeCalculator(type, self.baseFee, years, self.demandFactor)
end

--- @param auction Auction
function Auction.endTimestampForAuction(auction)
	return auction.startTimestamp + auction.settings.durationMs
end

return Auction
