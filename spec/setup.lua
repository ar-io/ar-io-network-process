package.path = "./src/?.lua;" .. package.path

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

-- setup all process globals
require(".src.globals")

print("Setup global ao mocks successfully...")
