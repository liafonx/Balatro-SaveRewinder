--- Save Rewinder - Pruning.lua
--
-- Handles pruning of old saves and future timeline cleanup.
local Logger = require("Logger")
local M = {}
M.debug_log = Logger.create("Pruning")
-- Config index to actual ante count mapping (matches main.lua options order)
local KEEP_ANTES_VALUES = { 1, 2, 4, 6, 8, 16 }  -- Index 7 = "All" (nil)
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
    -- Remove files from older antes
    -- Iterate backwards to safely remove items from the table we are iterating
    local removed_count = 0
    local i = #all_entries
    while i >= 1 do
        local e = all_entries[i]
        if e[ENTRY_ANTE] and not allowed[e[ENTRY_ANTE]] then
            -- Remove old saves per retention policy
            love.filesystem.remove(save_dir .. "/" .. e[ENTRY_FILE])
            -- Also remove .meta file if it exists
            if e[ENTRY_FILE] and e[ENTRY_FILE]:match("%.jkr$") then
                local meta_file = e[ENTRY_FILE]:gsub("%.jkr$", ".meta")
                love.filesystem.remove(save_dir .. "/" .. meta_file)
            end
            table.remove(all_entries, i)
            removed_count = removed_count + 1
        end
        i = i - 1
    end
    
    if removed_count > 0 then
        M.debug_log("prune", string.format("Removed %d saves from old antes (keeping antes: %s)", 
            removed_count, table.concat(antes, ", ", 1, limit)))
    end
end
-- Prunes future saves using timestamp boundary (O(1) setup, single-pass deletion)
-- Deletes all saves with ENTRY_INDEX > boundary (these are "future" saves)
function M.prune_future_saves(save_dir, prune_boundary, save_cache, entry_constants)
    if not prune_boundary then return end
    
    local ENTRY_FILE = entry_constants.ENTRY_FILE
    local ENTRY_INDEX = entry_constants.ENTRY_INDEX
    
    -- Single pass: find saves to delete and delete them
    -- Entries are sorted newest-first, so "future" saves are at the start
    local prune_count = 0
    if save_cache then
        local i = 1
        while i <= #save_cache do
            local entry = save_cache[i]
            if entry and entry[ENTRY_INDEX] and entry[ENTRY_INDEX] > prune_boundary then
                -- Delete files
                local file = entry[ENTRY_FILE]
                if file then
                    love.filesystem.remove(save_dir .. "/" .. file)
                    if file:match("%.jkr$") then
                        love.filesystem.remove(save_dir .. "/" .. file:gsub("%.jkr$", ".meta"))
                    end
                end
                table.remove(save_cache, i)
                prune_count = prune_count + 1
                -- Don't increment i since we removed an element
            else
                -- Once we hit an entry <= boundary, all remaining are older (sorted order)
                break
            end
        end
    end
    
    if prune_count > 0 then
        M.debug_log("prune", "Pruning " .. prune_count .. " future saves")
    end
end
return M