--- Save Rewinder - FileIO.lua
--
-- Handles file I/O operations for save files.

local Logger = require("Logger")
local M = {}

M.debug_log = Logger.create("FileIO")

-- Get profile directory
function M.get_profile()
    if G and G.SETTINGS and G.SETTINGS.profile then
        return tostring(G.SETTINGS.profile)
    end
    return "1"
end

-- Get save directory path
function M.get_save_dir(saves_path)
    saves_path = saves_path or "SaveRewinder"
    local profile = M.get_profile()
    local dir = profile .. "/" .. saves_path

    if not love.filesystem.getInfo(profile) then
        love.filesystem.createDirectory(profile)
    end
    if not love.filesystem.getInfo(dir) then
        love.filesystem.createDirectory(dir)
    end

    return dir
end

-- Copy save file directly to save.jkr without decoding (fast path)
function M.copy_save_to_main(file, save_dir)
    local source_path = save_dir .. "/" .. file
    local profile = M.get_profile()
    local save_path = profile .. "/save.jkr"
    
    local info = love.filesystem.getInfo(source_path)
    if not info then
        M.debug_log("error", "File not found: " .. source_path)
        return false
    end
    
    -- Read save file (compressed bytes)
    local save_data = love.filesystem.read(source_path)
    if not save_data then
        M.debug_log("error", "Failed to read: " .. source_path)
        return false
    end
    
    -- Write directly to save.jkr
    local success, err = pcall(love.filesystem.write, save_path, save_data)
    if not success then
        M.debug_log("error", "Failed to write save: " .. tostring(err))
        return false
    end
    
    M.debug_log("debug", "Copied save to main: " .. source_path)
    return true
end

-- Load and unpack a save file
function M.load_save_file(file, save_dir)
    local full_path = save_dir .. "/" .. file
    
    local info = love.filesystem.getInfo(full_path)
    if not info then
        M.debug_log("error", "File not found: " .. full_path)
        return nil
    end
    
    local data = get_compressed(full_path)
    if data == nil then
        M.debug_log("error", "Failed to decompress: " .. full_path)
        return nil
    end
    
    local success, result = pcall(STR_UNPACK, data)
    if not success then
        M.debug_log("error", "Failed to unpack: " .. tostring(result))
        return nil
    end
    
    return result
end

-- Write a save file (pack + compress + write). Returns (ok, err_or_nil, compressed_bytes).
-- Third return value is the compressed bytes for reuse (avoids re-reading from disk).
function M.write_save_file(run_data, full_path)
    -- Note: Amulet/Talisman OmegaNum compatibility is handled by their STR_PACK/STR_UNPACK overrides
    -- We don't need to call sanitize - it corrupts the data

    local ok_pack, packed_or_err = pcall(STR_PACK, run_data)
    if not ok_pack then
        return false, "pack:" .. tostring(packed_or_err)
    end

    local compressed = love.data.compress("string", "deflate", packed_or_err, 1)

    local ok_write, write_err = pcall(love.filesystem.write, full_path, compressed)
    if not ok_write then
        return false, "write:" .. tostring(write_err)
    end

    return true, nil, compressed
end

-- Write pre-compressed bytes directly to save.jkr (avoids re-reading from disk)
function M.write_bytes_to_main(compressed_bytes)
    if not compressed_bytes then return false end
    local profile = M.get_profile()
    local save_path = profile .. "/save.jkr"
    local ok, err = pcall(love.filesystem.write, save_path, compressed_bytes)
    if not ok then
        M.debug_log("error", "Failed to write main save: " .. tostring(err))
        return false
    end
    return true
end

-- Sync save data to main save.jkr file
function M.sync_to_main_save(run_data)
    if not run_data then return false end
    local profile = M.get_profile()
    local save_path = profile .. "/save.jkr"
    local ok, err = M.write_save_file(run_data, save_path)
    if not ok then
        M.debug_log("error", "Failed to write main save: " .. tostring(err))
        return false
    end
    M.debug_log("debug", "Synced to main save")
    return true
end

return M
