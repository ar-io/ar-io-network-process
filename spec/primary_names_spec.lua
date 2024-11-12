local primaryNames = require("primary_names")

describe("Primary Names", function()
	before_each(function()
		_G.PrimaryNames = {
			owners = {},
			names = {},
			claims = {},
		}
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
				owners = {
					["owner"] = {
						name = "test",
						startTimestamp = 1234567890,
					},
				},
				names = {
					["test"] = "owner",
				},
				claims = {},
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
				initiator = "processId",
				baseName = "test",
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
			_G.PrimaryNames.claims = {
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
			_G.PrimaryNames.claims = {
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
			_G.PrimaryNames.claims = {
				["test"] = {
					name = "test",
					recipient = "recipient",
					baseName = "test",
					initiator = "processId",
					startTimestamp = 1234567890,
					endTimestamp = 1234567890 + 30 * 24 * 60 * 60 * 1000,
				},
			}
			_G.Balances = {
				["recipient"] = 100000000,
			}
			local claimedNameAndOwner = primaryNames.claimPrimaryName("test", "recipient", 1234567890)
			assert.are.same({
				primaryName = {
					name = "test",
					owner = "recipient",
					startTimestamp = 1234567890,
					baseName = "test",
				},
				claim = {
					name = "test",
					recipient = "recipient",
					startTimestamp = 1234567890,
					baseName = "test",
					initiator = "processId",
					endTimestamp = 1234567890 + 30 * 24 * 60 * 60 * 1000,
				},
			}, claimedNameAndOwner)
			assert.are.same({
				["recipient"] = { name = "test", startTimestamp = 1234567890, baseName = "test" },
			}, _G.PrimaryNames.owners)
			assert.are.same({
				["test"] = "recipient",
			}, _G.PrimaryNames.names)
			assert.are.equal(0, _G.Balances["recipient"])
		end)
	end)

	describe("getAddressForPrimaryName", function()
		it("should return nil if the name is not owned", function()
			assert.is_nil(primaryNames.getAddressForPrimaryName("test"))
		end)

		it("should return the owner if the name is owned", function()
			_G.PrimaryNames = {
				owners = {
					["owner"] = { name = "test", startTimestamp = 1234567890, baseName = "test" },
				},
				names = {
					["test"] = "owner",
				},
			}
			assert.are.same("owner", primaryNames.getAddressForPrimaryName("test"))
		end)
	end)

	describe("releasePrimaryName", function()
		it("should fail if the caller is not the owner of the primary name", function()
			local status, err = pcall(primaryNames.releasePrimaryName, "test", "owner")
			assert.is_false(status)
			assert.match("Caller is not the owner of the primary name", err)
		end)

		it("should release the primary name", function()
			_G.PrimaryNames = {
				owners = {
					["owner"] = { name = "test", startTimestamp = 1234567890 },
				},
				names = {
					["test"] = "owner",
				},
				claims = {},
			}
			local releasedNameAndOwner = primaryNames.releasePrimaryName("test", "owner")
			assert.are.same(nil, _G.PrimaryNames.owners["owner"])
			assert.are.same(nil, _G.PrimaryNames.names["test"])
			assert.are.same({
				releasedName = {
					name = "test",
					startTimestamp = 1234567890,
				},
				releasedOwner = "owner",
			}, releasedNameAndOwner)
		end)
	end)

	describe("getPrimaryNameDataWithOwnerFromAddress", function()
		it("should return nil if the name is not owned", function()
			assert.is_nil(primaryNames.getPrimaryNameDataWithOwnerFromAddress("test"))
		end)

		it("should return the primary name if the name is owned", function()
			_G.PrimaryNames = {
				owners = {
					["owner"] = { name = "test", startTimestamp = 1234567890, baseName = "test" },
				},
				names = {
					["test"] = "owner",
				},
			}
			assert.are.same(
				{ name = "test", owner = "owner", startTimestamp = 1234567890, baseName = "test" },
				primaryNames.getPrimaryNameDataWithOwnerFromAddress("owner")
			)
		end)
	end)

	describe("findPrimaryNamesForBaseName", function()
		it("should return all primary names with the given apex name", function()
			_G.PrimaryNames = {
				owners = {
					["owner"] = { name = "undername_test", startTimestamp = 1234567890, baseName = "test" },
					["owner2"] = { name = "undername2_test", startTimestamp = 1234567890, baseName = "test" },
					["owner3"] = { name = "test", startTimestamp = 1234567890, baseName = "test" },
					["owner4"] = { name = "test2", startTimestamp = 1234567890, baseName = "test2" },
					["owner5"] = { name = "test3", startTimestamp = 1234567890, baseName = "test3" },
				},
				names = {
					["test"] = "owner3",
					["undername_test"] = "owner",
					["undername2_test"] = "owner2",
					["test2"] = "owner4",
					["test3"] = "owner5",
				},
			}
			local allPrimaryNamesForArNSName = primaryNames.findPrimaryNamesForBaseName("test")
			assert.are.same({
				{ name = "test", owner = "owner3", startTimestamp = 1234567890, baseName = "test" },
				{ name = "undername_test", owner = "owner", startTimestamp = 1234567890, baseName = "test" },
				{ name = "undername2_test", owner = "owner2", startTimestamp = 1234567890, baseName = "test" },
			}, allPrimaryNamesForArNSName)
		end)
	end)

	describe("removePrimaryNamesForBaseName", function()
		it("should remove all primary names with the given apex name", function()
			_G.PrimaryNames = {
				owners = {
					["owner"] = { name = "undername_test", startTimestamp = 1234567890, baseName = "test" },
					["owner2"] = { name = "undername2_test", startTimestamp = 1234567890, baseName = "test" },
					["owner3"] = { name = "test", startTimestamp = 1234567890, baseName = "test" },
					["owner4"] = { name = "test2", startTimestamp = 1234567890, baseName = "test2" },
					["owner5"] = { name = "test3", startTimestamp = 1234567890, baseName = "test3" },
				},
				names = {
					["test"] = "owner3",
					["undername_test"] = "owner",
					["undername2_test"] = "owner2",
					["test2"] = "owner4",
					["test3"] = "owner5",
				},
				claims = {},
			}
			local removedNamesAndOwners = primaryNames.removePrimaryNamesForBaseName("test")
			assert.are.same({
				owner = "owner3",
				name = "test",
			}, removedNamesAndOwners[1])
			assert.are.same({
				owner = "owner",
				name = "undername_test",
			}, removedNamesAndOwners[2])
			assert.are.same({
				owner = "owner2",
				name = "undername2_test",
			}, removedNamesAndOwners[3])
			assert.are.same({
				owners = {
					["owner4"] = { name = "test2", startTimestamp = 1234567890, baseName = "test2" },
					["owner5"] = { name = "test3", startTimestamp = 1234567890, baseName = "test3" },
				},
				names = {
					["test2"] = "owner4",
					["test3"] = "owner5",
				},
				claims = {},
			}, _G.PrimaryNames)
		end)
	end)
end)
