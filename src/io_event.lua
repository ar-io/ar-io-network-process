local AOEvent = require("ao_event")
local utils = require("utils")

-- TODO: RENAME TO ARIOEvent
-- Convenience factory function for prepopulating analytic and msg fields into AOEvents
local function IOEvent(msg, initialData)
	local event = AOEvent({
		Cron = msg.Cron or false,
		Cast = msg.Cast or false,
	})
	event:addFields(msg.Tags or {})
	event:addFieldsIfExist(msg, { "From", "Timestamp", "Action" })
	event:addField("Message-Id", msg.Id)
	event:addField("From-Formatted", utils.formatAddress(msg.From))
	if initialData ~= nil then
		event:addFields(initialData)
	end
	return event
end

return IOEvent
