local nk = require("nakama")
local StaticData = require("core.static_data")
local Utilities = require("core.utilities")

local PlayerData = {}

local ACCOUNT_BOOTSTRAP_KEY = "account_bootstrap_v1"
local STARTER_RAIN_UNIT_ID = "100000102"
local STARTER_LASSWELL_UNIT_ID = "100000202"
local STARTER_RAIN_INSTANCE_ID = "starter_100000102"
local STARTER_LASSWELL_INSTANCE_ID = "starter_100000202"

local function build_starter_unit(unit_id, instance_id)
    local unit_data = StaticData.units_data[unit_id]
    if not unit_data then
        return nil
    end

    local exp_pattern = unit_data.exp_pattern or 5
    local next_xp = StaticData.calculate_xp_for_level(2, exp_pattern)

    return {
        instance_id = instance_id,
        unit_id = unit_id,
        level = 1,
        xp = 0,
        current_rarity = unit_data.rarity_min or 1,
        next_xp = next_xp,
        equipment = {},
        trust_value = 0.0,
        limitburst_level = 1,
        limitburst_xp = 0,
        is_locked = false
    }
end

local function build_default_parties(rain_instance_id, lasswell_instance_id)
    local parties = {}
    for i = 1, 5 do
        table.insert(parties, {
            name = "Party " .. i,
            units = {"", "", "", "", ""}
        })
    end

    parties[1].units[1] = rain_instance_id
    parties[1].units[2] = lasswell_instance_id

    return parties
end

function PlayerData.ensure_new_account_initialized(user_id)
    local bootstrap_object = nk.storage_read({
        {
            collection = "user_data",
            key = ACCOUNT_BOOTSTRAP_KEY,
            user_id = user_id
        }
    })
    if #bootstrap_object > 0 then
        return
    end

    local wallet_ok, wallet_err = pcall(
        nk.wallet_update,
        user_id,
        { gil = 0, lapis = 0 },
        { source = "new_account_bootstrap" },
        true
    )
    if not wallet_ok then
        nk.logger_error("Failed to initialize wallet for user " .. tostring(user_id) .. ": " .. tostring(wallet_err))
    end

    local rain_unit = build_starter_unit(STARTER_RAIN_UNIT_ID, STARTER_RAIN_INSTANCE_ID)
    local lasswell_unit = build_starter_unit(STARTER_LASSWELL_UNIT_ID, STARTER_LASSWELL_INSTANCE_ID)
    if not rain_unit or not lasswell_unit then
        nk.logger_error("Failed to build starter units for user " .. tostring(user_id))
        return
    end

    local unit_objects = nk.storage_read({
        { collection = "unit", key = STARTER_RAIN_INSTANCE_ID, user_id = user_id },
        { collection = "unit", key = STARTER_LASSWELL_INSTANCE_ID, user_id = user_id }
    })
    local has_rain = false
    local has_lasswell = false
    for _, unit_object in ipairs(unit_objects) do
        if unit_object.key == STARTER_RAIN_INSTANCE_ID then
            has_rain = true
        elseif unit_object.key == STARTER_LASSWELL_INSTANCE_ID then
            has_lasswell = true
        end
    end

    local starter_writes = {}
    if not has_rain then
        table.insert(starter_writes, {
            collection = "unit",
            key = STARTER_RAIN_INSTANCE_ID,
            user_id = user_id,
            value = rain_unit,
            permission_read = 1,
            permission_write = 1
        })
    end
    if not has_lasswell then
        table.insert(starter_writes, {
            collection = "unit",
            key = STARTER_LASSWELL_INSTANCE_ID,
            user_id = user_id,
            value = lasswell_unit,
            permission_read = 1,
            permission_write = 1
        })
    end
    if #starter_writes > 0 then
        nk.storage_write(starter_writes)
    end

    local parties_object = nk.storage_read({
        {
            collection = "user_data",
            key = "parties",
            user_id = user_id
        }
    })

    if #parties_object == 0 then
        nk.storage_write({
            {
                collection = "user_data",
                key = "parties",
                user_id = user_id,
                value = { parties = build_default_parties(STARTER_RAIN_INSTANCE_ID, STARTER_LASSWELL_INSTANCE_ID) },
                permission_read = 1,
                permission_write = 1
            }
        })
    else
        local current_value = parties_object[1].value or {}
        local current_parties = current_value.parties
        local changed = false

        if type(current_parties) ~= "table" then
            current_parties = build_default_parties(STARTER_RAIN_INSTANCE_ID, STARTER_LASSWELL_INSTANCE_ID)
            changed = true
        else
            if type(current_parties[1]) ~= "table" then
                current_parties[1] = { name = "Party 1", units = {"", "", "", "", ""} }
                changed = true
            end
            if type(current_parties[1].units) ~= "table" then
                current_parties[1].units = {"", "", "", "", ""}
                changed = true
            end
            for i = #current_parties + 1, 5 do
                current_parties[i] = { name = "Party " .. i, units = {"", "", "", "", ""} }
                changed = true
            end
            for i = 1, 5 do
                if type(current_parties[i].units) ~= "table" then
                    current_parties[i].units = {"", "", "", "", ""}
                    changed = true
                end
                for slot = #current_parties[i].units + 1, 5 do
                    current_parties[i].units[slot] = ""
                    changed = true
                end
            end
            if current_parties[1].units[1] ~= STARTER_RAIN_INSTANCE_ID then
                current_parties[1].units[1] = STARTER_RAIN_INSTANCE_ID
                changed = true
            end
            if current_parties[1].units[2] ~= STARTER_LASSWELL_INSTANCE_ID then
                current_parties[1].units[2] = STARTER_LASSWELL_INSTANCE_ID
                changed = true
            end
        end

        if changed then
            nk.storage_write({
                {
                    collection = "user_data",
                    key = "parties",
                    user_id = user_id,
                    value = { parties = current_parties },
                    permission_read = 1,
                    permission_write = 1
                }
            })
        end
    end

    nk.storage_write({
        {
            collection = "user_data",
            key = ACCOUNT_BOOTSTRAP_KEY,
            user_id = user_id,
            value = { initialized = true, initialized_at = math.floor(nk.time() / 1000) },
            permission_read = 0,
            permission_write = 0
        }
    })
end

function PlayerData.get_player_stats(context, payload)
    local object_ids = {
        {collection = "stats", key = "player_stats", user_id = context.user_id}
    }
    local objects = nk.storage_read(object_ids)

    local stats = {
        rank = 1,
        xp = 0,
        current_nrg = 41,
        last_nrg_update_time = math.floor(nk.time() / 1000),
        last_entered_mission_id = ""
    }

    if #objects > 0 then
        local data = objects[1].value
        if data then
            stats.rank = data.rank or stats.rank
            stats.xp = data.xp or stats.xp
            -- Backwards compatibility with old energy fields
            stats.current_nrg = data.current_nrg or data.energy or stats.current_nrg
            stats.last_nrg_update_time = data.last_nrg_update_time or data.last_energy_update_time or stats.last_nrg_update_time
            stats.last_entered_mission_id = tostring(data.last_entered_mission_id or "")
        end
    else
        -- Brand new account: lazy initialization
        PlayerData.ensure_new_account_initialized(context.user_id)
        nk.storage_write({
            {
                collection = "stats",
                key = "player_stats",
                user_id = context.user_id,
                value = stats,
                permission_read = 1,
                permission_write = 1
            }
        })
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
        last_entered_mission_id = stats.last_entered_mission_id
    }

    return nk.json_encode(payload_out)
end

return PlayerData
