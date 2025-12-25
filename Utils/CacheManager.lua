--- Save Rewinder - CacheManager.lua
--
-- Manages cache entry flags and current file tracking.

local Logger = require("Logger")
local M = {}

M.debug_log = Logger.create("CacheManager")

-- Helper to update cache flags for a specific file (more efficient than full update)
function M.set_cache_current_file(save_cache, file, entry_constants, last_loaded_file_ref)
    if not save_cache or not file then return end
    
    local ENTRY_FILE = entry_constants.ENTRY_FILE
    local ENTRY_IS_CURRENT = entry_constants.ENTRY_IS_CURRENT
    
    local count = 0
    for _, entry in ipairs(save_cache) do
        if entry and entry[ENTRY_FILE] then
            entry[ENTRY_IS_CURRENT] = (entry[ENTRY_FILE] == file)
            if entry[ENTRY_IS_CURRENT] then count = count + 1 end
        end
    end
    
    if last_loaded_file_ref then
        last_loaded_file_ref[1] = file  -- Update via reference
    end
    
    M.debug_log("cache", string.format("_set_current: file=%s, marked=%d", file, count))
end

-- Updates the is_current flag in cache entries based on current file
function M.update_cache_current_flags(save_cache, last_loaded_file_ref, entry_constants)
    if not save_cache then return end
    
    local ENTRY_FILE = entry_constants.ENTRY_FILE
    local ENTRY_IS_CURRENT = entry_constants.ENTRY_IS_CURRENT
    
    -- Find current file - check multiple sources in priority order
    local current_file = nil
    
    -- Priority 1: _last_loaded_file (most reliable for recent restores and new saves)
    -- This takes absolute priority because it's set immediately when loading/creating saves
    if last_loaded_file_ref and last_loaded_file_ref[1] then
        current_file = last_loaded_file_ref[1]
        -- Don't check other sources if _last_loaded_file is set - it's the most authoritative
        -- This prevents old G.SAVED_GAME._file from overriding newly created saves
    else
        -- Only check other sources if _last_loaded_file is not set
        -- Priority 2: G.SAVED_GAME._file (set when game is running)
        if G and G.SAVED_GAME and G.SAVED_GAME._file then
            current_file = G.SAVED_GAME._file
            if last_loaded_file_ref then
                last_loaded_file_ref[1] = current_file  -- Sync it
            end
        end
    end
    
    -- Note: Removed expensive save.jkr decompression fallback.
    -- The _last_loaded_file and G.SAVED_GAME._file sources are sufficient.
    -- If neither is set, we simply have no current file to highlight.
    
    -- Update flags in cache - ensure ALL entries are updated
    local marked_count = 0
    for _, entry in ipairs(save_cache) do
        if entry and entry[ENTRY_FILE] then
            entry[ENTRY_IS_CURRENT] = (current_file and entry[ENTRY_FILE] == current_file) or false
            if entry[ENTRY_IS_CURRENT] then marked_count = marked_count + 1 end
        end
    end
    
    M.debug_log("cache", string.format("_update_flags: current=%s, marked=%d, _last=%s", 
        current_file or "nil", marked_count, (last_loaded_file_ref and last_loaded_file_ref[1]) or "nil"))
end

return M

