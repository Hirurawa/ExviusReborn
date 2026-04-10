local nk = require("nakama")
local StaticData = require("core.static_data")

local PlayerData = {}

function PlayerData.get_player_stats(context, payload)
    local object_ids = {
        {collection = "stats", key = "player_stats", user_id = context.user_id}
    }
    local objects = nk.storage_read(object_ids)

    local stats = {
        rank = 1,
        xp = 0,
        current_nrg = 41,
        last_nrg_update_time = math.floor(nk.time() / 1000)
    }

    if #objects > 0 then
        local data = objects[1].value
        if data then
            stats.rank = data.rank or stats.rank
            stats.xp = data.xp or stats.xp
            -- Backwards compatibility with old energy fields
            stats.current_nrg = data.current_nrg or data.energy or stats.current_nrg
            stats.last_nrg_update_time = data.last_nrg_update_time or data.last_energy_update_time or stats.last_nrg_update_time
        end
    end

    local max_energy
    if not StaticData.RankData[1] then
        -- Fallback if CSV is missing or empty
        max_energy = 41
    elseif stats.rank > StaticData.MaxRank then
        max_energy = StaticData.RankData[StaticData.MaxRank].energy
    elseif StaticData.RankData[stats.rank] then
        max_energy = StaticData.RankData[stats.rank].energy
    else
        max_energy = 41
    end

    local current_time = math.floor(nk.time() / 1000)
    local elapsed_seconds = current_time - stats.last_nrg_update_time

    -- In case of time skew, don't allow negative elapsed time
    if elapsed_seconds < 0 then elapsed_seconds = 0 end

    local nrg_regen_rate_seconds = 300
    local seconds_until_next_nrg = 0

    local stats_changed = false

    if stats.current_nrg >= max_energy then
        -- Player is at or above max energy (overflow).
        -- Don't add passive energy, update timestamp to now so they don't accrue
        if elapsed_seconds > 0 then
            stats.last_nrg_update_time = current_time
            stats_changed = true
        end
        seconds_until_next_nrg = 0
    else
        -- Player is under max energy and should gain some.
        local energy_to_add = math.floor(elapsed_seconds / nrg_regen_rate_seconds)
        local remainder = elapsed_seconds % nrg_regen_rate_seconds

        if energy_to_add > 0 then
            stats.current_nrg = stats.current_nrg + energy_to_add
            if stats.current_nrg > max_energy then
                stats.current_nrg = max_energy
                stats.last_nrg_update_time = current_time
                seconds_until_next_nrg = 0
            else
                stats.last_nrg_update_time = current_time - remainder
                seconds_until_next_nrg = nrg_regen_rate_seconds - remainder
            end
            stats_changed = true
        else
            seconds_until_next_nrg = nrg_regen_rate_seconds - remainder
        end
    end

    if stats_changed then
        -- Save updated stats
        local write_objects = {
            {
                collection = "stats",
                key = "player_stats",
                user_id = context.user_id,
                value = stats,
                permission_read = 1,
                permission_write = 1
            }
        }
        nk.storage_write(write_objects)
    end

    local next_rank_xp = 0
    if stats.rank < StaticData.MaxRank then
        next_rank_xp = StaticData.RankData[stats.rank + 1].exp
    end

    local payload_out = {
        rank = stats.rank,
        xp = stats.xp,
        next_rank_xp = next_rank_xp,
        current_nrg = stats.current_nrg,
        max_nrg = max_energy,
        nrg_regen_rate_seconds = nrg_regen_rate_seconds,
        seconds_until_next_nrg = seconds_until_next_nrg,
        -- Backward compatibility
        energy = stats.current_nrg,
        max_energy = max_energy
    }

    return nk.json_encode(payload_out)
end

function PlayerData.add_rank_xp(context, payload)
    local request = nk.json_decode(payload)
    local xp_amount = request.xp_amount or 0

    if xp_amount <= 0 then
        return nk.json_encode({error = "Invalid xp amount"})
    end

    -- First sync current energy
    local stats_str = PlayerData.get_player_stats(context, "")
    local stats = nk.json_decode(stats_str)

    stats.xp = stats.xp + xp_amount

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
        -- Recalculate final max energy to return it properly
        local final_max_energy = StaticData.RankData[stats.rank].energy
        stats.max_energy = final_max_energy
        stats.max_nrg = final_max_energy
    end

    local next_rank_xp = 0
    if stats.rank < StaticData.MaxRank and StaticData.RankData[stats.rank + 1] then
        next_rank_xp = StaticData.RankData[stats.rank + 1].exp
    end
    stats.next_rank_xp = next_rank_xp

    -- Re-fetch the real raw storage object to properly update the DB with current_nrg and timestamp
    local object_ids = {
        {collection = "stats", key = "player_stats", user_id = context.user_id}
    }
    local objects = nk.storage_read(object_ids)

    local raw_stats = {}
    if #objects > 0 then
        raw_stats = objects[1].value
    end

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

    return nk.json_encode(stats)
end

return PlayerData
