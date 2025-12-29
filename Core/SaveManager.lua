--- Save Rewinder - SaveManager.lua
--
-- Manages the lifecycle of save files: listing, pruning, loading, and metadata.
-- Decoupled from UI code to improve performance and testability.

local M = {}
local StateSignature = require("StateSignature")
local EntryConstants = require("EntryConstants")
local MetaFile = require("MetaFile")
local FileIO = require("FileIO")
local ActionDetector = require("ActionDetector")
local CacheManager = require("CacheManager")
local Pruning = require("Pruning")
local DuplicateDetector = require("DuplicateDetector")

local save_cache = nil -- In-memory cache for save files
local save_cache_by_file = nil -- Map: filename -> entry
local save_index_by_file = nil -- Map: filename -> 1-based index in save_cache

-- Re-export constants for backward compatibility
M.ENTRY_FILE = EntryConstants.ENTRY_FILE
M.ENTRY_ANTE = EntryConstants.ENTRY_ANTE
M.ENTRY_ROUND = EntryConstants.ENTRY_ROUND
M.ENTRY_INDEX = EntryConstants.ENTRY_INDEX
M.ENTRY_MODTIME = EntryConstants.ENTRY_MODTIME
M.ENTRY_STATE = EntryConstants.ENTRY_STATE
M.ENTRY_ACTION_TYPE = EntryConstants.ENTRY_ACTION_TYPE
M.ENTRY_IS_OPENING_PACK = EntryConstants.ENTRY_IS_OPENING_PACK
M.ENTRY_MONEY = EntryConstants.ENTRY_MONEY
M.ENTRY_SIGNATURE = EntryConstants.ENTRY_SIGNATURE
M.ENTRY_DISCARDS_USED = EntryConstants.ENTRY_DISCARDS_USED
M.ENTRY_HANDS_PLAYED = EntryConstants.ENTRY_HANDS_PLAYED
M.ENTRY_IS_CURRENT = EntryConstants.ENTRY_IS_CURRENT
M.ENTRY_BLIND_KEY = EntryConstants.ENTRY_BLIND_KEY

-- Local references for convenience
local ENTRY_FILE = EntryConstants.ENTRY_FILE
local ENTRY_ANTE = EntryConstants.ENTRY_ANTE
local ENTRY_ROUND = EntryConstants.ENTRY_ROUND
local ENTRY_INDEX = EntryConstants.ENTRY_INDEX
local ENTRY_MODTIME = EntryConstants.ENTRY_MODTIME
local ENTRY_STATE = EntryConstants.ENTRY_STATE
local ENTRY_ACTION_TYPE = EntryConstants.ENTRY_ACTION_TYPE
local ENTRY_IS_OPENING_PACK = EntryConstants.ENTRY_IS_OPENING_PACK
local ENTRY_MONEY = EntryConstants.ENTRY_MONEY
local ENTRY_SIGNATURE = EntryConstants.ENTRY_SIGNATURE
local ENTRY_DISCARDS_USED = EntryConstants.ENTRY_DISCARDS_USED
local ENTRY_HANDS_PLAYED = EntryConstants.ENTRY_HANDS_PLAYED
local ENTRY_IS_CURRENT = EntryConstants.ENTRY_IS_CURRENT
local ENTRY_BLIND_KEY = EntryConstants.ENTRY_BLIND_KEY

-- Configuration for file paths
M.PATHS = {
    SAVES = "SaveRewinder",
}

-- Internal state
M._last_loaded_file = nil
M._pending_skip_reason = nil
M._loaded_mark_applied = nil
M._loaded_meta = nil
-- _loaded_had_action removed: use _loaded_meta.is_opening_pack instead
M._restore_active = false
M.skip_next_save = false
M.skipping_pack_open = nil
M.pending_future_prune = {}
M.current_index = nil
M.pending_index = nil
M._last_save_sig = nil  -- Track last save signature to prevent duplicates
M._last_save_time = nil  -- Track when last save was created
M._meta_task = nil          -- Background metadata loading task

-- Tunables to reduce main-thread I/O
local META_FIRST_PASS_COUNT = 12   -- Load this many entries eagerly (covers first UI page)
local META_CHUNK_SIZE = 8          -- Entries to process per background slice

local function _rebuild_file_index()
   if not save_cache then
      save_cache_by_file = nil
      save_index_by_file = nil
      return
   end

   save_cache_by_file = {}
   save_index_by_file = {}
   for i, entry in ipairs(save_cache) do
      local file = entry and entry[ENTRY_FILE]
      if file then
         save_cache_by_file[file] = entry
         save_index_by_file[file] = i
      end
   end
end

function M.get_entry_by_file(file)
   if not file then return nil end
   if not save_cache_by_file then _rebuild_file_index() end
   return save_cache_by_file and save_cache_by_file[file] or nil
end

function M.get_index_by_file(file)
   if not file then return nil end
   if not save_index_by_file then _rebuild_file_index() end
   return save_index_by_file and save_index_by_file[file] or nil
end

-- Helper: find index of current save (by _last_loaded_file or is_current flag)
function M.find_current_index()
   -- Fast path: use _last_loaded_file with index lookup
   if M._last_loaded_file then
      local idx = M.get_index_by_file(M._last_loaded_file)
      if idx then return idx end
   end
   -- Fallback: scan for is_current flag
   if save_cache then
      for i, entry in ipairs(save_cache) do
         if entry and entry[ENTRY_IS_CURRENT] == true then
            return i
         end
      end
   end
   return nil
end

-- Debug logging (centralized via Logger module)
local Logger = require("Logger")
M.debug_log = Logger.create("SaveManager")

-- Schedule background metadata loading to avoid long stalls
local function _schedule_meta_load(entries, start_idx)
   if not entries or start_idx > #entries then return end

   -- Fallback: if no scheduler is available, load synchronously
   if not (G and G.E_MANAGER and Event) then
      for i = start_idx, #entries do
         if entries[i] and not entries[i][ENTRY_SIGNATURE] then
            M.get_save_meta(entries[i])
         end
      end
      ActionDetector.detect_action_types_for_entries(entries, entries, M.get_save_meta, EntryConstants)
      M._update_cache_current_flags()
      return
   end

   -- If a task is already running on this table, just move the pointer earlier
   if M._meta_task and M._meta_task.entries == entries then
      M._meta_task.idx = math.min(M._meta_task.idx, start_idx)
      return
   end

   M._meta_task = { entries = entries, idx = start_idx }

   G.E_MANAGER:add_event(Event({
      trigger = 'after',
      delay = 0,
      func = function()
         if not M._meta_task or M._meta_task.entries ~= entries then
            return true
         end

         local i = M._meta_task.idx
         local processed = 0
         while i <= #entries and processed < META_CHUNK_SIZE do
            if entries[i] and not entries[i][ENTRY_SIGNATURE] then
               M.get_save_meta(entries[i])
            end
            i = i + 1
            processed = processed + 1
         end

         M._meta_task.idx = i

         if i > #entries then
            -- Finalize: detect action types now that all metadata is available
            ActionDetector.detect_action_types_for_entries(entries, entries, M.get_save_meta, EntryConstants)
            M._update_cache_current_flags()
            M._meta_task = nil
            return true
         end

         -- Continue on next frame
         return false
      end
   }))
end

-- --- File System Helpers ---

function M.get_profile()
    return FileIO.get_profile()
end

function M.get_save_dir()
    return FileIO.get_save_dir(M.PATHS.SAVES)
end

-- Clears all saves from the filesystem and resets the in-memory cache.
function M.clear_all_saves()
    local dir = M.get_save_dir()
    if love.filesystem.getInfo(dir) then
        for _, file in ipairs(love.filesystem.getDirectoryItems(dir)) do
            pcall(love.filesystem.remove, dir .. "/" .. file)
            -- Also remove .meta file if it exists
            if file:match("%.jkr$") then
                local meta_file = file:gsub("%.jkr$", ".meta")
                pcall(love.filesystem.remove, dir .. "/" .. meta_file)
            end
        end
    end
    save_cache = {} -- Reset cache to an empty table
    _rebuild_file_index()
    -- M.debug_log("prune", "Cleared all saves and reset cache.") -- This log can cause recursion with other mods (e.g. debugplus) during a new run.
end

-- --- Save Listing & Metadata ---

function M.get_save_meta(entry)
    if not entry or not entry[ENTRY_FILE] then return nil end
    
    -- If already loaded (has signature and action_type if applicable), return early
    if entry[ENTRY_SIGNATURE] and (entry[ENTRY_ACTION_TYPE] ~= nil or (entry[ENTRY_STATE] and entry[ENTRY_STATE] ~= (G and G.STATES and G.STATES.SELECTING_HAND))) then
        return true
    end

    local dir = M.get_save_dir()
    local full_path = dir .. "/" .. entry[ENTRY_FILE]
    local meta_path = dir .. "/" .. entry[ENTRY_FILE]:gsub("%.jkr$", ".meta")

    -- Try to read from .meta file first (fast path)
    local meta = MetaFile.read_meta_file(meta_path)
    if meta then
        -- Store flattened structure directly in entry array
        entry[ENTRY_STATE] = meta.state
        entry[ENTRY_ACTION_TYPE] = meta.action_type
        entry[ENTRY_IS_OPENING_PACK] = meta.is_opening_pack or false
        entry[ENTRY_MONEY] = meta.money
        entry[ENTRY_SIGNATURE] = meta.signature
        entry[ENTRY_DISCARDS_USED] = meta.discards_used
        entry[ENTRY_HANDS_PLAYED] = meta.hands_played
        entry[ENTRY_BLIND_KEY] = meta.blind_key
        M.debug_log("info", "Loaded blind_key from meta file: " .. tostring(meta.blind_key) .. " for file " .. tostring(entry[ENTRY_FILE]))
        return true
    end

    -- Fallback: unpack full save file (slow path)
    local run_data = FileIO.load_save_file(entry[ENTRY_FILE], dir)
    
    if run_data then
        -- Get signature which will include action_type, is_opening_pack and tracking values from run_data
        local sig = StateSignature.get_signature(run_data)
        if sig then
            -- Store flattened structure directly in entry array
            entry[ENTRY_STATE] = sig.state
            entry[ENTRY_ACTION_TYPE] = sig.action_type  -- Only "play" or "discard" for SELECTING_HAND, nil otherwise
            entry[ENTRY_IS_OPENING_PACK] = sig.is_opening_pack or false  -- Boolean for shop states
            entry[ENTRY_MONEY] = sig.money
            entry[ENTRY_SIGNATURE] = sig.signature
            entry[ENTRY_DISCARDS_USED] = sig.discards_used  -- Store for action type detection
            entry[ENTRY_HANDS_PLAYED] = sig.hands_played   -- Store for action type detection
            entry[ENTRY_BLIND_KEY] = sig.blind_key
            M.debug_log("info", "Loaded blind_key from save file: " .. tostring(sig.blind_key) .. " for file " .. tostring(entry[ENTRY_FILE]))
            
            -- Write .meta file for future fast reads (same structure as cache entry metadata)
            local entry_meta = {
                state = sig.state,
                action_type = sig.action_type,  -- Only "play" or "discard" for SELECTING_HAND
                is_opening_pack = sig.is_opening_pack or false,  -- Boolean for shop states
                money = sig.money,
                signature = sig.signature,
                discards_used = sig.discards_used,
                hands_played = sig.hands_played,
                blind_key = sig.blind_key,
            }
            MetaFile.write_meta_file(meta_path, entry_meta)
            
            -- Note: action_type for SELECTING_HAND (play/discard) is detected in get_save_files second pass
            -- to ensure save_cache is populated and entries are sorted
            return true
        end
    end
    return nil
end

-- Returns a sorted list of all available saves with metadata.
function M.get_save_files(force_reload)
   if save_cache and not force_reload then
      -- Always update current flags even when returning cached entries
      M._update_cache_current_flags()
      if not save_cache_by_file or not save_index_by_file then
         _rebuild_file_index()
      end
      return save_cache
   end
   local dir = M.get_save_dir()
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
            
            -- Create entry as array: {file, ante, round, index, modtime, state, action_type, is_opening_pack, money, signature, discards_used, hands_played, is_current, blind_key}
            local entry = {
               file,  -- [ENTRY_FILE]
               ante,  -- [ENTRY_ANTE]
               round,  -- [ENTRY_ROUND]
               index,  -- [ENTRY_INDEX]
               info.modtime or 0,  -- [ENTRY_MODTIME]
               nil,  -- [ENTRY_STATE] - loaded by get_save_meta
               nil,  -- [ENTRY_ACTION_TYPE] - loaded by get_save_meta or detected later (only "play" or "discard")
               false,  -- [ENTRY_IS_OPENING_PACK] - loaded by get_save_meta (boolean for shop states)
               nil,  -- [ENTRY_MONEY] - loaded by get_save_meta
               nil,  -- [ENTRY_SIGNATURE] - loaded by get_save_meta
               nil,  -- [ENTRY_DISCARDS_USED] - loaded by get_save_meta
               nil,  -- [ENTRY_HANDS_PLAYED] - loaded by get_save_meta
               false,  -- [ENTRY_IS_CURRENT] - set by _update_cache_current_flags
               nil,  -- [ENTRY_BLIND_KEY] - loaded by get_save_meta (e.g., "bl_small", "bl_final_acorn")
            }

            table.insert(entries, entry)
         end
      end
   end

   -- Sort by modtime (newest first), then by index as tie-breaker
   table.sort(entries, function(a, b)
      if a[ENTRY_MODTIME] ~= b[ENTRY_MODTIME] then
         return a[ENTRY_MODTIME] > b[ENTRY_MODTIME]
      end
      return a[ENTRY_INDEX] > b[ENTRY_INDEX]
   end)

   save_cache = entries
   _rebuild_file_index()
  
   -- First pass: load metadata for the newest entries (covers first UI page)
   local preload = math.min(META_FIRST_PASS_COUNT, #entries)
   for i = 1, preload do
      if not entries[i][ENTRY_SIGNATURE] then
         M.get_save_meta(entries[i])
      end
   end

   -- Update current file flags immediately for the visible page
   M._update_cache_current_flags()

   -- Background-load the remaining metadata to avoid blocking the main thread
   if preload < #entries then
      _schedule_meta_load(entries, preload + 1)
   else
      -- If everything is already loaded, finish action detection synchronously
      ActionDetector.detect_action_types_for_entries(entries, entries, M.get_save_meta, EntryConstants)
      M._update_cache_current_flags()
   end
   
   return entries
end

-- Fully preload metadata for all entries synchronously.
-- This is intended to run during boot so no further `.meta` reads / `.jkr` decodes
-- occur later when opening the UI.
function M.preload_all_metadata(force_reload)
   local entries = M.get_save_files(force_reload == true)

   -- Cancel any queued background task for metadata loading.
   M._meta_task = nil

   for i = 1, #entries do
      if entries[i] and not entries[i][ENTRY_SIGNATURE] then
         M.get_save_meta(entries[i])
      end
   end

   ActionDetector.detect_action_types_for_entries(entries, entries, M.get_save_meta, EntryConstants)
   M._update_cache_current_flags()
   _rebuild_file_index()
   return entries
end

-- Helper to update cache flags for a specific file (more efficient than full update)
-- Use a persistent reference table so CacheManager can update _last_loaded_file
local _last_loaded_file_ref = {nil}
function M._set_cache_current_file(file)
   _last_loaded_file_ref[1] = file  -- Update the reference
   M._last_loaded_file = file      -- Also update the direct field for backward compatibility
   CacheManager.set_cache_current_file(save_cache, file, EntryConstants, _last_loaded_file_ref)
end

-- Updates the is_current flag in cache entries based on current file
function M._update_cache_current_flags()
   -- Sync the reference with the current value
   _last_loaded_file_ref[1] = M._last_loaded_file
   CacheManager.update_cache_current_flags(save_cache, _last_loaded_file_ref, EntryConstants)
   -- Sync back after update (in case CacheManager updated it)
   M._last_loaded_file = _last_loaded_file_ref[1]
end

-- Describes a save for logging/debugging.
-- Always computes on-demand (description field removed for performance).
function M.describe_save(opts)
   opts = opts or {}
   local file = opts.file
   local entry = opts.entry

   -- 1. Best case: Generate from entry fields in cache.
   if entry and entry[ENTRY_STATE] ~= nil then
      local sig = {
         ante = entry[ENTRY_ANTE],
         round = entry[ENTRY_ROUND],
         state = entry[ENTRY_STATE],
         action_type = entry[ENTRY_ACTION_TYPE],
         is_opening_pack = entry[ENTRY_IS_OPENING_PACK] or false,
         money = entry[ENTRY_MONEY],
      }
      return StateSignature.describe_signature(sig) or "Save"
   end

   -- 2. Good case: Find the entry in the cache using the filename.
   if file then
      local e = M.get_entry_by_file(file)
      if e and e[ENTRY_STATE] ~= nil then
         local sig = {
            ante = e[ENTRY_ANTE],
            round = e[ENTRY_ROUND],
            state = e[ENTRY_STATE],
            action_type = e[ENTRY_ACTION_TYPE],
            is_opening_pack = e[ENTRY_IS_OPENING_PACK] or false,
            money = e[ENTRY_MONEY],
         }
         return StateSignature.describe_signature(sig) or "Save"
      end
   end
   
   -- 3. Last resort: Generate from run_data
   if opts.run_data then
      local sig = StateSignature.get_signature(opts.run_data)
      return StateSignature.describe_signature(sig) or "Save"
   end
   
   return "Save"
end


-- --- Loading & State Management ---

-- Syncs the save data to the main save.jkr file
function M.sync_to_main_save(run_data)
    return FileIO.sync_to_main_save(run_data)
end

-- Copy save file directly to save.jkr without decoding (fast path)
function M.copy_save_to_main(file)
    return FileIO.copy_save_to_main(file, M.get_save_dir())
end

function M.load_save_file(file)
    return FileIO.load_save_file(file, M.get_save_dir())
end

local function start_from_file(file, opts)
   opts = opts or {}
   -- Sync index with save list to maintain stepping history
   local idx_from_list = nil
   local entries = M.get_save_files()
   for i, e in ipairs(entries) do
      if e and e[ENTRY_FILE] == file then
         idx_from_list = i
         break
      end
   end

   M.pending_future_prune = {}
   if entries and idx_from_list and idx_from_list > 1 then
      for i = 1, idx_from_list - 1 do
         local e = entries[i]
         if e and e[ENTRY_FILE] then
            table.insert(M.pending_future_prune, e[ENTRY_FILE])
         end
      end
   end

   M.current_index = M.pending_index or idx_from_list or 1
   M.pending_index = nil

   if REWINDER then REWINDER.saves_open = false end

   -- Copy save file directly to save.jkr (fast path, no decode needed)
   local copied_ok = M.copy_save_to_main(file)
   if not copied_ok then
      M.debug_log("error", "Failed to copy save to save.jkr")
      return false
   end

   -- Load run data from save.jkr (QuickLoad-style).
   -- This keeps the in-memory savetext consistent with what's on disk after copy.
   local run_data = nil
   if get_compressed and STR_UNPACK then
      local ok, packed = pcall(get_compressed, M.get_profile() .. "/save.jkr")
      if ok and packed then
         local ok_unpack, unpacked = pcall(STR_UNPACK, packed)
         if ok_unpack then run_data = unpacked end
      end
   end

   -- Fallback: unpack directly from the target file.
   if not run_data then
      run_data = M.load_save_file(file)
   end
   if not run_data then
      M.debug_log("error", "Failed to load save file for start_run")
      return false
   end

   -- Set up the saved game data
   G.SAVED_GAME = run_data
   G.SETTINGS = G.SETTINGS or {}
   G.SETTINGS.current_setup = "Continue"
   
   -- CRITICAL: Ensure _file is set on G.SAVED_GAME so start_run can preserve it
   run_data._file = file
   G.SAVED_GAME._file = file
   
   -- Update current file tracking and cache flags
   M._set_cache_current_file(file)

   -- Start the run
   if opts.no_wipe and G and G.delete_run and G.start_run then
      -- Brainstorm-style: direct delete_run + start_run avoids loading wipe.
      local ok, err = pcall(function()
         G:delete_run()
         G:start_run({ savetext = G.SAVED_GAME })
      end)
      if not ok then
         M.debug_log("error", "start_run failed: " .. tostring(err))
      end
   else
      if G and G.FUNCS and G.FUNCS.start_run then
         local ok, err = pcall(function()
            G.FUNCS.start_run(nil, { savetext = G.SAVED_GAME })
         end)
         if not ok then
            M.debug_log("error", "start_run failed: " .. tostring(err))
         end
      elseif G and G.start_run then
         local ok, err = pcall(function()
            G:start_run({ savetext = G.SAVED_GAME })
         end)
         if not ok then
            M.debug_log("error", "start_run failed: " .. tostring(err))
         end
      else
         M.debug_log("error", "start_run not found!")
      end
   end

   return true
end

function M.load_and_start_from_file(file, opts)
   opts = opts or {}
   
   local mark_restore = not opts.skip_restore_identical
   local reason = mark_restore and "restore" or "step"
   
   -- Reset State
   M._loaded_mark_applied = nil
   M._loaded_meta = nil
   M._pending_skip_reason = reason
   M._restore_active = (reason == "restore")
   M._last_loaded_file = file
   M.skip_next_save = true
   
   -- Update cache flags immediately (before starting run)
   -- This ensures highlight works if UI is opened again
   M._last_loaded_file = file  -- Set directly first
   M._set_cache_current_file(file)

   -- Get description from cache entry (computed on-demand)
   if mark_restore then
      local description = M.describe_save({file = file})
      M.debug_log("restore", "Loading " .. description)
   end
   
   -- Use fast path: copy file directly, then load for start_run
   start_from_file(file, opts)
end

function M.revert_to_previous_save()
   local entries = M.get_save_files()
   if not entries or #entries == 0 then
      M.debug_log("step", "No saves to revert to")
      return
   end

   -- Infer current index from file (most reliable)
   local current_file = (G and G.SAVED_GAME and G.SAVED_GAME._file) or M._last_loaded_file
   local current_idx = 0
   
   if current_file then
      for i, e in ipairs(entries) do
         if e[ENTRY_FILE] == current_file then
            current_idx = i
            break
         end
      end
   end
   
   -- Fallback to stored current_index
   if current_idx == 0 and M.current_index then
      local stored_idx = tonumber(M.current_index or 0) or 0
      if stored_idx >= 1 and stored_idx <= #entries then
         current_idx = stored_idx
      end
   end

   local target_idx
   if current_idx == 0 then -- Current state is not a save, revert to newest save
      if #entries == 0 then return end
      target_idx = 1
   else -- Current state is a save, revert to the next oldest one
      if current_idx >= #entries then return end -- Already at the oldest save
      target_idx = current_idx + 1
   end

   local target_entry = entries[target_idx]
   if not target_entry or not target_entry[ENTRY_FILE] then return end

   -- By just loading an older save, we rely on the `pending_future_prune`
   -- mechanism to clean up the divergent timeline on the *next* save.
   -- This makes the "revert" action non-destructive, allowing the user to
   -- step forward again if they reverted by mistake (a feature that could be added later).
   -- The immediate pruning that was here before was inconsistent with the deferred pruning
   -- used elsewhere.

   -- We don't need to set pending_index. `load_and_start_from_file` will
   -- call `start_from_file`, which correctly identifies the index from the file list.
   local label = M.describe_save({ entry = target_entry })
   M.debug_log("step", "hotkey S -> loading " .. label)
   M.load_and_start_from_file(target_entry[ENTRY_FILE], { skip_restore_identical = true, no_wipe = true })
end

function M.load_save_at_index(index)
   local entries = M.get_save_files()
   if not entries or #entries == 0 then
      M.debug_log("error", "No saves available")
      return
   end
   
   if index < 1 or index > #entries then
      M.debug_log("error", "Invalid save index: " .. tostring(index))
      return
   end
   
   local entry = entries[index]
   if not entry or not entry[ENTRY_FILE] then
      M.debug_log("error", "Invalid entry at index: " .. tostring(index))
      return
   end
   
   M.pending_index = index
   M.load_and_start_from_file(entry[ENTRY_FILE])
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
      -- Update the reference table if it exists
      if _last_loaded_file_ref then
         _last_loaded_file_ref[1] = opts.last_loaded_file
      end
   end
   
   M._loaded_meta = StateSignature.get_signature(run_data)
   M._loaded_mark_applied = true
   
   local loaded_sig = M._loaded_meta
   local is_shop = StateSignature.is_shop_signature(loaded_sig)
   local has_action = (loaded_sig.is_opening_pack == true)
   
   -- IMPORTANT: Shop state without ACTION - don't skip the next save!
   -- When restoring to a shop state without action, the game won't auto-save immediately.
   -- The next save will be triggered by user action (refresh, buy, open pack, etc.)
   -- and that state SHOULD be saved, not skipped.
   if is_shop and not has_action then
      M.skip_next_save = false
      M.debug_log("restore", "Shop state without ACTION - next save will NOT be skipped")
   elseif opts.set_skip ~= false then
      M.skip_next_save = true
   end
   
   -- Only log for non-shop states with action, as shop without action is common
   if has_action then
      local desc = StateSignature.describe_signature(M._loaded_meta)
      M.debug_log("restore", "Marked: " .. desc .. " (has ACTION)")
   end
end

function M.consume_skip_on_save(save_table)
   if not M.skip_next_save then return false end

   if save_table and (not save_table._file) and M._last_loaded_file then
      save_table._file = M._last_loaded_file
   end

   local incoming_sig = M._loaded_meta
   local current_sig = StateSignature.get_signature(save_table)
   local should_skip = StateSignature.signatures_equal(incoming_sig, current_sig)

   -- Shop Pack Open Skip Logic
   local has_loaded_action = (incoming_sig and incoming_sig.is_opening_pack == true)
   if not should_skip and incoming_sig and StateSignature.is_shop_signature(incoming_sig) and has_loaded_action then
      if M.skipping_pack_open then
         should_skip = true
         M.skipping_pack_open = nil
      else
         local ca = save_table.cardAreas
         if ca and ca.pack_cards and ca.pack_cards.cards and next(ca.pack_cards.cards) then
            should_skip = true
         end
      end
   end
   
   M.skipping_pack_open = nil

   if save_table and should_skip then
      save_table.REWINDER_SKIP_SAVE = true
   end

   -- Only log when NOT skipping (actual saves are more important to track)
   if not should_skip then
       local into = StateSignature.describe_signature(current_sig)
       local log_msg = "Saving: " .. into
       if StateSignature.is_shop_signature(current_sig) and current_sig.is_opening_pack == true then
           log_msg = log_msg .. " [Shop with ACTION]"
       end
       M.debug_log("save", log_msg)
   end

   -- Reset flags (but preserve _last_loaded_file for UI highlighting)
   M.skip_next_save = false
   M._restore_active = false
   M._pending_skip_reason = nil
   -- DO NOT reset _last_loaded_file here - it's needed for UI highlighting
   -- It will only be reset when starting a brand new run (in GamePatches.lua)
   M._loaded_mark_applied = nil
   M._loaded_meta = nil

   return should_skip
end

-- --- Save Creation & Pruning ---

function M.create_save(run_data)
    local timing_enabled = false

    -- Check if we should skip this save
    if M.consume_skip_on_save(run_data) then
        return
    end

    local sig = StateSignature.get_signature(run_data)
    if not sig then
        M.debug_log("error", "No signature for save")
        return
    end

    -- Check config filters for different state types
    local st = G and G.STATES
    local config = REWINDER and REWINDER.config
    
    if st then
        -- Check filter for end of round (ROUND_EVAL or HAND_PLAYED states)
        if sig.state == st.ROUND_EVAL or sig.state == st.HAND_PLAYED then
            local should_save = (config == nil) or (config.save_on_round_end ~= false)
            if not should_save then
                M.debug_log("filter", "Skipping save at end of round (config disabled)")
                return
            end
        end
        
        -- Check filter for blind select (BLIND_SELECT state)
        if sig.state == st.BLIND_SELECT then
            local should_save = (config == nil) or (config.save_on_blind ~= false)
            if not should_save then
                M.debug_log("filter", "Skipping save at blind select (config disabled)")
                return
            end
        end
        
        -- Check filter for selecting hand (SELECTING_HAND state)
        if sig.state == st.SELECTING_HAND then
            local should_save = (config == nil) or (config.save_on_selecting_hand ~= false)
            if not should_save then
                M.debug_log("filter", "Skipping save at selecting hand (config disabled)")
                return
            end
        end
        
        -- Check filter for shop (SHOP state)
        if sig.state == st.SHOP then
            local should_save = (config == nil) or (config.save_on_shop ~= false)
            if not should_save then
                M.debug_log("filter", "Skipping save at shop (config disabled)")
                return
            end
        end
    end

    -- Check for duplicate saves
    local current_time = love.timer.getTime()
    if DuplicateDetector.should_skip_duplicate(sig, M._last_save_sig, M._last_save_time, current_time, StateSignature) then
        return
    end

    -- Ensure the cache is initialized before we modify it
    M.get_save_files()

    local dir = M.get_save_dir()

    -- Prune any divergent timelines before creating the new save
    Pruning.prune_future_saves(dir, M.pending_future_prune, save_cache, EntryConstants)
    _rebuild_file_index()

    -- Generate a unique filename. Using a high-precision timer for the unique part
    -- to prevent collisions if multiple saves occur within the same second.
    local unique_id = math.floor(love.timer.getTime() * 1000)
    local current_time = os.time()
    local filename = string.format("%d-%d-%d.jkr",
        sig.ante,
        sig.round,
        unique_id
    )

    -- Determine action type by comparing with previous save in the same round
    -- action_type is only for SELECTING_HAND states (play/discard)
    -- is_opening_pack is already set in sig for shop states
    local action_type = nil  -- Only "play" or "discard" for SELECTING_HAND states
    
    -- Create a temporary entry for action detection
    local temp_entry = {}
    temp_entry[ENTRY_ANTE] = sig.ante
    temp_entry[ENTRY_ROUND] = sig.round
    temp_entry[ENTRY_DISCARDS_USED] = sig.discards_used
    temp_entry[ENTRY_HANDS_PLAYED] = sig.hands_played
    
    -- Use ActionDetector to determine action type
    action_type = ActionDetector.detect_action_type(temp_entry, sig, save_cache, M.get_save_meta, EntryConstants)
    
    if action_type then
        local current_round_key = string.format("%d:%d", sig.ante, sig.round)
        M.debug_log("monitor", string.format("Action detected: %s in round %s", action_type, current_round_key))
    end
    
    -- Create an entry as array: {file, ante, round, index, modtime, state, action_type, is_opening_pack, money, signature, discards_used, hands_played, is_current, blind_key}
    local new_entry = {
        filename,  -- [ENTRY_FILE]
        sig.ante,  -- [ENTRY_ANTE]
        sig.round,  -- [ENTRY_ROUND]
        unique_id,  -- [ENTRY_INDEX]
        current_time,  -- [ENTRY_MODTIME]
        sig.state,  -- [ENTRY_STATE]
        action_type,  -- [ENTRY_ACTION_TYPE] - only "play" or "discard" for SELECTING_HAND, nil otherwise
        sig.is_opening_pack or false,  -- [ENTRY_IS_OPENING_PACK] - boolean for shop states
        sig.money,  -- [ENTRY_MONEY]
        sig.signature,  -- [ENTRY_SIGNATURE]
        sig.discards_used,  -- [ENTRY_DISCARDS_USED] - Store for future action type detection
        sig.hands_played,  -- [ENTRY_HANDS_PLAYED] - Store for future action type detection
        false,  -- [ENTRY_IS_CURRENT] - Set by _set_cache_current_file
        sig.blind_key,  -- [ENTRY_BLIND_KEY] - Blind identifier for UI display (e.g., "bl_small", "bl_final_acorn")
    }

    local full_path = dir .. "/" .. filename
    
    -- Serialize and save (reuse FileIO helper, with optional timing)
    local ok_write, write_result = FileIO.write_save_file(run_data, full_path, { timing = timing_enabled })
    if not ok_write then
        M.debug_log("error", "Failed to write save: " .. tostring(write_result))
        return
    end
    local file_timings = timing_enabled and write_result or nil

    -- Write .meta file for fast metadata loading (same structure as cache entry metadata)
    local t_meta = timing_enabled and love.timer.getTime() or nil
    local meta_path = dir .. "/" .. filename:gsub("%.jkr$", ".meta")
    local entry_meta = {
        state = sig.state,
        action_type = action_type,  -- only "play" or "discard" for SELECTING_HAND, nil otherwise
        is_opening_pack = sig.is_opening_pack or false,  -- boolean for shop states
        money = sig.money,
        signature = sig.signature,
        discards_used = sig.discards_used,
        hands_played = sig.hands_played,
        blind_key = sig.blind_key,  -- Blind identifier for UI display
    }
    MetaFile.write_meta_file(meta_path, entry_meta)

    -- Update cache and state
    table.insert(save_cache, 1, new_entry)
    run_data._file = filename
    M.current_index = 1
    
    -- Mark new entry as current (updates all cache flags)
    M._set_cache_current_file(filename)
    M._last_save_sig = sig  -- Track to prevent duplicates
    M._last_save_time = love.timer.getTime()  -- Track when save was created

    -- Log the save with description (computed on-demand)
    local log_msg = "Created: " .. StateSignature.describe_signature({
        ante = sig.ante,
        round = sig.round,
        state = sig.state,
        action_type = action_type,
        is_opening_pack = sig.is_opening_pack or false,
        money = sig.money,
    })
    M.debug_log("save", log_msg)

    -- Timing disabled (kept hook for future use)

    Pruning.apply_retention_policy(dir, save_cache, EntryConstants)
    _rebuild_file_index()
end

return M
