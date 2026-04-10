local nk = require("nakama")

local Utilities = {}

function Utilities.parse_payload(payload)
    if not payload or payload == "" then return {} end
    local success, decoded = pcall(nk.json_decode, payload)
    if not success then return nil end
    return decoded
end

function Utilities.read_json_file(file_path)
    local success, content = pcall(nk.file_read, file_path)
    if not success or not content then
        nk.logger_warn("Could not open file: " .. file_path)
        return nil
    end

    local decode_success, decoded = pcall(nk.json_decode, content)
    if not decode_success then
        nk.logger_warn("Could not decode JSON from file: " .. file_path)
        return nil
    end

    return decoded
end

function Utilities.read_csv_file(file_path)
    local success, content = pcall(nk.file_read, file_path)
    if not success or not content then
        nk.logger_warn("Could not open file: " .. file_path)
        return nil
    end

    local lines = {}
    for str in string.gmatch(content, "([^\r\n]+)") do
        table.insert(lines, str)
    end

    if #lines == 0 then return nil end

    local headers = {}
    for str in string.gmatch(lines[1], "([^,]+)") do
        table.insert(headers, str)
    end

    local data = {}
    local col_map = {}
    for i, header in ipairs(headers) do
        local gr = header:match("Gr (%d+)")
        if gr then
            col_map[i] = tonumber(gr)
            data[col_map[i]] = {}
        end
    end

    for i = 2, #lines do
        local line = lines[i]
        local cols = {}
        -- Need a custom split to handle empty fields like "-,-"
        local col_idx = 1
        local current_col = ""
        for char_idx = 1, #line do
            local char = line:sub(char_idx, char_idx)
            if char == "," then
                table.insert(cols, current_col)
                current_col = ""
                col_idx = col_idx + 1
            else
                current_col = current_col .. char
            end
        end
        table.insert(cols, current_col)

        local level = tonumber(cols[1])
        if level then
            for idx, col_val in ipairs(cols) do
                local gr = col_map[idx]
                if gr then
                    local val = tonumber(col_val) or 0
                    data[gr][level] = val
                end
            end
        end
    end

    return data
end

return Utilities
