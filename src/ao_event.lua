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

  local function isValidType(value)
    local valueType = type(value)
    return valueType == "string" or valueType == "number" or valueType == "boolean" or value == nil
  end

  function event:addField(key, value)
    if type(key) ~= "string" then
      print("ERROR: Field key must be a string.")
      return self
    end
    if not isValidType(value) then
      print("ERROR: Invalid field value type: " .. type(value) .. ". Supported types are string, number, boolean, or nil.")
      return self
    end
    self.data[key] = value
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
      if(table[key]) then
        self:addField(key, table[key])
      end
    end
    return self
  end

  -- Helper function to escape JSON control characters in strings
  local function escapeString(s)
    -- Escape backslashes first
    s = string.gsub(s, '\\', '\\\\')
    -- Escape double quotes
    s = string.gsub(s, '"', '\\"')
    -- Escape other control characters (optional for full JSON compliance)
    s = string.gsub(s, '\n', '\\n')
    s = string.gsub(s, '\r', '\\r')
    s = string.gsub(s, '\t', '\\t')
    return s
  end

  function event:printEvent()
    local serializedData = "{"

    -- The _e: 1 flag signifies that this is an event
    serializedData = serializedData .. '"_e": 1, '

    -- Serialize event data
    for key, value in pairs(self.data) do
      local serializedValue

      if type(value) == "string" then
        serializedValue = '"' .. escapeString(value) .. '"'
      elseif type(value) == "number" or type(value) == "boolean" then
        serializedValue = tostring(value)
      elseif value == nil then
        serializedValue = "null"
      else
        print("ERROR: Unsupported data type: " .. type(value))
        goto printNextValue
      end

      serializedData = serializedData .. '"' .. key .. '": ' .. serializedValue .. ', '
      ::printNextValue::
    end

    -- Remove trailing comma and space, if any
    if string.sub(serializedData, -2) == ", " then
      serializedData = string.sub(serializedData, 1, -3)
    end

    serializedData = serializedData .. "}"

    print(serializedData)
  end

  return event
end

-- Return the AOEvent function to make it accessible from other files
return AOEvent
