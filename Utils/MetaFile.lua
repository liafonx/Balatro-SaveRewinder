--- Save Rewinder - MetaFile.lua
--
-- Handles reading and writing .meta files for fast metadata loading.
local Logger = require("Logger")
local M = {}
M.debug_log = Logger.create("MetaFile")
-- Reads metadata from .meta file (fast path)
-- Format: money, signature, discards_used, hands_played, blind_idx, display_type, ordinal
function M.read_meta_file(meta_path)
    local info = love.filesystem.getInfo(meta_path)
    if not info or info.type ~= "file" then return nil end
    
    local data = love.filesystem.read(meta_path)
    if not data then return nil end
    local meta = {}
    for line in data:gmatch("([^\n]+)") do
        local key, value = line:match("^([^=]+)=(.+)$")
        if key and value then
            if key == "money" or key == "discards_used" or key == "hands_played" or key == "ordinal" or key == "blind_idx" then
                meta[key] = tonumber(value)
            elseif key == "display_type" then
                meta[key] = (value ~= "") and value or nil
            elseif key == "signature" then
                meta[key] = value
            end
        end
    end
    
    -- Validate we have essential field
    if meta.signature and meta.display_type then
        return meta
    end
    return nil
end

-- Writes metadata to .meta file (fast path for future reads)
function M.write_meta_file(meta_path, entry_meta)
    if not entry_meta or not entry_meta.signature then return false end

    local lines = {
        string.format("money=%d", entry_meta.money or 0),
        string.format("signature=%s", entry_meta.signature),
        string.format("discards_used=%d", entry_meta.discards_used or 0),
        string.format("hands_played=%d", entry_meta.hands_played or 0),
        string.format("blind_idx=%d", entry_meta.blind_idx or 0),
        string.format("display_type=%s", entry_meta.display_type or "?"),
        string.format("ordinal=%d", entry_meta.ordinal or 1),
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