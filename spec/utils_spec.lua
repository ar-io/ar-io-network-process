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

	describe("isValidUnformattedEthAddress", function()
		it("should return true on a valid unformatted ETH address", function()
			assert.is_true(utils.isValidUnformattedEthAddress(testEthAddress))
		end)

		it("should return false on a non-string value", function()
			assert.is_false(utils.isValidUnformattedEthAddress(3))
		end)

		it("should return false on an invalid unformatted ETH address", function()
			assert.is_false(utils.isValidUnformattedEthAddress("ZxFCAd0B19bB29D4674531d6f115237E16AfCE377C"))
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

		it("should provide a numeric index in the reducer function for any kind of table", function()
			local reducer = function(acc, _, value, i)
				return acc + value + i
			end
			assert.are.same(45, utils.reduce({ foo = 2, bar = 4, baz = 6, oof = 8, rab = 10 }, reducer, 0))
			assert.are.same(12, utils.reduce({ 1, 2, 3 }, reducer, 0))
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

		it("correctly handles a nil cursorField and sortBy on a table of non-table values", function()
			local arr = { "1", "2", "3" }
			local cursor = ""
			local cursorField = nil
			local limit = 1
			local sortOrder = "asc"
			local sortBy = nil
			local result = utils.paginateTableWithCursor(arr, cursor, cursorField, limit, sortBy, sortOrder)
			assert.are.same({
				items = {
					[1] = "1",
				},
				limit = 1,
				totalItems = 3,
				sortOrder = "asc",
				nextCursor = "1",
				hasMore = true,
			}, result)
			local result2 = utils.paginateTableWithCursor(arr, result.nextCursor, cursorField, limit, sortBy, sortOrder)
			assert.are.same({
				items = {
					[1] = "2",
				},
				limit = 1,
				totalItems = 3,
				sortOrder = "asc",
				nextCursor = "2",
				hasMore = true,
			}, result2)
		end)

		it("applies table filters when paginating", function()
			local list = {
				{ name = "alpha", type = "lease" },
				{ name = "beta", type = "permabuy" },
				{ name = "gamma", type = "lease" },
			}
			local result = utils.paginateTableWithCursor(list, nil, "name", 10, "name", "asc", { type = "lease" })
			assert.are.same({
				items = {
					{ name = "alpha", type = "lease" },
					{ name = "gamma", type = "lease" },
				},
				limit = 10,
				totalItems = 2,
				sortBy = "name",
				sortOrder = "asc",
				nextCursor = nil,
				hasMore = false,
			}, result)
		end)

		it("applies array filters when paginating", function()
			local list = {
				{ name = "alpha", type = "lease" },
				{ name = "beta", type = "permabuy" },
				{ name = "gamma", type = "renewal" },
			}
			local result =
				utils.paginateTableWithCursor(list, nil, "name", 10, "name", "asc", { type = { "lease", "renewal" } })
			assert.are.same({
				items = {
					{ name = "alpha", type = "lease" },
					{ name = "gamma", type = "renewal" },
				},
				limit = 10,
				totalItems = 2,
				sortBy = "name",
				sortOrder = "asc",
				nextCursor = nil,
				hasMore = false,
			}, result)
		end)

		it("applies filters when filter values are numbers", function()
			local list = {
				{ name = "alpha", type = 1 },
				{ name = "beta", type = 2 },
				{ name = "gamma", type = 3 },
			}
			local result = utils.paginateTableWithCursor(list, nil, "name", 10, "name", "asc", { type = 1 })
			assert.are.same({
				items = {
					{ name = "alpha", type = 1 },
				},
				limit = 10,
				totalItems = 1,
				sortBy = "name",
				sortOrder = "asc",
				nextCursor = nil,
				hasMore = false,
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

		it("should return an empty table for a nil input string", function()
			local result = utils.splitAndTrimString(nil)
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

		it("should handle regex characters as delimiters", function()
			local input = "apple|banana.cherry[date]eggplant"
			local result = utils.splitAndTrimString(input, "[|.]")
			assert.are.same({ "apple", "banana", "cherry", "date", "eggplant" }, result)
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

		it("should use a provided value assignment function", function()
			local input = { "apple", "banana", "cherry", "date" }
			local result = utils.createLookupTable(input, function(_, value)
				return value .. "s"
			end)
			assert.are.same({
				apple = "apples",
				banana = "bananas",
				cherry = "cherrys",
				date = "dates",
			}, result)
		end)
	end)

	describe("roundToPrecision", function()
		it("should round to 3 decimal places", function()
			local result = utils.roundToPrecision(1.23456789, 3)
			assert.are.equal(1.235, result)
		end)

		it("should round to 7 decimal places", function()
			local result = utils.roundToPrecision(1.23456789, 7)
			assert.are.equal(1.2345679, result)
		end)

		it("should handle negative numbers", function()
			local result = utils.roundToPrecision(-1.23456789, 3)
			assert.are.equal(-1.235, result)
		end)

		it("should handle zero", function()
			local result = utils.roundToPrecision(0, 3)
			assert.are.equal(0, result)
		end)

		it("should handle large numbers", function()
			local result = utils.roundToPrecision(123456.789, 3)
			assert.are.equal(123456.789, result)
		end)
	end)

	describe("sortTableByFields", function()
		local nestedTableData = {
			{ name = "Alice", details = { age = 30, score = 85 } },
			{ name = "Bob", details = { age = 25, score = 92 } },
			{ name = "Alice", details = { age = 22, score = 90 } },
			{ name = "Charlie", details = { age = 30, score = 88 } },
		}

		it("sorts a number-indexed table of simple values in ascending order", function()
			local simpleValues = { 5, 2, 9, 1, 4 }
			local sortedData = utils.sortTableByFields(simpleValues, { { field = nil, order = "asc" } })
			local expectedData = { 1, 2, 4, 5, 9 }
			assert.are.same(expectedData, sortedData)
		end)

		it("sorts a number-indexed table of simple values in descending order", function()
			local simpleValues = { 5, 2, 9, 1, 4 }
			local sortedData = utils.sortTableByFields(simpleValues, { { field = nil, order = "desc" } })
			local expectedData = { 9, 5, 4, 2, 1 }
			assert.are.same(expectedData, sortedData)
		end)

		it("handles an empty table gracefully", function()
			local simpleValues = {}
			local sortedData = utils.sortTableByFields(simpleValues, { { field = nil, order = "asc" } })
			local expectedData = {}
			assert.are.same(expectedData, sortedData)
		end)

		it("handles a table with identical values", function()
			local simpleValues = { 3, 3, 3, 3 }
			local sortedData = utils.sortTableByFields(simpleValues, { { field = nil, order = "asc" } })
			local expectedData = { 3, 3, 3, 3 }
			assert.are.same(expectedData, sortedData)
		end)

		it("handles a table with nil values, placing them at the end", function()
			local simpleValues = { 7, nil, 2, nil, 5 }
			local sortedData = utils.sortTableByFields(simpleValues, { { field = nil, order = "asc" } })
			local expectedData = { 2, 5, 7, nil, nil }
			assert.are.same(expectedData, sortedData)
		end)

		it("sorts by a single top-level field in ascending order", function()
			local sortedData = utils.sortTableByFields(nestedTableData, { { field = "name", order = "asc" } })
			local expectedData = {
				{ name = "Alice", details = { age = 30, score = 85 } },
				{ name = "Alice", details = { age = 22, score = 90 } },
				{ name = "Bob", details = { age = 25, score = 92 } },
				{ name = "Charlie", details = { age = 30, score = 88 } },
			}
			assert.are.same(expectedData, sortedData)
		end)

		it("sorts by a single top-level field in descending order", function()
			local sortedData = utils.sortTableByFields(nestedTableData, { { field = "name", order = "desc" } })
			local expectedData = {
				{ name = "Charlie", details = { age = 30, score = 88 } },
				{ name = "Bob", details = { age = 25, score = 92 } },
				{ name = "Alice", details = { age = 22, score = 90 } }, -- if this does not sort stably, implement a merge sort
				{ name = "Alice", details = { age = 30, score = 85 } },
			}
			assert.are.same(expectedData, sortedData)
		end)

		it("sorts by a single nested field in ascending order", function()
			local sortedData = utils.sortTableByFields(nestedTableData, { { field = "details.age", order = "asc" } })
			local expectedData = {
				{ name = "Alice", details = { age = 22, score = 90 } },
				{ name = "Bob", details = { age = 25, score = 92 } },
				{ name = "Alice", details = { age = 30, score = 85 } },
				{ name = "Charlie", details = { age = 30, score = 88 } },
			}
			assert.are.same(expectedData, sortedData)
		end)

		it("sorts by a single nested field in descending order", function()
			local sortedData = utils.sortTableByFields(nestedTableData, { { field = "details.age", order = "desc" } })
			local expectedData = {
				{ name = "Alice", details = { age = 30, score = 85 } },
				{ name = "Charlie", details = { age = 30, score = 88 } },
				{ name = "Bob", details = { age = 25, score = 92 } },
				{ name = "Alice", details = { age = 22, score = 90 } },
			}
			assert.are.same(expectedData, sortedData)
		end)

		it("sorts by multiple fields with different orders for each field", function()
			local sortedData = utils.sortTableByFields(nestedTableData, {
				{ field = "name", order = "asc" },
				{ field = "details.age", order = "desc" },
			})
			local expectedData = {
				{ name = "Alice", details = { age = 30, score = 85 } },
				{ name = "Alice", details = { age = 22, score = 90 } },
				{ name = "Bob", details = { age = 25, score = 92 } },
				{ name = "Charlie", details = { age = 30, score = 88 } },
			}
			assert.are.same(expectedData, sortedData)
		end)

		it("sorts by multiple nested fields", function()
			local sortedData = utils.sortTableByFields(nestedTableData, {
				{ field = "details.age", order = "asc" },
				{ field = "details.score", order = "asc" },
			})
			local expectedData = {
				{ name = "Alice", details = { age = 22, score = 90 } },
				{ name = "Bob", details = { age = 25, score = 92 } },
				{ name = "Alice", details = { age = 30, score = 85 } },
				{ name = "Charlie", details = { age = 30, score = 88 } },
			}
			assert.are.same(expectedData, sortedData)
		end)

		it("handles nil fields gracefully, placing them at the end", function()
			-- Add an entry with a nil field to test nil handling
			local dataWithNil = {
				{ name = "Alice", details = { age = 30, score = 85 } },
				{ name = "Bob", details = { age = 25, score = 92 } },
				{ name = "Alice", details = { age = 22, score = 90 } },
				{ name = "Charlie", details = { age = 30, score = 88 } },
				{ name = "Derek", details = { age = nil, score = 70 } },
			}

			local sortedData = utils.sortTableByFields(dataWithNil, { { field = "details.age", order = "asc" } })
			local expectedData = {
				{ name = "Alice", details = { age = 22, score = 90 } },
				{ name = "Bob", details = { age = 25, score = 92 } },
				{ name = "Charlie", details = { age = 30, score = 88 } }, -- if this does not sort stably, implement a merge sort
				{ name = "Alice", details = { age = 30, score = 85 } },
				{ name = "Derek", details = { age = nil, score = 70 } },
			}
			assert.are.same(expectedData, sortedData)
		end)
	end)

	describe("getTableKeys", function()
		it("should return the keys of a table", function()
			local input = { foo = "bar", baz = "qux" }
			local result = utils.getTableKeys(input)
			table.sort(result)
			assert.are.same({ "baz", "foo" }, result)
		end)

		it("should return an empty table for an empty table", function()
			local input = {}
			local result = utils.getTableKeys(input)
			assert.are.same({}, result)
		end)

		it("should return an empty table for a nil table", function()
			local result = utils.getTableKeys(nil)
			assert.are.same({}, result)
		end)
	end)

	describe("filterArray", function()
		it("should filter an array based on a predicate", function()
			local input = { 1, 2, 3, 4, 5 }
			local predicate = function(value)
				return value % 2 == 0
			end
			local result = utils.filterArray(input, predicate)
			assert.are.same({ 2, 4 }, result)
		end)

		it("should return an empty table for an empty input table", function()
			local input = {}
			local predicate = function(value)
				return value % 2 == 0
			end
			local result = utils.filterArray(input, predicate)
			assert.are.same({}, result)
		end)

		it("should return an empty table for a nil input table", function()
			local predicate = function(value)
				return value % 2 == 0
			end
			local result = utils.filterArray(nil, predicate)
			assert.are.same({}, result)
		end)

		it("should return an empty table for a nil predicate", function()
			local input = { 1, 2, 3, 4, 5 }
			local result = utils.filterArray(input, nil)
			assert.are.same({}, result)
		end)
	end)

	describe("filterDictionary", function()
		it("should filter a dictionary based on a predicate", function()
			local input = { foo = 1, bar = 2, baz = 3, qux = 4, quux = 5 }
			local predicate = function(_, value)
				return value % 2 == 0
			end
			local result = utils.filterDictionary(input, predicate)
			assert.are.same({ bar = 2, qux = 4 }, result)
		end)

		it("should return an empty table for an empty input table", function()
			local input = {}
			local predicate = function(_, value)
				return value % 2 == 0
			end
			local result = utils.filterDictionary(input, predicate)
			assert.are.same({}, result)
		end)

		it("should return an empty table for a nil input table", function()
			local predicate = function(_, value)
				return value % 2 == 0
			end
			local result = utils.filterDictionary(nil, predicate)
			assert.are.same({}, result)
		end)

		it("should return an empty table for a nil predicate", function()
			local input = { foo = 1, bar = 2, baz = 3, qux = 4, quux = 5 }
			local result = utils.filterDictionary(input, nil)
			assert.are.same({}, result)
		end)
	end)

	describe("parsePaginationTags", function()
		it("should parse pagination tags", function()
			local tags = {
				Tags = {
					Cursor = "1",
					Limit = "10",
					["Sort-By"] = "name",
					["Sort-Order"] = "asc",
					Filters = '{"type":"lease"}',
				},
			}
			local result = utils.parsePaginationTags(tags)
			assert.are.same({
				cursor = "1",
				limit = 10,
				sortBy = "name",
				sortOrder = "asc",
				filters = { type = "lease" },
			}, result)
		end)

		it("should handle missing tags gracefully", function()
			local tags = { Tags = {} }
			local result = utils.parsePaginationTags(tags)
			assert.are.same({ cursor = nil, limit = 100, sortBy = nil, sortOrder = "desc", filters = nil }, result)
		end)
	end)

	describe("slice", function()
		it("should slice a table from a given index to a given index by a given step", function()
			local input = { 1, 2, 3, 4, 5 }
			local result = utils.slice(input, 2, 4)
			assert.are.same({ 2, 3, 4 }, result)
		end)

		it("should slice a table from a given index to the end by a given step", function()
			local input = { 1, 2, 3, 4, 5 }
			local result = utils.slice(input, 2, nil, 2)
			assert.are.same({ 2, 4 }, result)
		end)
	end)

	describe("deepCopy", function()
		it("should deep copy a table with nested tables containing mixed types", function()
			local input = {
				foo = "bar",
				baz = 2,
				qux = { 1, 2, 3 },
				quux = { a = "b", c = "d" },
				oof = true,
			}
			local result = utils.deepCopy(input)
			assert.are.same(input, result)
			assert.are_not.equal(input, result)
			assert.are_not.equal(input.qux, result.qux)
			assert.are_not.equal(input.quux, result.quux)
		end)

		it("should exclude nested fields specified in the exclusion list while preserving array indexing", function()
			local input = {
				foo = "bar",
				baz = 2,
				qux = { 1, 2, 3 },
				quux = { a = "b", c = "d" },
				oof = true,
			}
			local result = utils.deepCopy(input, { "foo", "qux.2", "quux.c" })
			assert.are.same({
				baz = 2,
				qux = { 1, 3 },
				quux = { a = "b" },
				oof = true,
			}, result)
			assert.are_not.equal(input, result)
		end)
	end)

	describe("safeDecodeJson", function()
		it("should decode a JSON string", function()
			local input = '{"foo": "bar"}'
			local result = utils.safeDecodeJson(input)
			assert.are.same({ foo = "bar" }, result)
		end)

		it("should return nil for an invalid JSON string", function()
			local input = "not a JSON string"
			local result = utils.safeDecodeJson(input)
			assert.are.same(nil, result)
		end)

		it("should return nil for a nil input", function()
			local result = utils.safeDecodeJson(nil)
			assert.are.same(nil, result)
		end)
	end)

	describe("isInteger", function()
		it("should return true for valid integers", function()
			assert.is_true(utils.isInteger(0))
			assert.is_true(utils.isInteger(-1))
			assert.is_true(utils.isInteger(123456789))
			assert.is_true(utils.isInteger("0"))
			assert.is_true(utils.isInteger("-1"))
			assert.is_true(utils.isInteger("123456789"))
		end)

		it("should return false for non-integer floating-point numbers", function()
			assert.is_false(utils.isInteger(1.23))
			assert.is_false(utils.isInteger(-0.456))
			assert.is_false(utils.isInteger("1.23"))
			assert.is_false(utils.isInteger("-0.456"))
		end)

		it("should return true for integer floating-point numbers", function()
			assert.is_true(utils.isInteger(1.0))
			assert.is_true(utils.isInteger(1.))
			assert.is_true(utils.isInteger(-100.0))
			assert.is_true(utils.isInteger(0.0))
			assert.is_true(utils.isInteger(-0.0))
			assert.is_true(utils.isInteger("1.0"))
			assert.is_true(utils.isInteger("-100.0"))
			assert.is_true(utils.isInteger("1."))
		end)

		it("should return true for integers in scientific notation", function()
			assert.is_true(utils.isInteger("1e3")) -- 1000
			assert.is_true(utils.isInteger("-1e3")) -- -1000
			assert.is_true(utils.isInteger("1.0e3")) -- 1000
			assert.is_true(utils.isInteger("-1.0e3")) -- -1000
			assert.is_true(utils.isInteger("1.23e3")) -- 1230
			assert.is_true(utils.isInteger("-1.23e3")) -- -1230
		end)

		it("should return false for non-integers in scientific notation", function()
			assert.is_false(utils.isInteger("1.23e-3")) -- 0.00123
			assert.is_false(utils.isInteger("-1.23e-3")) -- -0.00123
		end)

		it("should return true for hexadecimal integers and hexadecimal integer floats", function()
			assert.is_true(utils.isInteger("0x1F")) -- 31
			assert.is_true(utils.isInteger("0xABC")) -- 2748
			assert.is_true(utils.isInteger("-0x10")) -- -16
			assert.is_true(utils.isInteger("0x1.8p3")) -- 12.0
		end)

		it("should return false for hexadecimal floats", function()
			assert.is_false(utils.isInteger("-0x1.921fbp+1")) -- ~3.14
		end)

		it("should return false for invalid strings", function()
			assert.is_false(utils.isInteger("123abc"))
			assert.is_false(utils.isInteger("1.2.3"))
			assert.is_false(utils.isInteger("1.0e--2"))
			assert.is_false(utils.isInteger("abc"))
			assert.is_false(utils.isInteger(""))
		end)

		it("should handle edge cases for `inf` and `nan`", function()
			assert.is_false(utils.isInteger(math.huge)) -- Infinity
			assert.is_false(utils.isInteger(-math.huge)) -- -Infinity
			assert.is_false(utils.isInteger(0 / 0)) -- NaN
			assert.is_false(utils.isInteger("inf"))
			assert.is_false(utils.isInteger("-inf"))
			assert.is_false(utils.isInteger("nan"))
		end)

		it("should handle large and small numbers", function()
			assert.is_true(utils.isInteger("1.7976931348623157e+308")) -- Max finite value, treated as integer
			assert.is_false(utils.isInteger("4.9406564584124654e-324")) -- Min positive subnormal value, not an integer
			assert.is_false(utils.isInteger("-4.9406564584124654e-324"))
		end)

		it("should handle negative zero", function()
			assert.is_true(utils.isInteger(-0.0))
			assert.is_true(utils.isInteger("0.0"))
			assert.is_true(utils.isInteger("-0.0"))
		end)

		it("should handle numbers with leading zeros", function()
			assert.is_true(utils.isInteger("000123"))
			assert.is_true(utils.isInteger("000000"))
			assert.is_true(utils.isInteger("-000456"))
		end)

		it("should return false for non-numbers and non-integer strings", function()
			assert.is_false(utils.isInteger({}))
			assert.is_false(utils.isInteger(nil))
			assert.is_false(utils.isInteger(true))
			assert.is_false(utils.isInteger(false))
			assert.is_false(utils.isInteger(function() end))
			assert.is_false(utils.isInteger("true"))
			assert.is_false(utils.isInteger("false"))
			assert.is_false(utils.isInteger("foo"))
			assert.is_false(utils.isInteger("1.234"))
			assert.is_false(utils.isInteger("1.0e-10"))
			assert.is_false(utils.isInteger("1.0e")) -- not a valid lua number
			assert.is_false(utils.isInteger("1.0e-")) -- not a valid lua number
			assert.is_false(utils.isInteger("1.0e+")) -- not a valid lua number
		end)
	end)

	describe("booleanOrBooleanStringToBoolean", function()
		it("should return a boolean as itself", function()
			assert.is_true(utils.booleanOrBooleanStringToBoolean(true))
			assert.is_false(utils.booleanOrBooleanStringToBoolean(false))
		end)

		it("should convert any casing of true or false to the analogous boolean value", function()
			assert.is_true(utils.booleanOrBooleanStringToBoolean("true"))
			assert.is_true(utils.booleanOrBooleanStringToBoolean("True"))
			assert.is_true(utils.booleanOrBooleanStringToBoolean("TRUE"))
			assert.is_true(utils.booleanOrBooleanStringToBoolean("tRuE"))
			assert.is_false(utils.booleanOrBooleanStringToBoolean("false"))
			assert.is_false(utils.booleanOrBooleanStringToBoolean("False"))
			assert.is_false(utils.booleanOrBooleanStringToBoolean("FALSE"))
			assert.is_false(utils.booleanOrBooleanStringToBoolean("fAlSe"))
		end)

		it("should not convert other truthy-like string values to boolean", function()
			assert.is_false(utils.booleanOrBooleanStringToBoolean("1"))
			assert.is_false(utils.booleanOrBooleanStringToBoolean("yes"))
			assert.is_false(utils.booleanOrBooleanStringToBoolean("Yes"))
			assert.is_false(utils.booleanOrBooleanStringToBoolean("YES"))
			assert.is_false(utils.booleanOrBooleanStringToBoolean("y"))
			assert.is_false(utils.booleanOrBooleanStringToBoolean("Y"))
			assert.is_false(utils.booleanOrBooleanStringToBoolean("t"))
			---@ diagnostic disable-next-line: param-type-mismatch
			assert.is_false(utils.booleanOrBooleanStringToBoolean({
				True = true,
			}))
			---@ diagnostic disable-next-line: param-type-mismatch
			assert.is_false(utils.booleanOrBooleanStringToBoolean(nil))
			---@ diagnostic disable-next-line: param-type-mismatch
			assert.is_false(utils.booleanOrBooleanStringToBoolean(1))
		end)
	end)
	describe("baseNameForName", function()
		it("should get base name for name with an undername", function()
			local undername = "undername"
			local basename = "basename"
			local name = undername .. "_" .. basename

			local baseNameFromName = utils.baseNameForName(name)
			assert.are.same(baseNameFromName, basename)
		end)
	end)

	describe("undernameForName", function()
		it("should get the undername name for a name with an undername", function()
			local undername = "undername"
			local basename = "basename"
			local name = undername .. "_" .. basename

			local undernameFromName = utils.undernameForName(name)
			assert.are.same(undername, undernameFromName)
		end)

		it("should return nil for a name with no undername", function()
			local basename = "basename"
			local undernameFromName = utils.undernameForName(basename)
			assert.are.same(nil, undernameFromName)
		end)

		it("should get the undername name for a name with an undername and base name with dashes", function()
			local undername = "test"
			local basename = "base-name-with-dashes"
			local name = undername .. "_" .. basename

			local undernameFromName = utils.undernameForName(name)
			assert.are.same(undername, undernameFromName)
		end)

		it("should return nil for a base name with dashes but no undername", function()
			local basename = "base-name-with-dashes"
			local undernameFromName = utils.undernameForName(basename)
			assert.are.same(nil, undernameFromName)
		end)

		it("should handle complex undername with base name containing dashes", function()
			local undername = "my-complex-undername"
			local basename = "test-base-name-with-dashes"
			local name = undername .. "_" .. basename

			local undernameFromName = utils.undernameForName(name)
			assert.are.same(undername, undernameFromName)
		end)

		it("should handle case where undername and base name are identical", function()
			local undername = "samename"
			local basename = "samename"
			local name = undername .. "_" .. basename

			local undernameFromName = utils.undernameForName(name)
			assert.are.same(undername, undernameFromName)
		end)

		it("should handle case where undername and base name are identical with dashes", function()
			local undername = "same-name-with-dashes"
			local basename = "same-name-with-dashes"
			local name = undername .. "_" .. basename

			local undernameFromName = utils.undernameForName(name)
			assert.are.same(undername, undernameFromName)
		end)
	end)
end)
