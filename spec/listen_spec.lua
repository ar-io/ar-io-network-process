local listen = require("listen")

describe("listen", function()
	describe("addListener", function()
		it("should track when a new key is added", function()
			local tracked = {}
			local testTable = {}

			testTable = listen.addListener(testTable, function(ctx)
				tracked[ctx.key] = ctx.value
			end)

			testTable.foo = "bar"

			assert.is.equal("bar", tracked.foo)
		end)

		it("should track when an existing key is updated", function()
			local tracked = {}
			local testTable = { foo = "bar" }

			testTable = listen.addListener(testTable, function(ctx)
				tracked[ctx.key] = ctx.value
			end)

			testTable.foo = "baz"

			assert.is.equal("baz", tracked.foo)
		end)

		it("should track when a key is deleted (set to nil)", function()
			local tracked = {}
			local testTable = { foo = "bar", keep = "me" }

			testTable = listen.addListener(testTable, function(ctx)
				tracked[ctx.key] = ctx.value
			end)

			testTable.foo = nil

			assert.is_nil(tracked.foo)
			assert.is_nil(testTable.foo)
			assert.is.equal("me", testTable.keep)
		end)

		it("should provide oldValue in context", function()
			local oldVal = nil
			local testTable = { count = 5 }

			testTable = listen.addListener(testTable, function(ctx)
				oldVal = ctx.oldValue
			end)

			testTable.count = 10

			assert.is.equal(5, oldVal)
		end)

		it("should provide nil as oldValue for new keys", function()
			local oldVal = "not-nil"
			local testTable = {}

			testTable = listen.addListener(testTable, function(ctx)
				oldVal = ctx.oldValue
			end)

			testTable.newKey = "value"

			assert.is_nil(oldVal)
		end)

		it("should provide the actual data table in context", function()
			local contextTable = nil
			local testTable = { existing = "value" }

			testTable = listen.addListener(testTable, function(ctx)
				contextTable = ctx.table
			end)

			testTable.foo = "bar"

			assert.is_not_nil(contextTable)
			assert.is.equal("value", contextTable.existing)
			assert.is.equal("bar", contextTable.foo)
		end)

		it("should support multiple listeners on the same table", function()
			local tracker1 = {}
			local tracker2 = {}
			local testTable = {}

			testTable = listen.addListener(testTable, function(ctx)
				tracker1[ctx.key] = ctx.value
			end)

			listen.addListener(testTable, function(ctx)
				tracker2[ctx.key] = ctx.value
			end)

			testTable.foo = "bar"

			assert.is.equal("bar", tracker1.foo)
			assert.is.equal("bar", tracker2.foo)
		end)

		it("should preserve table values during wrapping", function()
			local testTable = {
				str = "hello",
				num = 42,
				bool = true,
				tbl = { nested = "value" },
			}

			testTable = listen.addListener(testTable, function(ctx) end)

			assert.is.equal("hello", testTable.str)
			assert.is.equal(42, testTable.num)
			assert.is.equal(true, testTable.bool)
			assert.is.equal("value", testTable.tbl.nested)
		end)

		it("should work with pairs iteration", function()
			local testTable = { a = 1, b = 2, c = 3 }

			testTable = listen.addListener(testTable, function(ctx) end)

			local count = 0
			local sum = 0
			for k, v in pairs(testTable) do
				count = count + 1
				sum = sum + v
			end

			assert.is.equal(3, count)
			assert.is.equal(6, sum)
		end)

		it("should track changes made during iteration", function()
			local changes = {}
			local testTable = { a = 1, b = 2 }

			testTable = listen.addListener(testTable, function(ctx)
				changes[ctx.key] = true
			end)

			for k, v in pairs(testTable) do
				testTable[k] = v * 2
			end

			assert.is_true(changes.a)
			assert.is_true(changes.b)
			assert.is.equal(2, testTable.a)
			assert.is.equal(4, testTable.b)
		end)

		it("should handle rapid successive changes to same key", function()
			local changeCount = 0
			local finalValue = nil
			local testTable = {}

			testTable = listen.addListener(testTable, function(ctx)
				changeCount = changeCount + 1
				finalValue = ctx.value
			end)

			testTable.foo = 1
			testTable.foo = 2
			testTable.foo = 3
			testTable.foo = nil

			assert.is.equal(4, changeCount)
			assert.is_nil(finalValue)
		end)

		it("should handle listener that throws error", function()
			local testTable = {}
			local secondListenerCalled = false

			testTable = listen.addListener(testTable, function(ctx)
				error("intentional error")
			end)

			listen.addListener(testTable, function(ctx)
				secondListenerCalled = true
			end)

			-- First listener throws, but shouldn't prevent the value from being set
			assert.has_error(function()
				testTable.foo = "bar"
			end)

			-- Value should still be set despite error
			assert.is.equal("bar", testTable.foo)
		end)
	end)

	describe("removeAllListeners", function()
		it("should stop tracking after listeners are removed", function()
			local tracked = {}
			local testTable = {}

			testTable = listen.addListener(testTable, function(ctx)
				tracked[ctx.key] = ctx.value
			end)

			testTable.before = "remove"
			assert.is.equal("remove", tracked.before)

			listen.removeAllListeners(testTable)

			testTable.after = "remove"
			assert.is_nil(tracked.after)
		end)

		it("should handle removing listeners from unwrapped table", function()
			local testTable = {}

			-- Should not error
			assert.has_no.errors(function()
				listen.removeAllListeners(testTable)
			end)
		end)
	end)

	describe("getActualData", function()
		it("should return the actual data table", function()
			local testTable = { foo = "bar" }

			testTable = listen.addListener(testTable, function(ctx) end)

			local actualData = listen.getActualData(testTable)

			assert.is.equal("bar", actualData.foo)
		end)

		it("should return the same table if not wrapped", function()
			local testTable = { foo = "bar" }

			local result = listen.getActualData(testTable)

			assert.is.equal(testTable, result)
		end)

		it("should show changes made to wrapped table", function()
			local testTable = { foo = "bar" }

			testTable = listen.addListener(testTable, function(ctx) end)

			testTable.baz = "qux"

			local actualData = listen.getActualData(testTable)

			assert.is.equal("qux", actualData.baz)
		end)
	end)

	describe("HyperbeamSync pattern", function()
		it("should track changes like HyperbeamSync does", function()
			local changes = {}
			local data = {}

			data = listen.addListener(data, function(ctx)
				-- Track that a key changed (key = true, not the value)
				changes[ctx.key] = true
			end)

			data.alice = "owner123"
			data.bob = "owner456"
			data.alice = nil

			assert.is_true(changes.alice)
			assert.is_true(changes.bob)
			-- alice should still be tracked even though it was deleted
			assert.is_true(changes.alice)
		end)
	end)

	describe("edge cases", function()
		it("should handle number keys", function()
			local tracked = {}
			local testTable = {}

			testTable = listen.addListener(testTable, function(ctx)
				tracked[ctx.key] = ctx.value
			end)

			testTable[1] = "first"
			testTable[42] = "answer"

			assert.is.equal("first", tracked[1])
			assert.is.equal("answer", tracked[42])
		end)

		it("should handle mixed string and number keys", function()
			local changeCount = 0
			local testTable = {}

			testTable = listen.addListener(testTable, function(ctx)
				changeCount = changeCount + 1
			end)

			testTable.str = "value"
			testTable[1] = "numeric"
			testTable["123"] = "string number"

			assert.is.equal(3, changeCount)
		end)

		it("should handle setting same value multiple times", function()
			local changeCount = 0
			local testTable = {}

			testTable = listen.addListener(testTable, function(ctx)
				changeCount = changeCount + 1
			end)

			testTable.foo = "bar"
			testTable.foo = "bar"
			testTable.foo = "bar"

			-- Should track all changes, even if value is the same
			assert.is.equal(3, changeCount)
		end)

		it("should handle nested table values", function()
			local tracked = nil
			local testTable = {}

			testTable = listen.addListener(testTable, function(ctx)
				tracked = ctx.value
			end)

			local nestedTable = { inner = "value" }
			testTable.nested = nestedTable

			assert.is.equal(nestedTable, tracked)
			assert.is.equal("value", testTable.nested.inner)
		end)
	end)
end)
