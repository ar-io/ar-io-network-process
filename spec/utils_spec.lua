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

	describe("paginateTableWithCursor", function()
		local threeItemTable = {
			{ name = "foo" },
			{ name = "bar" },
			{ name = "baz" },
		}

		it("paginates, limits to less than list size, and sorts in ascending order with an empty cursor", function()
			local cursor = ""
			local cursorField = "name"
			local limit = 1
			local sortBy = "name"
			local sortOrder = "asc"
			local result = utils.paginateTableWithCursor(threeItemTable, cursor, cursorField, limit, sortBy, sortOrder)
			assert.are.same({
				items = {
					{ name = "bar" },
				},
				limit = 1,
				totalItems = 3,
				sortBy = "name",
				sortOrder = "asc",
				nextCursor = "bar",
				hasMore = true,
			}, result)
		end)

		it("paginates, limits to less than list size, and sorts in ascending order with a valid cursor", function()
			local cursor = "bar"
			local cursorField = "name"
			local limit = 1
			local sortBy = "name"
			local sortOrder = "asc"
			local result = utils.paginateTableWithCursor(threeItemTable, cursor, cursorField, limit, sortBy, sortOrder)
			assert.are.same({
				items = {
					{ name = "baz" },
				},
				limit = 1,
				totalItems = 3,
				sortBy = "name",
				sortOrder = "asc",
				nextCursor = "baz",
				hasMore = true,
			}, result)
		end)

		it("paginates, limits to less than list size, and sorts in descending order with an empty cursor", function()
			local cursor = ""
			local cursorField = "name"
			local limit = 1
			local sortOrder = "desc"
			local sortBy = "name"
			local result = utils.paginateTableWithCursor(threeItemTable, cursor, cursorField, limit, sortBy, sortOrder)
			assert.are.same({
				items = {
					{ name = "foo" },
				},
				limit = 1,
				totalItems = 3,
				sortBy = "name",
				sortOrder = "desc",
				nextCursor = "foo",
				hasMore = true,
			}, result)
		end)

		it("paginates, limits to less than list size, and sorts in descending order with a valid cursor", function()
			local cursor = "foo"
			local cursorField = "name"
			local limit = 1
			local sortOrder = "desc"
			local sortBy = "name"
			local result = utils.paginateTableWithCursor(threeItemTable, cursor, cursorField, limit, sortBy, sortOrder)
			assert.are.same({
				items = {
					{ name = "baz" },
				},
				limit = 1,
				totalItems = 3,
				sortBy = "name",
				sortOrder = "desc",
				nextCursor = "baz",
				hasMore = true,
			}, result)
		end)

		it("correctly handles a nil cursor", function()
			local cursor = nil
			local cursorField = "name"
			local limit = 1
			local sortOrder = "asc"
			local sortBy = "name"
			local result = utils.paginateTableWithCursor(threeItemTable, cursor, cursorField, limit, sortBy, sortOrder)
			assert.are.same({
				items = {
					{ name = "bar" },
				},
				limit = 1,
				totalItems = 3,
				sortBy = "name",
				sortOrder = "asc",
				nextCursor = "bar",
				hasMore = true,
			}, result)
		end)

		it("correctly handles a random cursor", function()
			local cursor = "bing"
			local cursorField = "name"
			local limit = 1
			local sortOrder = "asc"
			local sortBy = "name"
			local result = utils.paginateTableWithCursor(threeItemTable, cursor, cursorField, limit, sortBy, sortOrder)
			assert.are.same({
				items = {
					{ name = "bar" },
				},
				limit = 1,
				totalItems = 3,
				sortBy = "name",
				sortOrder = "asc",
				nextCursor = "bar",
				hasMore = true,
			}, result)
		end)

		it("correctly handles a numeric string cursor", function()
			local cursor = "1001"
			local cursorField = "name"
			local limit = 1
			local sortOrder = "asc"
			local sortBy = "name"
			local table = {
				{ name = "1000" },
				{ name = "1001" },
				{ name = "1002" },
			}
			local result = utils.paginateTableWithCursor(table, cursor, cursorField, limit, sortBy, sortOrder)
			assert.are.same({
				items = {
					{ name = "1002" },
				},
				limit = 1,
				totalItems = 3,
				sortBy = "name",
				sortOrder = "asc",
				hasMore = false,
			}, result)
		end)

		it("correctly handles an irrelevant numeric cursor", function()
			local cursor = 1001
			local cursorField = "name"
			local limit = 1
			local sortOrder = "asc"
			local sortBy = "name"
			local table = {
				{ name = "1000" },
				{ name = "1001" },
				{ name = "1002" },
			}
			local result = utils.paginateTableWithCursor(table, cursor, cursorField, limit, sortBy, sortOrder)
			assert.are.same({
				items = {
					{ name = "1000" },
				},
				limit = 1,
				totalItems = 3,
				sortBy = "name",
				sortOrder = "asc",
				hasMore = true,
				nextCursor = "1000",
			}, result)
		end)
	end)

	describe("splitAndTrimString", function()
		it("should split a comma-separated list and trim whitespace", function()
			local input = "  apple, banana  , cherry ,   date  "
			local result = utils.splitAndTrimString(input)
			assert.are.same({ "apple", "banana", "cherry", "date" }, result)
		end)

		it("should split a pipe-separated list and trim whitespace", function()
			local input = "  apple| banana  | cherry |   date  "
			local result = utils.splitAndTrimString(input, "|")
			assert.are.same({ "apple", "banana", "cherry", "date" }, result)
		end)

		it("should handle a single item without delimiter", function()
			local input = "  apple  "
			local result = utils.splitAndTrimString(input)
			assert.are.same({ "apple" }, result)
		end)

		it("should return an empty table for an empty input string", function()
			local input = ""
			local result = utils.splitAndTrimString(input)
			assert.are.same({}, result)
		end)

		it("should return an empty table for a whitespace input string", function()
			local input = "   "
			local result = utils.splitAndTrimString(input)
			assert.are.same({}, result)
		end)

		it("should handle custom delimiter without trimming unexpected characters", function()
			local input = "one two three"
			local result = utils.splitAndTrimString(input, " ")
			assert.are.same({ "one", "two", "three" }, result)
		end)

		it("should handle consecutive delimiters as separate items", function()
			local input = "apple,,banana, ,cherry,"
			local result = utils.splitAndTrimString(input)
			assert.are.same({ "apple", "banana", "cherry" }, result)
		end)
	end)

	describe("createLookupTable", function()
		it("should create a lookup table from a list of strings", function()
			local input = { "apple", "banana", "cherry", "date" }
			local result = utils.createLookupTable(input)
			assert.are.same({
				apple = true,
				banana = true,
				cherry = true,
				date = true,
			}, result)
		end)

		it("should create a lookup table from a list of numbers", function()
			local input = { 1, 2, 3, 4 }
			local result = utils.createLookupTable(input)
			assert.are.same({
				[1] = true,
				[2] = true,
				[3] = true,
				[4] = true,
			}, result)
		end)

		it("should create a lookup table from a list of mixed types", function()
			local input = { "apple", 2, "cherry", 4 }
			local result = utils.createLookupTable(input)
			assert.are.same({
				apple = true,
				[2] = true,
				cherry = true,
				[4] = true,
			}, result)
		end)

		it("should create an empty lookup table from an empty list", function()
			local input = {}
			local result = utils.createLookupTable(input)
			assert.are.same({}, result)
		end)

		it("should create an empty lookup table from a nil list", function()
			local result = utils.createLookupTable(nil)
			assert.are.same({}, result)
		end)
	end)
end)
