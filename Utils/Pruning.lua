--- Fast Save Loader - Pruning.lua
--
-- Handles pruning of old saves and future timeline cleanup.

local M = {}

-- Debug logging helper (injected by Init.lua)
M.debug_log = function(tag, msg)
    if LOADER and LOADER.debug_log then
        LOADER.debug_log(tag, msg)
    else
        print("[FastSL][Pruning][" .. tostring(tag) .. "] " .. tostring(msg))
    end
end

-- Applies retention policy based on max antes per run
function M.apply_retention_policy(save_dir, all_entries, entry_constants)
    if not all_entries then return end
    
    local ENTRY_ANTE = entry_constants.ENTRY_ANTE
    local ENTRY_FILE = entry_constants.ENTRY_FILE
    
    -- Read retention policy from config
    local keep_antes_config = (LOADER and LOADER.config and LOADER.config.keep_antes) or 7
    local option_text = (G.OPTION_CYCLE_TEXT and G.OPTION_CYCLE_TEXT["fastsl_max_antes_per_run"]) or {}
    local keep_antes = (keep_antes_config < 7 and tonumber(option_text[keep_antes_config])) or nil

    if not keep_antes or keep_antes <= 0 then return end -- "All" selected

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
    local i = #all_entries
    while i >= 1 do
        local e = all_entries[i]
        if e[ENTRY_ANTE] and not allowed[e[ENTRY_ANTE]] then
            -- Silently remove old saves per retention policy
            pcall(love.filesystem.remove, save_dir .. "/" .. e[ENTRY_FILE])
            -- Also remove .meta file if it exists
            if e[ENTRY_FILE] and e[ENTRY_FILE]:match("%.jkr$") then
                local meta_file = e[ENTRY_FILE]:gsub("%.jkr$", ".meta")
                pcall(love.filesystem.remove, save_dir .. "/" .. meta_file)
            end
            table.remove(all_entries, i)
        end
        i = i - 1
    end
end

-- Prunes future saves (divergent timeline cleanup)
-- Note: pending_future_prune is passed by reference (table), so clearing it here affects the original
function M.prune_future_saves(save_dir, pending_future_prune, save_cache, entry_constants)
    if not pending_future_prune or not next(pending_future_prune) then return end
    
    local ENTRY_FILE = entry_constants.ENTRY_FILE
    
    M.debug_log("prune", "Pruning " .. #pending_future_prune .. " future saves")
    
    for _, file_to_delete in ipairs(pending_future_prune) do
        pcall(love.filesystem.remove, save_dir .. "/" .. file_to_delete)
        -- Also remove .meta file if it exists
        if file_to_delete and file_to_delete:match("%.jkr$") then
            local meta_file = file_to_delete:gsub("%.jkr$", ".meta")
            pcall(love.filesystem.remove, save_dir .. "/" .. meta_file)
        end
    end

    -- Create a set for quick lookup
    local files_to_delete_set = {}
    for _, file in ipairs(pending_future_prune) do 
        files_to_delete_set[file] = true 
    end

    -- Remove from cache by iterating backwards
    if save_cache then
        local i = #save_cache
        while i >= 1 do
            if save_cache[i] and files_to_delete_set[save_cache[i][ENTRY_FILE]] then 
                table.remove(save_cache, i) 
            end
            i = i - 1
        end
    end
    
    -- Clear the pending list (tables are passed by reference in Lua)
    for i = #pending_future_prune, 1, -1 do
        table.remove(pending_future_prune, i)
    end
end

return M

