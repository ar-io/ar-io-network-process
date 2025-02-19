local process = { name = "ARIO", version = "1.0.0" }

-- load all the code related to the process

require(".src.init").init()
require(".state.init") -- load any desired state files

return process
