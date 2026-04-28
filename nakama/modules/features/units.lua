local nk = require("nakama")
local StaticData = require("core.static_data")
local Utilities = require("core.utilities")

local Units = {}

local ENHANCE_MAX_TRUST_VALUE = 100.0
local ENHANCE_MAX_LIMITBURST_LEVEL = 30
local ENHANCE_GIL_COST_PER_MATERIAL = 1000

local ENHANCE_BASE_XP_GAIN = 100
local ENHANCE_XP_PER_RARITY = 100
local ENHANCE_XP_PER_LEVEL = 20

local ENHANCE_BASE_TRUST_GAIN = 0.2
local ENHANCE_TRUST_PER_RARITY = 0.15
local ENHANCE_TRUST_PER_LEVEL = 0.01

local ENHANCE_BASE_LIMITBURST_XP_GAIN = 1
local ENHANCE_LIMITBURST_XP_PER_RARITY = 1
local ENHANCE_LIMITBURST_LEVEL_STEP = 20
local ENHANCE_LIMITBURST_BASE_XP_REQUIREMENT = 10
local ENHANCE_LIMITBURST_XP_REQUIREMENT_GROWTH = 5

local function parse_wallet(account_wallet)
    if type(account_wallet) == "table" then
        return account_wallet
    end
    if type(account_wallet) == "string" and account_wallet ~= "" then
        return Utilities.parse_payload(account_wallet) or {}
    end
    return {}
end

local function normalize_unit(unit)
    if not unit then
        return nil
    end

    unit.trust_value = tonumber(unit.trust_value) or 0.0
    if unit.trust_value < 0 then
        unit.trust_value = 0.0
    end

    unit.limitburst_level = math.floor(tonumber(unit.limitburst_level) or 1)
    if unit.limitburst_level < 1 then
        unit.limitburst_level = 1
    end
    if unit.limitburst_level > ENHANCE_MAX_LIMITBURST_LEVEL then
        unit.limitburst_level = ENHANCE_MAX_LIMITBURST_LEVEL
    end

    unit.limitburst_xp = math.floor(tonumber(unit.limitburst_xp) or 0)
    if unit.limitburst_xp < 0 then
        unit.limitburst_xp = 0
    end
    if unit.limitburst_level >= ENHANCE_MAX_LIMITBURST_LEVEL then
        unit.limitburst_xp = 0
    end

    if unit.is_locked == nil then
        unit.is_locked = false
    end

    return unit
end

local function get_unit_max_level(unit)
    return StaticData.rarity_max_levels[unit.current_rarity] or 15
end

local function update_unit_next_xp(unit, unit_data)
    if not unit_data then
        return
    end

    local exp_pattern = unit_data.exp_pattern or 5
    local max_level = get_unit_max_level(unit)
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

local function calculate_material_enhance_gains(material_unit)
    local rarity = math.max(1, math.floor(tonumber(material_unit.current_rarity) or 1))
    local level = math.max(1, math.floor(tonumber(material_unit.level) or 1))

    local xp_gain = ENHANCE_BASE_XP_GAIN + (rarity * ENHANCE_XP_PER_RARITY) + (level * ENHANCE_XP_PER_LEVEL)
    local trust_gain = ENHANCE_BASE_TRUST_GAIN + (rarity * ENHANCE_TRUST_PER_RARITY) + (level * ENHANCE_TRUST_PER_LEVEL)
    local limitburst_xp_gain = ENHANCE_BASE_LIMITBURST_XP_GAIN + (rarity * ENHANCE_LIMITBURST_XP_PER_RARITY) + math.floor(level / ENHANCE_LIMITBURST_LEVEL_STEP)

    return xp_gain, trust_gain, limitburst_xp_gain
end

local function limitburst_xp_required_for_next_level(level)
    return ENHANCE_LIMITBURST_BASE_XP_REQUIREMENT + ((level - 1) * ENHANCE_LIMITBURST_XP_REQUIREMENT_GROWTH)
end

local function apply_limitburst_gain(unit, added_xp)
    if unit.limitburst_level >= ENHANCE_MAX_LIMITBURST_LEVEL then
        unit.limitburst_level = ENHANCE_MAX_LIMITBURST_LEVEL
        unit.limitburst_xp = 0
        return
    end

    unit.limitburst_xp = unit.limitburst_xp + added_xp
    while unit.limitburst_level < ENHANCE_MAX_LIMITBURST_LEVEL do
        local xp_needed = limitburst_xp_required_for_next_level(unit.limitburst_level)
        if unit.limitburst_xp < xp_needed then
            break
        end
        unit.limitburst_xp = unit.limitburst_xp - xp_needed
        unit.limitburst_level = unit.limitburst_level + 1
    end

    if unit.limitburst_level >= ENHANCE_MAX_LIMITBURST_LEVEL then
        unit.limitburst_level = ENHANCE_MAX_LIMITBURST_LEVEL
        unit.limitburst_xp = 0
    end
end

local function rpc_fail(error_message)
    return nk.json_encode({success = false, error = error_message})
end

function Units.get_player_units(user_id)
    local units = {}
    local cursor = nil

    repeat
        local objects, next_cursor = nk.storage_list(user_id, "unit", 100, cursor)
        for _, obj in ipairs(objects) do
            local unit = normalize_unit(obj.value)

            -- Inject next_xp if it's missing or needs recalculation based on up-to-date data
            local unit_data = StaticData.units_data[unit.unit_id]
            update_unit_next_xp(unit, unit_data)

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
        return normalize_unit(objects[1].value)
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

function Units.delete_units(user_id, instance_ids)
    local deletes = {}
    for _, instance_id in ipairs(instance_ids) do
        table.insert(deletes, {
            collection = "unit",
            key = instance_id,
            user_id = user_id
        })
    end

    if #deletes == 0 then
        return true, nil
    end

    local ok, err = pcall(nk.storage_delete, deletes)
    if not ok then
        return false, tostring(err)
    end

    return true, nil
end

function Units.is_unit_assigned_to_party(user_id, unit_instance_id)
    local object_ids = {
        {
            collection = "user_data",
            key = "parties",
            user_id = user_id
        }
    }

    local objects = nk.storage_read(object_ids)
    if #objects == 0 then
        return false
    end

    local value = objects[1].value or {}
    local parties = value.parties
    if type(parties) ~= "table" then
        return false
    end

    for _, party in ipairs(parties) do
        local units = party.units
        if type(units) == "table" then
            for _, instance_id in ipairs(units) do
                if tostring(instance_id) == tostring(unit_instance_id) then
                    return true
                end
            end
        end
    end

    return false
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
            equipment = {},
            trust_value = 0.0,
            limitburst_level = 1,
            limitburst_xp = 0,
            is_locked = false
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
    local max_level = get_unit_max_level(unit)

    unit.xp = unit.xp + xp_amount
    unit.level = StaticData.calculate_level_from_xp(unit.xp, exp_pattern, max_level)
    update_unit_next_xp(unit, unit_data)

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

function Units.enhance_unit(context, payload)
    local request = Utilities.parse_payload(payload)
    if not request then
        return rpc_fail("Invalid JSON payload")
    end

    local base_unit_instance_id = request.base_unit_instance_id
    local material_unit_instance_ids = request.material_unit_instance_ids

    if type(base_unit_instance_id) ~= "string" or base_unit_instance_id == "" then
        return rpc_fail("Invalid base_unit_instance_id")
    end

    if type(material_unit_instance_ids) ~= "table" or #material_unit_instance_ids == 0 then
        return rpc_fail("material_unit_instance_ids must be a non-empty array")
    end

    local seen_materials = {}
    for _, material_id in ipairs(material_unit_instance_ids) do
        if type(material_id) ~= "string" or material_id == "" then
            return rpc_fail("All material ids must be non-empty strings")
        end
        if seen_materials[material_id] then
            return rpc_fail("Duplicate material ids are not allowed")
        end
        seen_materials[material_id] = true
        if material_id == base_unit_instance_id then
            return rpc_fail("Base unit cannot be used as enhancement material")
        end
    end

    local base_unit = Units.get_unit(context.user_id, base_unit_instance_id)
    if not base_unit then
        return rpc_fail("Ownership check failed for base unit")
    end

    local base_unit_data = StaticData.units_data[base_unit.unit_id]
    if not base_unit_data then
        return rpc_fail("Base unit data not found")
    end

    local base_max_level = get_unit_max_level(base_unit)
    if base_unit.level >= base_max_level and base_unit.trust_value >= ENHANCE_MAX_TRUST_VALUE then
        return rpc_fail("Base unit is already at maximum level and trust")
    end

    local material_units = {}
    for _, material_id in ipairs(material_unit_instance_ids) do
        local material_unit = Units.get_unit(context.user_id, material_id)
        if not material_unit then
            return rpc_fail("Ownership check failed for one or more material units")
        end

        if material_unit.is_locked == true then
            return rpc_fail("One or more material units are locked")
        end

        if Units.is_unit_assigned_to_party(context.user_id, material_id) then
            return rpc_fail("One or more material units are assigned to a party")
        end

        table.insert(material_units, material_unit)
    end

    local total_cost = #material_unit_instance_ids * ENHANCE_GIL_COST_PER_MATERIAL
    local account = nk.account_get_id(context.user_id)
    local wallet = parse_wallet(account.wallet)
    local current_gil = tonumber(wallet.gil) or 0
    if current_gil < total_cost then
        return rpc_fail("Insufficient gil")
    end

    local total_xp_gain = 0
    local total_trust_gain = 0.0
    local total_limitburst_xp_gain = 0
    for _, material_unit in ipairs(material_units) do
        local xp_gain, trust_gain, lb_xp_gain = calculate_material_enhance_gains(material_unit)
        total_xp_gain = total_xp_gain + xp_gain
        total_trust_gain = total_trust_gain + trust_gain
        total_limitburst_xp_gain = total_limitburst_xp_gain + lb_xp_gain
    end

    local wallet_ok, wallet_result = pcall(
        nk.wallet_update,
        context.user_id,
        { gil = -total_cost },
        {
            source = "enhance_unit",
            base_unit_instance_id = base_unit_instance_id,
            material_count = #material_unit_instance_ids
        },
        true
    )
    if not wallet_ok then
        return rpc_fail("Failed to deduct gil: " .. tostring(wallet_result))
    end

    local exp_pattern = base_unit_data.exp_pattern or 5
    base_unit.xp = base_unit.xp + total_xp_gain
    base_unit.level = StaticData.calculate_level_from_xp(base_unit.xp, exp_pattern, base_max_level)
    update_unit_next_xp(base_unit, base_unit_data)

    base_unit.trust_value = base_unit.trust_value + total_trust_gain
    if base_unit.trust_value > ENHANCE_MAX_TRUST_VALUE then
        base_unit.trust_value = ENHANCE_MAX_TRUST_VALUE
    end

    apply_limitburst_gain(base_unit, total_limitburst_xp_gain)

    local save_ok, save_err = pcall(Units.save_unit, context.user_id, base_unit)
    if not save_ok then
        return rpc_fail("Failed to save enhanced base unit: " .. tostring(save_err))
    end

    local delete_ok, delete_err = Units.delete_units(context.user_id, material_unit_instance_ids)
    if not delete_ok then
        return rpc_fail("Failed to consume material units: " .. tostring(delete_err))
    end

    local updated_account = nk.account_get_id(context.user_id)
    local updated_wallet = parse_wallet(updated_account.wallet)

    return nk.json_encode({
        success = true,
        updated_base_unit = {
            instance_id = base_unit.instance_id,
            level = base_unit.level,
            xp = base_unit.xp,
            trust_value = base_unit.trust_value,
            limitburst_level = base_unit.limitburst_level,
            limitburst_xp = base_unit.limitburst_xp
        },
        consumed_material_ids = material_unit_instance_ids,
        updated_currency = {
            gil = tonumber(updated_wallet.gil) or 0
        }
    })
end

return Units
