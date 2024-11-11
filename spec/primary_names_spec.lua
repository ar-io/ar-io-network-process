local primaryNames = require("primary_names")

describe("Primary Names", function()
	before_each(function()
		_G.PrimaryNames = {}
		_G.PrimaryNameClaims = {}
		_G.Balances = {}
		_G.NameRegistry = {
			records = {},
		}
	end)

	describe("createPrimaryNameClaim", function()
		it("should fail if the arns record does not exist for the name", function()
			local status, err = pcall(primaryNames.createNameClaim, "test", "recipient", "processId", 1234567890)
			assert.is_false(status)
			assert.match("ArNS record 'test' does not exist", err)
		end)

		it("should fail if the caller is not the process id that owns the root name", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "processId",
				},
			}
			local status, err = pcall(primaryNames.createNameClaim, "test", "recipient", "processId2", 1234567890)
			assert.is_false(status)
			assert.match("Caller is not the process id that owns the base name", err)
		end)

		it("should fail if the primary name is already owned", function()
			_G.PrimaryNames = {
				["owner"] = {
					name = "test",
					startTimestamp = 1234567890,
				},
			}
			local status, err = pcall(primaryNames.createNameClaim, "test", "recipient", "processId", 1234567890)
			assert.is_false(status)
			assert.match("Primary name is already owned", err)
		end)

		it("should create a primary name claim", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "processId",
				},
			}
			local primaryNameClaim = primaryNames.createNameClaim("test", "recipient", "processId", 1234567890)
			assert.are.same({
				name = "test",
				startTimestamp = 1234567890,
				endTimestamp = 1234567890 + 30 * 24 * 60 * 60 * 1000,
				recipient = "recipient",
				processId = "processId",
				rootName = "test",
			}, primaryNameClaim)
		end)
	end)

	describe("claimPrimaryName", function()
		it("should fail if the primary name claim does not exist", function()
			local status, err = pcall(primaryNames.claimPrimaryName, "test", "owner", 1234567890)
			assert.is_false(status)
			assert.match("Primary name claim for 'test' does not exist", err)
		end)

		it("should fail if the primary name claim has expired", function()
			_G.PrimaryNameClaims = {
				["test"] = {
					recipient = "recipient",
					processId = "processId",
					startTimestamp = 1234567890,
					endTimestamp = 1234567890 - 1,
				},
			}
			local status, err = pcall(primaryNames.claimPrimaryName, "test", "recipient", 1234567890)
			assert.is_false(status)
			assert.match("Primary name claim for 'test' has expired", err)
		end)

		it("should fail if the the recipient of the name does not have sufficient balance", function()
			_G.PrimaryNameClaims = {
				["test"] = {
					recipient = "recipient",
					startTimestamp = 1234567890,
					processId = "processId",
					endTimestamp = 1234567890 + 30 * 24 * 60 * 60 * 1000,
				},
			}
			local status, err = pcall(primaryNames.claimPrimaryName, "test", "recipient", 1234567890)
			assert.is_false(status)
			assert.match("Insufficient balance to claim primary name", err)
		end)

		it("should claim the primary name", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "processId",
				},
			}
			_G.PrimaryNameClaims = {
				["test"] = {
					recipient = "recipient",
					processId = "processId",
					startTimestamp = 1234567890,
					endTimestamp = 1234567890 + 30 * 24 * 60 * 60 * 1000,
				},
			}
			_G.Balances = {
				["recipient"] = 100000000,
			}
			local claimedName = primaryNames.claimPrimaryName("test", "recipient", 1234567890)
			assert.are.same({
				name = "test",
				startTimestamp = 1234567890,
			}, claimedName)
			assert.are.same({
				["recipient"] = { name = "test", startTimestamp = 1234567890 },
			}, _G.PrimaryNames)
			assert.are.equal(0, _G.Balances["recipient"])
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
			local primaryNamesForApexName = primaryNames.findPrimaryNamesForArNSName("test")
			assert.are.same({
				{ name = "test", owner = "owner3", startTimestamp = 1234567890 },
				{ name = "undername_test", owner = "owner", startTimestamp = 1234567890 },
				{ name = "undername2_test", owner = "owner2", startTimestamp = 1234567890 },
			}, primaryNamesForApexName)
		end)
	end)

	describe("removePrimaryNamesForArNSName", function()
		it("should remove all primary names with the given apex name", function()
			_G.PrimaryNames = {
				["owner"] = { name = "undername_test", startTimestamp = 1234567890 },
				["owner2"] = { name = "undername2_test", startTimestamp = 1234567890 },
				["owner3"] = { name = "test", startTimestamp = 1234567890 },
				["owner4"] = { name = "test2", startTimestamp = 1234567890 },
				["owner5"] = { name = "test3", startTimestamp = 1234567890 },
			}
			local removedNames = primaryNames.removePrimaryNamesForArNSName("test")
			assert.are.same({ "test", "undername_test", "undername2_test" }, removedNames)
			assert.are.same({
				["owner4"] = { name = "test2", startTimestamp = 1234567890 },
				["owner5"] = { name = "test3", startTimestamp = 1234567890 },
			}, _G.PrimaryNames)
		end)
	end)
end)
