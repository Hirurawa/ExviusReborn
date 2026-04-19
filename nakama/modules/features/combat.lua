local nk = require("nakama")
local StaticData = require("core.static_data")
local PlayerData = require("core.player_data")
local Utilities = require("core.utilities")

local Combat = {}

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
    local raw_stats = objects[1].value

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

    local mission_data = StaticData.missions_data[tostring(mission_id)]

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
                last_nrg_update_time = raw_stats.last_nrg_update_time or raw_stats.last_energy_update_time or math.floor(nk.time() / 1000)
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
                last_nrg_update_time = raw_stats.last_nrg_update_time or raw_stats.last_energy_update_time or math.floor(nk.time() / 1000)
                -- active_mission is omitted, clearing it
            },
            permission_read = 1,
            permission_write = 1
        }
    }
    nk.storage_write(write_objects)

    -- Add gil
    local wallet_out = {}
    if gil_reward > 0 then
        local changeset = { gil = gil_reward }
        local metadata = { source = "finish_mission", mission_id = mission_id }
        local status, result = pcall(nk.wallet_update, context.user_id, changeset, metadata, true)
        if not status then
            return nk.json_encode({success = false, error_message = "Failed to update wallet: " .. tostring(result)})
        end
    end

    local account = nk.account_get_id(context.user_id)

    return nk.json_encode({
        success = true,
        gameplay_result = "win",
        rewards = {
            stats = stats,
            wallet = account.wallet
        }
    })
end

return Combat
