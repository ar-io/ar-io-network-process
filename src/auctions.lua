local Auction = {}

--- Represents an Auction.
--- @class Auction
--- @field name string The name of the auction
--- @field decayRate number The decay rate for price calculation
--- @field scalingExponent number The scaling exponent for price calculation
--- @field demandFactor number The demand factor for pricing
--- @field durationMs number The duration of the auction in milliseconds
--- @field initiator string The address of the initiator of the auction
--- @field baseFee number The base fee for the auction
--- @field startTimestamp number The starting timestamp for the auction
--- @field endTimestamp number The ending timestamp for the auction
--- @field startPriceMultiplier number The multiplier for the starting price
--- @field registrationFeeCalculator function Function to calculate registration fee

--- Creates a new Auction instance
--- @param name string The name of the auction
--- @param startTimestamp number The starting timestamp for the auction
--- @param durationMs number The duration of the auction in milliseconds
--- @param decayRate number The decay rate for price calculation
--- @param scalingExponent number The scaling exponent for price calculation
--- @param demandFactor number The demand factor for pricing
--- @param baseFee number The base fee for the auction
--- @param initiator string The address of the initiator of the auction
--- @param startPriceMultiplier number The multiplier for the starting price
--- @param registrationFeeCalculator function Function to calculate registration fee that supports type, baseFee, years, demandFactor
--- @return Auction The new Auction instance
function Auction:new(
	name,
	startTimestamp,
	durationMs,
	decayRate,
	scalingExponent,
	demandFactor,
	baseFee,
	initiator,
	startPriceMultiplier,
	registrationFeeCalculator
)
	local auction = {
		name = name,
		decayRate = decayRate,
		scalingExponent = scalingExponent,
		demandFactor = demandFactor,
		durationMs = durationMs,
		initiator = initiator,
		baseFee = baseFee,
		startTimestamp = startTimestamp,
		endTimestamp = startTimestamp + (durationMs or 14 * 24 * 60 * 60 * 1000),
		startPriceMultiplier = startPriceMultiplier or 50,
		registrationFeeCalculator = registrationFeeCalculator,
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
	for i = self.startTimestamp, self.endTimestamp, intervalMs do
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
	local startPrice = self.registrationFeeCalculator(type, self.baseFee, years, self.demandFactor)
		* self.startPriceMultiplier
	local timeSinceStart = timestamp - self.startTimestamp
	local totalDecaySinceStart = self.decayRate * timeSinceStart
	local currentPrice = math.floor(startPrice * ((1 - totalDecaySinceStart) ^ self.scalingExponent))
	return currentPrice
end

return Auction
