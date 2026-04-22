local nk = require("nakama")
local StaticData = require("core.static_data")
local Units = require("features.units")
local Utilities = require("core.utilities")

local Inventory = {}

function Inventory.get_stackables(user_id)
    local object_ids = {
        {collection = "inventory", key = "stackables", user_id = user_id}
    }
    local objects = nk.storage_read(object_ids)
    if #objects > 0 then
        return objects[1].value
    end
    return {}
end

function Inventory.save_stackables(user_id, stackables)
    nk.storage_write({
        {
            collection = "inventory",
            key = "stackables",
            user_id = user_id,
            value = stackables,
            permission_read = 1,
            permission_write = 1
        }
    })
end

function Inventory.remove_stackables(user_id, items_to_remove)
    if not items_to_remove or type(items_to_remove) ~= "table" then
        return false, "Invalid items_to_remove table"
    end

    local stackables = Inventory.get_stackables(user_id)
    for item_id, count in pairs(items_to_remove) do
        local id_str = tostring(item_id)
        if type(count) == "number" and count > 0 then
            stackables[id_str] = (stackables[id_str] or 0) - count
            if stackables[id_str] < 0 then
                stackables[id_str] = 0
            end
        end
    end
    Inventory.save_stackables(user_id, stackables)
    return true
end

function Inventory.get_equipment(user_id)
    local equipment = {}
    local cursor = nil

    repeat
        local objects, next_cursor = nk.storage_list(user_id, "equipment", 100, cursor)
        for _, obj in ipairs(objects) do
            table.insert(equipment, obj.value)
        end
        cursor = next_cursor
    until not cursor

    return equipment
end

function Inventory.save_equipment(user_id, equips)
    local writes = {}
    for _, eq in ipairs(equips) do
        table.insert(writes, {
            collection = "equipment",
            key = eq.instance_id,
            user_id = user_id,
            value = eq,
            permission_read = 1,
            permission_write = 1
        })
    end
    if #writes > 0 then
        nk.storage_write(writes)
    end
end

function Inventory.get_player_items_rpc(context, payload)
    local stackables = Inventory.get_stackables(context.user_id)
    local equipment = Inventory.get_equipment(context.user_id)

    return nk.json_encode({
        stackables = stackables,
        equipment = equipment
    })
end

function Inventory.add_item(context, payload)
    local request = Utilities.parse_payload(payload)
    if not request then
        return nk.json_encode({error = "Invalid JSON payload"})
    end
    local item_id = request.item_id
    local quantity = request.quantity or 1

    if quantity > 10000 then
        return nk.json_encode({error = "Amount exceeds debug limits"})
    end

    if not item_id or quantity <= 0 then
        return nk.json_encode({error = "Invalid parameters"})
    end

    if StaticData.equipment_data and StaticData.equipment_data[item_id] then
        -- It's an equipment
        local new_equips = {}
        for i = 1, quantity do
            table.insert(new_equips, {
                instance_id = nk.uuid_v4(),
                template_id = item_id,
                equipped_to = ""
            })
        end
        Inventory.save_equipment(context.user_id, new_equips)
        return nk.json_encode({success = true, added_equipment = new_equips})
    elseif StaticData.items_data and StaticData.items_data[item_id] then
        -- It's a stackable
        local stackables = Inventory.get_stackables(context.user_id)
        stackables[item_id] = (stackables[item_id] or 0) + quantity
        Inventory.save_stackables(context.user_id, stackables)
        return nk.json_encode({success = true, stackables = stackables})
    else
        return nk.json_encode({error = "Item data not found"})
    end
end

function Inventory.rpc_equip_item(context, payload)
    local request = Utilities.parse_payload(payload)
    if not request then
        return nk.json_encode({error = "Invalid JSON payload"})
    end
    local unit_id = request.unit_instance_id
    local slot = request.slot
    local item_instance_id = request.item_instance_id -- nil or empty string implies unequip

    if not unit_id or not slot then
        return nk.json_encode({error = "Missing unit_instance_id or slot"})
    end

    local valid_slots = {
        r_hand = true, l_hand = true, head = true,
        body = true, accessory1 = true, accessory2 = true
    }

    if not valid_slots[slot] then
        return nk.json_encode({error = "Invalid slot: " .. tostring(slot)})
    end

    local target_unit = Units.get_unit(context.user_id, unit_id)
    if not target_unit then
        return nk.json_encode({error = "Unit not found"})
    end

    if not target_unit.equipment then
        target_unit.equipment = {}
    end

    local is_unequipping = (not item_instance_id or item_instance_id == "")
    local updated_units = {[target_unit.instance_id] = target_unit}
    local updated_equips = {}

    if is_unequipping then
        local old_item_instance_id = target_unit.equipment[slot]
        target_unit.equipment[slot] = nil

        if old_item_instance_id then
            local obj_id = {collection = "equipment", key = old_item_instance_id, user_id = context.user_id}
            local objects = nk.storage_read({obj_id})
            if #objects > 0 then
                local eq_obj = objects[1].value
                eq_obj.equipped_to = ""
                updated_equips[eq_obj.instance_id] = eq_obj
            end
        end
    else
        -- Equipping validation
        local obj_id = {collection = "equipment", key = item_instance_id, user_id = context.user_id}
        local objects = nk.storage_read({obj_id})
        if #objects == 0 then
            return nk.json_encode({error = "Equipment instance not found or not owned"})
        end
        local eq_obj = objects[1].value

        local template_id = eq_obj.template_id
        local eq_data = StaticData.equipment_data[template_id]
        if not eq_data then
            return nk.json_encode({error = "Invalid equipment template_id: " .. tostring(template_id)})
        end

        local unit_base_data = StaticData.units_data[target_unit.unit_id]
        if not unit_base_data then
            return nk.json_encode({error = "Base unit data not found"})
        end

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

        -- Prevent equipping the exact same item instance to multiple slots on the same unit
        for s, inst_id in pairs(target_unit.equipment) do
            if inst_id == item_instance_id and s ~= slot then
                target_unit.equipment[s] = nil
            end
        end

        -- Check if it's already equipped to another unit
        if eq_obj.equipped_to and eq_obj.equipped_to ~= "" and eq_obj.equipped_to ~= target_unit.instance_id then
            local other_unit_id = eq_obj.equipped_to
            local other_unit = Units.get_unit(context.user_id, other_unit_id)
            if other_unit and other_unit.equipment then
                for s, inst_id in pairs(other_unit.equipment) do
                    if inst_id == item_instance_id then
                        other_unit.equipment[s] = nil
                        break
                    end
                end
                updated_units[other_unit.instance_id] = other_unit
            end
        end

        -- If replacing an item, mark the old item as unequipped
        local old_item_instance_id = target_unit.equipment[slot]
        if old_item_instance_id and old_item_instance_id ~= item_instance_id then
            local old_obj_id = {collection = "equipment", key = old_item_instance_id, user_id = context.user_id}
            local old_objects = nk.storage_read({old_obj_id})
            if #old_objects > 0 then
                local old_eq_obj = old_objects[1].value
                old_eq_obj.equipped_to = ""
                updated_equips[old_eq_obj.instance_id] = old_eq_obj
            end
        end

        eq_obj.equipped_to = target_unit.instance_id
        target_unit.equipment[slot] = item_instance_id
        updated_equips[eq_obj.instance_id] = eq_obj

        -- Two-handed rule
        if eq_data.is_two_handed or eq_data.is_twohanded then
            local off_slot = (slot == "r_hand") and "l_hand" or "r_hand"
            local off_item_instance_id = target_unit.equipment[off_slot]
            if off_item_instance_id then
                target_unit.equipment[off_slot] = nil
                local off_obj_id = {collection = "equipment", key = off_item_instance_id, user_id = context.user_id}
                local off_objects = nk.storage_read({off_obj_id})
                if #off_objects > 0 then
                    local off_eq_obj = off_objects[1].value
                    off_eq_obj.equipped_to = ""
                    updated_equips[off_eq_obj.instance_id] = off_eq_obj
                end
            end
        end
    end

    local units_to_save = {}
    for _, u in pairs(updated_units) do table.insert(units_to_save, u) end
    Units.save_units(context.user_id, units_to_save)

    local equips_to_save = {}
    for _, e in pairs(updated_equips) do table.insert(equips_to_save, e) end
    Inventory.save_equipment(context.user_id, equips_to_save)

    return nk.json_encode({success = true, units_updated = units_to_save, equips_updated = equips_to_save})
end

return Inventory
