local nk = require("nakama")
local StaticData = require("core.static_data")
local PlayerData = require("core.player_data")

local Combat = {}

function Combat.perform_mission(context, payload)
    local request = nk.json_decode(payload)
    local mission_id = request.mission_id

    if not mission_id then
        return nk.json_encode({error = "Invalid mission_id"})
    end

    local mission_data = StaticData.missions_data[tostring(mission_id)]
    if not mission_data then
        return nk.json_encode({error = "Mission not found"})
    end

    local cost_type = mission_data.cost_type or "NRG"
    local cost = mission_data.cost or 0
    local gil_reward = mission_data.gil or 0
    local exp_reward = mission_data.exp or 0

    -- First sync current stats
    local stats_str = PlayerData.get_player_stats(context, "")
    local stats = nk.json_decode(stats_str)

    if cost_type == "NRG" then
        if stats.current_nrg < cost then
            return nk.json_encode({error = "Not enough NRG"})
        end
        stats.current_nrg = stats.current_nrg - cost
        stats.energy = stats.current_nrg -- keep backward compatibility
    else
        -- If other costs are introduced later
    end

    -- Add exp
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

    -- Save stats
    local object_ids = {
        {collection = "stats", key = "player_stats", user_id = context.user_id}
    }
    local objects = nk.storage_read(object_ids)
    local raw_stats = objects[1].value

    local write_objects = {
        {
            collection = "stats",
            key = "player_stats",
            user_id = context.user_id,
            value = {
                rank = stats.rank,
                xp = stats.xp,
                current_nrg = stats.current_nrg,
                last_nrg_update_time = raw_stats.last_nrg_update_time or raw_stats.last_energy_update_time or math.floor(nk.time() / 1000)
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
        local metadata = { source = "perform_mission", mission_id = mission_id }
        local status, result = pcall(nk.wallet_update, context.user_id, changeset, metadata, true)
        if not status then
            return nk.json_encode({error = "Failed to update wallet: " .. tostring(result)})
        end
    end

    local account = nk.account_get_id(context.user_id)
    return nk.json_encode({
        success = true,
        stats = stats,
        wallet = account.wallet
    })
end

return Combat
