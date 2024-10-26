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

	describe("reduce", function()
		it("should return the starting value if the input table is empty", function()
			local input = {}
			local stubReducer = function(acc, value)
				return acc + value
			end
			assert.are.same(0, utils.reduce(input, stubReducer, 0))
			assert.are.same({}, utils.reduce(input, stubReducer, {}))
			assert.are.same("foo", utils.reduce(input, stubReducer, "foo"))
		end)

		it("should return the reduced value for a numeric table", function()
			local input = { 1, 3, 5, 7, 9 }
			assert.are.same(
				15,
				utils.reduce(input, function(acc, key)
					return acc + key
				end, 0)
			)
			assert.are.same(
				25,
				utils.reduce(input, function(acc, _, value)
					return acc + value
				end, 0)
			)
		end)

		it("should return the reduced value for a keyed table", function()
			local input = { foo = 2, bar = 4, baz = 6, oof = 8, rab = 10 }
			local reducer = function(acc, _, value)
				return acc + value
			end
			assert.are.same(30, utils.reduce(input, reducer, 0))
		end)
	end)

	describe("map", function()
		it("should return a new table with the mapped values", function()
			local input = { 1, 2, 3, 4, 5 }
			local mapper = function(value)
				return value * 2
			end
			assert.are.same({ 2, 4, 6, 8, 10 }, utils.map(input, mapper))
		end)
	end)

	describe("toTrainCase", function()
		it("should convert a string to Train-Case", function()
			assert.are.same("Hello", utils.toTrainCase("hello"))
			assert.are.same("Hello", utils.toTrainCase("Hello"))
			assert.are.same("Hello-World", utils.toTrainCase("Hello World"))
			assert.are.same("Hello-World", utils.toTrainCase("hello world"))
			assert.are.same("Hello-World", utils.toTrainCase("hello-world"))
			assert.are.same("Hello-World", utils.toTrainCase("hello_world"))
			assert.are.same("Hello-World", utils.toTrainCase("helloWorld"))
			assert.are.same("Hello-World", utils.toTrainCase("HelloWorld"))
			assert.are.same("Hello-World", utils.toTrainCase("Hello-World"))
			assert.are.same("Hello-Worl-D", utils.toTrainCase("Hello-WorlD"))
			assert.are.same("HW-Hello-World", utils.toTrainCase("HW-helloWorld"))
		end)
	end)
end)
