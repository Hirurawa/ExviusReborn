local nk = require("nakama")
local Utilities = require("core.utilities")

local StaticData = {}

StaticData.RankData = {}
StaticData.MaxRank = 1

local function parse_rank_exp_csv()
    local file_path = "data/rank-exp.csv"
    local success, content = pcall(nk.file_read, file_path)
    if not success or not content then
        nk.logger_warn("Could not open file: " .. file_path)
        return
    end

    local is_header = true
    for line in string.gmatch(content, "([^\n\r]+)") do
        if is_header then
            is_header = false
        else
            local rank, exp, energy, friend_slot = string.match(line, "^%s*(%d+)%s*,%s*([%d%-]+)%s*,%s*(%d+)%s*,%s*(%d+)%s*$")
            if rank then
                local exp_val = exp == "-" and 0 or tonumber(exp)
                local r = tonumber(rank)
                StaticData.RankData[r] = {
                    exp = exp_val,
                    energy = tonumber(energy),
                    friend_slot = tonumber(friend_slot)
                }
                if r > StaticData.MaxRank then
                    StaticData.MaxRank = r
                end
            end
        end
    end
end

-- Parse CSV globally at module load
parse_rank_exp_csv()

StaticData.units_data = Utilities.read_json_file("data/units.json") or {}
StaticData.items_data = Utilities.read_json_file("data/items.json") or {}
StaticData.equipment_data = Utilities.read_json_file("data/equipment.json") or {}
StaticData.worlds_data = Utilities.read_json_file("data/worlds.json") or {}
StaticData.dungeons_data = Utilities.read_json_file("data/dungeons.json") or {}
StaticData.missions_data = Utilities.read_json_file("data/missions.json") or {}
StaticData.versions_data = Utilities.read_json_file("data/versions.json") or {}

StaticData.unit_exp_patterns = Utilities.read_csv_file("data/unit-exp-pattern.csv") or {}

StaticData.cached_game_data = {
    units = StaticData.units_data,
    items = StaticData.items_data,
    worlds = StaticData.worlds_data,
    dungeons = StaticData.dungeons_data,
    missions = StaticData.missions_data
}

StaticData.rarity_max_levels = {
    [1] = 15,
    [2] = 30,
    [3] = 40,
    [4] = 60,
    [5] = 80,
    [6] = 100,
    [7] = 120
}

function StaticData.calculate_xp_for_level(level, exp_pattern)
    if level <= 1 then return 0 end
    if StaticData.unit_exp_patterns[exp_pattern] and StaticData.unit_exp_patterns[exp_pattern][level] then
        return StaticData.unit_exp_patterns[exp_pattern][level]
    end
    return 0
end

function StaticData.calculate_level_from_xp(xp, exp_pattern, max_level)
    if xp <= 0 then return 1 end

    local level = 1
    local total_xp_needed = 0

    if not StaticData.unit_exp_patterns[exp_pattern] then
        return level
    end

    for i = 2, max_level do
        local xp_needed = StaticData.unit_exp_patterns[exp_pattern][i] or 0
        total_xp_needed = total_xp_needed + xp_needed
        if xp >= total_xp_needed then
            level = i
        else
            break
        end
    end

    return level
end

function StaticData.calculate_total_xp_for_level(target_level, exp_pattern)
    local total = 0
    if not StaticData.unit_exp_patterns[exp_pattern] then return 0 end
    for i = 2, target_level do
        total = total + (StaticData.unit_exp_patterns[exp_pattern][i] or 0)
    end
    return total
end

return StaticData
