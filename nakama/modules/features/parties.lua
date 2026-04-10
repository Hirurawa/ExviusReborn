local nk = require("nakama")

local Parties = {}

function Parties.rpc_get_parties(context, payload)
    local object_ids = {
        {
            collection = "user_data",
            key = "parties",
            user_id = context.user_id
        }
    }

    local objects = nk.storage_read(object_ids)

    if #objects == 0 then
        -- Initialize default parties
        local default_parties = {}
        for i = 1, 5 do
            table.insert(default_parties, {
                name = "Party " .. i,
                units = {"", "", "", "", ""}
            })
        end

        nk.storage_write({
            {
                collection = "user_data",
                key = "parties",
                user_id = context.user_id,
                value = { parties = default_parties },
                permission_read = 1,
                permission_write = 1
            }
        })

        return nk.json_encode({ parties = default_parties })
    end

    return nk.json_encode(objects[1].value)
end

function Parties.rpc_save_parties(context, payload)
    local request = nk.json_decode(payload)

    if not request.parties then
        return nk.json_encode({error = "Missing 'parties' field in payload"})
    end

    nk.storage_write({
        {
            collection = "user_data",
            key = "parties",
            user_id = context.user_id,
            value = { parties = request.parties },
            permission_read = 1,
            permission_write = 1
        }
    })

    return nk.json_encode({ success = true, parties = request.parties })
end

return Parties
