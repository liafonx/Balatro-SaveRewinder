--- Save Rewinder - MetaFile.lua
--
-- Handles reading and writing .meta files for fast metadata loading.

local Logger = require("Logger")
local M = {}

M.debug_log = Logger.create("MetaFile")

-- Reads metadata from .meta file (fast path)
function M.read_meta_file(meta_path)
    local info = love.filesystem.getInfo(meta_path)
    if not info or info.type ~= "file" then return nil end
    
    local data = love.filesystem.read(meta_path)
    if not data then return nil end
    
    -- Meta file format: simple key=value pairs, one per line
    -- Format: state=<num>, action_type=<str|nil>, is_opening_pack=<0|1>, money=<num>, signature=<str>, discards_used=<num>, hands_played=<num>, blind_key=<str>
    local meta = {}
    for line in data:gmatch("([^\n]+)") do
        local key, value = line:match("^([^=]+)=(.+)$")
        if key and value then
            if key == "state" or key == "money" or key == "discards_used" or key == "hands_played" then
                meta[key] = tonumber(value)
            elseif key == "action_type" then
                if value == "" then
                    meta[key] = nil
                else
                    meta[key] = value
                end
            elseif key == "is_opening_pack" then
                meta[key] = (value == "1")
            elseif key == "signature" or key == "blind_key" then
                meta[key] = value
            end
        end
    end
    
    -- Validate we have essential fields
    if meta.state and meta.signature then
        return meta
    end
    return nil
end

-- Writes metadata to .meta file (fast path for future reads)
function M.write_meta_file(meta_path, entry_meta)
    if not entry_meta or not entry_meta.signature then return false end
    
    -- Store only the metadata fields that match cache entry structure
    -- (excludes file, ante, round, index, modtime which come from filename/filesystem,
    --  and is_current which is computed)
    local lines = {
        string.format("state=%d", entry_meta.state or 0),
        string.format("action_type=%s", entry_meta.action_type or ""),
        string.format("is_opening_pack=%s", (entry_meta.is_opening_pack and "1") or "0"),
        string.format("money=%d", entry_meta.money or 0),
        string.format("signature=%s", entry_meta.signature),
        string.format("discards_used=%d", entry_meta.discards_used or 0),
        string.format("hands_played=%d", entry_meta.hands_played or 0),
        string.format("blind_key=%s", entry_meta.blind_key or ""),
    }
    
    local content = table.concat(lines, "\n")
    local success, err = pcall(love.filesystem.write, meta_path, content)
    if not success then
        M.debug_log("error", "Failed to write meta file: " .. tostring(err))
        return false
    end
    return true
end

return M

