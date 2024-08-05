local utils = require("utils")

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
