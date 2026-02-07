--- Save Rewinder - Pruning.lua
--
-- Handles pruning of old saves and future timeline cleanup.
local Logger = require("Logger")
local M = {}
M.debug_log = Logger.create("Pruning")
-- Config index to actual ante count mapping (matches main.lua options order)
local KEEP_ANTES_VALUES = { 1, 2, 4, 6, 8, 16 }  -- Index 7 = "All" (nil)

local function _remove_save_file_pair(save_dir, file)
    if not file then return end
    love.filesystem.remove(save_dir .. "/" .. file)
    if file:match("%.jkr$") then
        love.filesystem.remove(save_dir .. "/" .. file:gsub("%.jkr$", ".meta"))
    end
end

-- Applies retention policy based on max antes per run
function M.apply_retention_policy(save_dir, all_entries, entry_constants)
    if not all_entries then return end
    
    local ENTRY_ANTE = entry_constants.ENTRY_ANTE
    local ENTRY_FILE = entry_constants.ENTRY_FILE
    
    -- Read retention policy from config (1-7, where 7 = "All")
    local keep_antes_config = (REWINDER and REWINDER.config and REWINDER.config.keep_antes) or 7
    local keep_antes = KEEP_ANTES_VALUES[keep_antes_config]  -- nil if index 7 ("All")
    if not keep_antes or keep_antes <= 0 then return end -- "All" selected or invalid
    -- Find all unique antes
    local ante_set = {}
    for _, e in ipairs(all_entries) do
        if e[ENTRY_ANTE] then ante_set[e[ENTRY_ANTE]] = true end
    end
    local antes = {}
    for a in pairs(ante_set) do
        table.insert(antes, a)
    end
    table.sort(antes, function(a, b) return a > b end)
    -- Determine which antes to keep
    local allowed = {}
    local limit = math.min(keep_antes, #antes)
    for i = 1, limit do
        allowed[antes[i]] = true
    end
    -- Single-pass in-place compaction (O(N), avoids repeated table.remove shifts)
    local removed_count = 0
    local write = 1
    local total = #all_entries
    for read = 1, total do
        local e = all_entries[read]
        if e[ENTRY_ANTE] and not allowed[e[ENTRY_ANTE]] then
            -- Remove old saves per retention policy
            _remove_save_file_pair(save_dir, e[ENTRY_FILE])
            removed_count = removed_count + 1
        else
            if write ~= read then
                all_entries[write] = e
            end
            write = write + 1
        end
    end
    for i = write, total do
        all_entries[i] = nil
    end
    
    if removed_count > 0 then
        M.debug_log("info", string.format("Removed %d saves from old antes (keeping antes: %s)", 
            removed_count, table.concat(antes, ", ", 1, limit)))
    else
        M.debug_log("debug", "Retention policy: no pruning needed")
    end
end
-- Prunes future saves using timestamp boundary.
-- Internal cache order is oldest-first, so "future" saves are a contiguous tail.
function M.prune_future_saves(save_dir, prune_boundary, save_cache, entry_constants)
    if not prune_boundary or not save_cache then return end

    local ENTRY_FILE = entry_constants.ENTRY_FILE
    local ENTRY_INDEX = entry_constants.ENTRY_INDEX

    -- Count/remove how many consecutive entries at the end are future saves.
    local prune_count = 0
    for i = #save_cache, 1, -1 do
        local entry = save_cache[i]
        if entry and entry[ENTRY_INDEX] and entry[ENTRY_INDEX] > prune_boundary then
            -- Delete files from disk
            _remove_save_file_pair(save_dir, entry[ENTRY_FILE])
            prune_count = prune_count + 1
        else
            break  -- Remaining entries are <= boundary
        end
    end

    -- Trim contiguous tail in O(K) without shifting retained entries.
    if prune_count > 0 then
        local start_idx = #save_cache - prune_count + 1
        for i = start_idx, #save_cache do
            save_cache[i] = nil
        end
        M.debug_log("info", "Pruning " .. prune_count .. " future saves")
    end
end
return M
