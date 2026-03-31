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

local cached_game_data = {
    units = read_json_file("/nakama/data/modules/data/units.json") or {},
    items = read_json_file("/nakama/data/modules/data/items.json") or {},
    weapons = read_json_file("/nakama/data/modules/data/weapons.json") or {}
}

local function get_game_data(context, payload)
    return nk.json_encode(cached_game_data)
end

nk.register_rpc(get_game_data, "get_game_data")
