local nk = require("nakama")
local Utilities = require("core.utilities")

local CombatItems = {}

function CombatItems.rpc_get_combat_items(context, payload)
	local object_ids = {
		{
			collection = "user_data",
			key = "combat_items",
			user_id = context.user_id
		}
	}

	local objects = nk.storage_read(object_ids)

	if #objects == 0 then
		-- Initialize default empty slots
		local default_slots = {"", "", "", "", "", "", "", "", "", ""}

		nk.storage_write({
			{
				collection = "user_data",
				key = "combat_items",
				user_id = context.user_id,
				value = { slots = default_slots },
				permission_read = 1,
				permission_write = 1
			}
		})

		return nk.json_encode({ slots = default_slots })
	end

	local value = objects[1].value or {}
	local slots = value.slots or {"", "", "", "", "", "", "", "", "", ""}

	return nk.json_encode({ slots = slots })
end

function CombatItems.rpc_save_combat_items(context, payload)
	local request = Utilities.parse_payload(payload)
	if not request then
		return nk.json_encode({error = "Invalid JSON payload"})
	end

	if type(request.slots) ~= "table" then
		return nk.json_encode({error = "Missing 'slots' field in payload"})
	end

	nk.storage_write({
		{
			collection = "user_data",
			key = "combat_items",
			user_id = context.user_id,
			value = { slots = request.slots },
			permission_read = 1,
			permission_write = 1
		}
	})

	return nk.json_encode({ success = true, slots = request.slots })
end

return CombatItems
