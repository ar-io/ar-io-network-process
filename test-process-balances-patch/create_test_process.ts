import fs from 'fs';
import path from 'path';
import { connect, createDataItemSigner } from '@permaweb/aoconnect';

const __dirname = path.dirname(new URL(import.meta.url).pathname);

// This is the _actual_ module id, but its a 16gb memory and not supported on legacynet
const moduleId = 'CWxzoe4IoNpFHiykadZWphZtLWybDF8ocNi7gmK6zCg';
// this is a module id that is supported on legacy net from around the same time.
//const moduleId = 'cbn0KKrBZH7hdNkNokuXLtGryrWM--PjSTBqIzw9Kkk';
const jwk = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'test-wallet.json'), 'utf8'),
);
const authority = 'fcoN_xJeisVsPXA-trzVAuIiqO3ydLQxM-L4XbrQKzY';
const scheduler = '_GQ33BkPtZrqxA84vM8Zk-N2aO0toNNu_C-l-rawrBA';
const signer = createDataItemSigner(jwk);
const ao = connect({
  CU_URL: 'https://cu.ardrive.io',
});

const arioLua = fs.readFileSync(
  path.join(__dirname, '../dist/aos-bundled.lua'),
  'utf8',
);
const balancesLua = fs.readFileSync(
  path.join(__dirname, 'balances.lua'),
  'utf8',
);
const balances2Lua = fs.readFileSync(
  path.join(__dirname, 'balances_2.lua'),
  'utf8',
);
const patchHbLua = `
  ${balancesLua}\n
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

`;

fs.writeFileSync(path.join(__dirname, 'test-process.lua'), patchHbLua);

const processId = await ao.spawn({
  module: moduleId,
  scheduler,
  tags: [
    { name: 'Authority', value: authority },
    { name: 'Name', value: 'ARIO_HB_TEST_BALANCES_PATCH' },
    { name: 'Device', value: 'process@1.0' },
    { name: 'Execution-Device', value: 'genesis-wasm@1.0' },
    { name: 'Scheduler-Device', value: 'scheduler@1.0' },
  ],
  signer,
});

const loadArioId = await ao.message({
  process: processId,
  data: arioLua,
  tags: [{ name: 'Action', value: 'Eval' }],
  signer,
});

const loadCodeId = await ao.message({
  process: processId,
  data: patchHbLua,
  tags: [{ name: 'Action', value: 'Eval' }],
  signer,
});

const patchBalancesId = await ao.message({
  process: processId,
  data: ' ',
  tags: [{ name: 'Action', value: 'Patch-Hyperbeam-Balances' }],
  signer,
});

const initBalances2Id = await ao.message({
  process: processId,
  data: balances2Lua,
  tags: [{ name: 'Action', value: 'Eval' }],
  signer,
});

const patchBalances2Id = await ao.message({
  process: processId,
  data: ' ',
  tags: [{ name: 'Action', value: 'Patch-Hyperbeam-Balances' }],
  signer,
});

fs.writeFileSync(
  path.join(__dirname, 'test-process.json'),
  JSON.stringify(
    {
      processId,
      authority,
      scheduler,
      loadCodeId,
      patchBalancesId,
      timestamp: Date.now(),
    },
    null,
    2,
  ),
);

console.log(
  `Test process created: ${JSON.stringify(
    {
      processId,
      authority,
      scheduler,
      loadCodeId,
      patchBalancesId,
      timestamp: Date.now(),
    },
    null,
    2,
  )}`,
);
