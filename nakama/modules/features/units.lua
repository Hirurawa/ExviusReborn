local nk = require("nakama")
local StaticData = require("core.static_data")

local Units = {}

function Units.get_player_units(user_id)
    local object_ids = {
        {collection = "units", key = "player_units", user_id = user_id}
    }
    local objects = nk.storage_read(object_ids)

    if #objects > 0 then
        local data = objects[1].value
        if data and data.units then
            -- Inject next_xp if it's missing or needs recalculation based on up-to-date data
            for _, unit in ipairs(data.units) do
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
            end
            return data.units
        end
    end

    return {}
end

function Units.save_player_units(user_id, units)
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

function Units.get_player_units_rpc(context, payload)
    local units = Units.get_player_units(context.user_id)
    return nk.json_encode({units = units})
end

function Units.summon_units(context, payload)
    local request = nk.json_decode(payload)
    local amount = request.amount or 1

    local available_unit_ids = {}
    for id, _ in pairs(StaticData.units_data) do
        table.insert(available_unit_ids, id)
    end

    if #available_unit_ids == 0 then
        return nk.json_encode({error = "No units available"})
    end

    local player_units = Units.get_player_units(context.user_id)
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

        table.insert(player_units, new_unit)
        table.insert(summoned_units, new_unit)
    end

    Units.save_player_units(context.user_id, player_units)

    return nk.json_encode({summoned = summoned_units})
end

function Units.add_unit_xp(context, payload)
    local request = nk.json_decode(payload)
    local instance_id = request.instance_id
    local xp_amount = request.xp_amount

    if not instance_id or not xp_amount or xp_amount <= 0 then
        return nk.json_encode({error = "Invalid parameters"})
    end

    local player_units = Units.get_player_units(context.user_id)
    local unit_found = false
    local updated_unit = nil

    for i, unit in ipairs(player_units) do
        if unit.instance_id == instance_id then
            unit_found = true
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

            updated_unit = unit
            break
        end
    end

    if not unit_found then
        return nk.json_encode({error = "Unit instance not found"})
    end

    Units.save_player_units(context.user_id, player_units)

    return nk.json_encode({unit = updated_unit})
end

function Units.awaken_unit(context, payload)
    local request = nk.json_decode(payload)
    local instance_id = request.instance_id

    if not instance_id then
        return nk.json_encode({error = "Invalid parameters"})
    end

    local player_units = Units.get_player_units(context.user_id)
    local unit_found = false
    local updated_unit = nil

    for i, unit in ipairs(player_units) do
        if unit.instance_id == instance_id then
            unit_found = true
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

            unit.current_rarity = unit.current_rarity + 1
            unit.level = 1
            unit.xp = 0 -- Optionally reset XP too, or just level

            local exp_pattern = unit_data.exp_pattern or 5
            local next_xp = StaticData.calculate_xp_for_level(2, exp_pattern)
            unit.next_xp = next_xp

            updated_unit = unit
            break
        end
    end

    if not unit_found then
        return nk.json_encode({error = "Unit instance not found"})
    end

    Units.save_player_units(context.user_id, player_units)

    return nk.json_encode({unit = updated_unit})
end

return Units
