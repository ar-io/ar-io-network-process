--[[
	Adds www to the reserved names list.

	Reviewers: Jonathon, Ariel, Phil, Dylan
]]
--

-- confirm name registry and name registry reserved are not nil
if not NameRegistry or not NameRegistry.reserved then
	error("NameRegistry or NameRegistry.reserved is nil")
end

-- add www to the reserved names list
NameRegistry.reserved["www"] = {}
