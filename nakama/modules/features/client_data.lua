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

    -- Reload versions on each call so newly added static types do not require a server restart.
    local latest_versions = Utilities.read_json_file("data/versions.json") or {}
    if latest_versions and next(latest_versions) ~= nil then
        StaticData.versions_data = latest_versions
    end

    local version = StaticData.versions_data[data_type]
    if not version then
        -- Graceful bootstrap path: if file exists but version key is missing, allow download with default version.
        local file_path = "data/" .. tostring(data_type) .. ".json"
        local has_file, file_content = pcall(nk.file_read, file_path)
        if has_file and file_content and file_content ~= "" then
            version = "v1.0.0"
            StaticData.versions_data[data_type] = version
            nk.logger_warn("Missing version for type '" .. tostring(data_type) .. "'. Falling back to v1.0.0")
        else
            return nk.json_encode({error = "Version not found for type: " .. tostring(data_type)})
        end
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
            items = StaticData.items_data,
            summons = StaticData.summons_data,
            summons_boards = StaticData.summons_boards_data
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
