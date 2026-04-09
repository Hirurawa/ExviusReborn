local nk = require("nakama")

local RankData = {}
local MaxRank = 1

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
                RankData[r] = {
                    exp = exp_val,
                    energy = tonumber(energy),
                    friend_slot = tonumber(friend_slot)
                }
                if r > MaxRank then
                    MaxRank = r
                end
            end
        end
    end
end

-- Parse CSV globally at module load
parse_rank_exp_csv()

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

local units_data = read_json_file("data/units.json") or {}
local items_data = read_json_file("data/items.json") or {}
local equipment_data = read_json_file("data/equipment.json") or {}
local worlds_data = read_json_file("data/worlds.json") or {}
local dungeons_data = read_json_file("data/dungeons.json") or {}
local missions_data = read_json_file("data/missions.json") or {}
local versions_data = read_json_file("data/versions.json") or {}

local function read_csv_file(file_path)
    local success, content = pcall(nk.file_read, file_path)
    if not success or not content then
        nk.logger_warn("Could not open file: " .. file_path)
        return nil
    end

    local lines = {}
    for str in string.gmatch(content, "([^\r\n]+)") do
        table.insert(lines, str)
    end
    
    if #lines == 0 then return nil end

    local headers = {}
    for str in string.gmatch(lines[1], "([^,]+)") do
        table.insert(headers, str)
    end

    local data = {}
    local col_map = {}
    for i, header in ipairs(headers) do
        local gr = header:match("Gr (%d+)")
        if gr then
            col_map[i] = tonumber(gr)
            data[col_map[i]] = {}
        end
    end

    for i = 2, #lines do
        local line = lines[i]
        local cols = {}
        -- Need a custom split to handle empty fields like "-,-"
        local col_idx = 1
        local current_col = ""
        for char_idx = 1, #line do
            local char = line:sub(char_idx, char_idx)
            if char == "," then
                table.insert(cols, current_col)
                current_col = ""
                col_idx = col_idx + 1
            else
                current_col = current_col .. char
            end
        end
        table.insert(cols, current_col)
        
        local level = tonumber(cols[1])
        if level then
            for idx, col_val in ipairs(cols) do
                local gr = col_map[idx]
                if gr then
                    local val = tonumber(col_val) or 0
                    data[gr][level] = val
                end
            end
        end
    end

    return data
end

local unit_exp_patterns = read_csv_file("data/unit-exp-pattern.csv") or {}

local cached_game_data = {
    units = units_data,
    items = items_data,
    worlds = worlds_data,
    dungeons = dungeons_data,
    missions = missions_data
}


local function get_data_version(context, payload)
    local request = {}
    if payload and payload ~= "" then
        pcall(function() request = nk.json_decode(payload) end)
    end

    local data_type = request.type
    if not data_type then
        return nk.json_encode({error = "No type provided"})
    end

    local version = versions_data[data_type]
    if not version then
        return nk.json_encode({error = "Version not found for type: " .. tostring(data_type)})
    end

    local response = {
        version = version,
        download_url = "http://127.0.0.1:8081/" .. data_type .. ".json"
    }

    return nk.json_encode(response)
end

nk.register_rpc(get_data_version, "get_data_version")


local function get_game_data(context, payload)
    local request = {}
    if payload and payload ~= "" then
        pcall(function() request = nk.json_decode(payload) end)
    end

    local data_type = request.type or "all"
    
    if data_type == "core" then
        return nk.json_encode({
            units = units_data,
            items = items_data
        })
    elseif data_type == "map" then
        return nk.json_encode({
            worlds = worlds_data,
            dungeons = dungeons_data
        })
    else
        -- Fallback for older clients, but might exceed limits
        return nk.json_encode(cached_game_data)
    end
end

nk.register_rpc(get_game_data, "get_game_data")

local function get_dungeon_missions(context, payload)
    local request = nk.json_decode(payload)
    local mission_ids = request.mission_ids or {}

    local result = {}
    for _, id in ipairs(mission_ids) do
        if missions_data[tostring(id)] then
            result[tostring(id)] = missions_data[tostring(id)]
        end
    end

    return nk.json_encode({missions = result})
end

nk.register_rpc(get_dungeon_missions, "get_dungeon_missions")

local rarity_max_levels = {
    [1] = 15,
    [2] = 30,
    [3] = 40,
    [4] = 60,
    [5] = 80,
    [6] = 100,
    [7] = 120
}

local function calculate_xp_for_level(level, exp_pattern)
    if level <= 1 then return 0 end
    if unit_exp_patterns[exp_pattern] and unit_exp_patterns[exp_pattern][level] then
        return unit_exp_patterns[exp_pattern][level]
    end
    return 0
end

local function calculate_level_from_xp(xp, exp_pattern, max_level)
    if xp <= 0 then return 1 end

    local level = 1
    local total_xp_needed = 0
    
    if not unit_exp_patterns[exp_pattern] then
        return level
    end

    for i = 2, max_level do
        local xp_needed = unit_exp_patterns[exp_pattern][i] or 0
        total_xp_needed = total_xp_needed + xp_needed
        if xp >= total_xp_needed then
            level = i
        else
            break
        end
    end

    return level
end

local function calculate_total_xp_for_level(target_level, exp_pattern)
    local total = 0
    if not unit_exp_patterns[exp_pattern] then return 0 end
    for i = 2, target_level do
        total = total + (unit_exp_patterns[exp_pattern][i] or 0)
    end
    return total
end

local function get_player_units(user_id)
    local object_ids = {
        {collection = "units", key = "player_units", user_id = user_id}
    }
    local objects = nk.storage_read(object_ids)

    if #objects > 0 then
        local data = objects[1].value
        if data and data.units then
            -- Inject next_xp if it's missing or needs recalculation based on up-to-date data
            for _, unit in ipairs(data.units) do
                local unit_data = units_data[unit.unit_id]
                if unit_data then
                    local exp_pattern = unit_data.exp_pattern or 5
                    local max_level = rarity_max_levels[unit.current_rarity] or 15
                    if unit.level < max_level then
                        local base_xp = calculate_total_xp_for_level(unit.level, exp_pattern)
                        local xp_into_level = unit.xp - base_xp
                        local required_marginal_xp = calculate_xp_for_level(unit.level + 1, exp_pattern)
                        unit.next_xp = required_marginal_xp - xp_into_level
                        if unit.next_xp < 0 then unit.next_xp = 0 end
                    else
                        unit.next_xp = 0
                    end
                end
            end
            return data.units
        end
    end

    return {}
end

local function get_player_units_rpc(context, payload)
    local units = get_player_units(context.user_id)
    return nk.json_encode({units = units})
end

nk.register_rpc(get_player_units_rpc, "get_player_units")


local function save_player_units(user_id, units)
    local objects = {
        {
            collection = "units",
            key = "player_units",
            user_id = user_id,
            value = {units = units},
            permission_read = 1,
            permission_write = 1
        }
    }
    nk.storage_write(objects)
end

local function summon_units(context, payload)
    local request = nk.json_decode(payload)
    local amount = request.amount or 1

    local available_unit_ids = {}
    for id, _ in pairs(units_data) do
        table.insert(available_unit_ids, id)
    end

    if #available_unit_ids == 0 then
        return nk.json_encode({error = "No units available"})
    end

    local player_units = get_player_units(context.user_id)
    local summoned_units = {}

    for i = 1, amount do
        local random_index = math.random(1, #available_unit_ids)
        local unit_id = available_unit_ids[random_index]
        local unit_data = units_data[unit_id]

        local exp_pattern = unit_data.exp_pattern or 5
        local next_xp = calculate_xp_for_level(2, exp_pattern)

        local new_unit = {
            instance_id = nk.uuid_v4(),
            unit_id = unit_id,
            level = 1,
            xp = 0,
            current_rarity = unit_data.rarity_min or 1,
            next_xp = next_xp,
            equipment = {}
        }

        table.insert(player_units, new_unit)
        table.insert(summoned_units, new_unit)
    end

    save_player_units(context.user_id, player_units)

    return nk.json_encode({summoned = summoned_units})
end

nk.register_rpc(summon_units, "summon_units")

local function add_unit_xp(context, payload)
    local request = nk.json_decode(payload)
    local instance_id = request.instance_id
    local xp_amount = request.xp_amount

    if not instance_id or not xp_amount or xp_amount <= 0 then
        return nk.json_encode({error = "Invalid parameters"})
    end

    local player_units = get_player_units(context.user_id)
    local unit_found = false
    local updated_unit = nil

    for i, unit in ipairs(player_units) do
        if unit.instance_id == instance_id then
            unit_found = true
            local unit_data = units_data[unit.unit_id]
            if not unit_data then
                return nk.json_encode({error = "Unit data not found"})
            end

            local exp_pattern = unit_data.exp_pattern or 5
            local max_level = rarity_max_levels[unit.current_rarity] or 15

            unit.xp = unit.xp + xp_amount
            unit.level = calculate_level_from_xp(unit.xp, exp_pattern, max_level)
            
            if unit.level < max_level then
                local base_xp = calculate_total_xp_for_level(unit.level, exp_pattern)
                local xp_into_level = unit.xp - base_xp
                local required_marginal_xp = calculate_xp_for_level(unit.level + 1, exp_pattern)
                unit.next_xp = required_marginal_xp - xp_into_level
                if unit.next_xp < 0 then unit.next_xp = 0 end
            else
                unit.next_xp = 0
            end

            updated_unit = unit
            break
        end
    end

    if not unit_found then
        return nk.json_encode({error = "Unit instance not found"})
    end

    save_player_units(context.user_id, player_units)

    return nk.json_encode({unit = updated_unit})
end

nk.register_rpc(add_unit_xp, "add_unit_xp")

local function awaken_unit(context, payload)
    local request = nk.json_decode(payload)
    local instance_id = request.instance_id

    if not instance_id then
        return nk.json_encode({error = "Invalid parameters"})
    end

    local player_units = get_player_units(context.user_id)
    local unit_found = false
    local updated_unit = nil

    for i, unit in ipairs(player_units) do
        if unit.instance_id == instance_id then
            unit_found = true
            local unit_data = units_data[unit.unit_id]
            if not unit_data then
                return nk.json_encode({error = "Unit data not found"})
            end

            local max_level = rarity_max_levels[unit.current_rarity] or 15
            local max_rarity = unit_data.rarity_max or 1

            if unit.level < max_level then
                return nk.json_encode({error = "Unit is not at max level for current rarity"})
            end

            if unit.current_rarity >= max_rarity then
                return nk.json_encode({error = "Unit is already at max rarity"})
            end

            unit.current_rarity = unit.current_rarity + 1
            unit.level = 1
            unit.xp = 0 -- Optionally reset XP too, or just level

            local exp_pattern = unit_data.exp_pattern or 5
            local next_xp = calculate_xp_for_level(2, exp_pattern)
            unit.next_xp = next_xp

            updated_unit = unit
            break
        end
    end

    if not unit_found then
        return nk.json_encode({error = "Unit instance not found"})
    end

    save_player_units(context.user_id, player_units)

    return nk.json_encode({unit = updated_unit})
end

nk.register_rpc(awaken_unit, "awaken_unit")

local function get_player_items(user_id)
    local object_ids = {
        {collection = "items", key = "player_items", user_id = user_id}
    }
    local objects = nk.storage_read(object_ids)

    if #objects > 0 then
        local data = objects[1].value
        if data and data.items then
            return data.items
        end
    end

    return {}
end

local function save_player_items(user_id, items)
    local objects = {
        {
            collection = "items",
            key = "player_items",
            user_id = user_id,
            value = {items = items},
            permission_read = 1,
            permission_write = 1
        }
    }
    nk.storage_write(objects)
end

local function add_item(context, payload)
    local request = nk.json_decode(payload)
    local item_id = request.item_id
    local quantity = request.quantity or 1

    if not item_id or quantity <= 0 then
        return nk.json_encode({error = "Invalid parameters"})
    end

    local item_data = items_data[item_id]
    if not item_data then
        return nk.json_encode({error = "Item data not found"})
    end

    local player_items = get_player_items(context.user_id)
    local item_found = false

    for i, item in ipairs(player_items) do
        if item.item_id == item_id then
            item.quantity = item.quantity + quantity
            item_found = true
            break
        end
    end

    if not item_found then
        table.insert(player_items, {
            item_id = item_id,
            quantity = quantity
        })
    end

    save_player_items(context.user_id, player_items)

    return nk.json_encode({success = true, items = player_items})
end

nk.register_rpc(add_item, "add_item")

local function add_currency(context, payload)
    local request = nk.json_decode(payload)
    local gil = request.gil or 0
    local lapis = request.lapis or 0

    if gil == 0 and lapis == 0 then
        return nk.json_encode({error = "No currency to add"})
    end

    local changeset = {}
    if gil ~= 0 then changeset.gil = gil end
    if lapis ~= 0 then changeset.lapis = lapis end

    local metadata = { source = "debug_add" }

    local status, result = pcall(nk.wallet_update, context.user_id, changeset, metadata, true)

    if not status then
        return nk.json_encode({error = "Failed to update wallet: " .. tostring(result)})
    end

    -- Return the updated wallet to the client
    local account = nk.account_get_id(context.user_id)
    return nk.json_encode({success = true, wallet = account.wallet})
end

nk.register_rpc(add_currency, "add_currency")

local function get_player_stats(context, payload)
    local object_ids = {
        {collection = "stats", key = "player_stats", user_id = context.user_id}
    }
    local objects = nk.storage_read(object_ids)

    local stats = {
        rank = 1,
        xp = 0,
        current_nrg = 41,
        last_nrg_update_time = math.floor(nk.time() / 1000)
    }

    if #objects > 0 then
        local data = objects[1].value
        if data then
            stats.rank = data.rank or stats.rank
            stats.xp = data.xp or stats.xp
            -- Backwards compatibility with old energy fields
            stats.current_nrg = data.current_nrg or data.energy or stats.current_nrg
            stats.last_nrg_update_time = data.last_nrg_update_time or data.last_energy_update_time or stats.last_nrg_update_time
        end
    end

    local max_energy
    if not RankData[1] then
        -- Fallback if CSV is missing or empty
        max_energy = 41
    elseif stats.rank > MaxRank then
        max_energy = RankData[MaxRank].energy
    elseif RankData[stats.rank] then
        max_energy = RankData[stats.rank].energy
    else
        max_energy = 41
    end

    local current_time = math.floor(nk.time() / 1000)
    local elapsed_seconds = current_time - stats.last_nrg_update_time

    -- In case of time skew, don't allow negative elapsed time
    if elapsed_seconds < 0 then elapsed_seconds = 0 end

    local nrg_regen_rate_seconds = 300
    local seconds_until_next_nrg = 0

    local stats_changed = false

    if stats.current_nrg >= max_energy then
        -- Player is at or above max energy (overflow).
        -- Don't add passive energy, update timestamp to now so they don't accrue
        if elapsed_seconds > 0 then
            stats.last_nrg_update_time = current_time
            stats_changed = true
        end
        seconds_until_next_nrg = 0
    else
        -- Player is under max energy and should gain some.
        local energy_to_add = math.floor(elapsed_seconds / nrg_regen_rate_seconds)
        local remainder = elapsed_seconds % nrg_regen_rate_seconds

        if energy_to_add > 0 then
            stats.current_nrg = stats.current_nrg + energy_to_add
            if stats.current_nrg > max_energy then
                stats.current_nrg = max_energy
                stats.last_nrg_update_time = current_time
                seconds_until_next_nrg = 0
            else
                stats.last_nrg_update_time = current_time - remainder
                seconds_until_next_nrg = nrg_regen_rate_seconds - remainder
            end
            stats_changed = true
        else
            seconds_until_next_nrg = nrg_regen_rate_seconds - remainder
        end
    end

    if stats_changed then
        -- Save updated stats
        local write_objects = {
            {
                collection = "stats",
                key = "player_stats",
                user_id = context.user_id,
                value = stats,
                permission_read = 1,
                permission_write = 1
            }
        }
        nk.storage_write(write_objects)
    end

    local next_rank_xp = 0
    if stats.rank < MaxRank then
        next_rank_xp = RankData[stats.rank + 1].exp
    end

    local payload_out = {
        rank = stats.rank,
        xp = stats.xp,
        next_rank_xp = next_rank_xp,
        current_nrg = stats.current_nrg,
        max_nrg = max_energy,
        nrg_regen_rate_seconds = nrg_regen_rate_seconds,
        seconds_until_next_nrg = seconds_until_next_nrg,
        -- Backward compatibility
        energy = stats.current_nrg,
        max_energy = max_energy
    }

    return nk.json_encode(payload_out)
end

nk.register_rpc(get_player_stats, "get_player_stats")

local function add_rank_xp(context, payload)
    local request = nk.json_decode(payload)
    local xp_amount = request.xp_amount or 0

    if xp_amount <= 0 then
        return nk.json_encode({error = "Invalid xp amount"})
    end

    -- First sync current energy
    local stats_str = get_player_stats(context, "")
    local stats = nk.json_decode(stats_str)

    stats.xp = stats.xp + xp_amount

    local rank_up_occurred = false

    if RankData[1] then
        while stats.rank < MaxRank and RankData[stats.rank + 1] and stats.xp >= RankData[stats.rank + 1].exp do
            local required_exp = RankData[stats.rank + 1].exp
            if required_exp <= 0 then
                break -- Should not happen, but safe guard
            end

            stats.xp = stats.xp - required_exp
            stats.rank = stats.rank + 1

            if RankData[stats.rank] then
                local new_max_energy = RankData[stats.rank].energy
                stats.current_nrg = stats.current_nrg + new_max_energy
                stats.energy = stats.current_nrg -- keep backward compatibility in this table before saving
            end
            rank_up_occurred = true
        end
    end

    if rank_up_occurred and RankData[stats.rank] then
        -- Recalculate final max energy to return it properly
        local final_max_energy = RankData[stats.rank].energy
        stats.max_energy = final_max_energy
        stats.max_nrg = final_max_energy
    end

    local next_rank_xp = 0
    if stats.rank < MaxRank and RankData[stats.rank + 1] then
        next_rank_xp = RankData[stats.rank + 1].exp
    end
    stats.next_rank_xp = next_rank_xp

    -- Re-fetch the real raw storage object to properly update the DB with current_nrg and timestamp
    local object_ids = {
        {collection = "stats", key = "player_stats", user_id = context.user_id}
    }
    local objects = nk.storage_read(object_ids)

    local raw_stats = {}
    if #objects > 0 then
        raw_stats = objects[1].value
    end

    local write_objects = {
        {
            collection = "stats",
            key = "player_stats",
            user_id = context.user_id,
            value = {
                rank = stats.rank,
                xp = stats.xp,
                current_nrg = stats.current_nrg,
                last_nrg_update_time = raw_stats.last_nrg_update_time or raw_stats.last_energy_update_time or math.floor(nk.time() / 1000)
            },
            permission_read = 1,
            permission_write = 1
        }
    }
    nk.storage_write(write_objects)

    return nk.json_encode(stats)
end

nk.register_rpc(add_rank_xp, "add_rank_xp")


local function buy_item(context, payload)
    local request = nk.json_decode(payload)
    local item_id = request.item_id
    local quantity = request.quantity or 1

    if not item_id or quantity <= 0 then
        return nk.json_encode({error = "Invalid parameters"})
    end

    local account = nk.account_get_id(context.user_id)
    local wallet = {}
    if account.wallet then
        if type(account.wallet) == "table" then
            wallet = account.wallet
        elseif type(account.wallet) == "string" and account.wallet ~= "" then
            wallet = nk.json_decode(account.wallet)
        end
    end

    local current_gil = wallet.gil or 0

    local item_data = items_data[item_id]
    if not item_data then
        item_data = equipment_data[item_id]
    end
    if not item_data then
        return nk.json_encode({error = "Item data not found"})
    end

    if not item_data.price_buy then
        return nk.json_encode({error = "Item cannot be purchased"})
    end

    local total_cost = item_data.price_buy * quantity

    if current_gil < total_cost then
        return nk.json_encode({error = "Insufficient gil. Need " .. tostring(total_cost) .. ", have " .. tostring(current_gil)})
    end

    local changeset = { gil = -total_cost }
    local metadata = { source = "buy_item", item_id = item_id, quantity = quantity }

    local status, result = pcall(nk.wallet_update, context.user_id, changeset, metadata, true)

    if not status then
        return nk.json_encode({error = "Failed to deduct gil: " .. tostring(result)})
    end

    -- Add the item
    local player_items = get_player_items(context.user_id)
    local item_found = false

    for i, item in ipairs(player_items) do
        if item.item_id == item_id then
            item.quantity = item.quantity + quantity
            item_found = true
            break
        end
    end

    if not item_found then
        table.insert(player_items, {
            item_id = item_id,
            quantity = quantity
        })
    end

    save_player_items(context.user_id, player_items)

    -- Return the updated wallet to the client
    account = nk.account_get_id(context.user_id)
    return nk.json_encode({success = true, wallet = account.wallet, items = player_items})
end

nk.register_rpc(buy_item, "buy_item")


local function perform_mission(context, payload)
    local request = nk.json_decode(payload)
    local mission_id = request.mission_id

    if not mission_id then
        return nk.json_encode({error = "Invalid mission_id"})
    end

    local mission_data = missions_data[tostring(mission_id)]
    if not mission_data then
        return nk.json_encode({error = "Mission not found"})
    end

    local cost_type = mission_data.cost_type or "NRG"
    local cost = mission_data.cost or 0
    local gil_reward = mission_data.gil or 0
    local exp_reward = mission_data.exp or 0

    -- First sync current stats
    local stats_str = get_player_stats(context, "")
    local stats = nk.json_decode(stats_str)

    if cost_type == "NRG" then
        if stats.current_nrg < cost then
            return nk.json_encode({error = "Not enough NRG"})
        end
        stats.current_nrg = stats.current_nrg - cost
        stats.energy = stats.current_nrg -- keep backward compatibility
    else
        -- If other costs are introduced later
    end

    -- Add exp
    if exp_reward > 0 then
        stats.xp = stats.xp + exp_reward

        local rank_up_occurred = false

        if RankData[1] then
            while stats.rank < MaxRank and RankData[stats.rank + 1] and stats.xp >= RankData[stats.rank + 1].exp do
                local required_exp = RankData[stats.rank + 1].exp
                if required_exp <= 0 then
                    break -- Should not happen, but safe guard
                end

                stats.xp = stats.xp - required_exp
                stats.rank = stats.rank + 1

                if RankData[stats.rank] then
                    local new_max_energy = RankData[stats.rank].energy
                    stats.current_nrg = stats.current_nrg + new_max_energy
                    stats.energy = stats.current_nrg -- keep backward compatibility in this table before saving
                end
                rank_up_occurred = true
            end
        end

        if rank_up_occurred and RankData[stats.rank] then
            local final_max_energy = RankData[stats.rank].energy
            stats.max_energy = final_max_energy
            stats.max_nrg = final_max_energy
        end

    end

    -- Always ensure next_rank_xp is populated in the returned stats
    local next_rank_xp = 0
    if stats.rank < MaxRank and RankData[stats.rank + 1] then
        next_rank_xp = RankData[stats.rank + 1].exp
    end
    stats.next_rank_xp = next_rank_xp

    -- Save stats
    local object_ids = {
        {collection = "stats", key = "player_stats", user_id = context.user_id}
    }
    local objects = nk.storage_read(object_ids)
    local raw_stats = objects[1].value

    local write_objects = {
        {
            collection = "stats",
            key = "player_stats",
            user_id = context.user_id,
            value = {
                rank = stats.rank,
                xp = stats.xp,
                current_nrg = stats.current_nrg,
                last_nrg_update_time = raw_stats.last_nrg_update_time or raw_stats.last_energy_update_time or math.floor(nk.time() / 1000)
            },
            permission_read = 1,
            permission_write = 1
        }
    }
    nk.storage_write(write_objects)

    -- Add gil
    local wallet_out = {}
    if gil_reward > 0 then
        local changeset = { gil = gil_reward }
        local metadata = { source = "perform_mission", mission_id = mission_id }
        local status, result = pcall(nk.wallet_update, context.user_id, changeset, metadata, true)
        if not status then
            return nk.json_encode({error = "Failed to update wallet: " .. tostring(result)})
        end
    end

    local account = nk.account_get_id(context.user_id)
    return nk.json_encode({
        success = true,
        stats = stats,
        wallet = account.wallet
    })
end

nk.register_rpc(perform_mission, "perform_mission")

local function rpc_equip_item(context, payload)
    local request = nk.json_decode(payload)
    local unit_id = request.unit_id
    local slot = request.slot
    local item_id = request.item_id -- nil or empty string implies unequip

    if not unit_id or not slot then
        return nk.json_encode({error = "Missing unit_id or slot"})
    end

    local valid_slots = {
        r_hand = true, l_hand = true, head = true,
        body = true, accessory1 = true, accessory2 = true
    }

    if not valid_slots[slot] then
        return nk.json_encode({error = "Invalid slot: " .. tostring(slot)})
    end

    local is_unequipping = (not item_id or item_id == "")

    local player_units = get_player_units(context.user_id)
    local player_items = get_player_items(context.user_id)

    -- Find target unit
    local target_unit = nil
    for _, u in ipairs(player_units) do
        if u.instance_id == unit_id then
            target_unit = u
            break
        end
    end

    if not target_unit then
        return nk.json_encode({error = "Unit not found"})
    end

    -- Ensure equipment table exists (backward compatibility)
    if not target_unit.equipment then
        target_unit.equipment = {}
    end

    if is_unequipping then
        target_unit.equipment[slot] = nil
    else
        -- Equipping validation
        local eq_data = equipment_data[item_id]
        if not eq_data then
            return nk.json_encode({error = "Invalid equipment item_id: " .. tostring(item_id)})
        end

        local unit_base_data = units_data[target_unit.unit_id]
        if not unit_base_data then
            return nk.json_encode({error = "Base unit data not found"})
        end

        -- Check if unit can equip this type
        local can_equip = false
        if type(unit_base_data.equip) == "table" then
            for _, type_id in ipairs(unit_base_data.equip) do
                if type_id == eq_data.type_id then
                    can_equip = true
                    break
                end
            end
        end

        if not can_equip then
            return nk.json_encode({error = "Unit cannot equip this item type"})
        end

        -- Check ownership and quantity
        local owned_quantity = 0
        for _, item in ipairs(player_items) do
            if item.item_id == item_id then
                owned_quantity = item.quantity or 0
                break
            end
        end

        if owned_quantity <= 0 then
            return nk.json_encode({error = "Player does not own this item"})
        end

        -- Count how many of this item are currently equipped across ALL units
        local equipped_count = 0
        local first_found_unit_with_item = nil
        local first_found_slot = nil

        for _, u in ipairs(player_units) do
            if u.equipment then
                for s, eq_id in pairs(u.equipment) do
                    if eq_id == item_id then
                        equipped_count = equipped_count + 1
                        if not first_found_unit_with_item then
                            first_found_unit_with_item = u
                            first_found_slot = s
                        end
                    end
                end
            end
        end

        -- If we don't have enough spare items, unequip from another unit
        if equipped_count >= owned_quantity then
            if first_found_unit_with_item and first_found_slot then
                first_found_unit_with_item.equipment[first_found_slot] = nil
            else
                -- Failsafe: technically shouldn't happen unless data corruption
                return nk.json_encode({error = "Not enough items and failed to auto-unequip"})
            end
        end

        -- Apply the equipment
        target_unit.equipment[slot] = item_id

        -- Two-handed rule
        if eq_data.is_two_handed or eq_data.is_twohanded then
            if slot == "r_hand" then
                target_unit.equipment.l_hand = nil
            elseif slot == "l_hand" then
                target_unit.equipment.r_hand = nil
            end
        end
    end

    save_player_units(context.user_id, player_units)

    return nk.json_encode({success = true, units = player_units})
end
nk.register_rpc(rpc_equip_item, "equip_item")
local function rpc_get_parties(context, payload)
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
        local default_parties = {}
        for i = 1, 5 do
            table.insert(default_parties, {
                name = "Party " .. i,
                units = {"", "", "", "", ""}
            })
        end

        nk.storage_write({
            {
                collection = "user_data",
                key = "parties",
                user_id = context.user_id,
                value = { parties = default_parties },
                permission_read = 1,
                permission_write = 1
            }
        })

        return nk.json_encode({ parties = default_parties })
    end

    return nk.json_encode(objects[1].value)
end
nk.register_rpc(rpc_get_parties, "get_parties")

local function rpc_save_parties(context, payload)
    local request = nk.json_decode(payload)

    if not request.parties then
        return nk.json_encode({error = "Missing 'parties' field in payload"})
    end

    nk.storage_write({
        {
            collection = "user_data",
            key = "parties",
            user_id = context.user_id,
            value = { parties = request.parties },
            permission_read = 1,
            permission_write = 1
        }
    })

    return nk.json_encode({ success = true, parties = request.parties })
end
nk.register_rpc(rpc_save_parties, "save_parties")
