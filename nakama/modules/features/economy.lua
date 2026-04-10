local nk = require("nakama")
local StaticData = require("core.static_data")
local Inventory = require("features.inventory")
local Utilities = require("core.utilities")

local Economy = {}

function Economy.add_currency(context, payload)
    local request = Utilities.parse_payload(payload)
    if not request then
        return nk.json_encode({error = "Invalid JSON payload"})
    end
    local gil = request.gil or 0
    local lapis = request.lapis or 0

    if gil > 10000 or lapis > 10000 then
        return nk.json_encode({error = "Amount exceeds debug limits"})
    end

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

function Economy.buy_item(context, payload)
    local request = Utilities.parse_payload(payload)
    if not request then
        return nk.json_encode({error = "Invalid JSON payload"})
    end
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
            wallet = Utilities.parse_payload(account.wallet) or {}
        end
    end

    local current_gil = wallet.gil or 0

    local is_equipment = false
    local item_data = StaticData.equipment_data[item_id]

    if item_data then
        is_equipment = true
    else
        item_data = StaticData.items_data[item_id]
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
    local response_payload = {success = true}

    if is_equipment then
        local new_equips = {}
        for i = 1, quantity do
            table.insert(new_equips, {
                instance_id = nk.uuid_v4(),
                template_id = item_id,
                equipped_to = ""
            })
        end
        Inventory.save_equipment(context.user_id, new_equips)
        response_payload.added_equipment = new_equips
    else
        local stackables = Inventory.get_stackables(context.user_id)
        stackables[item_id] = (stackables[item_id] or 0) + quantity
        Inventory.save_stackables(context.user_id, stackables)
        response_payload.stackables = stackables
    end

    -- Return the updated wallet to the client
    account = nk.account_get_id(context.user_id)
    response_payload.wallet = account.wallet

    return nk.json_encode(response_payload)
end

return Economy
