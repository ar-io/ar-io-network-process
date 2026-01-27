--[[
    Updates the hyperbeam patch message for primary names to use PrimaryNameInfo for the owners mapping
    to allow for sdk compatible lookups on hyperbeam.

	Reviewers: Dylan, Ariel, Atticus
]]
--

_G.package.loaded[".src.hb"].createPrimaryNamesPatch = function()
	local primaryNames = require(".src.primary_names")
	---@type {names: table<string, string>, owners: table<string, PrimaryNameInfo>, requests: table<string, table<string, string>>}
	local affectedPrimaryNamesAddresses = {
		names = {},
		---@type table<string, PrimaryNameInfo>
		owners = {},
		requests = {},
	}

	-- if no changes, return early. This will allow downstream code to not send the patch state for this key ('primary-names')
	if
		next(_G.HyperbeamSync.primaryNames.names) == nil
		and next(_G.HyperbeamSync.primaryNames.owners) == nil
		and next(_G.HyperbeamSync.primaryNames.requests) == nil
	then
		return nil
	end

	-- build the affected primary names addresses table for the patch message
	for name, _ in pairs(_G.HyperbeamSync.primaryNames.names) do
		-- we need to send an empty string to remove the name
		affectedPrimaryNamesAddresses.names[name] = PrimaryNames.names[name] or ""
	end
	for owner, _ in pairs(_G.HyperbeamSync.primaryNames.owners) do
		-- we need to send an empty table to remove the owner primary name data
		affectedPrimaryNamesAddresses.owners[owner] = primaryNames.getPrimaryNameDataWithOwnerFromAddress(owner) or {}
	end
	for address, _ in pairs(_G.HyperbeamSync.primaryNames.requests) do
		-- we need to send an empty table to remove the request
		affectedPrimaryNamesAddresses.requests[address] = PrimaryNames.requests[address] or {}
	end

	-- Setting the property to {} will nuke the entire table from patch device state
	-- We do this because we want to remove the entire table from patch device state if it's empty
	if next(PrimaryNames.names) == nil then
		affectedPrimaryNamesAddresses.names = {}
	-- setting the property to nil will remove it from the patch message entirely to avoid sending an empty table and nuking patch device state
	-- We do this to AVOID sending an empty table and nuking patch device state if our lua state is not empty.
	elseif next(affectedPrimaryNamesAddresses.names) == nil then
		affectedPrimaryNamesAddresses.names = nil
	end

	if next(PrimaryNames.owners) == nil then
		affectedPrimaryNamesAddresses.owners = {}
	elseif next(affectedPrimaryNamesAddresses.owners) == nil then
		affectedPrimaryNamesAddresses.owners = nil
	end

	if next(PrimaryNames.requests) == nil then
		affectedPrimaryNamesAddresses.requests = {}
	elseif next(affectedPrimaryNamesAddresses.requests) == nil then
		affectedPrimaryNamesAddresses.requests = nil
	end

	-- if we're not sending any data, return nil which will allow downstream code to not send the patch message
	-- We do this to AVOID sending an empty table and nuking patch device state if our lua state is not empty.
	if next(affectedPrimaryNamesAddresses) == nil then
		return nil
	end

	return affectedPrimaryNamesAddresses
end
