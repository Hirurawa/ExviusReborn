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

local units_data = read_json_file("data/units.json") or {}
local items_data = read_json_file("data/items.json") or {}
local weapons_data = read_json_file("data/weapons.json") or {}

local cached_game_data = {
    units = units_data,
    items = items_data,
    weapons = weapons_data
}

local function get_game_data(context, payload)
    return nk.json_encode(cached_game_data)
end

nk.register_rpc(get_game_data, "get_game_data")

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
            current_rarity = unit_data.base_rarity or 1
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
            local max_rarity = unit_data.max_rarity or unit_data.base_rarity or 1

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
