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
    local ok1 = love.filesystem.remove(save_dir .. "/" .. file)
    if not ok1 then
        M.debug_log("debug", "Failed to remove " .. tostring(file))
    end
    if file:match("%.jkr$") then
        local meta = require("SaveManagerEntrySchema").meta_filename(file)
        local ok2 = love.filesystem.remove(save_dir .. "/" .. meta)
        if not ok2 then
            M.debug_log("debug", "Failed to remove " .. tostring(meta))
        end
    end
end

-- Applies retention policy based on max antes per run
function M.apply_retention_policy(save_dir, all_entries, entry_constants, opts)
    if not all_entries then return end
    opts = opts or {}
    
    local ENTRY_ANTE = entry_constants.ENTRY_ANTE
    local ENTRY_FILE = entry_constants.ENTRY_FILE
    local ENTRY_IS_KEY = entry_constants.ENTRY_IS_KEY
    local should_preserve_entry = opts.should_preserve_entry
    
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
    local removed_files = {}
    local write = 1
    local total = #all_entries
    for read = 1, total do
        local e = all_entries[read]
        if e[ENTRY_ANTE] and not allowed[e[ENTRY_ANTE]] then
            local keep = false
            if should_preserve_entry then
                local ok, preserve = pcall(should_preserve_entry, e)
                keep = ok and preserve == true
            elseif ENTRY_IS_KEY and e[ENTRY_IS_KEY] == true then
                -- Backward-compatible fallback for callers without policy callback.
                keep = true
            end

            if keep then
                if write ~= read then
                    all_entries[write] = e
                end
                write = write + 1
            else
                -- Remove old saves per retention policy
                local removed_file = e[ENTRY_FILE]
                _remove_save_file_pair(save_dir, removed_file)
                removed_files[#removed_files + 1] = removed_file
                removed_count = removed_count + 1
            end
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

    return removed_count, removed_files
end
-- Config index to actual per-type-per-round limit mapping (matches main.lua options order)
local TYPE_ROUND_LIMIT_VALUES = { 8, 16, 64, 128 }  -- Index 5 = "All" (nil)

function M.get_type_round_limit(config_index)
    return TYPE_ROUND_LIMIT_VALUES[config_index]
end

-- Trims oldest non-key saves in a (display_type + round) bucket down to limit.
-- save_cache is oldest-first order; removes entries in-place and deletes files.
-- Returns number of removed entries.
function M.trim_type_round_bucket(save_dir, save_cache, entry_constants, display_type, round)
    local limit_config = (REWINDER and REWINDER.config and REWINDER.config.max_saves_per_type_per_round) or 5
    local limit = M.get_type_round_limit(limit_config)
    if not limit then
        if Logger.is_verbose() then
            M.debug_log("debug", string.format("Type-round trim: limit=all bucket=%s/%s (skip)", tostring(display_type), tostring(round)))
        end
        return 0, {}
    end

    local E_FILE = entry_constants.ENTRY_FILE
    local E_ROUND = entry_constants.ENTRY_ROUND
    local E_DISPLAY_TYPE = entry_constants.ENTRY_DISPLAY_TYPE
    local E_IS_KEY = entry_constants.ENTRY_IS_KEY

    -- Collect indices of non-key entries matching the bucket (oldest-first order).
    local non_key_indices = {}
    for i, e in ipairs(save_cache) do
        if e[E_ROUND] == round and e[E_DISPLAY_TYPE] == display_type and e[E_IS_KEY] ~= true then
            non_key_indices[#non_key_indices + 1] = i
        end
    end

    local non_key_count = #non_key_indices
    local excess = non_key_count - limit
    if Logger.is_verbose() then
        M.debug_log("debug", string.format(
            "Type-round trim: bucket=%s/%s non_key=%d limit=%d excess=%d",
            tostring(display_type), tostring(round), non_key_count, limit, math.max(0, excess)))
    end

    if excess <= 0 then return 0, {} end

    -- Mark oldest non-key entries for removal (first `excess` in oldest-first order).
    local remove_set = {}
    for j = 1, excess do
        remove_set[non_key_indices[j]] = true
    end

    -- Delete files and compact save_cache in-place.
    local removed = 0
    local removed_files = {}
    local write = 1
    local total = #save_cache
    for read = 1, total do
        if remove_set[read] then
            local removed_file = save_cache[read][E_FILE]
            local ok, err = pcall(_remove_save_file_pair, save_dir, removed_file)
            if not ok then
                M.debug_log("error", string.format(
                    "Type-round trim: failed to delete file=%s bucket=%s/%s err=%s",
                    tostring(removed_file), tostring(display_type), tostring(round), tostring(err)))
            end
            removed_files[#removed_files + 1] = removed_file
            removed = removed + 1
        else
            if write ~= read then
                save_cache[write] = save_cache[read]
            end
            write = write + 1
        end
    end
    for i = write, total do
        save_cache[i] = nil
    end

    if removed > 0 then
        M.debug_log("info", string.format(
            "Type-round trim: removed %d oldest non-key saves bucket=%s/%s",
            removed, tostring(display_type), tostring(round)))
    end
    return removed, removed_files
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
