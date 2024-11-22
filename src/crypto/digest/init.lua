local SHA2_256 = require(".crypto.digest.sha2_256")
local SHA3 = require(".crypto.digest.sha3")

local digest = {
	_version = "0.0.1",
	sha2_256 = SHA2_256.sha2_256,
	keccak256 = SHA3.keccak256,
}

return digest
