--- Save Rewinder - MetaFile.lua
--
-- Handles reading and writing .meta files for fast metadata loading.
local Logger = require("Logger")
local M = {}
M.debug_log = Logger.create("MetaFile")

-- Fields that should be parsed as numbers
local NUMERIC_FIELDS = { money=true, discards_used=true, hands_played=true, ordinal=true, blind_idx=true }
local BOOLEAN_FIELDS = { is_key=true }

-- Reads metadata from .meta file (fast path)
function M.read_meta_file(meta_path)
    local info = love.filesystem.getInfo(meta_path)
    if not info or info.type ~= "file" then return nil end
    
    local data = love.filesystem.read(meta_path)
    if not data then return nil end
    
    local meta = {}
    for line in data:gmatch("([^\n]+)") do
        local key, value = line:match("^([^=]+)=(.+)$")
        if key and value then
            if NUMERIC_FIELDS[key] then
                meta[key] = tonumber(value)
            elseif BOOLEAN_FIELDS[key] then
                meta[key] = (value == "1")
            elseif key == "display_type" then
                meta[key] = value ~= "" and value or nil
            elseif key == "signature" then
                meta[key] = value
            elseif key == "custom_state_name" then
                meta[key] = value
            end
        end
    end
    
    return (meta.signature and meta.display_type) and meta or nil
end

-- Reused line buffer to avoid per-save table allocation in write_meta_file.
local _meta_lines_buf = {}

function M.serialize_meta(entry_meta)
    if not entry_meta or not entry_meta.signature then return nil end

    _meta_lines_buf[1] = "money=" .. tostring(entry_meta.money or 0)
    _meta_lines_buf[2] = "signature=" .. entry_meta.signature
    _meta_lines_buf[3] = "discards_used=" .. tostring(entry_meta.discards_used or 0)
    _meta_lines_buf[4] = "hands_played=" .. tostring(entry_meta.hands_played or 0)
    _meta_lines_buf[5] = "blind_idx=" .. tostring(entry_meta.blind_idx or 0)
    _meta_lines_buf[6] = "display_type=" .. (entry_meta.display_type or "?")
    _meta_lines_buf[7] = "ordinal=" .. tostring(entry_meta.ordinal or 1)
    local n = 7
    if entry_meta.is_key == true then
        n = 8
        _meta_lines_buf[8] = "is_key=1"
    end
    if entry_meta.custom_state_name and entry_meta.custom_state_name ~= "" then
        n = n + 1
        -- Strip newlines to prevent meta file corruption
        local sanitized = entry_meta.custom_state_name:gsub("[\r\n]", " ")
        _meta_lines_buf[n] = "custom_state_name=" .. sanitized
    end

    -- Clear trailing stale slot if previous call had more fields.
    _meta_lines_buf[n + 1] = nil

    return table.concat(_meta_lines_buf, "\n", 1, n)
end

-- Writes metadata to .meta file (fast path for future reads)
function M.write_meta_file(meta_path, entry_meta)
    local content = M.serialize_meta(entry_meta)
    if not content then return false end
    local success, err = pcall(love.filesystem.write, meta_path, content)
    if not success then
        M.debug_log("error", "Failed to write meta file: " .. tostring(err))
        return false
    end
    return true
end

return M
