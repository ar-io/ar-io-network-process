local utils = require("utils")

local testArweaveAddress = "test-this-is-valid-arweave-wallet-address-1"
local testEthAddress = "0xFCAd0B19bB29D4674531d6f115237E16AfCE377c"

describe("utils", function()
	describe("isValidEthAddress", function()
		it("should validate eth address", function()
			assert.is_true(utils.isValidEthAddress(testEthAddress))
			-- invalid non-hexadecimal G character
			assert.is_false(utils.isValidEthAddress("0xFCAd0B19bB29D4674531d6f115237E16AfCE377G"))
			-- invalid length
			assert.is_false(utils.isValidEthAddress("0xFCAd0B19bB29D4674531d6f115237E16AfCE37"))
		end)
	end)

	describe("formatAddress", function()
		it("should format ETH address to lowercase", function()
			assert.is.equal("0xfcad0b19bb29d4674531d6f115237e16afce377c", utils.formatAddress(testEthAddress))
		end)
		it("should return non-ETH address as-is", function()
			assert.is.equal(testArweaveAddress, utils.formatAddress(testArweaveAddress))
		end)
	end)
end)
