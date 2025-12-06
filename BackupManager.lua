--- Fast Save Loader - BackupManager.lua
--
-- Manages the lifecycle of backup files: listing, pruning, loading, and metadata.
-- Decoupled from UI code to improve performance and testability.

local M = {}
local StateSignature = require("StateSignature")

-- Configuration for file paths
M.PATHS = {
    BACKUPS = "FastSaveLoader",
}

-- Internal state
M._last_loaded_file = nil
M._pending_skip_reason = nil
M._loaded_mark_applied = nil
M._loaded_meta = nil
M._restore_active = false
M.skip_next_backup = false
M.skipping_pack_open = nil
M.pending_future_prune = {}
M.current_index = nil
M.pending_index = nil

-- Debug logging helper (injected or default)
M.debug_log = function(tag, msg)
    if LOADER and LOADER.debug_log then
        LOADER.debug_log(tag, msg)
    else
        print("[FastSL][BackupManager][" .. tostring(tag) .. "] " .. tostring(msg))
    end
end

-- --- File System Helpers ---

function M.get_profile()
    if G and G.SETTINGS and G.SETTINGS.profile then
        return tostring(G.SETTINGS.profile)
    end
    return "1"
end

function M.get_backup_dir()
    local profile = M.get_profile()
    local dir = profile .. "/" .. M.PATHS.BACKUPS

    if not love.filesystem.getInfo(profile) then
        love.filesystem.createDirectory(profile)
    end
    if not love.filesystem.getInfo(dir) then
        love.filesystem.createDirectory(dir)
    end

    return dir
end

-- --- Backup Listing & Metadata ---

-- Parses a meta string (e.g., "ante:1,round:2,state:shop") into a table
local function parse_meta_string(meta_string)
    local meta_table = {}
    if meta_string then
        for pair in meta_string:gmatch("([^,]+)") do
            local key, value = pair:match("([^:]+):(.*)")
            if key and value then
                -- Try to convert to number if possible
                meta_table[key] = tonumber(value) or value
            end
        end
    end
    return meta_table
end

-- Reads the metadata for a single backup file.
function M.get_backup_meta(entry)
    if not entry or not entry.file then return nil end
    
    if entry.meta then return entry.meta end

    local dir = M.get_backup_dir()
    local meta_filename = entry.file:gsub("%.jkr$", ".meta")
    local meta_full_path = dir .. "/" .. meta_filename

    local meta_string = nil
    local success, content = pcall(love.filesystem.read, meta_full_path)
    if success and content then
        meta_string = content
    end

    if meta_string then
        local meta_table = parse_meta_string(meta_string)
        if next(meta_table) then -- Check if table is not empty
            entry.meta = meta_table
            return meta_table
        end
    end

    -- Fallback: Read the full save file (Slow!)
    local full_path = dir .. "/" .. entry.file
    local data = get_compressed(full_path)
    
    if data then
        local success, run_data = pcall(STR_UNPACK, data)
        if success and run_data then
            local sig = StateSignature.get_signature(run_data)
            entry.meta = sig
            return sig
        end
    end
    return nil
end

-- Returns a sorted list of all available backups with metadata.
function M.get_backup_files()
   local dir = M.get_backup_dir()
   local files = love.filesystem.getDirectoryItems(dir)
   local entries = {}

   for _, file in ipairs(files) do
      if file:match("%.jkr$") then -- Only process .jkr files
         local full = dir .. "/" .. file
         local info = love.filesystem.getInfo(full)
         if info and info.type == "file" then
            -- Filename format: "<ante>-<round>-<index>.jkr"
            local ante_str, round_str, index_str = string.match(file, "^(%d+)%-(%d+)%-(%d+)%.jkr$")
            local ante = tonumber(ante_str or 0)
            local round = tonumber(round_str or 0)
            local index = tonumber(index_str or 0)
            
            local entry = {
               file = file,
               ante = ante,
               round = round,
               index = index,
               modtime = info.modtime or 0,
            }
            
            -- Attempt to read companion .meta file
            local meta_filename = file:gsub("%.jkr$", ".meta")
            local meta_full_path = dir .. "/" .. meta_filename
            local meta_string = nil
            local success, content = pcall(love.filesystem.read, meta_full_path)
            if success and content then
                meta_string = content
            end

            if meta_string then
                entry.meta = parse_meta_string(meta_string)
            end

            table.insert(entries, entry)
         end
      end
   end

   -- Sort by modtime (newest first), then by index as tie-breaker
   table.sort(entries, function(a, b)
      if a.modtime ~= b.modtime then
         return a.modtime > b.modtime
      end
      return a.index > b.index
   end)

   return entries
end

function M.describe_backup(opts)
   opts = opts or {}
   local file = opts.file
   local entry = opts.entry
   local run_data = opts.run_data
   local meta = opts.meta

   local function resolve_meta()
      if meta then return meta end
      if entry then
          return M.get_backup_meta(entry)
      end
      if file then
         local entries = M.get_backup_files()
         for _, e in ipairs(entries) do
            if e.file == file then
               return M.get_backup_meta(e)
            end
         end
      end
      if run_data and type(run_data) == "table" then
          return StateSignature.get_signature(run_data)
      end
      return nil
   end

   meta = resolve_meta()

   local ante = meta and meta.ante or "?"
   local round = meta and meta.round or "?"
   local state = (meta and meta.debug_label) or (StateSignature.describe_state_label(meta and meta.state)) or ""
   if state == "" then state = "state" end

   return string.format("Ante %s Round %s%s",
      tostring(ante),
      tostring(round),
      (state ~= "" and (" (" .. state .. ")") or "")
   )
end


-- --- Loading & State Management ---

function M.load_backup_file(file)
   local dir = M.get_backup_dir()
   local full_path = dir .. "/" .. file
   local data = get_compressed(full_path)
   if data ~= nil then
      return STR_UNPACK(data)
   end
   return nil
end

local function start_from_run_data(run_data)
   if not run_data then return false end

   -- Sync index with backup list to maintain stepping history
   local idx_from_list = nil
   local entries = nil
   if run_data._file then
      entries = M.get_backup_files()
      for _, e in ipairs(entries) do
         if e.file == run_data._file then
            idx_from_list = i
            break
         end
      end
   end

   M.pending_future_prune = {}
   if entries and idx_from_list and idx_from_list > 1 then
      for i = 1, idx_from_list - 1 do
         local e = entries[i]
         if e and e.file then
            table.insert(M.pending_future_prune, e.file)
         end
      end
   end

   M.current_index = M.pending_index or idx_from_list or 1
   M.pending_index = nil
   M._deferred_prune = nil

   -- UI Cleanup
   if G then
      G.SETTINGS = G.SETTINGS or {}
      G.SETTINGS.current_setup = "Continue"
      if G.OVERLAY_MENU and G.FUNCS and G.FUNCS.exit_overlay_menu then
          G.FUNCS.exit_overlay_menu()
      end
   end
   
   if LOADER then LOADER.backups_open = false end

   G.SAVED_GAME = run_data

   if G and G.FUNCS and G.FUNCS.start_run then
      G.FUNCS.start_run(nil, { savetext = G.SAVED_GAME })
   elseif G and G.start_run then
      G:start_run({
         savetext = G.SAVED_GAME,
      })
   end

   return true
end

function M.load_and_start_from_file(file, opts)
   opts = opts or {}
   local run_data = M.load_backup_file(file)
   if run_data then
      run_data._file = file
   end
   
   local mark_restore = not opts.skip_restore_identical
   local reason = mark_restore and "restore" or "step"
   
   -- Reset State
   M.restore_skip_count = 0
   M._loaded_mark_applied = nil
   M._loaded_meta = nil
   M._pending_skip_reason = reason
   M._restore_active = (reason == "restore")
   M._last_loaded_file = file
   M.skip_next_backup = true

   if mark_restore then
      local label = M.describe_backup({ file = file, run_data = run_data })
      M.debug_log("restore", "Loaded backup " .. label)
   end
   start_from_run_data(run_data)
end

function M.revert_to_previous_backup()
   local entries = M.get_backup_files()
   if not entries or #entries == 0 then
      M.debug_log("step", "no entries; nothing to revert")
      return
   end

   local current_idx = tonumber(M.current_index or 0) or 0
   if current_idx < 1 or current_idx > #entries then
      current_idx = 0
   end

   -- Infer current index if missing
   local current_file = nil
   if current_idx > 0 then
      local e = entries[current_idx]
      current_file = e and e.file or nil
   else
      if G and G.SAVED_GAME and G.SAVED_GAME._file then
         current_file = G.SAVED_GAME._file
      elseif M._last_loaded_file then
         current_file = M._last_loaded_file
      end

      if current_file then
         for i, e in ipairs(entries) do
            if e.file == current_file then
               current_idx = i
               break
            end
         end
      end
   end

   M.debug_log("step", "entries=" .. tostring(#entries) .. " current_idx=" .. tostring(current_idx))

   local target_idx
   local delete_from, delete_to

   if current_idx == 0 then
      if #entries < 2 then return end
      target_idx = 2
      delete_from, delete_to = 1, 1
   else
      if current_idx >= #entries then return end
      target_idx = current_idx + 1
      delete_from, delete_to = 1, current_idx
   end

   local target_entry = entries[target_idx]
   if not target_entry or not target_entry.file then return end

   -- Prune forward history
   local dir = M.get_backup_dir()
   if delete_from and delete_to then
      for i = delete_from, delete_to do
         local e = entries[i]
         if e and e.file then
            local path = dir .. "/" .. e.file
            if love.filesystem.getInfo(path) then
               love.filesystem.remove(path)
            end
         end
      end
   end

   M.pending_index = 1
   local label = M.describe_backup({ entry = target_entry })
   M.debug_log("step", "hotkey S -> loading " .. label)
   M.load_and_start_from_file(target_entry.file, { skip_restore_identical = true })
end

-- --- Logic Hook for Save Skipping ---

function M.mark_loaded_state(run_data, opts)
   opts = opts or {}
   local incoming_reason = opts.reason
   
   if not M._pending_skip_reason then
      M._pending_skip_reason = incoming_reason
   end
   M._restore_active = (M._pending_skip_reason == "restore")

   if opts.last_loaded_file and not M._last_loaded_file then
      M._last_loaded_file = opts.last_loaded_file
   end

   if opts.set_skip ~= false then
      M.skip_next_backup = true
   end
   
   M._loaded_meta = StateSignature.get_signature(run_data)
   M._loaded_mark_applied = true
   
   local loaded_sig = M._loaded_meta
   local is_shop = StateSignature.is_shop_signature(loaded_sig)
   
   if (incoming_reason == "restore" or incoming_reason == "step") and is_shop then
      -- We don't need complex arming anymore, just know we are in shop
      -- But keeping the logic structure for consistency if needed later
   end
   
   if M.debug_log then
       local label = M.describe_backup({ meta = M._loaded_meta })
       M.debug_log("restore", "Marking loaded state (" .. label .. ")")
   end
end

function M.consume_skip_on_save(save_table)
   if not M.skip_next_backup then return false end

   if save_table and (not save_table._file) and M._last_loaded_file then
      save_table._file = M._last_loaded_file
   end

   local incoming_sig = M._loaded_meta
   local current_sig = StateSignature.get_signature(save_table)
   local should_skip = StateSignature.signatures_equal(incoming_sig, current_sig)

   -- Shop Pack Open Skip Logic (The Fix)
   if not should_skip and incoming_sig and StateSignature.is_shop_signature(incoming_sig) then
      if M.skipping_pack_open then
         should_skip = true
         M.debug_log("skip", "Forcing skip on Shop Pack Open (flag detected)")
         M.skipping_pack_open = nil
      else
         -- Fallback heuristic
         local ca = save_table.cardAreas
         if ca and ca.pack_cards and ca.pack_cards.cards and next(ca.pack_cards.cards) then
            should_skip = true
            M.debug_log("skip", "Forcing skip on Shop Pack Open auto-save (fallback)")
         end
      end
   end

   if save_table and should_skip then
      save_table.LOADER_SKIP_BACKUP = true
   end

   -- Logging
   if M.debug_log then
       if should_skip then
           M.debug_log("skip", "Skipping backup (match/forced)")
       else
           local from = StateSignature.describe_signature(incoming_sig)
           local into = StateSignature.describe_signature(current_sig)
           M.debug_log("save", "State changed; keeping backup (" .. from .. " -> " .. into .. ")")
       end
   end

   -- Reset flags
   M.skip_next_backup = false
   M._restore_active = false
   M._pending_skip_reason = nil
   M._last_loaded_file = nil
   M._loaded_mark_applied = nil
   M._loaded_meta = nil

   return should_skip
end

return M
