import re

with open('nakama/modules/main.lua', 'r') as f:
    content = f.read()

# Let's extract the exact old function to be absolutely sure.
pattern = re.compile(r'local function get_player_stats\(context, payload\).*?return nk\.json_encode\([^)]+\)\nend', re.DOTALL)
match = pattern.search(content)

new_func = """local function get_player_stats(context, payload)
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
    if stats.rank <= 100 then
        max_energy = stats.rank + 40
    else
        max_energy = 140 + math.floor((stats.rank - 100) / 2)
    end
    if max_energy > 240 then max_energy = 240 end

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

    local payload_out = {
        rank = stats.rank,
        xp = stats.xp,
        current_nrg = stats.current_nrg,
        max_nrg = max_energy,
        nrg_regen_rate_seconds = nrg_regen_rate_seconds,
        seconds_until_next_nrg = seconds_until_next_nrg,
        -- Backward compatibility
        energy = stats.current_nrg,
        max_energy = max_energy
    }

    return nk.json_encode(payload_out)
end"""

if match:
    content = content[:match.start()] + new_func + content[match.end():]
    with open('nakama/modules/main.lua', 'w') as f:
        f.write(content)
    print("Replaced get_player_stats")
else:
    print("Failed to replace get_player_stats")
