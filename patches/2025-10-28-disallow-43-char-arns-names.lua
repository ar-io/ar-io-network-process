--[[
	Disallow 43-character ARNS names to prevent Arweave address conflicts.

	ARNS names of exactly 43 characters conflict with Arweave addresses (ProcessIds)
	in sandboxed subdomain resolution, as Arweave addresses are always 43 characters.
	This creates ambiguity in the gateway sandbox system.

	Changes:
	- Add ARWEAVE_ADDRESS_LENGTH constants
	- Update arns.assertValidArNSName() to reject 43-character names
	- Valid name lengths remain: 1-42 and 44-51 characters

	Reviewers: Dylan, Ariel, Phil
]]
--

local constants = require(".src.constants")
local arns = require(".src.arns")

-- Add new constants for Arweave address length
constants.ARWEAVE_ADDRESS_LENGTH = 43 -- Arweave addresses (ProcessIds) are exactly 43 characters

-- Override the assertValidArNSName function to include the 43-character restriction
arns.assertValidArNSName = function(name)
	assert(name and type(name) == "string", "Name is required and must be a string.")
	assert(
		#name >= constants.MIN_NAME_LENGTH and #name <= constants.MAX_BASE_NAME_LENGTH,
		"Name length is invalid. Must be between "
			.. constants.MIN_NAME_LENGTH
			.. " and "
			.. constants.MAX_BASE_NAME_LENGTH
			.. " characters."
	)
	assert(
		#name ~= constants.ARWEAVE_ADDRESS_LENGTH,
		"Name cannot be "
			.. constants.ARWEAVE_ADDRESS_LENGTH
			.. " characters as it conflicts with Arweave address length."
	)
	if #name == 1 then
		assert(
			name:match(constants.ARNS_NAME_SINGLE_CHAR_REGEX),
			"Single-character name pattern for "
				.. name
				.. " is invalid. Must match "
				.. constants.ARNS_NAME_SINGLE_CHAR_REGEX
		)
	else
		assert(
			name:match(constants.ARNS_NAME_MULTICHARACTER_REGEX),
			"Name pattern for " .. name .. " is invalid. Must match " .. constants.ARNS_NAME_MULTICHARACTER_REGEX
		)
	end
end
