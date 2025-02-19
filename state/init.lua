local state = {}

--[[
    To load any state, add raw lua files to this directory and require them here.
    When a Lua file is required, it is executed from top to bottom.
    Any global variables or functions defined will be available in the requiring scope.
]]
function state.init()
	print("Initializing state...")
	-- TODO: add reference state files
end

return state
