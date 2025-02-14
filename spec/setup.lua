package.path = "./src/?.lua;" .. package.path

_G.ao = {
	send = function(val)
		return val
	end,
	id = "test",
}

_G.Handlers = {
	utils = {
		reply = function()
			return true
		end,
	},
}

print("Setup global ao mocks successfully...")
