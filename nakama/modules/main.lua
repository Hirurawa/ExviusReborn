local nk = require("nakama")

local RankData = {}
local MaxRank = 1

local function parse_rank_exp_csv()
    local file_path = "modules/data/rank-exp.csv"
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
local weapons_data = read_json_file("data/weapons.json") or {}
local worlds_data = read_json_file("data/worlds.json") or {}
local dungeons_data = read_json_file("data/dungeons.json") or {}
local missions_data = read_json_file("data/missions.json") or {}

local cached_game_data = {
    units = units_data,
    items = items_data,
    weapons = weapons_data,
    worlds = worlds_data,
    dungeons = dungeons_data,
    missions = missions_data
}

local function get_game_data(context, payload)
    local request = {}
    if payload and payload ~= "" then
        pcall(function() request = nk.json_decode(payload) end)
    end

    local data_type = request.type or "all"
    
    if data_type == "core" then
        return nk.json_encode({
            units = units_data,
            items = items_data,
            weapons = weapons_data
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

local function calculate_xp_for_level(level, growth_factor)
    if level <= 1 then return 0 end
    local xp = growth_factor * 500000 * (math.pow(level / 99, 2.5) - math.pow((level - 1) / 99, 2.5))
    return math.floor(xp + 0.5)
end

local function calculate_level_from_xp(xp, growth_factor, max_level)
    if xp <= 0 then return 1 end

    local level = 1
    local total_xp_needed = 0

    for i = 2, max_level do
        total_xp_needed = total_xp_needed + calculate_xp_for_level(i, growth_factor)
        if xp >= total_xp_needed then
            level = i
        else
            break
        end
    end

    return level
end

local function get_player_units(user_id)
    local object_ids = {
        {collection = "units", key = "player_units", user_id = user_id}
    }
    local objects = nk.storage_read(object_ids)

    if #objects > 0 then
        local data = objects[1].value
        if data and data.units then
            return data.units
        end
    end

    return {}
end

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

        local new_unit = {
            instance_id = nk.uuid_v4(),
            unit_id = unit_id,
            level = 1,
            xp = 0,
            current_rarity = unit_data.rarity_min or 1
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

            local growth_factor = unit_data.growth_factor or 1.0
            local max_level = rarity_max_levels[unit.current_rarity] or 15

            unit.xp = unit.xp + xp_amount
            unit.level = calculate_level_from_xp(unit.xp, growth_factor, max_level)

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


local function buy_potion(context, payload)
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

    local item_id = "101000100"
    local item_data = items_data[item_id]
    if not item_data then
        return nk.json_encode({error = "Item data not found"})
    end

    local cost = item_data.price_buy or 100

    if current_gil < cost then
        return nk.json_encode({error = "Insufficient gil. Need " .. tostring(cost) .. ", have " .. tostring(current_gil)})
    end

    local changeset = { gil = -cost }
    local metadata = { source = "buy_potion" }

    local status, result = pcall(nk.wallet_update, context.user_id, changeset, metadata, true)

    if not status then
        return nk.json_encode({error = "Failed to deduct gil: " .. tostring(result)})
    end

    -- Add the item
    local quantity = 1

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

nk.register_rpc(buy_potion, "buy_potion")
