local patch = {}

--- PatchedState
--- @class PatchedState
--- @field records table<string, Record> The records to patch
--- @field reservedNames table<string, ReservedName> The reserved names to patch
--- TODO: extend with other patches of state

--- Sends a patch message to the patch device with the given patched state
--- @param patchedState table The patched state to send
function patch.sendPatchMessage(patchedState)
	Send({
		device = "patch@1.0",
		cache = patchedState,
	})
end

--- Sends a patch message to the patch device with the given record for the given name
--- @param name string The name of the record to patch
--- @param record StoredRecord | nil The record to patch, or nil to remove the record from the cache
function patch.sendRecordPatch(name, record)
	patch.sendPatchMessage({
		records = {
			[name] = record,
		},
	})
end

-- TODO: add other patches
return patch
