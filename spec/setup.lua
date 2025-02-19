package.path = "spec/?.lua;spec/?/init.lua;" .. package.path

_G.ao = {
	send = function(val)
		return val
	end,
	id = "test",
	env = {
		Process = {
			Id = "test",
			Owner = "test",
		},
	},
}

_G.Handlers = {
	utils = {
		reply = function()
			return true
		end,
	},
}

-- stash it in package.loaded under the name ".crypto.init"
-- so that any 'require(".crypto.init")' finds it:
_G.package.loaded[".crypto.init"] = require("crypto.init")

-- setup all process globals
require(".src.globals")

print("Setup global ao mocks successfully...")
