local primaryNames = require("primary_names")

describe("Primary Names", function()
	before_each(function()
		_G.PrimaryNames = {}
		_G.Balances = {}
		_G.NameRegistry = {
			records = {},
		}
	end)

	describe("setPrimaryName", function()
		it("should fail if the arns record does not exist for the name", function()
			local status, err = pcall(primaryNames.setPrimaryName, "test", "owner", "processId", 1234567890)
			assert.is_false(status)
			assert.match("ArNS record 'test' does not exist", err)
		end)

		it("should fail if the owner claiming the primary name does not have sufficient balance", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "processId",
				},
			}
			_G.Balances = {
				["owner"] = 0,
			}
			local status, err = pcall(primaryNames.setPrimaryName, "test", "owner", "processId", 1234567890)
			assert.is_false(status)
			assert.match("Insufficient balance to claim primary name", err)
		end)

		it("should fail if the primary name is already owned", function()
			_G.PrimaryNames = {
				["owner"] = {
					name = "test",
					startTimestamp = 1234567890,
				},
			}
			local status, err = pcall(primaryNames.setPrimaryName, "test", "owner", "processId", 1234567890)
			assert.is_false(status)
			assert.match("Primary name is already owned", err)
		end)

		it("should set a primary name and deduct balance from the owner", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "processId",
				},
			}
			_G.Balances = {
				["owner"] = 100000000,
			}
			local primaryName = primaryNames.setPrimaryName("test", "owner", "processId", 1234567890)
			assert.are.same({
				name = "test",
				startTimestamp = 1234567890,
			}, primaryName)
		end)
	end)

	describe("findPrimaryNameOwner", function()
		it("should return nil if the name is not owned", function()
			assert.is_nil(primaryNames.findPrimaryNameOwner("test"))
		end)

		it("should return the owner if the name is owned", function()
			_G.PrimaryNames = {
				["owner"] = { name = "test", startTimestamp = 1234567890 },
			}
			assert.are.same("owner", primaryNames.findPrimaryNameOwner("test"))
		end)
	end)

	describe("releasePrimaryName", function()
		it("should fail if the name is not owned", function()
			local status, err = pcall(primaryNames.releasePrimaryName, "test", "owner")
			assert.is_false(status)
			assert.match("Primary name is not owned", err)
		end)

		it("should release the primary name", function()
			_G.PrimaryNames = {
				["owner"] = { name = "test", startTimestamp = 1234567890 },
			}
			local releasedName = primaryNames.releasePrimaryName("owner", "test")
			assert.are.same(nil, _G.PrimaryNames["owner"])
			assert.are.same({
				name = "test",
				owner = "owner",
				startTimestamp = 1234567890,
			}, releasedName)
		end)
	end)

	describe("getPrimaryName", function()
		it("should return nil if the name is not owned", function()
			assert.is_nil(primaryNames.getPrimaryName("test"))
		end)

		it("should return the primary name if the name is owned", function()
			_G.PrimaryNames = {
				["owner"] = { name = "test", startTimestamp = 1234567890 },
			}
			assert.are.same(
				{ name = "test", owner = "owner", startTimestamp = 1234567890 },
				primaryNames.getPrimaryName("test")
			)
		end)
	end)

	describe("findPrimaryNamesWithApexName", function()
		it("should return all primary names with the given apex name", function()
			_G.PrimaryNames = {
				["owner"] = { name = "undername_test", startTimestamp = 1234567890 },
				["owner2"] = { name = "undername2_test", startTimestamp = 1234567890 },
				["owner3"] = { name = "test", startTimestamp = 1234567890 },
				["owner4"] = { name = "test2", startTimestamp = 1234567890 },
				["owner5"] = { name = "test3", startTimestamp = 1234567890 },
			}
			local primaryNamesForApexName = primaryNames.findPrimaryNamesWithApexName("test")
			assert.are.same({
				{ name = "test", owner = "owner3", startTimestamp = 1234567890 },
				{ name = "undername_test", owner = "owner", startTimestamp = 1234567890 },
				{ name = "undername2_test", owner = "owner2", startTimestamp = 1234567890 },
			}, primaryNamesForApexName)
		end)
	end)

	describe("removePrimaryNamesWithApexName", function()
		it("should remove all primary names with the given apex name", function()
			_G.PrimaryNames = {
				["owner"] = { name = "undername_test", startTimestamp = 1234567890 },
				["owner2"] = { name = "undername2_test", startTimestamp = 1234567890 },
				["owner3"] = { name = "test", startTimestamp = 1234567890 },
				["owner4"] = { name = "test2", startTimestamp = 1234567890 },
				["owner5"] = { name = "test3", startTimestamp = 1234567890 },
			}
			local removedNames = primaryNames.removePrimaryNamesWithApexName("test")
			assert.are.same({ "test", "undername_test", "undername2_test" }, removedNames)
			assert.are.same({
				["owner4"] = { name = "test2", startTimestamp = 1234567890 },
				["owner5"] = { name = "test3", startTimestamp = 1234567890 },
			}, _G.PrimaryNames)
		end)
	end)
end)
