local nk = require("nakama")
local Utilities = require("core.utilities")

local Parties = {}

local function _build_default_parties()
    local default_parties = {}
    for i = 1, 5 do
        table.insert(default_parties, {
            name = "Party " .. i,
            units = {"", "", "", "", ""}
        })
    end
    return default_parties
end

local function _clamp_selected_party_index(selected_party_index, party_count)
    local parsed_index = tonumber(selected_party_index) or 0
    parsed_index = math.floor(parsed_index)
    if party_count <= 0 then
        return 0
    end
    if parsed_index < 0 then
        return 0
    end
    local max_index = party_count - 1
    if parsed_index > max_index then
        return max_index
    end
    return parsed_index
end

function Parties.rpc_get_parties(context, payload)
    local object_ids = {
        {
            collection = "user_data",
            key = "parties",
            user_id = context.user_id
        }
    }

    local objects = nk.storage_read(object_ids)

    if #objects == 0 then
        -- Initialize default parties
        local default_parties = _build_default_parties()
        local selected_party_index = 0

        nk.storage_write({
            {
                collection = "user_data",
                key = "parties",
                user_id = context.user_id,
                value = { parties = default_parties, selected_party_index = selected_party_index },
                permission_read = 1,
                permission_write = 1
            }
        })

        return nk.json_encode({ parties = default_parties, selected_party_index = selected_party_index })
    end

    local value = objects[1].value or {}
    local parties = value.parties
    local changed = false

    if type(parties) ~= "table" then
        parties = _build_default_parties()
        changed = true
    end

    local selected_party_index = _clamp_selected_party_index(value.selected_party_index, #parties)
    if value.selected_party_index ~= selected_party_index then
        changed = true
    end

    if changed then
        nk.storage_write({
            {
                collection = "user_data",
                key = "parties",
                user_id = context.user_id,
                value = { parties = parties, selected_party_index = selected_party_index },
                permission_read = 1,
                permission_write = 1
            }
        })
    end

    return nk.json_encode({ parties = parties, selected_party_index = selected_party_index })
end

function Parties.rpc_save_parties(context, payload)
    local request = Utilities.parse_payload(payload)
    if not request then
        return nk.json_encode({error = "Invalid JSON payload"})
    end

    if type(request.parties) ~= "table" then
        return nk.json_encode({error = "Missing 'parties' field in payload"})
    end

    local selected_party_index = _clamp_selected_party_index(request.selected_party_index, #request.parties)

    nk.storage_write({
        {
            collection = "user_data",
            key = "parties",
            user_id = context.user_id,
            value = { parties = request.parties, selected_party_index = selected_party_index },
            permission_read = 1,
            permission_write = 1
        }
    })

    return nk.json_encode({ success = true, parties = request.parties, selected_party_index = selected_party_index })
end

return Parties
