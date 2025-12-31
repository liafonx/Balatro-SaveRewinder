--- Save Rewinder - SaveManager.lua
-- Manages save file lifecycle: listing, pruning, loading, and metadata.
local M = {}
local StateSignature = require("StateSignature")
local EntryConstants = require("EntryConstants")
local MetaFile = require("MetaFile")
local FileIO = require("FileIO")
local ActionDetector = require("ActionDetector")
local CacheManager = require("CacheManager")
local Pruning = require("Pruning")
local DuplicateDetector = require("DuplicateDetector")
local Logger = require("Logger")

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

-- Local aliases
local E = EntryConstants

M.PATHS = { SAVES = "SaveRewinder" }
M.debug_log = Logger.create("SaveManager")

-- Internal state
local save_cache, save_cache_by_file, save_index_by_file = nil, nil, nil
local _last_loaded_file_ref = {nil}

M._last_loaded_file = nil
M._pending_skip_reason = nil
M._loaded_mark_applied = nil
M._loaded_meta = nil
M._restore_active = false
M.skip_next_save = false
M.skipping_pack_open = nil
M.pending_future_prune = {}
M.current_index = nil
M.pending_index = nil
M._last_save_sig = nil
M._last_save_time = nil

-- --- Index Helpers ---

local function _rebuild_file_index()
   if not save_cache then
      save_cache_by_file, save_index_by_file = nil, nil
      return
   end
   save_cache_by_file, save_index_by_file = {}, {}
   for i, entry in ipairs(save_cache) do
      local file = entry and entry[E.ENTRY_FILE]
      if file then
         save_cache_by_file[file] = entry
         save_index_by_file[file] = i
      end
   end
end

function M.get_entry_by_file(file)
   if not file then return nil end
   if not save_cache_by_file then _rebuild_file_index() end
   return save_cache_by_file and save_cache_by_file[file]
end

function M.get_index_by_file(file)
   if not file then return nil end
   if not save_index_by_file then _rebuild_file_index() end
   return save_index_by_file and save_index_by_file[file]
end

function M.find_current_index()
   if M._last_loaded_file then
      local idx = M.get_index_by_file(M._last_loaded_file)
      if idx then return idx end
   end
   if save_cache then
      for i, entry in ipairs(save_cache) do
         if entry and entry[E.ENTRY_IS_CURRENT] then return i end
      end
   end
   return nil
end

-- --- File System Helpers ---

function M.get_profile() return FileIO.get_profile() end
function M.get_save_dir() return FileIO.get_save_dir(M.PATHS.SAVES) end

function M.clear_all_saves()
   local dir = M.get_save_dir()
   if love.filesystem.getInfo(dir) then
      for _, file in ipairs(love.filesystem.getDirectoryItems(dir)) do
         love.filesystem.remove(dir .. "/" .. file)
      end
   end
   save_cache = {}
   _rebuild_file_index()
end

-- --- Save Listing & Metadata ---

function M.get_save_meta(entry)
   if not entry or not entry[E.ENTRY_FILE] then return nil end
   if entry[E.ENTRY_SIGNATURE] then return true end

   local dir = M.get_save_dir()
   local meta_path = dir .. "/" .. entry[E.ENTRY_FILE]:gsub("%.jkr$", ".meta")
   local meta = MetaFile.read_meta_file(meta_path)
   
   if meta then
      entry[E.ENTRY_STATE] = meta.state
      entry[E.ENTRY_ACTION_TYPE] = meta.action_type
      entry[E.ENTRY_IS_OPENING_PACK] = meta.is_opening_pack or false
      entry[E.ENTRY_MONEY] = meta.money
      entry[E.ENTRY_SIGNATURE] = meta.signature
      entry[E.ENTRY_DISCARDS_USED] = meta.discards_used
      entry[E.ENTRY_HANDS_PLAYED] = meta.hands_played
      entry[E.ENTRY_BLIND_KEY] = meta.blind_key
      return true
   end

   -- Fallback: unpack full save file
   local run_data = FileIO.load_save_file(entry[E.ENTRY_FILE], dir)
   if not run_data then return nil end
   
   local sig = StateSignature.get_signature(run_data)
   if not sig then return nil end
   
   entry[E.ENTRY_STATE] = sig.state
   entry[E.ENTRY_ACTION_TYPE] = sig.action_type
   entry[E.ENTRY_IS_OPENING_PACK] = sig.is_opening_pack or false
   entry[E.ENTRY_MONEY] = sig.money
   entry[E.ENTRY_SIGNATURE] = sig.signature
   entry[E.ENTRY_DISCARDS_USED] = sig.discards_used
   entry[E.ENTRY_HANDS_PLAYED] = sig.hands_played
   entry[E.ENTRY_BLIND_KEY] = sig.blind_key
   
   -- Write .meta file for future fast reads
   MetaFile.write_meta_file(meta_path, {
      state = sig.state, action_type = sig.action_type,
      is_opening_pack = sig.is_opening_pack or false, money = sig.money,
      signature = sig.signature, discards_used = sig.discards_used,
      hands_played = sig.hands_played, blind_key = sig.blind_key,
   })
   return true
end

local function _list_and_sort_entries()
   local dir = M.get_save_dir()
   local files = love.filesystem.getDirectoryItems(dir)
   local entries = {}

   for _, file in ipairs(files) do
      if file:match("%.jkr$") then
         local full = dir .. "/" .. file
         local info = love.filesystem.getInfo(full)
         if info and info.type == "file" then
            local ante_str, round_str, index_str = file:match("^(%d+)%-(%d+)%-(%d+)%.jkr$")
            local ante, round, index = tonumber(ante_str) or 0, tonumber(round_str) or 0, tonumber(index_str) or 0
            entries[#entries+1] = {
               file, ante, round, index, info.modtime or 0,
               nil, nil, false, nil, nil, nil, nil, false, nil
            }
         end
      end
   end

   table.sort(entries, function(a, b)
      if a[E.ENTRY_MODTIME] ~= b[E.ENTRY_MODTIME] then
         return a[E.ENTRY_MODTIME] > b[E.ENTRY_MODTIME]
      end
      return a[E.ENTRY_INDEX] > b[E.ENTRY_INDEX]
   end)
   return entries
end

function M._set_cache_current_file(file)
   _last_loaded_file_ref[1] = file
   M._last_loaded_file = file
   CacheManager.set_cache_current_file(save_cache, file, EntryConstants, _last_loaded_file_ref)
end

function M._update_cache_current_flags()
   _last_loaded_file_ref[1] = M._last_loaded_file
   CacheManager.update_cache_current_flags(save_cache, _last_loaded_file_ref, EntryConstants)
   M._last_loaded_file = _last_loaded_file_ref[1]
end

-- Returns sorted list of saves. Use sync=true to load all metadata synchronously.
function M.get_save_files(force_reload, sync)
   if save_cache and not force_reload then
      M._update_cache_current_flags()
      if not save_cache_by_file then _rebuild_file_index() end
      return save_cache
   end

   save_cache = _list_and_sort_entries()
   _rebuild_file_index()
   
   for i = 1, #save_cache do
      if not save_cache[i][E.ENTRY_SIGNATURE] then
         M.get_save_meta(save_cache[i])
      end
   end
   
   ActionDetector.detect_action_types_for_entries(save_cache, save_cache, M.get_save_meta, EntryConstants)
   M._update_cache_current_flags()
   return save_cache
end

function M.preload_all_metadata(force_reload)
   return M.get_save_files(force_reload, true)
end

-- Build sig table from entry for describe_signature
local function _sig_from_entry(e)
   return {
      ante = e[E.ENTRY_ANTE], round = e[E.ENTRY_ROUND], state = e[E.ENTRY_STATE],
      action_type = e[E.ENTRY_ACTION_TYPE], is_opening_pack = e[E.ENTRY_IS_OPENING_PACK] or false,
      money = e[E.ENTRY_MONEY],
   }
end

function M.describe_save(opts)
   opts = opts or {}
   if opts.entry and opts.entry[E.ENTRY_STATE] ~= nil then
      return StateSignature.describe_signature(_sig_from_entry(opts.entry)) or "Save"
   end
   if opts.file then
      local e = M.get_entry_by_file(opts.file)
      if e and e[E.ENTRY_STATE] ~= nil then
         return StateSignature.describe_signature(_sig_from_entry(e)) or "Save"
      end
   end
   if opts.run_data then
      return StateSignature.describe_signature(StateSignature.get_signature(opts.run_data)) or "Save"
   end
   return "Save"
end

-- --- Loading & State Management ---

function M.sync_to_main_save(run_data) return FileIO.sync_to_main_save(run_data) end
function M.copy_save_to_main(file) return FileIO.copy_save_to_main(file, M.get_save_dir()) end
function M.load_save_file(file) return FileIO.load_save_file(file, M.get_save_dir()) end

local function start_from_file(file, opts)
   opts = opts or {}
   local entries = M.get_save_files()
   local idx_from_list = M.get_index_by_file(file)

   M.pending_future_prune = {}
   if idx_from_list and idx_from_list > 1 then
      for i = 1, idx_from_list - 1 do
         local e = entries[i]
         if e and e[E.ENTRY_FILE] then
            M.pending_future_prune[#M.pending_future_prune+1] = e[E.ENTRY_FILE]
         end
      end
   end

   M.current_index = M.pending_index or idx_from_list or 1
   M.pending_index = nil
   if REWINDER then REWINDER.saves_open = false end

   if not M.copy_save_to_main(file) then
      M.debug_log("error", "Failed to copy save to save.jkr")
      return false
   end

   local run_data = M.load_save_file(file)
   if not run_data then
      M.debug_log("error", "Failed to load save file")
      return false
   end

   G.SAVED_GAME = run_data
   G.SETTINGS = G.SETTINGS or {}
   G.SETTINGS.current_setup = "Continue"
   run_data._file = file
   G.SAVED_GAME._file = file
   M._set_cache_current_file(file)

   if opts.no_wipe and G.delete_run and G.start_run then
      G:delete_run()
      G:start_run({ savetext = G.SAVED_GAME })
   elseif G.FUNCS and G.FUNCS.start_run then
      G.FUNCS.start_run(nil, { savetext = G.SAVED_GAME })
   elseif G.start_run then
      G:start_run({ savetext = G.SAVED_GAME })
   else
      M.debug_log("error", "start_run not found!")
   end
   return true
end

function M.load_and_start_from_file(file, opts)
   opts = opts or {}
   local mark_restore = not opts.skip_restore_identical
   local reason = mark_restore and "restore" or "step"
   
   M._loaded_mark_applied = nil
   M._loaded_meta = nil
   M._pending_skip_reason = reason
   M._restore_active = (reason == "restore")
   M._last_loaded_file = file
   M.skip_next_save = true
   M._set_cache_current_file(file)

   if mark_restore then
      M.debug_log("restore", "Loading " .. M.describe_save({file = file}))
   end
   start_from_file(file, opts)
end

function M.revert_to_previous_save()
   local entries = M.get_save_files()
   if not entries or #entries == 0 then return end

   local current_file = (G and G.SAVED_GAME and G.SAVED_GAME._file) or M._last_loaded_file
   local current_idx = current_file and M.get_index_by_file(current_file) or 0
   if current_idx == 0 and M.current_index then current_idx = M.current_index end

   local target_idx = (current_idx == 0) and 1 or (current_idx + 1)
   if target_idx > #entries then return end

   local target_entry = entries[target_idx]
   if not target_entry or not target_entry[E.ENTRY_FILE] then return end

   M.debug_log("step", "hotkey S -> loading " .. M.describe_save({ entry = target_entry }))
   M.load_and_start_from_file(target_entry[E.ENTRY_FILE], { skip_restore_identical = true, no_wipe = true })
end

function M.load_save_at_index(index)
   local entries = M.get_save_files()
   if not entries or index < 1 or index > #entries then return end
   local entry = entries[index]
   if not entry or not entry[E.ENTRY_FILE] then return end
   M.pending_index = index
   M.load_and_start_from_file(entry[E.ENTRY_FILE])
end

-- --- Logic Hook for Save Skipping ---

function M.mark_loaded_state(run_data, opts)
   opts = opts or {}
   if not M._pending_skip_reason then M._pending_skip_reason = opts.reason end
   M._restore_active = (M._pending_skip_reason == "restore")

   if opts.last_loaded_file and not M._last_loaded_file then
      M._last_loaded_file = opts.last_loaded_file
      _last_loaded_file_ref[1] = opts.last_loaded_file
   end
   
   M._loaded_meta = StateSignature.get_signature(run_data)
   M._loaded_mark_applied = true
   
   local is_shop = StateSignature.is_shop_signature(M._loaded_meta)
   local has_action = M._loaded_meta and M._loaded_meta.is_opening_pack
   
   if is_shop and not has_action then
      M.skip_next_save = false
   elseif opts.set_skip ~= false then
      M.skip_next_save = true
   end
end

function M.consume_skip_on_save(save_table)
   if not M.skip_next_save then return false end
   if save_table and not save_table._file and M._last_loaded_file then
      save_table._file = M._last_loaded_file
   end

   local incoming_sig = M._loaded_meta
   local current_sig = StateSignature.get_signature(save_table)
   local should_skip = StateSignature.signatures_equal(incoming_sig, current_sig)

   -- Shop Pack Open Skip Logic
   if not should_skip and incoming_sig and StateSignature.is_shop_signature(incoming_sig) and incoming_sig.is_opening_pack then
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

   if save_table and should_skip then save_table.REWINDER_SKIP_SAVE = true end

   if not should_skip then
      M.debug_log("save", "Saving: " .. StateSignature.describe_signature(current_sig))
   end

   M.skip_next_save = false
   M._restore_active = false
   M._pending_skip_reason = nil
   M._loaded_mark_applied = nil
   M._loaded_meta = nil
   return should_skip
end

-- --- Save Creation ---

-- Config filter lookup
local function _should_save_state(state, config)
   local st = G and G.STATES
   if not st or not config then return true end
   local filters = {
      [st.ROUND_EVAL] = "save_on_round_end", [st.HAND_PLAYED] = "save_on_round_end",
      [st.BLIND_SELECT] = "save_on_blind", [st.SELECTING_HAND] = "save_on_selecting_hand",
      [st.SHOP] = "save_on_shop",
   }
   local key = filters[state]
   return not key or config[key] ~= false
end

function M.create_save(run_data)
   if M.consume_skip_on_save(run_data) then return end

   local sig = StateSignature.get_signature(run_data)
   if not sig then return end

   if not _should_save_state(sig.state, REWINDER and REWINDER.config) then return end

   local current_time = love.timer.getTime()
   if DuplicateDetector.should_skip_duplicate(sig, M._last_save_sig, M._last_save_time, current_time, StateSignature) then
      return
   end

   M.get_save_files()
   local dir = M.get_save_dir()

   Pruning.prune_future_saves(dir, M.pending_future_prune, save_cache, EntryConstants)
   _rebuild_file_index()

   local unique_id = math.floor(love.timer.getTime() * 1000)
   local filename = string.format("%d-%d-%d.jkr", sig.ante, sig.round, unique_id)

   -- Detect action type
   local temp_entry = {}
   temp_entry[E.ENTRY_ANTE] = sig.ante
   temp_entry[E.ENTRY_ROUND] = sig.round
   temp_entry[E.ENTRY_DISCARDS_USED] = sig.discards_used
   temp_entry[E.ENTRY_HANDS_PLAYED] = sig.hands_played
   local action_type = ActionDetector.detect_action_type(temp_entry, sig, save_cache, M.get_save_meta, EntryConstants)

   local new_entry = {
      filename, sig.ante, sig.round, unique_id, os.time(),
      sig.state, action_type, sig.is_opening_pack or false, sig.money, sig.signature,
      sig.discards_used, sig.hands_played, false, sig.blind_key,
   }

   local full_path = dir .. "/" .. filename
   if not FileIO.write_save_file(run_data, full_path) then
      M.debug_log("error", "Failed to write save")
      return
   end

   MetaFile.write_meta_file(dir .. "/" .. filename:gsub("%.jkr$", ".meta"), {
      state = sig.state, action_type = action_type,
      is_opening_pack = sig.is_opening_pack or false, money = sig.money,
      signature = sig.signature, discards_used = sig.discards_used,
      hands_played = sig.hands_played, blind_key = sig.blind_key,
   })

   table.insert(save_cache, 1, new_entry)
   run_data._file = filename
   M.current_index = 1
   M._set_cache_current_file(filename)
   M._last_save_sig = sig
   M._last_save_time = love.timer.getTime()

   M.debug_log("save", "Created: " .. StateSignature.describe_signature({
      ante = sig.ante, round = sig.round, state = sig.state,
      action_type = action_type, is_opening_pack = sig.is_opening_pack or false, money = sig.money,
   }))

   Pruning.apply_retention_policy(dir, save_cache, EntryConstants)
   _rebuild_file_index()
end

return M
