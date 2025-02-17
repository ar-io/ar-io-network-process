local primaryNames = require("primary_names")
local utils = require("utils")

describe("Primary Names", function()
	before_each(function()
		_G.PrimaryNames = {
			owners = {},
			names = {},
			requests = {},
		}
		_G.DemandFactor.currentDemandFactor = 1
		_G.Balances = {}
		_G.NameRegistry = {
			records = {},
		}
	end)

	describe("assertValidPrimaryName", function()
		local validPrimaryNames = {
			"1",
			"a",
			"1a",
			"1-1",
			"a-1",
			"1-a",
			("").rep("1", 51),
			("").rep("a", 51),
			-- undernames
			"1_test",
			"1234_test",
			"fsakdjhflkasjdhflkaf_test",
			("").rep("1", 61) .. "_t",
			("").rep("a", 61) .. "_t",
			"a_" .. ("").rep("1", 51),
			"9_" .. ("").rep("z", 51),
		}

		for _, primaryName in ipairs(validPrimaryNames) do
			it("should be a valid primary name", function()
				local status, res = pcall(primaryNames.assertValidPrimaryName, primaryName)

				assert(status == true, "Failed to validate name: " .. primaryName .. " error: " .. (res or ""))
			end)
		end

		local invalidPrimaryNames = {
			"%",
			"#",
			".",
			"()",
			"-",
			"_",
			"-_-",
			"_-_",
			"-a",
			"_a",
			"a-",
			"a_a_",
			"_a_a",
			("").rep("1", 62) .. "_t",
			"1_" .. ("").rep("a", 52),
		}
		for _, primaryName in ipairs(invalidPrimaryNames) do
			it("should be a assert primary name is invalid", function()
				local status, _ = pcall(primaryNames.assertValidPrimaryName, primaryName)

				assert(status == false, "Primary name " .. primaryName .. " incorrectly shows as valid")
			end)
		end
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
					startTimestamp = 0,
					processId = "base-name-owner",
					type = "lease",
					endTimestamp = 1234567890 + 30 * 24 * 60 * 60 * 1000,
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
				[[Primary name request by 'user-requesting-primary-name' for 'test' already exists]],
				err,
				nil,
				true
			)
		end)

		it("should fail if the arns record is in its grace period", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "base-name-owner",
					type = "lease",
					endTimestamp = 1234567890,
				},
			}
			local status, err = pcall(
				primaryNames.createPrimaryNameRequest,
				"test",
				"user-requesting-primary-name",
				-- Just after grace period starts
				1234567890 + 1,
				"test-msg-id"
			)
			assert.is_false(status)
			assert.match("ArNS record 'test' is not active", err)
		end)

		it(
			"should create a primary name request and transfer the cost from the initiator to the protocol balance",
			function()
				_G.Balances = {
					["user-requesting-primary-name"] = 10000000,
				}
				_G.NameRegistry.records = {
					["test"] = {
						startTimestamp = 0,
						processId = "processId",
						type = "lease",
						endTimestamp = 1234567890 + 30 * 24 * 60 * 60 * 1000,
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
						balance = 400000, -- cost should be the undername cost for 1 year on a 51 character name of the same type, against the current demand factor
						shortfall = 0,
						stakes = {},
					},
					fundingResult = {
						newWithdrawVaults = {},
						totalFunded = 400000,
					},
				}, primaryNameRequest)
				assert.are.equal(9600000, _G.Balances["user-requesting-primary-name"])
				assert.are.equal(400000, _G.Balances[ao.id])
			end
		)

		local validPrimaryUndernameNames = {
			"1_test",
			"1234_test",
			"fsakdjhflkasjdhflkaf_test",
			("").rep("1", 61) .. "_t",
			"a_" .. ("").rep("1", 51),
		}

		for _, primaryName in ipairs(validPrimaryUndernameNames) do
			it(
				"should create a primary name request with undername and transfer the cost from the initiator to the protocol balance",
				function()
					local baseName = utils.baseNameForName(primaryName)
					_G.Balances = {
						["user-requesting-primary-name"] = 10000000,
					}
					_G.NameRegistry.records = {
						[baseName] = {
							startTimestamp = 0,
							processId = "processId",
							type = "lease",
							endTimestamp = 1234567890 + 30 * 24 * 60 * 60 * 1000,
						},
					}
					local primaryNameRequest = primaryNames.createPrimaryNameRequest(
						primaryName,
						"user-requesting-primary-name",
						1234567890,
						"test-msg-id"
					)
					assert.are.same({
						request = {
							name = primaryName,
							startTimestamp = 1234567890,
							endTimestamp = 1234567890 + 7 * 24 * 60 * 60 * 1000,
						},
						baseNameOwner = "processId",
						fundingPlan = {
							address = "user-requesting-primary-name",
							balance = 400000, -- cost should be the undername cost for 1 year on a 51 character name of the same type, against the current demand factor
							shortfall = 0,
							stakes = {},
						},
						fundingResult = {
							newWithdrawVaults = {},
							totalFunded = 400000,
						},
					}, primaryNameRequest)
					assert.are.equal(9600000, _G.Balances["user-requesting-primary-name"])
					assert.are.equal(400000, _G.Balances[ao.id])
				end
			)
		end
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

		it("should remove the existing primary name if the recipient already has one and set the new one", function()
			_G.NameRegistry.records = {
				["test"] = {
					processId = "owning-process-id",
				},
			}
			_G.PrimaryNames = {
				owners = {
					["owner"] = { name = "test", startTimestamp = 1234567890 },
				},
				names = {
					["test"] = "owner",
				},
				requests = {
					["owner"] = {
						name = "new_test",
						startTimestamp = 1234567890,
						endTimestamp = 1234567890 + 30 * 24 * 60 * 60 * 1000,
					},
				},
			}
			primaryNames.approvePrimaryNameRequest("owner", "new_test", "owning-process-id", 1234567890)
			assert.are.same({
				name = "new_test",
				startTimestamp = 1234567890,
			}, _G.PrimaryNames.owners["owner"])
			assert.are.same(nil, _G.PrimaryNames.names["test"]) -- old name should be removed
			assert.are.same({}, _G.PrimaryNames.requests) -- request should be removed
			-- new primary name should be set
			assert.are.same({
				["owner"] = { name = "new_test", startTimestamp = 1234567890 },
			}, _G.PrimaryNames.owners)
			assert.are.same({
				["new_test"] = "owner",
			}, _G.PrimaryNames.names)
		end)
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
			_G.NameRegistry = {
				records = {
					["test"] = {
						processId = "base-name-owner",
					},
				},
			}
			assert.are.same(
				{ name = "test", owner = "owner", startTimestamp = 1234567890, processId = "base-name-owner" },
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
			_G.NameRegistry = {
				records = {
					["test"] = {
						processId = "base-name-owner",
					},
					["test2"] = {
						processId = "base-name-owner-2",
					},
					["test3"] = {
						processId = "base-name-owner-3",
					},
				},
			}
			local allPrimaryNamesForArNSName = primaryNames.getPrimaryNamesForBaseName("test")
			assert.are.same({
				{ name = "test", owner = "owner3", startTimestamp = 1234567890, processId = "base-name-owner" },

				{
					name = "undername_test",
					owner = "owner",
					startTimestamp = 1234567890,
					processId = "base-name-owner",
				},
				{
					name = "undername2_test",
					owner = "owner2",
					startTimestamp = 1234567890,
					processId = "base-name-owner",
				},
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
				["test2"] = {
					processId = "base-name-owner-2",
				},
				["test3"] = {
					processId = "base-name-owner-3",
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
			_G.NameRegistry = {
				records = {
					["test"] = {
						processId = "base-name-owner",
					},
				},
			}
			local paginatedPrimaryNames = primaryNames.getPaginatedPrimaryNames(nil, 10, "startTimestamp", "asc")
			assert.are.same({
				items = {
					{ name = "test", owner = "owner", startTimestamp = 1234567890, processId = "base-name-owner" },
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
