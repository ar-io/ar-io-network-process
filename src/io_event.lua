local AOEvent = require("ao_event")
local utils = require("utils")

-- Convenience factory function for prepopulating analytic and msg fields into AOEvents
local function IOEvent(msg, initialData)
	local event = AOEvent({
		Cron = msg.Cron or false,
		Cast = msg.Cast or false,
	})
	event:addFieldsIfExist(msg, { "From", "Timestamp", "Action" })
	event:addField("FromFormatted", utils.formatAddress(msg.From))
	if initialData ~= nil then
		event:addFields(initialData)
	end
	if msg.prunedRecords ~= nil then
		event:addField("PrunedRecords", table.concat(msg.prunedRecords, ";"))
		event:addField("PrunedRecordsCount", #msg.prunedRecords)
	end
	if msg.tickError ~= nil then
		event:addField("TickError", msg.tickError)
	end
	return event
end

return IOEvent
