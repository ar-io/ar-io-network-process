--- Pads a number with leading zeros to 32 digits.
-- @lfunction padZero32
-- @tparam {number} num The number to pad
-- @treturn {string} The padded number as a string
local function padZero32(num)
	return string.format("%032d", num)
end

--- Checks if a key exists in a list.
-- @lfunction _includes
-- @tparam {table} list The list to check against
-- @treturn {function} A function that takes a key and returns true if the key exists in the list
local function _includes(list)
	return function(key)
		local exists = false
		for _, listKey in ipairs(list) do
			if key == listKey then
				exists = true
				break
			end
		end
		if not exists then
			return false
		end
		return true
	end
end

--- Checks if a table is an array.
-- @lfunction isArray
-- @tparam {table} table The table to check
-- @treturn {boolean} True if the table is an array, false otherwise
local function isArray(table)
	if type(table) == "table" then
		local maxIndex = 0
		for k, v in pairs(table) do
			if type(k) ~= "number" or k < 1 or math.floor(k) ~= k then
				return false -- If there's a non-integer key, it's not an array
			end
			maxIndex = math.max(maxIndex, k)
		end
		-- If the highest numeric index is equal to the number of elements, it's an array
		return maxIndex == #table
	end
	return false
end

if not ao.reference then
	ao.reference = 0
end

--- Sends a message.
-- @function send
-- @tparam {table} msg The message to send
ao.send = function(msg)
	assert(type(msg) == "table", "msg should be a table")
	ao.reference = ao.reference + 1
	local referenceString = tostring(ao.reference)

	local message = {
		Target = msg.Target,
		Data = msg.Data,
		Anchor = padZero32(ao.reference),
		Tags = {
			{ name = "Data-Protocol", value = "ao" },
			{ name = "Variant", value = "ao.TN.1" },
			{ name = "Type", value = "Message" },
			{ name = "Reference", value = referenceString },
		},
	}

	-- if custom tags in root move them to tags
	for k, v in pairs(msg) do
		if not _includes({ "Target", "Data", "Anchor", "Tags", "From" })(k) then
			table.insert(message.Tags, { name = k, value = v })
		end
	end

	if msg.Tags then
		if isArray(msg.Tags) then
			for _, o in ipairs(msg.Tags) do
				table.insert(message.Tags, o)
			end
		else
			for k, v in pairs(msg.Tags) do
				table.insert(message.Tags, { name = k, value = v })
			end
		end
	end

	-- If running in an environment without the AOS Handlers module, do not add
	-- the onReply and receive functions to the message.
	if not Handlers then
		return message
	end

	-- clone message info and add to outbox
	local extMessage = {}
	for k, v in pairs(message) do
		extMessage[k] = v
	end

	-- add message to outbox
	table.insert(ao.outbox.Messages, extMessage)

	-- add callback for onReply handler(s)
	message.onReply = function(...) -- Takes either (AddressThatWillReply, handler(s)) or (handler(s))
		local from, resolver
		if select("#", ...) == 2 then
			from = select(1, ...)
			resolver = select(2, ...)
		else
			from = message.Target
			resolver = select(1, ...)
		end

		-- Add a one-time callback that runs the user's (matching) resolver on reply
		Handlers.once({ From = from, ["X-Reference"] = referenceString }, resolver)
	end

	message.receive = function(...)
		local from = message.Target
		if select("#", ...) == 1 then
			from = select(1, ...)
		end
		return Handlers.receive({ From = from, ["X-Reference"] = referenceString })
	end

	return message
end

ao.send({ device = "patch@1.0", balances = { device = "trie@1.0" } })
