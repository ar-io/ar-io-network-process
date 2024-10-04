local utils = require("utils")
local json = require("json")

-- Factory function for creating an "AOEvent"
local function AOEvent(initialData)
	local event = {
		sampleRate = nil, -- Optional sample rate
	}

	if type(initialData) ~= "table" then
		print("ERROR: AOEvent data must be a table.")
		event.data = {}
	else
		event.data = initialData
	end

	local function isValidTableValueType(table)
		local valueType = type(value)
		return valueType == "string" or valueType == "number" or valueType == "boolean" or value == nil
	end

	local function isValidType(value)
		local valueType = type(value)
		if isValidTableValueType(value) then
			return true
		elseif valueType == "table" then
			-- Prevent nested tables
			for _, v in pairs(value) do
				if not isValidTableValueType(v) then
					return false
				end
			end
			return true
		end
		return false
	end

	function event:addField(key, value)
		if type(key) ~= "string" then
			print("ERROR: Field key must be a string.")
			return self
		end
		if not isValidType(value) then
			print(
				"ERROR: Invalid field value type: "
					.. type(value)
					.. ". Supported types are string, number, boolean, or nil."
			)
			return self
		end
		self.data[utils.toTrainCase(key)] = value
		return self
	end

	function event:addFields(fields)
		if type(fields) ~= "table" then
			print("ERROR: Fields must be provided as a table.")
			return self
		end
		for key, value in pairs(fields) do
			self:addField(key, value)
		end
		return self
	end

	function event:addFieldsIfExist(table, fields)
		if type(table) ~= "table" then
			print("ERROR: Fields must be provided as a table.")
			return self
		end
		for _, key in pairs(fields) do
			if table[key] then
				self:addField(key, table[key])
			end
		end
		return self
	end

	function event:addFieldsWithPrefixIfExist(srcTable, prefix, fields)
		if type(srcTable) ~= "table" or type(fields) ~= "table" then
			print("ERROR: table and fields must be provided as a table.")
			return self
		end
		for _, key in pairs(fields) do
			if srcTable[key] ~= nil then
				self:addField(prefix .. key, srcTable[key])
			end
		end
		return self
	end

	-- Helper function to escape JSON control characters in strings
	local function escapeString(s)
		-- Escape backslashes first
		s = string.gsub(s, "\\", "\\\\")
		-- Escape double quotes
		s = string.gsub(s, '"', '\\"')
		-- Escape other control characters (optional for full JSON compliance)
		s = string.gsub(s, "\n", "\\n")
		s = string.gsub(s, "\r", "\\r")
		s = string.gsub(s, "\t", "\\t")
		return s
	end

	function event:printEvent()
		-- The _e: 1 flag signifies that this is an event. Ensure it is set.
		self.data["_e"] = 1
		print(json.encode(self.data))
	end

	return event
end

-- Return the AOEvent function to make it accessible from other files
return AOEvent
