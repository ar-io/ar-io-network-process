local utils = require("utils")

local testArweaveAddress = "test-this-is-valid-arweave-wallet-address-1"
local testEthAddress = "0xFCAd0B19bB29D4674531d6f115237E16AfCE377c"

describe("utils", function()
	describe("isValidEthAddress", function()
		it("should validate eth address", function()
			assert.is_true(utils.isValidEthAddress(testEthAddress))
		end)

		it("should fail on non-hexadecimal character ", function()
			-- invalid non-hexadecimal G character
			assert.is_false(utils.isValidEthAddress("0xFCAd0B19bB29D4674531d6f115237E16AfCE377G"))
		end)

		it("should return false on an an invalid-length address", function()
			assert.is_false(utils.isValidEthAddress("0xFCAd0B19bB29D4674531d6f115237E16AfCE37"))
		end)

		it("should return false on passing in non-string value", function()
			assert.is_false(utils.isValidEthAddress(3))
		end)
	end)

	describe("formatAddress", function()
		it("should format ETH address to lowercase", function()
			assert.is.equal(testEthAddress, utils.formatAddress(testEthAddress))
			assert.is.equal(testEthAddress, utils.formatAddress(string.lower(testEthAddress)))
			assert.is.equal(testEthAddress, utils.formatAddress("0x" .. string.upper(string.sub(testEthAddress, 3))))
		end)
		it("should return non-ETH address as-is", function()
			assert.is.equal(testArweaveAddress, utils.formatAddress(testArweaveAddress))
		end)
	end)

	describe("findInArray", function()
		it("should return the index of the found element", function()
			local array = { { key = "hello" }, { key = "world" } }
			local predicate = function(element)
				return element.key == "world"
			end
			assert.are.same(2, utils.findInArray(array, predicate))
		end)

		it("should return nil if the element is not found", function()
			local array = { { key = "hello" }, { key = "world" } }
			local predicate = function(element)
				return element.key == "foo"
			end
			assert.are.same(nil, utils.findInArray(array, predicate))
		end)
	end)
end)
