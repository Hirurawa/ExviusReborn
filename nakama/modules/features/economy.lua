local nk = require("nakama")
local StaticData = require("core.static_data")
local Inventory = require("features.inventory")

local Economy = {}

function Economy.add_currency(context, payload)
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

function Economy.buy_item(context, payload)
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

    local item_data = StaticData.items_data[item_id]
    if not item_data then
        item_data = StaticData.equipment_data[item_id]
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

    -- Return the updated wallet to the client
    account = nk.account_get_id(context.user_id)
    return nk.json_encode({success = true, wallet = account.wallet, items = player_items})
end

return Economy
