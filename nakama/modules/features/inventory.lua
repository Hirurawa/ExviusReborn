local nk = require("nakama")
local StaticData = require("core.static_data")
local Units = require("features.units")

local Inventory = {}

function Inventory.get_player_items(user_id)
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

function Inventory.save_player_items(user_id, items)
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

function Inventory.add_item(context, payload)
    local request = nk.json_decode(payload)
    local item_id = request.item_id
    local quantity = request.quantity or 1

    if not item_id or quantity <= 0 then
        return nk.json_encode({error = "Invalid parameters"})
    end

    local item_data = StaticData.items_data[item_id]
    if not item_data then
        return nk.json_encode({error = "Item data not found"})
    end

    local player_items = Inventory.get_player_items(context.user_id)
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

    Inventory.save_player_items(context.user_id, player_items)

    return nk.json_encode({success = true, items = player_items})
end

function Inventory.rpc_equip_item(context, payload)
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

    local player_units = Units.get_player_units(context.user_id)
    local player_items = Inventory.get_player_items(context.user_id)

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
        local eq_data = StaticData.equipment_data[item_id]
        if not eq_data then
            return nk.json_encode({error = "Invalid equipment item_id: " .. tostring(item_id)})
        end

        local unit_base_data = StaticData.units_data[target_unit.unit_id]
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

    Units.save_player_units(context.user_id, player_units)

    return nk.json_encode({success = true, units = player_units})
end

return Inventory
