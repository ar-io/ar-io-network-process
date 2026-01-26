--[[
	Updates the Logo to the new process logo ID.

	This patch ensures the global Logo variable is set to the updated logo ID
	for systems that may still have the old value.

	Reviewers: Dylan
]]
--
local constants = require(".src.constants")

constants.LOGO = "WMLnh8pQL-UIXZMpdU2NUIriHfcFB5Bc49V8jTHjsZc"

-- Update the global Logo to the new logo ID
Logo = constants.LOGO
