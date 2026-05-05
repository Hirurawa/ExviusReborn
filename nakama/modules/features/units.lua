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

local UNIT_TYPE_PLAYABLE = "playable"
local UNIT_TYPE_EXP_MATERIAL = "exp_material"
local UNIT_TYPE_TRUST_MATERIAL = "trust_material"

local PLAYABLE_ACCUMULATED_EXP_TRANSFER_RATE = 0.5
local PLAYABLE_DUPLICATE_TRUST_BONUS = 5.0
local DEFAULT_MAX_ACCUMULATED_EXP = 2000000000

local EXP_UNIT_JOB_ID = 901
local TRUST_MATERIAL_JOB_ID = 903
local EXP_UNIT_YIELD_BY_PATTERN = {
    [201] = 5000,
    [202] = 10000,
    [203] = 30000,
    [204] = 100000,
}

local TRUST_YIELD_BY_UNIT_ID = {
    [904000101] = 1.0,  -- 1★ Trust Moogle
    [904000104] = 5.0,  -- 4★ Trust Moogle
    [904000105] = 10.0, -- 5★ Trust Moogle
}

local function get_raw_unit_exp_pattern(unit_id, unit_data, rarity)
    local entries = unit_data and unit_data.entries
    if type(entries) == "table" then
        if rarity ~= nil then
            for _, entry in pairs(entries) do
                if type(entry) == "table" and tonumber(entry.rarity) == tonumber(rarity) and tonumber(entry.exp_pattern) then
                    return tonumber(entry.exp_pattern)
                end
            end
        end

        local keyed_entry = entries[tostring(unit_id)]
        if type(keyed_entry) == "table" and tonumber(keyed_entry.exp_pattern) then
            return tonumber(keyed_entry.exp_pattern)
        end

        for _, entry in pairs(entries) do
            if type(entry) == "table" and tonumber(entry.exp_pattern) then
                return tonumber(entry.exp_pattern)
            end
        end
    end

    return nil
end

local function get_progression_exp_pattern(unit_id, unit_data, rarity)
    local exp_pattern = get_raw_unit_exp_pattern(unit_id, unit_data, rarity)
    if exp_pattern and StaticData.unit_exp_patterns[exp_pattern] then
        return exp_pattern
    end

    return 5
end

local function get_exp_unit_yield(unit_id)
    local unit_data = StaticData.units_data[unit_id]
    if not unit_data or unit_data.job_id ~= EXP_UNIT_JOB_ID then
        return nil
    end

    local exp_pattern = get_raw_unit_exp_pattern(unit_id, unit_data, unit_data.rarity_min)
    if not exp_pattern then
        return nil
    end

    return EXP_UNIT_YIELD_BY_PATTERN[exp_pattern]
end

local function get_unit_type(unit_data)
    if not unit_data then
        return UNIT_TYPE_PLAYABLE
    end

    if unit_data.job_id == EXP_UNIT_JOB_ID then
        return UNIT_TYPE_EXP_MATERIAL
    end
    if unit_data.job_id == TRUST_MATERIAL_JOB_ID then
        return UNIT_TYPE_TRUST_MATERIAL
    end

    return UNIT_TYPE_PLAYABLE
end

local function clamp_min(value, minimum)
    if value < minimum then
        return minimum
    end
    return value
end

local function clamp_max(value, maximum)
    if value > maximum then
        return maximum
    end
    return value
end

local function get_base_exp_yield(unit, unit_data)
    if unit_data and tonumber(unit_data.base_exp_yield) then
        return math.floor(tonumber(unit_data.base_exp_yield))
    end

    local unit_type = get_unit_type(unit_data)
    if unit_type == UNIT_TYPE_EXP_MATERIAL then
        return get_exp_unit_yield(unit.unit_id) or 0
    end

    if unit_type == UNIT_TYPE_PLAYABLE then
        local rarity = math.max(1, math.floor(tonumber(unit.current_rarity) or tonumber(unit_data and unit_data.rarity_min) or 1))
        return ENHANCE_BASE_XP_GAIN + (rarity * ENHANCE_XP_PER_RARITY) + ENHANCE_XP_PER_LEVEL
    end

    return 0
end

local function get_material_accumulated_exp(material_unit)
    local stored = tonumber(material_unit.current_accumulated_exp)
    if stored == nil then
        stored = tonumber(material_unit.bonus_exp)
    end
    if stored == nil then
        stored = tonumber(material_unit.xp) or 0
    end
    return clamp_min(math.floor(stored), 0)
end

local function get_material_accumulated_trust(material_unit)
    return clamp_min(tonumber(material_unit.trust_value) or 0.0, 0.0)
end

local function get_trust_yield(unit_id, unit_data)
    if not unit_data then
        return 0.0
    end

    local configured_trust_yield = tonumber(unit_data.trust_yield)
    if configured_trust_yield ~= nil then
        return clamp_min(configured_trust_yield, 0.0)
    end

    local fallback_trust_yield = TRUST_YIELD_BY_UNIT_ID[tonumber(unit_id)]
    if fallback_trust_yield ~= nil then
        return fallback_trust_yield
    end

    return 0.0
end

local function get_trust_mastery_id(unit_data)
    if not unit_data then
        return nil
    end

    if unit_data.trust_mastery_id ~= nil then
        return tostring(unit_data.trust_mastery_id)
    end

    if type(unit_data.TMR) == "table" and unit_data.TMR[2] ~= nil then
        return tostring(unit_data.TMR[2])
    end

    return nil
end

local function is_duplicate_unit(base_unit, base_unit_data, material_unit, material_unit_data)
    if tostring(base_unit.unit_id) == tostring(material_unit.unit_id) then
        return true
    end

    local base_mastery = get_trust_mastery_id(base_unit_data)
    local material_mastery = get_trust_mastery_id(material_unit_data)
    if base_mastery and material_mastery and base_mastery == material_mastery then
        return true
    end

    return false
end

local function get_max_accumulated_exp(unit_data)
    if unit_data and tonumber(unit_data.max_accumulated_exp) then
        return math.max(0, math.floor(tonumber(unit_data.max_accumulated_exp)))
    end
    return DEFAULT_MAX_ACCUMULATED_EXP
end

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

    if unit.trust_reward_claimed == nil then
        unit.trust_reward_claimed = false
    end

    unit.current_accumulated_exp = math.floor(tonumber(unit.current_accumulated_exp) or tonumber(unit.bonus_exp) or 0)
    if unit.current_accumulated_exp < 0 then
        unit.current_accumulated_exp = 0
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

    local exp_pattern = get_progression_exp_pattern(unit.unit_id, unit_data, unit.current_rarity)
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

local function calculate_material_enhance_gains(material_unit, material_unit_data)
    local material_type = get_unit_type(material_unit_data)

    if material_type == UNIT_TYPE_EXP_MATERIAL then
        local exp_total = get_base_exp_yield(material_unit, material_unit_data) + get_material_accumulated_exp(material_unit)
        return exp_total, 0.0, 0
    end

    if material_type == UNIT_TYPE_TRUST_MATERIAL then
        local trust_total = get_trust_yield(material_unit.unit_id, material_unit_data) + get_material_accumulated_trust(material_unit)
        return 0, trust_total, 0
    end

    local base_exp = get_base_exp_yield(material_unit, material_unit_data)
    local stored_exp = get_material_accumulated_exp(material_unit)
    local xp_gain = base_exp + math.floor(stored_exp * PLAYABLE_ACCUMULATED_EXP_TRANSFER_RATE)

    return xp_gain, 0.0, 0
end

-- Returns reward_type ("EQUIP" or "MATERIA"), template_id, error_message.
local function resolve_trust_reward(unit_data)
    if not unit_data then
        return nil, nil, "Missing unit static data for trust reward"
    end

    if type(unit_data.TMR) == "table" and unit_data.TMR[2] ~= nil then
        local reward_type = tostring(unit_data.TMR[1] or "")
        local reward_id   = tostring(unit_data.TMR[2])

        if reward_type == "EQUIP" then
            if StaticData.equipment_data[reward_id] == nil then
                return nil, nil, "Trust reward equipment template not found"
            end
            return "EQUIP", reward_id, nil
        elseif reward_type == "MATERIA" then
            if StaticData.materia_data[reward_id] == nil then
                return nil, nil, "Trust reward materia template not found"
            end
            return "MATERIA", reward_id, nil
        else
            return nil, nil, "Unsupported trust reward type: " .. reward_type
        end
    end

    if unit_data.trust_mastery_id ~= nil then
        local reward_id = tostring(unit_data.trust_mastery_id)
        if StaticData.equipment_data[reward_id] ~= nil then
            return "EQUIP", reward_id, nil
        end
        if StaticData.materia_data[reward_id] ~= nil then
            return "MATERIA", reward_id, nil
        end
    end

    return nil, nil, "No supported trust reward configured"
end

-- Stores one or more instanced items (EQUIP or MATERIA) in the "equipment" collection.
-- Each instance carries an item_type field so the client can route to the correct data table.
local function grant_instanced_item(user_id, item_type, template_id, amount)
    local grant_count = math.max(1, math.floor(tonumber(amount) or 1))
    local writes = {}
    local granted_items = {}

    for _ = 1, grant_count do
        local item_instance = {
            instance_id = nk.uuid_v4(),
            template_id = tostring(template_id),
            item_type   = tostring(item_type),
            equipped_to = ""
        }
        table.insert(granted_items, item_instance)
        table.insert(writes, {
            collection = "equipment",
            key = item_instance.instance_id,
            user_id = user_id,
            value = item_instance,
            permission_read = 1,
            permission_write = 1
        })
    end

    local ok, err = pcall(nk.storage_write, writes)
    if not ok then
        return false, tostring(err), {}
    end

    return true, nil, granted_items
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

local function build_unit_instance(unit_id)
    local unit_data = StaticData.units_data[unit_id]
    if not unit_data then
        return nil
    end

    local exp_pattern = get_progression_exp_pattern(unit_id, unit_data, unit_data.rarity_min)
    local next_xp = StaticData.calculate_xp_for_level(2, exp_pattern)

    return {
        instance_id = nk.uuid_v4(),
        unit_id = unit_id,
        level = 1,
        xp = 0,
        current_rarity = unit_data.rarity_min or 1,
        next_xp = next_xp,
        equipment = {},
        trust_value = 0.0,
        trust_reward_claimed = false,
        limitburst_level = 1,
        limitburst_xp = 0,
        is_locked = false,
        current_accumulated_exp = 0
    }
end

local function summon_fixed_unit(context, unit_id, amount)
    local unit_data = StaticData.units_data[unit_id]
    if not unit_data then
        return nk.json_encode({error = "Unit data not found for unit_id " .. tostring(unit_id)})
    end

    local summon_amount = math.max(1, math.floor(tonumber(amount) or 1))
    local summoned_units = {}
    for _ = 1, summon_amount do
        local new_unit = build_unit_instance(unit_id)
        if not new_unit then
            return nk.json_encode({error = "Failed to build summoned unit"})
        end
        table.insert(summoned_units, new_unit)
    end

    Units.save_units(context.user_id, summoned_units)
    return nk.json_encode({summoned = summoned_units})
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
        local new_unit = build_unit_instance(unit_id)
        if not new_unit then
            return nk.json_encode({error = "Failed to build summoned unit for unit_id " .. tostring(unit_id)})
        end

        table.insert(summoned_units, new_unit)
    end

    Units.save_units(context.user_id, summoned_units)

    return nk.json_encode({summoned = summoned_units})
end

function Units.debug_add_exp_boost_units(context, payload)
    local request = Utilities.parse_payload(payload)
    if request == nil then
        return nk.json_encode({error = "Invalid JSON payload"})
    end

    local amount = request.amount or 3
    return summon_fixed_unit(context, "900020401", amount)
end

function Units.debug_add_trust_units(context, payload)
    local request = Utilities.parse_payload(payload)
    if request == nil then
        return nk.json_encode({error = "Invalid JSON payload"})
    end

    local amount = request.amount or 3
    return summon_fixed_unit(context, "904000105", amount)
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

    local exp_pattern = get_progression_exp_pattern(unit.unit_id, unit_data, unit.current_rarity)
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

    local exp_pattern = get_progression_exp_pattern(unit.unit_id, unit_data, unit.current_rarity)
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
    local base_unit_type = get_unit_type(base_unit_data)

    if base_unit_type == UNIT_TYPE_PLAYABLE then
        if base_unit.level >= base_max_level and base_unit.trust_value >= ENHANCE_MAX_TRUST_VALUE then
            return rpc_fail("Base unit is already at maximum level and trust")
        end
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

        local material_unit_data = StaticData.units_data[material_unit.unit_id]
        if not material_unit_data then
            return rpc_fail("Material unit data not found")
        end
        local material_type = get_unit_type(material_unit_data)

        if material_type == UNIT_TYPE_PLAYABLE and tonumber(material_unit.trust_value) ~= nil and tonumber(material_unit.trust_value) >= ENHANCE_MAX_TRUST_VALUE then
            return rpc_fail("One or more material units are already at 100% trust")
        end

        if base_unit_type == UNIT_TYPE_EXP_MATERIAL and material_type ~= UNIT_TYPE_EXP_MATERIAL then
            return rpc_fail("Cannot use non-EXP materials to enhance an EXP unit")
        end

        if base_unit_type == UNIT_TYPE_TRUST_MATERIAL and material_type ~= UNIT_TYPE_TRUST_MATERIAL then
            return rpc_fail("Cannot use non-trust materials to enhance a trust material unit")
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

    local granted_trust_reward = nil
    local trust_reward_warning = nil

    if base_unit_type == UNIT_TYPE_EXP_MATERIAL then
        local total_exp_to_add = 0
        for _, material_unit in ipairs(material_units) do
            local material_unit_data = StaticData.units_data[material_unit.unit_id]
            local xp_gain, _, _ = calculate_material_enhance_gains(material_unit, material_unit_data)
            total_exp_to_add = total_exp_to_add + xp_gain
        end

        local max_accumulated_exp = get_max_accumulated_exp(base_unit_data)
        base_unit.current_accumulated_exp = clamp_max(base_unit.current_accumulated_exp + total_exp_to_add, max_accumulated_exp)
    elseif base_unit_type == UNIT_TYPE_TRUST_MATERIAL then
        local total_trust_to_add = 0.0
        for _, material_unit in ipairs(material_units) do
            local material_unit_data = StaticData.units_data[material_unit.unit_id]
            local _, trust_gain, _ = calculate_material_enhance_gains(material_unit, material_unit_data)
            total_trust_to_add = total_trust_to_add + trust_gain
        end

        base_unit.trust_value = clamp_max(base_unit.trust_value + total_trust_to_add, ENHANCE_MAX_TRUST_VALUE)
    else
        local total_xp_gain = 0
        local total_trust_gain = 0.0
        local previous_trust_value = tonumber(base_unit.trust_value) or 0.0

        for _, material_unit in ipairs(material_units) do
            local material_unit_data = StaticData.units_data[material_unit.unit_id]
            local xp_gain, trust_gain, _ = calculate_material_enhance_gains(material_unit, material_unit_data)

            total_xp_gain = total_xp_gain + xp_gain
            total_trust_gain = total_trust_gain + trust_gain

            if get_unit_type(material_unit_data) == UNIT_TYPE_PLAYABLE and is_duplicate_unit(base_unit, base_unit_data, material_unit, material_unit_data) then
                total_trust_gain = total_trust_gain + PLAYABLE_DUPLICATE_TRUST_BONUS + get_material_accumulated_trust(material_unit)
            end
        end

        local exp_pattern = get_progression_exp_pattern(base_unit.unit_id, base_unit_data, base_unit.current_rarity)
        base_unit.xp = base_unit.xp + total_xp_gain
        base_unit.level = StaticData.calculate_level_from_xp(base_unit.xp, exp_pattern, base_max_level)
        update_unit_next_xp(base_unit, base_unit_data)

        base_unit.trust_value = base_unit.trust_value + total_trust_gain
        if base_unit.trust_value > ENHANCE_MAX_TRUST_VALUE then
            base_unit.trust_value = ENHANCE_MAX_TRUST_VALUE
        end

        if previous_trust_value < ENHANCE_MAX_TRUST_VALUE and base_unit.trust_value >= ENHANCE_MAX_TRUST_VALUE and base_unit.trust_reward_claimed ~= true then
            local reward_type, reward_template_id, reward_warning = resolve_trust_reward(base_unit_data)
            if reward_template_id ~= nil then
                local grant_ok, grant_err, granted_items = grant_instanced_item(context.user_id, reward_type, reward_template_id, 1)
                if grant_ok then
                    granted_trust_reward = {
                        reward_type = reward_type,
                        template_id = reward_template_id,
                        quantity = 1,
                        granted_equipment = granted_items
                    }
                    base_unit.trust_reward_claimed = true
                else
                    trust_reward_warning = "Failed to grant trust reward: " .. tostring(grant_err)
                end
            else
                trust_reward_warning = reward_warning
            end
        end
    end

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
            limitburst_xp = base_unit.limitburst_xp,
            current_accumulated_exp = base_unit.current_accumulated_exp
        },
        consumed_material_ids = material_unit_instance_ids,
        updated_currency = {
            gil = tonumber(updated_wallet.gil) or 0
        },
        granted_trust_reward = granted_trust_reward,
        trust_reward_warning = trust_reward_warning
    })
end

return Units
