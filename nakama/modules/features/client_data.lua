local nk = require("nakama")
local StaticData = require("core.static_data")
local Utilities = require("core.utilities")

local ClientData = {}

function ClientData.get_data_version(context, payload)
    local request = Utilities.parse_payload(payload)
    if not request then
        return nk.json_encode({error = "Invalid JSON payload"})
    end

    local data_type = request.type
    if not data_type then
        return nk.json_encode({error = "No type provided"})
    end

    local version = StaticData.versions_data[data_type]
    if not version then
        return nk.json_encode({error = "Version not found for type: " .. tostring(data_type)})
    end

    local response = {
        version = version,
        download_url = "http://127.0.0.1:8081/" .. data_type .. ".json"
    }

    return nk.json_encode(response)
end

function ClientData.get_game_data(context, payload)
    local request = Utilities.parse_payload(payload)
    if not request then
        return nk.json_encode({error = "Invalid JSON payload"})
    end

    local data_type = request.type or "all"

    if data_type == "core" then
        return nk.json_encode({
            units = StaticData.units_data,
            items = StaticData.items_data
        })
    elseif data_type == "map" then
        return nk.json_encode({
            worlds = StaticData.worlds_data,
            dungeons = StaticData.dungeons_data
        })
    else
        -- Fallback for older clients, but might exceed limits
        return nk.json_encode(StaticData.cached_game_data)
    end
end

function ClientData.get_dungeon_missions(context, payload)
    local request = Utilities.parse_payload(payload)
    if not request then
        return nk.json_encode({error = "Invalid JSON payload"})
    end
    local mission_ids = request.mission_ids or {}

    local result = {}
    for _, id in ipairs(mission_ids) do
        if StaticData.missions_data[tostring(id)] then
            result[tostring(id)] = StaticData.missions_data[tostring(id)]
        end
    end

    return nk.json_encode({missions = result})
end

function ClientData.get_mission_progress(context, payload)
    local object_ids = {
        {collection = "mission_progress", key = "cleared_missions", user_id = context.user_id}
    }
    local objects = nk.storage_read(object_ids)

    local cleared_missions = {}
    if #objects > 0 and objects[1].value then
        cleared_missions = objects[1].value
    end

    return nk.json_encode({cleared_missions = cleared_missions})
end

return ClientData
