local primaryNames = require("primary_names")

describe("Primary Names", function()
	before_each(function()
		_G.PrimaryNames = {
			owners = {},
			names = {},
			requests = {},
		}
		_G.Balances = {}
		_G.NameRegistry = {
			records = {},
		}
	end)

	describe("createPrimaryNameRequest", function()
		it("should fail if the arns record does not exist for the name", function()
			local status, err =
				pcall(primaryNames.createPrimaryNameRequest, "test", "processId", 1234567890, "test-msg-id")
			assert.is_false(status)
			assert.match("ArNS record 'test' does not exist", err)
		end)

		it("should fail if the caller does not have a balance", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "base-name-owner",
				},
			}
			_G.Balances = {
				["user-requesting-primary-name"] = 0,
			}
			local status, err = pcall(
				primaryNames.createPrimaryNameRequest,
				"test",
				"user-requesting-primary-name",
				1234567890,
				"test-msg-id"
			)
			assert.is_false(status)
			assert.match("Insufficient balance", err)
		end)

		it("should fail if the primary name is already owned", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "base-name-owner",
				},
			}
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
				requests = {},
			}
			local status, err = pcall(
				primaryNames.createPrimaryNameRequest,
				"test",
				"user-requesting-	primary-name",
				1234567890,
				"test-msg-id"
			)
			assert.is_false(status)
			assert.match("Primary name is already owned", err)
		end)

		it("should fail if the caller already has a primary name request for the same name", function()
			_G.PrimaryNames.requests = {
				["user-requesting-primary-name"] = { name = "test", startTimestamp = 1234567890 },
			}
			local status, err = pcall(
				primaryNames.createPrimaryNameRequest,
				"test",
				"user-requesting-primary-name",
				1234567890,
				"test-msg-id"
			)
			assert.is_false(status)
			assert.match(
				"Primary name request for '"
					.. "user-requesting-primary-name"
					.. "' for '"
					.. "test"
					.. "' already exists",
				err,
				nil,
				true
			)
		end)

		it(
			"should create a primary name request and transfer the cost from the initiator to the protocol balance",
			function()
				_G.Balances = {
					["user-requesting-primary-name"] = 100000000,
				}
				_G.NameRegistry.records = {
					["test"] = {
						processId = "processId",
					},
				}
				local primaryNameRequest = primaryNames.createPrimaryNameRequest(
					"test",
					"user-requesting-primary-name",
					1234567890,
					"test-msg-id"
				)
				assert.are.same({
					request = {
						name = "test",
						startTimestamp = 1234567890,
						endTimestamp = 1234567890 + 7 * 24 * 60 * 60 * 1000,
					},
					baseNameOwner = "processId",
					fundingPlan = {
						address = "user-requesting-primary-name",
						balance = 100000000,
						shortfall = 0,
						stakes = {},
					},
					fundingResult = {
						newWithdrawVaults = {},
						totalFunded = 100000000,
					},
				}, primaryNameRequest)
				assert.are.equal(0, _G.Balances["user-requesting-primary-name"])
				assert.are.equal(100000000, _G.Balances[ao.id])
			end
		)
	end)

	describe("approvePrimaryNameRequest", function()
		it("should fail if the primary name request does not exist", function()
			local status, err =
				pcall(primaryNames.approvePrimaryNameRequest, "primary-name-recipient", "test", "owner", 1234567890)
			assert.is_false(status)
			assert.match("Primary name request not found", err)
		end)

		it("should fail if the primary name request has expired", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "owner",
				},
			}
			_G.PrimaryNames.requests = {
				["primary-name-recipient"] = {
					name = "test",
					startTimestamp = 1234567890,
					endTimestamp = 1234567890 - 1,
				},
			}
			local status, err =
				pcall(primaryNames.approvePrimaryNameRequest, "primary-name-recipient", "test", "owner", 1234567890)
			assert.is_false(status)
			assert.match("Primary name request has expired", err)
		end)

		it(
			"should approve the primary name request and set the primary name in both the owners and names tables",
			function()
				_G.NameRegistry.records = {
					["test"] = {
						processId = "owner",
					},
				}
				_G.PrimaryNames.requests = {
					["primary-name-recipient"] = {
						name = "test",
						startTimestamp = 1234567890,
						endTimestamp = 1234567890 + 30 * 24 * 60 * 60 * 1000,
					},
				}
				local approvePrimaryNameRequestResult =
					primaryNames.approvePrimaryNameRequest("primary-name-recipient", "test", "owner", 1234567890)
				assert.are.same({
					newPrimaryName = {
						name = "test",
						owner = "primary-name-recipient",
						startTimestamp = 1234567890,
					},
					request = {
						endTimestamp = 1234567890 + 30 * 24 * 60 * 60 * 1000,
						name = "test",
						startTimestamp = 1234567890,
					},
				}, approvePrimaryNameRequestResult)
				assert.are.same({
					["primary-name-recipient"] = { name = "test", startTimestamp = 1234567890 },
				}, _G.PrimaryNames.owners)
				assert.are.same({
					["test"] = "primary-name-recipient",
				}, _G.PrimaryNames.names)
			end
		)
	end)

	describe("getAddressForPrimaryName", function()
		it("should return nil if the name is not owned", function()
			assert.is_nil(primaryNames.getAddressForPrimaryName("test"))
		end)

		it("should return the owner if the name is owned", function()
			_G.PrimaryNames = {
				owners = {
					["owner"] = { name = "test", startTimestamp = 1234567890 },
				},
				names = {
					["test"] = "owner",
				},
			}
			assert.are.same("owner", primaryNames.getAddressForPrimaryName("test"))
		end)
	end)

	describe("removePrimaryName", function()
		it("should fail if the primary name does not exist", function()
			local status, err = pcall(primaryNames.removePrimaryName, "test", "owner")
			assert.is_false(status)
			assert.match("Primary name 'test' does not exist", err)
		end)

		it("should fail if the caller is not the owner of the primary name or the owner of the base name", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "base-name-owner",
				},
			}
			_G.PrimaryNames = {
				owners = {
					["owner"] = { name = "test", startTimestamp = 1234567890 },
				},
				names = {
					["test"] = "owner",
				},
			}
			local status, err = pcall(primaryNames.removePrimaryName, "test", "owner2")
			assert.is_false(status)
			assert.match("Caller is not the owner of the primary name", err)
		end)

		it("should remove the primary name when the caller is the owner of the primary name", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "base-name-owner",
				},
			}
			_G.PrimaryNames = {
				owners = {
					["owner"] = { name = "test", startTimestamp = 1234567890 },
				},
				names = {
					["test"] = "owner",
				},
				requests = {},
			}
			local releasedNameAndOwner = primaryNames.removePrimaryName("test", "owner")
			assert.are.same(nil, _G.PrimaryNames.owners["owner"])
			assert.are.same(nil, _G.PrimaryNames.names["test"])
			assert.are.same({
				name = "test",
				owner = "owner",
			}, releasedNameAndOwner)
		end)

		it("should remove the primary name when the caller is the owner of the base name", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "base-name-owner",
				},
			}
			_G.PrimaryNames = {
				owners = {
					["owner"] = { name = "test", startTimestamp = 1234567890 },
				},
				names = {
					["test"] = "owner",
				},
				requests = {},
			}
			local removedNameAndOwner = primaryNames.removePrimaryName("test", "base-name-owner")
			assert.are.same(nil, _G.PrimaryNames.owners["owner"])
			assert.are.same(nil, _G.PrimaryNames.names["test"])
			assert.are.same({
				name = "test",
				owner = "owner",
			}, removedNameAndOwner)
		end)
	end)

	describe("getPrimaryNameDataWithOwnerFromAddress", function()
		it("should return nil if the name is not owned", function()
			assert.is_nil(primaryNames.getPrimaryNameDataWithOwnerFromAddress("test"))
		end)

		it("should return the primary name if the name is owned", function()
			_G.PrimaryNames = {
				owners = {
					["owner"] = { name = "test", startTimestamp = 1234567890 },
				},
				names = {
					["test"] = "owner",
				},
			}
			assert.are.same(
				{ name = "test", owner = "owner", startTimestamp = 1234567890 },
				primaryNames.getPrimaryNameDataWithOwnerFromAddress("owner")
			)
		end)
	end)

	describe("getPrimaryNamesForBaseName", function()
		it("should return all primary names with the given base  name", function()
			_G.PrimaryNames = {
				owners = {
					["owner"] = { name = "undername_test", startTimestamp = 1234567890 },
					["owner2"] = { name = "undername2_test", startTimestamp = 1234567890 },
					["owner3"] = { name = "test", startTimestamp = 1234567890 },
					["owner4"] = { name = "test2", startTimestamp = 1234567890 },
					["owner5"] = { name = "test3", startTimestamp = 1234567890 },
				},
				names = {
					["test"] = "owner3",
					["undername_test"] = "owner",
					["undername2_test"] = "owner2",
					["test2"] = "owner4",
					["test3"] = "owner5",
				},
			}
			local allPrimaryNamesForArNSName = primaryNames.getPrimaryNamesForBaseName("test")
			assert.are.same({
				{ name = "test", owner = "owner3", startTimestamp = 1234567890 },
				{ name = "undername_test", owner = "owner", startTimestamp = 1234567890 },
				{ name = "undername2_test", owner = "owner2", startTimestamp = 1234567890 },
			}, allPrimaryNamesForArNSName)
		end)
	end)

	describe("removePrimaryNames", function()
		it("should remove all primary names for the given names when from is owner of the base name", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "base-name-owner",
				},
			}
			_G.PrimaryNames = {
				owners = {
					["primary-name-owner"] = { name = "test", startTimestamp = 1234567890 },
					["primary-name-owner2"] = {
						name = "undername_test",
						startTimestamp = 1234567890,
					},
					["primary-name-owner3"] = {
						name = "undername2_test",
						startTimestamp = 1234567890,
					},
				},
				names = {
					["test"] = "primary-name-owner",
					["undername_test"] = "primary-name-owner2",
					["undername2_test"] = "primary-name-owner3",
				},
				requests = {},
			}
			local removedPrimaryNamesAndOwners =
				primaryNames.removePrimaryNames({ "test", "undername_test", "undername2_test" }, "base-name-owner")
			assert.are.same({
				{ name = "test", owner = "primary-name-owner" },
				{ name = "undername_test", owner = "primary-name-owner2" },
				{ name = "undername2_test", owner = "primary-name-owner3" },
			}, removedPrimaryNamesAndOwners)
			assert.are.same({
				owners = {},
				names = {},
				requests = {},
			}, _G.PrimaryNames)
		end)
	end)

	describe("removePrimaryNamesForBaseName", function()
		it("should remove all primary names with the given base  name", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "base-name-owner",
				},
			}
			_G.PrimaryNames = {
				owners = {
					["owner"] = { name = "undername_test", startTimestamp = 1234567890 },
					["owner2"] = { name = "undername2_test", startTimestamp = 1234567890 },
					["owner3"] = { name = "test", startTimestamp = 1234567890 },
					["owner4"] = { name = "test2", startTimestamp = 1234567890 },
					["owner5"] = { name = "test3", startTimestamp = 1234567890 },
				},
				names = {
					["test"] = "owner3",
					["undername_test"] = "owner",
					["undername2_test"] = "owner2",
					["test2"] = "owner4",
					["test3"] = "owner5",
				},
				requests = {},
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
					["owner4"] = { name = "test2", startTimestamp = 1234567890 },
					["owner5"] = { name = "test3", startTimestamp = 1234567890 },
				},
				names = {
					["test2"] = "owner4",
					["test3"] = "owner5",
				},
				requests = {},
			}, _G.PrimaryNames)
		end)
	end)

	describe("getPaginatedPrimaryNames", function()
		it("should return all primary names", function()
			_G.PrimaryNames = {
				owners = {
					["owner"] = { name = "test", startTimestamp = 1234567890 },
				},
				names = {
					["test"] = "owner",
				},
				requests = {},
			}
			local paginatedPrimaryNames = primaryNames.getPaginatedPrimaryNames(nil, 10, "startTimestamp", "asc")
			assert.are.same({
				items = {
					{ name = "test", owner = "owner", startTimestamp = 1234567890 },
				},
				totalItems = 1,
				limit = 10,
				hasMore = false,
				sortBy = "startTimestamp",
				sortOrder = "asc",
			}, paginatedPrimaryNames)
		end)
	end)

	describe("getPaginatedPrimaryNameRequests", function()
		it("should return all primary name requests", function()
			_G.PrimaryNames.requests = {
				["initiator1"] = {
					name = "test",
					startTimestamp = 1234567890,
					endTimestamp = 1234567890 + 30 * 24 * 60 * 60 * 1000,
				},
			}
			local paginatedPrimaryNameRequests =
				primaryNames.getPaginatedPrimaryNameRequests(nil, 10, "startTimestamp", "asc")
			assert.are.same({
				items = {
					{
						name = "test",
						startTimestamp = 1234567890,
						endTimestamp = 1234567890 + 30 * 24 * 60 * 60 * 1000,
						initiator = "initiator1",
					},
				},
				totalItems = 1,
				limit = 10,
				hasMore = false,
				sortBy = "startTimestamp",
				sortOrder = "asc",
			}, paginatedPrimaryNameRequests)
		end)
	end)
end)
