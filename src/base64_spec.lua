local base64 = require("base64")

describe("base64", function()
	describe("decode", function()
		describe("with the default base64 decoder", function()
			it("should decode a standard base64 string without padding", function()
				local input = "SGVsbG8gV29ybGQh" -- "Hello World!" in Base64
				local expected = "Hello World!"
				local result = base64.decode(input)
				assert.are.equal(expected, result)
			end)

			it("should decode a standard base64 string with single padding", function()
				local input = "U29mdHdhcmU=" -- "Software" in Base64
				local expected = "Software"
				local result = base64.decode(input)
				assert.are.equal(expected, result)
			end)

			it("should decode a standard base64 string with double padding", function()
				local input = "QQ==" -- "A" in Base64
				local expected = "A"
				local result = base64.decode(input)
				assert.are.equal(expected, result)
			end)

			it("should decode using a custom decoder", function()
				local customDecoder = {}
				for i = 0, 25 do
					customDecoder[string.byte("A") + i] = i
					customDecoder[string.byte("a") + i] = 26 + i
				end
				for i = 0, 9 do
					customDecoder[string.byte("0") + i] = 52 + i
				end
				customDecoder[string.byte("-")] = 62
				customDecoder[string.byte("_")] = 63 -- Custom Base64 URL-safe alphabet

				local input = "SGVsbG8gV29ybGQh"
				local expected = "Hello World!"
				local result = base64.decode(input, customDecoder, false)
				assert.are.equal(expected, result)
			end)

			it("should handle invalid characters by stripping them out", function()
				local input = "SGVsbG8g@@#%V29ybGQh" -- Invalid characters mixed in
				local expected = "Hello World!"
				local result = base64.decode(input)
				assert.are.equal(expected, result)
			end)

			it("should work correctly with caching enabled", function()
				local input = "SGVsbG8gV29ybGQh" -- "Hello World!"
				local expected = "Hello World!"
				local resultWithCaching = base64.decode(input, nil, true)
				local resultWithoutCaching = base64.decode(input)
				assert.are.equal(expected, resultWithCaching)
				assert.are.equal(resultWithCaching, resultWithoutCaching)
			end)

			it("should decode a long base64 string efficiently with caching", function()
				local input = ("SGVsbG8g"):rep(1000) -- "Hello " repeated 1000 times
				local expected = ("Hello "):rep(1000)
				local result = base64.decode(input, nil, true)
				assert.are.equal(expected, result)
			end)

			it("should handle an empty string input", function()
				local input = ""
				local expected = ""
				local result = base64.decode(input)
				assert.are.equal(expected, result)
			end)

			it("should handle invalid Base64 padding gracefully", function()
				local input = "SGVsbG8g===" -- Invalid triple padding
				local expected = "Hello " -- Trims invalid padding and decodes valid part
				local result = base64.decode(input)
				assert.are.equal(expected, result)
			end)

			it("should handle invalid '=' characters mid-string by stopping at invalid segments", function()
				local input = "SGVsb=G8gV29ybGQh" -- Invalid '=' mid-string
				local expected = "Hel" -- Stops decoding at the invalid segment
				local result = base64.decode(input)
				assert.are.equal(expected, result)
			end)

			it("should handle trailing invalid characters gracefully", function()
				local input = "SGVsbG8g@"
				local expected = "Hello " -- Stops decoding at invalid character
				local result = base64.decode(input)
				assert.are.equal(expected, result)
			end)

			it("should handle Base64 strings without padding", function()
				local input = "SGVsbG8"
				local expected = "Hello" -- Decodes correctly without padding
				local result = base64.decode(input)
				assert.are.equal(expected, result)
			end)

			it("should handle Base64 strings with embedded whitespace", function()
				local input = "SGVs\nbG8gV29y bGQh"
				local expected = "Hello World!" -- Ignores whitespace and decodes correctly
				local result = base64.decode(input)
				assert.are.equal(expected, result)
			end)
		end)

		describe("with base64url decoder", function()
			local URL_DECODER = base64.URL_DECODER

			it("should decode a standard base64url string without padding", function()
				local input = "SGVsbG8gV29ybGQh" -- "Hello World!" in Base64url
				local expected = "Hello World!"
				local result = base64.decode(input, URL_DECODER, false)
				assert.are.equal(expected, result)
			end)

			it("should decode a standard base64url string with single padding", function()
				local input = "U29mdHdhcmU=" -- "Software" in Base64url
				local expected = "Software"
				local result = base64.decode(input, URL_DECODER, false)
				assert.are.equal(expected, result)
			end)

			it("should decode a standard base64url string with double padding", function()
				local input = "QQ==" -- "A" in Base64url
				local expected = "A"
				local result = base64.decode(input, URL_DECODER, false)
				assert.are.equal(expected, result)
			end)

			it("should decode using a custom decoder with base64url-specific characters", function()
				local input = "U29mLXdhX3N0YWtl" -- Example using '-' and '_'
				local expected = "Sof-wa_stake"
				local result = base64.decode(input, URL_DECODER, false)
				assert.are.equal(expected, result)
			end)

			it("should handle invalid characters by stripping them out in base64url", function()
				local input = "SGVsbG8g@@#%V29ybGQh" -- Invalid characters mixed in
				local expected = "Hello World!"
				local result = base64.decode(input, URL_DECODER, false)
				assert.are.equal(expected, result)
			end)

			it("should work correctly with caching enabled for base64url", function()
				local input = "SGVsbG8gV29ybGQh" -- "Hello World!" in Base64url
				local expected = "Hello World!"
				local resultWithCaching = base64.decode(input, URL_DECODER, true)
				local resultWithoutCaching = base64.decode(input, URL_DECODER, false)
				assert.are.equal(expected, resultWithCaching)
				assert.are.equal(resultWithCaching, resultWithoutCaching)
			end)

			it("should decode a long base64url string efficiently with caching", function()
				local input = ("SGVsbG8g"):rep(1000) -- "Hello " repeated 1000 times
				local expected = ("Hello "):rep(1000)
				local result = base64.decode(input, URL_DECODER, true)
				assert.are.equal(expected, result)
			end)

			it("should handle an empty string input for base64url", function()
				local input = ""
				local expected = ""
				local result = base64.decode(input, URL_DECODER, false)
				assert.are.equal(expected, result)
			end)

			it("should handle invalid base64url padding gracefully", function()
				local input = "SGVsbG8g===" -- Invalid triple padding
				local expected = "Hello " -- Trims invalid padding and decodes valid part
				local result = base64.decode(input, URL_DECODER, false)
				assert.are.equal(expected, result)
			end)

			it(
				"should handle invalid '=' characters mid-string by stopping at invalid segments in base64url",
				function()
					local input = "SGVsb=G8gV29ybGQh" -- Invalid '=' mid-string
					local expected = "Hel" -- Stops decoding at the invalid segment
					local result = base64.decode(input, URL_DECODER, false)
					assert.are.equal(expected, result)
				end
			)

			it("should handle trailing invalid characters gracefully in base64url", function()
				local input = "SGVsbG8g@"
				local expected = "Hello " -- Stops decoding at invalid character
				local result = base64.decode(input, URL_DECODER, false)
				assert.are.equal(expected, result)
			end)

			it("should handle base64url strings without padding", function()
				local input = "SGVsbG8" -- "Hello" without padding
				local expected = "Hello"
				local result = base64.decode(input, URL_DECODER, false)
				assert.are.equal(expected, result)
			end)

			it("should handle base64url strings with embedded whitespace", function()
				local input = "SGVs\nbG8gV29y bGQh"
				local expected = "Hello World!" -- Ignores whitespace and decodes correctly
				local result = base64.decode(input, URL_DECODER, false)
				assert.are.equal(expected, result)
			end)

			it("should handle excessive padding in malformed Base64 strings", function()
				-- Input string with excessive padding ('==') causing it to be malformed
				local input = "observer1c29tZSBzYW1wbGUgaGFzaA=="

				-- Expected result after trimming excessive '=' and decoding
				local expectedHex = "a1bb1eaef7abd5cdbdb59481cd85b5c1b19481a185cda0"

				-- Decode the input string using the Base64 decoder
				local decoded = base64.decode(input, base64.URL_DECODER)

				-- Convert the decoded binary data to a hexadecimal string
				local function toHex(str)
					return (
						str:gsub(".", function(c)
							return string.format("%02x", string.byte(c)) -- Convert each character to lowercase hex
						end)
					)
				end

				local resultHex = toHex(decoded)
				assert.are.same(expectedHex, resultHex, "Hex representation should match the expected value")
			end)
		end)
	end)

	describe("base64.encode/decode", function()
		it("should correctly encode and decode empty string", function()
			local input = ""
			local encoded = base64.encode(input)
			local decoded = base64.decode(encoded)
			assert.are.equal(input, decoded)
		end)

		it("should correctly encode and decode short strings", function()
			local testCases = {
				["f"] = "Zg==",
				["fo"] = "Zm8=",
				["foo"] = "Zm9v",
				["foob"] = "Zm9vYg==",
				["fooba"] = "Zm9vYmE=",
				["foobar"] = "Zm9vYmFy",
			}
			for input, expected in pairs(testCases) do
				local encoded = base64.encode(input)
				assert.are.equal(encoded, expected)
				local decoded = base64.decode(encoded)
				assert.are.equal(decoded, input)
			end
		end)
	end)

	describe("base64.encode/decode with random data", function()
		-- Generating random characters slows down the unit tests a bunch. Memoize all the chars we need.
		local function memoizeRandomBytes(maxLength)
			-- Generate a single long random string
			local fullRandom = {}
			for _ = 1, maxLength do
				fullRandom[#fullRandom + 1] = string.char(math.random(0, 255))
			end
			local fullRandomStr = table.concat(fullRandom)

			return function(length)
				assert(length <= maxLength, "Requested length exceeds maximum memoized length")
				-- Optionally use a random offset for randomness
				local offset = math.random(0, maxLength - length)
				return fullRandomStr:sub(offset + 1, offset + length)
			end
		end

		-- Memoized random generator for up to 64 bytes
		local getRandomBytes = memoizeRandomBytes(128)

		it("should correctly handle random byte sequences", function()
			-- Representative lengths for coverage
			local lengths = { 2, 20, 128 }
			for _, length in ipairs(lengths) do
				local input = getRandomBytes(length)
				local encoded = base64.encode(input)
				local decoded = base64.decode(encoded)
				assert.are.equal(input, decoded)
			end
		end)
	end)

	describe("base64.encode/decode with invalid inputs", function()
		local invalidInputs = { nil, 123, {}, true, function() end }
		for _, input in ipairs(invalidInputs) do
			it("should throw error for invalid input", function()
				assert.has_error(function()
					base64.encode(input)
				end)
				assert.has_error(function()
					base64.decode(input)
				end)
			end)
		end
	end)
end)
