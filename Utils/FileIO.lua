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

-- Cached save directory path (profile + saves_path don't change mid-session)
local _cached_save_dir = nil
local _cached_save_dir_key = nil

-- Get save directory path
function M.get_save_dir(saves_path)
    saves_path = saves_path or "SaveRewinder"
    local profile = M.get_profile()
    local key = profile .. "/" .. saves_path

    -- Return cached result if profile + path haven't changed
    if _cached_save_dir and _cached_save_dir_key == key then
        return _cached_save_dir
    end

    if not love.filesystem.getInfo(profile) then
        love.filesystem.createDirectory(profile)
    end
    if not love.filesystem.getInfo(key) then
        love.filesystem.createDirectory(key)
    end

    _cached_save_dir = key
    _cached_save_dir_key = key
    return key
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

-- Check if a file exists at an absolute OS path.
function M.file_exists_os(path)
   if type(path) ~= "string" or path == "" then return false end
   local fh = io.open(path, "rb")
   if fh then
      fh:close()
      return true
   end
   return false
end

-- Sanitize a string for safe use as a filesystem path component.
-- Replaces forbidden characters and collapses whitespace to underscores.
function M.sanitize_path_component(str)
   if type(str) ~= "string" then return "" end
   local s = str:match("^%s*(.-)%s*$") or str
   s = s:gsub('[\\/:*?"<>|\r\n\t]', "_")
   s = s:gsub(" +", "_")
   return s
end

-- Platform-aware directory creation (creates parent directories as needed).
function M.create_dir_os(path)
   if type(path) ~= "string" or path == "" then return false end
   local sep = package.config:sub(1, 1)
   local ok
   if sep == "\\" then
      local win_path = path:gsub("/", "\\"):gsub('"', '\\"')
      ok = os.execute('mkdir "' .. win_path .. '" 2>NUL')
   else
      local unix_path = path:gsub("'", "'\\''")
      ok = os.execute("mkdir -p '" .. unix_path .. "'")
   end
   return ok ~= false
end

-- Copy a love.filesystem file to an absolute OS path.
-- Returns true on success, false on failure.
function M.copy_love_to_os(love_relative_src, os_abs_dest)
   if type(love_relative_src) ~= "string" or type(os_abs_dest) ~= "string" then return false end
   local data = love.filesystem.read(love_relative_src)
   if not data then
      M.debug_log("error", "copy_love_to_os: cannot read " .. love_relative_src)
      return false
   end
   local fh, err = io.open(os_abs_dest, "wb")
   if not fh then
      M.debug_log("error", "copy_love_to_os: cannot open dest " .. os_abs_dest .. " err=" .. tostring(err))
      return false
   end
   fh:write(data)
   fh:close()
   return true
end

return M
