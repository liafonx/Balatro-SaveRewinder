--- Fast Save Loader - FileIO.lua
--
-- Handles file I/O operations for save files.

local M = {}

-- Debug logging helper (injected by Init.lua)
M.debug_log = function(tag, msg)
    if LOADER and LOADER.debug_log then
        LOADER.debug_log(tag, msg)
    else
        print("[FastSL][FileIO][" .. tostring(tag) .. "] " .. tostring(msg))
    end
end

-- Get profile directory
function M.get_profile()
    if G and G.SETTINGS and G.SETTINGS.profile then
        return tostring(G.SETTINGS.profile)
    end
    return "1"
end

-- Get save directory path
function M.get_save_dir(saves_path)
    saves_path = saves_path or "FastSaveLoader"
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

-- Write a save file (pack + compress + write). Returns (ok, timings|err).
-- opts.timing=true returns per-stage timings in milliseconds.
function M.write_save_file(run_data, full_path, opts)
    opts = opts or {}

    local ok_pack, packed_or_err = pcall(STR_PACK, run_data)
    if not ok_pack then
        return false, "pack:" .. tostring(packed_or_err)
    end

    local compressed = love.data.compress("string", "deflate", packed_or_err, 1)

    local ok_write, write_err = pcall(love.filesystem.write, full_path, compressed)
    if not ok_write then
        return false, "write:" .. tostring(write_err)
    end

    return true
end

-- Sync save data to main save.jkr file
function M.sync_to_main_save(run_data)
    if not run_data then return false end
    local profile = M.get_profile()
    local save_path = profile .. "/save.jkr"
    local ok, err_or_timings = M.write_save_file(run_data, save_path, { timing = false })
    if not ok then
        M.debug_log("error", "Failed to write main save: " .. tostring(err_or_timings))
        return false
    end
    return true
end

return M
