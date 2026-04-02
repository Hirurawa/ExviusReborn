import re

with open('nakama/modules/main.lua', 'r') as f:
    content = f.read()

# Let's extract the exact old function to be absolutely sure.
pattern = re.compile(r'local function add_rank_xp\(context, payload\).*?return nk\.json_encode\(stats\)\nend', re.DOTALL)
match = pattern.search(content)

new_func = """local function add_rank_xp(context, payload)
    local request = nk.json_decode(payload)
    local xp_amount = request.xp_amount or 0

    if xp_amount <= 0 then
        return nk.json_encode({error = "Invalid xp amount"})
    end

    -- First sync current energy
    local stats_str = get_player_stats(context, "")
    local stats = nk.json_decode(stats_str)

    stats.xp = stats.xp + xp_amount

    local rank_up_occurred = false
    while stats.xp >= stats.rank * 100 and stats.rank < 300 do
        stats.xp = stats.xp - (stats.rank * 100)
        stats.rank = stats.rank + 1

        local new_max_energy
        if stats.rank <= 100 then
            new_max_energy = stats.rank + 40
        else
            new_max_energy = 140 + math.floor((stats.rank - 100) / 2)
        end
        if new_max_energy > 240 then new_max_energy = 240 end

        stats.current_nrg = stats.current_nrg + new_max_energy
        stats.energy = stats.current_nrg -- keep backward compatibility in this table before saving
        rank_up_occurred = true
    end

    if rank_up_occurred then
        -- Recalculate final max energy to return it properly
        local final_max_energy
        if stats.rank <= 100 then
            final_max_energy = stats.rank + 40
        else
            final_max_energy = 140 + math.floor((stats.rank - 100) / 2)
        end
        if final_max_energy > 240 then final_max_energy = 240 end
        stats.max_energy = final_max_energy
        stats.max_nrg = final_max_energy
    end

    -- Re-fetch the real raw storage object to properly update the DB with current_nrg and timestamp
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

    return nk.json_encode(stats)
end"""

if match:
    content = content[:match.start()] + new_func + content[match.end():]
    with open('nakama/modules/main.lua', 'w') as f:
        f.write(content)
    print("Replaced add_rank_xp")
else:
    print("Failed to replace add_rank_xp")
