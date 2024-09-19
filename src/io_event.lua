local AOEvent = require "ao_event"

-- Convenience factory function for prepopulating analytic and msg fields into AOEvents
local function IOEvent(msg, initialData)
  local event = AOEvent({
    Cron = msg.Cron or false,
    Cast = msg.Cast or false,
  })
  event.addFieldsIfExist(msg, {"From", "Timestamp", "Action"})
  if initialData ~= nil then
   event:addFields(initialData)
  end
  return event
end

return IOEvent