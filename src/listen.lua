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
	-- If the table already has a listener, replace it
	local existingMeta = getmetatable(targetTable)
	if existingMeta and existingMeta.__listener then
		-- Already has a listener metatable, just replace the callback
		existingMeta.__listener = callback
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

	-- Store original metamethods if they exist
	local originalIndex = existingMeta and existingMeta.__index
	local originalNewIndex = existingMeta and existingMeta.__newindex
	local originalPairs = existingMeta and existingMeta.__pairs
	local originalLen = existingMeta and existingMeta.__len

	local meta = {
		__index = function(t, key)
			return actualData[key]
		end,
		__newindex = function(t, key, value)
			local oldValue = actualData[key]
			-- Set the new value
			actualData[key] = value
			-- Call the listener from the metatable (not the closure)
			local listener = getmetatable(t).__listener
			if listener then
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
		-- Store metadata for later access
		__listener = callback,
		__actualData = actualData,
		__originalMeta = {
			__index = originalIndex,
			__newindex = originalNewIndex,
			__pairs = originalPairs,
			__len = originalLen,
		},
	}

	local proxy = setmetatable({}, meta)

	return proxy
end

--- Remove the listener from a table and restore original metamethods
--- @param wrappedTable table The wrapped table
--- @return table The unwrapped table with original data and metamethods
function listen.removeListener(wrappedTable)
	local meta = getmetatable(wrappedTable)
	if not meta or not meta.__actualData then
		-- Not a wrapped table, return as-is
		return wrappedTable
	end

	-- Get the actual data
	local actualData = meta.__actualData
	local originalMeta = meta.__originalMeta

	-- Restore original metatable if it existed
	if
		originalMeta and (originalMeta.__index or originalMeta.__newindex or originalMeta.__pairs or originalMeta.__len)
	then
		-- Build a new metatable with original metamethods
		local restoredMeta = {}
		if originalMeta.__index then
			restoredMeta.__index = originalMeta.__index
		end
		if originalMeta.__newindex then
			restoredMeta.__newindex = originalMeta.__newindex
		end
		if originalMeta.__pairs then
			restoredMeta.__pairs = originalMeta.__pairs
		end
		if originalMeta.__len then
			restoredMeta.__len = originalMeta.__len
		end

		setmetatable(actualData, restoredMeta)
	else
		-- No original metatable, clear it
		setmetatable(actualData, nil)
	end

	return actualData
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
