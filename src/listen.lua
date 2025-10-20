--- @class ListenerContext
--- @field key string|number The key being modified
--- @field value any The new value being set
--- @field oldValue any The previous value (nil if key didn't exist)
--- @field table table The table being modified

local listen = {}

--- Add a listener to a table that gets called whenever a property changes
--- @param targetTable table The table to observe
--- @param callback fun(ctx: ListenerContext) Function called on each change
--- @return table The wrapped table (use this instead of original)
function listen.addListener(targetTable, callback)
	-- If the table already has a metatable with listeners, add to existing
	local existingMeta = getmetatable(targetTable)
	if existingMeta and existingMeta.__listeners then
		table.insert(existingMeta.__listeners, callback)
		return targetTable
	end

	--[[
		Store the actual data separately to ensure __newindex always fires.
		
		WHY USE A PROXY?
		In Lua, __newindex is ONLY called when the key doesn't exist in the table.
		This means:
		- Updating existing keys wouldn't trigger __newindex
		- Deletions (setting to nil) wouldn't trigger __newindex for existing keys
		
		By keeping the proxy empty and storing data separately, __newindex fires
		for ALL writes (creates, updates, and deletions), giving complete tracking.
	]]
	local actualData = {}
	for k, v in pairs(targetTable) do
		actualData[k] = v
	end

	-- Create new metatable with listener support
	local listeners = { callback }

	local proxy = setmetatable({}, {
		__index = function(t, key)
			return actualData[key]
		end,
		__newindex = function(t, key, value)
			local oldValue = actualData[key]
			-- Set the new value
			actualData[key] = value

			-- Call all listeners
			for _, listener in ipairs(listeners) do
				listener({
					key = key,
					value = value,
					oldValue = oldValue,
					table = actualData,
				})
			end
		end,
		__pairs = function(t)
			return pairs(actualData)
		end,
		__len = function(t)
			return #actualData
		end,
		__listeners = listeners,
		__actualData = actualData,
	})

	return proxy
end

--- Remove all listeners from a table
--- @param wrappedTable table The wrapped table
function listen.removeAllListeners(wrappedTable)
	local meta = getmetatable(wrappedTable)
	if meta and meta.__listeners then
		-- Clear the table instead of replacing it (preserves closure references)
		for k in pairs(meta.__listeners) do
			meta.__listeners[k] = nil
		end
	end
end

--- Get the actual data from a wrapped table (bypassing the proxy)
--- @param wrappedTable table The wrapped table
--- @return table The actual data table
function listen.getActualData(wrappedTable)
	local meta = getmetatable(wrappedTable)
	if meta and meta.__actualData then
		return meta.__actualData
	end
	return wrappedTable
end

return listen
