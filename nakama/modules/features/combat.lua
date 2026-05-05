local nk = require("nakama")
local StaticData = require("core.static_data")
local PlayerData = require("core.player_data")
local Utilities = require("core.utilities")
local Inventory = require("features.inventory")

local Combat = {}

local function get_mission_progress(user_id)
    local object_ids = {
        {collection = "mission_progress", key = "cleared_missions", user_id = user_id}
    }
    local objects = nk.storage_read(object_ids)
    if #objects == 0 or not objects[1].value then
        return {}
    end
    return objects[1].value
end

local function save_mission_progress(user_id, mission_key, objectives)
    local progress = get_mission_progress(user_id)
    progress[mission_key] = {
        cleared = true,
        objectives = objectives
    }

    nk.storage_write({
        {
            collection = "mission_progress",
            key = "cleared_missions",
            user_id = user_id,
            value = progress,
            permission_read = 1,
            permission_write = 1
        }
    })
end

local function normalize_currency_key(raw_currency)
    if type(raw_currency) ~= "string" then
        return nil
    end
    return string.lower(raw_currency)
end

local function is_wallet_currency(currency_key)
    return currency_key == "gil" or currency_key == "lapis"
end

local function add_reward_tuple(changeset, reward_tuple)
    if type(reward_tuple) ~= "table" or #reward_tuple < 3 then
        return
    end

    local currency_key = normalize_currency_key(reward_tuple[1])
    local amount = tonumber(reward_tuple[3])
    if not currency_key or not amount or amount == 0 then
        return
    end

    -- Only wallet currencies are supported in this reward path for now.
    if not is_wallet_currency(currency_key) then
        return
    end

    changeset[currency_key] = (changeset[currency_key] or 0) + amount
end

local function get_optional_objective_rewards(mission_data)
    local rewards = {}
    local challenges = mission_data and mission_data.challenges
    if type(challenges) ~= "table" or #challenges == 0 then
        return rewards
    end

    -- Prefer skipping base completion challenge when present.
    local start_index = 1
    if #challenges >= 4 then
        start_index = 2
    end

    for i = start_index, math.min(start_index + 2, #challenges) do
        local challenge = challenges[i]
        if challenge and challenge.reward then
            table.insert(rewards, challenge.reward)
        end
    end

    return rewards
end

local function apply_mission_drops_to_stackables(user_id, mission_drops)
    if type(mission_drops) ~= "table" or #mission_drops == 0 then
        return
    end

    local stackables = Inventory.get_stackables(user_id)
    local changed = false

    for _, item_id in ipairs(mission_drops) do
        local id_str = tostring(item_id)
        if id_str ~= "" then
            stackables[id_str] = (stackables[id_str] or 0) + 1
            changed = true
        end
    end

    if changed then
        Inventory.save_stackables(user_id, stackables)
    end
end

function Combat.start_mission(context, payload)
    local request = Utilities.parse_payload(payload)
    if not request then
        return nk.json_encode({success = false, error_message = "Invalid JSON payload"})
    end
    local mission_id = request.mission_id

    if not mission_id then
        return nk.json_encode({success = false, error_message = "Invalid mission_id"})
    end

    local mission_data = StaticData.missions_data[tostring(mission_id)]
    if not mission_data then
        return nk.json_encode({success = false, error_message = "Mission not found"})
    end

    local cost_type = mission_data.cost_type or "NRG"
    local cost = mission_data.cost or 0

    -- First sync current stats
    local stats_str = PlayerData.get_player_stats(context, "")
    local stats = Utilities.parse_payload(stats_str)
    if not stats then
        return nk.json_encode({success = false, error_message = "Failed to parse player stats"})
    end

    if cost_type == "NRG" then
        if stats.current_nrg < cost then
            return nk.json_encode({success = false, error_message = "Not enough NRG"})
        end
        stats.current_nrg = stats.current_nrg - cost
        stats.energy = stats.current_nrg -- keep backward compatibility
    else
        -- If other costs are introduced later
    end

    -- Save stats and set active_mission
    local object_ids = {
        {collection = "stats", key = "player_stats", user_id = context.user_id}
    }
    local objects = nk.storage_read(object_ids)
    local raw_stats = {}
    if #objects > 0 and objects[1].value then
        raw_stats = objects[1].value
    end

    -- Check if player already has an active mission, could be optional but good for safety
    if raw_stats.active_mission then
        return nk.json_encode({success = false, error_message = "Player already has an active mission"})
    end

    local current_time = math.floor(nk.time() / 1000)

    local write_objects = {
        {
            collection = "stats",
            key = "player_stats",
            user_id = context.user_id,
            value = {
                rank = stats.rank,
                xp = stats.xp,
                current_nrg = stats.current_nrg,
                last_nrg_update_time = raw_stats.last_nrg_update_time or raw_stats.last_energy_update_time or current_time,
                last_entered_mission_id = tostring(mission_id),
                active_mission = {
                    mission_id = mission_id,
                    start_time = current_time
                }
            },
            permission_read = 1,
            permission_write = 1
        }
    }
    nk.storage_write(write_objects)

    return nk.json_encode({success = true})
end

function Combat.finish_mission(context, payload)
    local request = Utilities.parse_payload(payload)
    if not request then
        return nk.json_encode({success = false, error_message = "Invalid JSON payload"})
    end

    -- Treat win_status as true unless explicitly passed as false
    local win_status = true
    if request.win_status == false then
        win_status = false
    end

    -- Read current stats
    local object_ids = {
        {collection = "stats", key = "player_stats", user_id = context.user_id}
    }
    local objects = nk.storage_read(object_ids)
    if #objects == 0 then
        return nk.json_encode({success = false, error_message = "Player stats not found"})
    end

    local raw_stats = objects[1].value
    if not raw_stats.active_mission then
        return nk.json_encode({success = false, error_message = "No active mission found"})
    end

    local active_mission = raw_stats.active_mission
    local mission_id = active_mission.mission_id
    local mission_key = "mission_" .. tostring(mission_id)

    local mission_data = StaticData.missions_data[tostring(mission_id)]

    -- Anti-cheat validation for used items
    if request.used_items and type(request.used_items) == "table" then
        local stackables = Inventory.get_stackables(context.user_id)
        for item_id, used_count in pairs(request.used_items) do
            local id_str = tostring(item_id)
            if type(used_count) == "number" and used_count > 0 then
                local current_amount = stackables[id_str] or 0
                if current_amount < used_count then
                    return nk.json_encode({success = false, error_message = "Anti-cheat: Not enough items"})
                end
            end
        end
        -- Deduction
        Inventory.remove_stackables(context.user_id, request.used_items)
    end

    -- Clear the active mission lock
    local write_objects = {
        {
            collection = "stats",
            key = "player_stats",
            user_id = context.user_id,
            value = {
                rank = raw_stats.rank,
                xp = raw_stats.xp,
                current_nrg = raw_stats.current_nrg,
                last_nrg_update_time = raw_stats.last_nrg_update_time or raw_stats.last_energy_update_time or math.floor(nk.time() / 1000),
                last_entered_mission_id = tostring(raw_stats.last_entered_mission_id or mission_id)
                -- active_mission is omitted, thus clearing it
            },
            permission_read = 1,
            permission_write = 1
        }
    }

    if not win_status then
        -- Game Over or Surrender
        nk.storage_write(write_objects)
        return nk.json_encode({success = true, gameplay_result = "loss", rewards = {}})
    end

    if not mission_data then
        nk.storage_write(write_objects)
        return nk.json_encode({success = false, error_message = "Mission data not found for active mission"})
    end

    local mission_progress = get_mission_progress(context.user_id)
    local is_first_clear = mission_progress[mission_key] == nil

    local gil_reward = mission_data.gil or 0
    local exp_reward = mission_data.exp or 0

    -- Apply EXP via get_player_stats logic for energy updates
    local stats_str = PlayerData.get_player_stats(context, "")
    local stats = Utilities.parse_payload(stats_str)

    if exp_reward > 0 then
        stats.xp = stats.xp + exp_reward

        local rank_up_occurred = false

        if StaticData.RankData[1] then
            while stats.rank < StaticData.MaxRank and StaticData.RankData[stats.rank + 1] and stats.xp >= StaticData.RankData[stats.rank + 1].exp do
                local required_exp = StaticData.RankData[stats.rank + 1].exp
                if required_exp <= 0 then
                    break -- Should not happen, but safe guard
                end

                stats.xp = stats.xp - required_exp
                stats.rank = stats.rank + 1

                if StaticData.RankData[stats.rank] then
                    local new_max_energy = StaticData.RankData[stats.rank].energy
                    stats.current_nrg = stats.current_nrg + new_max_energy
                    stats.energy = stats.current_nrg -- keep backward compatibility in this table before saving
                end
                rank_up_occurred = true
            end
        end

        if rank_up_occurred and StaticData.RankData[stats.rank] then
            local final_max_energy = StaticData.RankData[stats.rank].energy
            stats.max_energy = final_max_energy
            stats.max_nrg = final_max_energy
        end
    end

    -- Always ensure next_rank_xp is populated in the returned stats
    local next_rank_xp = 0
    if stats.rank < StaticData.MaxRank and StaticData.RankData[stats.rank + 1] then
        next_rank_xp = StaticData.RankData[stats.rank + 1].exp
    end
    stats.next_rank_xp = next_rank_xp

    -- Refetch objects after get_player_stats since it might have written to DB
    objects = nk.storage_read(object_ids)
    raw_stats = objects[1].value

    write_objects = {
        {
            collection = "stats",
            key = "player_stats",
            user_id = context.user_id,
            value = {
                rank = stats.rank,
                xp = stats.xp,
                current_nrg = stats.current_nrg,
                last_nrg_update_time = raw_stats.last_nrg_update_time or raw_stats.last_energy_update_time or math.floor(nk.time() / 1000),
                last_entered_mission_id = tostring(raw_stats.last_entered_mission_id or mission_id)
                -- active_mission is omitted, clearing it
            },
            permission_read = 1,
            permission_write = 1
        }
    }
    nk.storage_write(write_objects)

    -- Use challenge_results from the payload if provided and valid, otherwise fall back
    -- to marking all objectives complete (backward-compatible default).
    local objective_flags = {true, true, true}
    if type(request.challenge_results) == "table" and #request.challenge_results > 0 then
        objective_flags = {}
        for i, v in ipairs(request.challenge_results) do
            objective_flags[i] = v == true
        end
    end

    local wallet_changeset = {}
    if gil_reward > 0 then
        wallet_changeset.gil = gil_reward
    end

    if is_first_clear then
        if type(mission_data.rewards) == "table" then
            for _, reward_tuple in ipairs(mission_data.rewards) do
                add_reward_tuple(wallet_changeset, reward_tuple)
            end
        end

        local optional_rewards = get_optional_objective_rewards(mission_data)
        for _, reward_tuple in ipairs(optional_rewards) do
            add_reward_tuple(wallet_changeset, reward_tuple)
        end
    end

    if next(wallet_changeset) ~= nil then
        local metadata = {
            source = "finish_mission",
            mission_id = mission_id,
            first_clear = is_first_clear
        }
        local status, result = pcall(nk.wallet_update, context.user_id, wallet_changeset, metadata, true)
        if not status then
            return nk.json_encode({success = false, error_message = "Failed to update wallet: " .. tostring(result)})
        end
    end

    if is_first_clear then
        save_mission_progress(context.user_id, mission_key, objective_flags)
    end

    apply_mission_drops_to_stackables(context.user_id, request.mission_drops)

    local account = nk.account_get_id(context.user_id)

    return nk.json_encode({
        success = true,
        gameplay_result = "win",
        first_clear = is_first_clear,
        mission_progress = {
            key = mission_key,
            cleared = true,
            objectives = objective_flags
        },
        rewards = {
            stats = stats,
            wallet = account.wallet
        }
    })
end

return Combat
