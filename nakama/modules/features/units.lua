local nk = require("nakama")
local StaticData = require("core.static_data")
local Utilities = require("core.utilities")

local Units = {}

function Units.get_player_units(user_id)
    local units = {}
    local cursor = nil

    repeat
        local objects, next_cursor = nk.storage_list(user_id, "unit", 100, cursor)
        for _, obj in ipairs(objects) do
            local unit = obj.value

            -- Inject next_xp if it's missing or needs recalculation based on up-to-date data
            local unit_data = StaticData.units_data[unit.unit_id]
            if unit_data then
                local exp_pattern = unit_data.exp_pattern or 5
                local max_level = StaticData.rarity_max_levels[unit.current_rarity] or 15
                if unit.level < max_level then
                    local base_xp = StaticData.calculate_total_xp_for_level(unit.level, exp_pattern)
                    local xp_into_level = unit.xp - base_xp
                    local required_marginal_xp = StaticData.calculate_xp_for_level(unit.level + 1, exp_pattern)
                    unit.next_xp = required_marginal_xp - xp_into_level
                    if unit.next_xp < 0 then unit.next_xp = 0 end
                else
                    unit.next_xp = 0
                end
            end

            table.insert(units, unit)
        end
        cursor = next_cursor
    until not cursor

    return units
end

function Units.get_unit(user_id, instance_id)
    local object_ids = {
        {collection = "unit", key = instance_id, user_id = user_id}
    }
    local objects = nk.storage_read(object_ids)
    if #objects > 0 then
        return objects[1].value
    end
    return nil
end

function Units.save_unit(user_id, unit)
    Units.save_units(user_id, {unit})
end

function Units.save_units(user_id, units)
    local writes = {}
    for _, unit in ipairs(units) do
        table.insert(writes, {
            collection = "unit",
            key = unit.instance_id,
            user_id = user_id,
            value = unit,
            permission_read = 1,
            permission_write = 1
        })
    end
    if #writes > 0 then
        nk.storage_write(writes)
    end
end

function Units.get_player_units_rpc(context, payload)
    local units = Units.get_player_units(context.user_id)
    return nk.json_encode({units = units})
end

function Units.summon_units(context, payload)
    local request = Utilities.parse_payload(payload)
    if not request then
        return nk.json_encode({error = "Invalid JSON payload"})
    end
    local amount = request.amount or 1

    -- TODO: Add currency/ticket deduction logic here before summoning

    local available_unit_ids = {}
        for id, unit_data in pairs(StaticData.units_data) do
            if unit_data.is_summonable == true then
                table.insert(available_unit_ids, id)
            end
    end

    if #available_unit_ids == 0 then
        return nk.json_encode({error = "No units available"})
    end

    local summoned_units = {}

    for i = 1, amount do
        local random_index = math.random(1, #available_unit_ids)
        local unit_id = available_unit_ids[random_index]
        local unit_data = StaticData.units_data[unit_id]

        local exp_pattern = unit_data.exp_pattern or 5
        local next_xp = StaticData.calculate_xp_for_level(2, exp_pattern)

        local new_unit = {
            instance_id = nk.uuid_v4(),
            unit_id = unit_id,
            level = 1,
            xp = 0,
            current_rarity = unit_data.rarity_min or 1,
            next_xp = next_xp,
            equipment = {}
        }

        table.insert(summoned_units, new_unit)
    end

    Units.save_units(context.user_id, summoned_units)

    return nk.json_encode({summoned = summoned_units})
end

function Units.add_unit_xp(context, payload)
    local request = Utilities.parse_payload(payload)
    if not request then
        return nk.json_encode({error = "Invalid JSON payload"})
    end
    local instance_id = request.instance_id
    local xp_amount = request.xp_amount

    if xp_amount and xp_amount > 10000 then
        return nk.json_encode({error = "Amount exceeds debug limits"})
    end

    if not instance_id or not xp_amount or xp_amount <= 0 then
        return nk.json_encode({error = "Invalid parameters"})
    end

    local unit = Units.get_unit(context.user_id, instance_id)
    if not unit then
        return nk.json_encode({error = "Unit instance not found"})
    end

    local unit_data = StaticData.units_data[unit.unit_id]
    if not unit_data then
        return nk.json_encode({error = "Unit data not found"})
    end

    local exp_pattern = unit_data.exp_pattern or 5
    local max_level = StaticData.rarity_max_levels[unit.current_rarity] or 15

    unit.xp = unit.xp + xp_amount
    unit.level = StaticData.calculate_level_from_xp(unit.xp, exp_pattern, max_level)

    if unit.level < max_level then
        local base_xp = StaticData.calculate_total_xp_for_level(unit.level, exp_pattern)
        local xp_into_level = unit.xp - base_xp
        local required_marginal_xp = StaticData.calculate_xp_for_level(unit.level + 1, exp_pattern)
        unit.next_xp = required_marginal_xp - xp_into_level
        if unit.next_xp < 0 then unit.next_xp = 0 end
    else
        unit.next_xp = 0
    end

    Units.save_unit(context.user_id, unit)

    return nk.json_encode({unit = unit})
end

function Units.awaken_unit(context, payload)
    local request = Utilities.parse_payload(payload)
    if not request then
        return nk.json_encode({error = "Invalid JSON payload"})
    end
    local instance_id = request.instance_id

    if not instance_id then
        return nk.json_encode({error = "Invalid parameters"})
    end

    local unit = Units.get_unit(context.user_id, instance_id)
    if not unit then
        return nk.json_encode({error = "Unit instance not found"})
    end

    local unit_data = StaticData.units_data[unit.unit_id]
    if not unit_data then
        return nk.json_encode({error = "Unit data not found"})
    end

    local max_level = StaticData.rarity_max_levels[unit.current_rarity] or 15
    local max_rarity = unit_data.rarity_max or 1

    if unit.level < max_level then
        return nk.json_encode({error = "Unit is not at max level for current rarity"})
    end

    if unit.current_rarity >= max_rarity then
        return nk.json_encode({error = "Unit is already at max rarity"})
    end

    -- TODO: Add material and currency deduction logic here before awakening

    unit.current_rarity = unit.current_rarity + 1
    unit.level = 1
    unit.xp = 0

    local exp_pattern = unit_data.exp_pattern or 5
    local next_xp = StaticData.calculate_xp_for_level(2, exp_pattern)
    unit.next_xp = next_xp

    Units.save_unit(context.user_id, unit)

    return nk.json_encode({unit = unit})
end

return Units
