local nk = require("nakama")

local function read_json_file(file_path)
    local success, content = pcall(nk.file_read, file_path)
    if not success or not content then
        nk.logger_warn("Could not open file: " .. file_path)
        return nil
    end

    local decode_success, decoded = pcall(nk.json_decode, content)
    if not decode_success then
        nk.logger_warn("Could not decode JSON from file: " .. file_path)
        return nil
    end

    return decoded
end

local units_data = read_json_file("/nakama/data/modules/data/units.json") or {}
local items_data = read_json_file("/nakama/data/modules/data/items.json") or {}
local weapons_data = read_json_file("/nakama/data/modules/data/weapons.json") or {}

nk.logger_info("Loaded units data size: " .. tostring(nk.json_encode(units_data):len()))

local cached_game_data = {
    units = units_data,
    items = items_data,
    weapons = weapons_data
}

local function get_game_data(context, payload)
    nk.logger_info("get_game_data RPC called. Returning: " .. nk.json_encode(cached_game_data))
    return nk.json_encode(cached_game_data)
end

nk.register_rpc(get_game_data, "get_game_data")
