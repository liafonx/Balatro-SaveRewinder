--- Save Rewinder - SaveManager.lua
-- Manages save file lifecycle: listing, pruning, loading, and metadata.
-- Includes inlined: EntryConstants, DuplicateDetector, CacheManager

local M = {}
local StateSignature = require("StateSignature")
local MetaFile = require("MetaFile")
local FileIO = require("FileIO")
local Pruning = require("Pruning")
local Logger = require("Logger")


-- ============================================================================
-- Entry Constants - Cache entry array indices (1-based in Lua)
-- Format: {file, ante, round, index, money, signature, discards_used,
--          hands_played, is_current, blind_idx, display_type, ordinal}
-- ============================================================================
-- Single source of truth: name -> index mapping (12 fields)
local ENTRY_KEYS = {
   "FILE", "ANTE", "ROUND", "INDEX",
   "MONEY", "SIGNATURE", "DISCARDS_USED", "HANDS_PLAYED",
   "IS_CURRENT", "BLIND_IDX", "DISPLAY_TYPE", "ORDINAL",
}

-- Local shorthand variables (for internal use)
local ENTRY_FILE, ENTRY_ANTE, ENTRY_ROUND, ENTRY_INDEX = 1, 2, 3, 4
local ENTRY_MONEY, ENTRY_SIGNATURE, ENTRY_DISCARDS_USED, ENTRY_HANDS_PLAYED = 5, 6, 7, 8
local ENTRY_IS_CURRENT, ENTRY_BLIND_IDX, ENTRY_DISPLAY_TYPE, ENTRY_ORDINAL = 9, 10, 11, 12

-- Auto-export constants to module (UI can access via REWINDER.ENTRY_* or SaveManager.ENTRY_*)
for i, key in ipairs(ENTRY_KEYS) do
   M["ENTRY_" .. key] = i
end

-- Internal alias 'E' for SaveManager code
local E = {}
for i, key in ipairs(ENTRY_KEYS) do
   E["ENTRY_" .. key] = i
end

M.PATHS = { SAVES = "SaveRewinder" }
M.debug_log = Logger.create("SaveManager")

-- Blind key <-> index mapping for compact storage (string "bl_small" -> number 1)
-- Index 0 reserved for unknown blinds
local BLIND_KEYS = {
   "bl_small", "bl_big", "bl_ox", "bl_hook", "bl_mouth", "bl_fish",
   "bl_club", "bl_manacle", "bl_tooth", "bl_wall", "bl_house", "bl_mark",
   "bl_final_bell", "bl_wheel", "bl_arm", "bl_psychic", "bl_goad", "bl_water",
   "bl_eye", "bl_plant", "bl_needle", "bl_head", "bl_final_leaf", "bl_final_vessel",
   "bl_window", "bl_serpent", "bl_pillar", "bl_flint", "bl_final_acorn", "bl_final_heart",
}

-- Build reverse lookup (key -> index)
local BLIND_KEY_TO_INDEX = {}
for i, key in ipairs(BLIND_KEYS) do
   BLIND_KEY_TO_INDEX[key] = i
end

-- Convert blind_key to compact index (0 = unknown)
function M.blind_key_to_index(blind_key)
   if not blind_key then return 0 end
   return BLIND_KEY_TO_INDEX[blind_key] or 0
end

-- Convert index back to blind_key (nil if unknown)
function M.index_to_blind_key(index)
   if not index or index == 0 then return nil end
   return BLIND_KEYS[index]
end

-- Internal state
local save_cache, save_cache_by_file, save_index_by_file = nil, nil, nil
local _last_loaded_file_ref = { nil }

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


-- Ordinal state: in-memory counters per blind for O(1) ordinal computation
-- Reset when entering new blind (last_display_type == "B" or ante changes)
local ordinal_state = {
   ante = nil,              -- Current ante for this state
   blind_key = nil,         -- Current blind_key
   last_display_type = nil, -- Last saved display_type (to detect first_shop)
   last_discards_used = 0,  -- For O(1) play/discard detection
   last_hands_played = 0,   -- For O(1) play/discard detection
   counters = {             -- Per-type ordinal counters (only types with show_ordinal=true)
      S = 0,                -- Shop
      O = 0,                -- Opening pack
      P = 0,                -- Play
      D = 0,                -- Discard
      H = 0,                -- Selecting hand (unknown)
      B = 0,                -- Choose blind
      ["?"] = 0,            -- Unknown/other
   }
}

-- Reset ordinal counters for new blind (or new run)
local function _reset_ordinal_state(ante, blind_key)
   ordinal_state.ante = ante
   ordinal_state.blind_key = blind_key
   ordinal_state.last_display_type = nil
   ordinal_state.last_discards_used = 0
   ordinal_state.last_hands_played = 0
   ordinal_state.counters = { S = 0, O = 0, P = 0, D = 0, H = 0, B = 0, ["?"] = 0 }
end

-- Export for GamePatches to reset on new run
function M.reset_ordinal_state()
   _reset_ordinal_state(nil, nil)
end

-- ============================================================================
-- Cache Manager (inlined from CacheManager.lua)
-- ============================================================================

-- Helper to update cache flags for a specific file
local function _set_cache_current_file_impl(file)
   if not save_cache or not file then return end
   local count = 0
   for _, entry in ipairs(save_cache) do
      if entry and entry[ENTRY_FILE] then
         entry[ENTRY_IS_CURRENT] = (entry[ENTRY_FILE] == file)
         if entry[ENTRY_IS_CURRENT] then count = count + 1 end
      end
   end
   _last_loaded_file_ref[1] = file
   M.debug_log("cache", string.format("_set_current: file=%s, marked=%d", file, count))
end
-- Updates the is_current flag in cache entries based on current file
local function _update_cache_current_flags_impl()
   if not save_cache then return end
   local current_file = nil

   -- Priority 1: _last_loaded_file (most reliable)
   if _last_loaded_file_ref[1] then
      current_file = _last_loaded_file_ref[1]
   else
      -- Priority 2: G.SAVED_GAME._file
      if G and G.SAVED_GAME and G.SAVED_GAME._file then
         current_file = G.SAVED_GAME._file
         _last_loaded_file_ref[1] = current_file
      end
   end

   local marked_count = 0
   for _, entry in ipairs(save_cache) do
      if entry and entry[ENTRY_FILE] then
         entry[ENTRY_IS_CURRENT] = (current_file and entry[ENTRY_FILE] == current_file) or false
         if entry[ENTRY_IS_CURRENT] then marked_count = marked_count + 1 end
      end
   end

   M.debug_log("cache", string.format("_update_flags: current=%s, marked=%d", current_file or "nil", marked_count))
end

-- ============================================================================
-- Duplicate Detector (inlined from DuplicateDetector.lua)
-- ============================================================================

-- Checks if a save should be skipped due to being a duplicate
local function _should_skip_duplicate(sig)
   if not sig then return false end

   -- Prevent duplicate saves if same signature AND created very recently (<0.5s)
   if M._last_save_sig and M._last_save_time and
       StateSignature.signatures_equal(M._last_save_sig, sig) and
       (love.timer.getTime() - M._last_save_time) < 0.5 then
      return true
   end

   -- Special handling for end of round states
   local st = G and G.STATES
   if st and (sig.state == st.ROUND_EVAL or sig.state == st.HAND_PLAYED) then
      if M._last_save_sig and M._last_save_time and
          (love.timer.getTime() - M._last_save_time) < 1.0 then
         if M._last_save_sig.state == st.ROUND_EVAL or M._last_save_sig.state == st.HAND_PLAYED then
            if M._last_save_sig.ante == sig.ante and M._last_save_sig.round == sig.round then
               M.debug_log("filter", "Skipping duplicate end of round save")
               return true
            end
         end
      end
   end

   return false
end

-- ============================================================================
-- Index Helpers
-- ============================================================================

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

-- --- Display Type Helper ---
-- Computes display_type code from game state fields
-- Returns: S=shop, F=first_shop, O=opening_pack, R=start_round,
--          P=play, D=discard, H=selecting_hand, E=end_round, B=choose_blind, ?=unknown
-- is_start_round: true if SELECTING_HAND with hands_played=0 and discards_used=0
function M.compute_display_type(state, action_type, is_opening_pack, is_first_shop, is_start_round)
   local st = G and G.STATES
   if not st then return "?" end

   if state == st.SHOP then
      if is_opening_pack then return "O" end
      if is_first_shop then return "F" end
      return "S"
   elseif state == st.SELECTING_HAND then
      if is_start_round then return "R" end  -- Start of round (hands=0, discards=0)
      if action_type == "play" then return "P" end
      if action_type == "discard" then return "D" end
      return "H"
   elseif state == st.ROUND_EVAL or state == st.HAND_PLAYED then
      return "E"
   elseif state == st.BLIND_SELECT then
      return "B"
   end
   return "?"
end

-- --- Save Listing & Metadata ---
function M.get_save_meta(entry)
   if not entry or not entry[E.ENTRY_FILE] then return nil end
   if entry[E.ENTRY_SIGNATURE] then return true end

   local dir = M.get_save_dir()
   local meta_path = dir .. "/" .. entry[E.ENTRY_FILE]:gsub("%.jkr$", ".meta")
   local meta = MetaFile.read_meta_file(meta_path)

   if meta and meta.display_type then
      entry[E.ENTRY_MONEY] = meta.money
      entry[E.ENTRY_SIGNATURE] = meta.signature
      entry[E.ENTRY_DISCARDS_USED] = meta.discards_used
      entry[E.ENTRY_HANDS_PLAYED] = meta.hands_played
      entry[E.ENTRY_BLIND_IDX] = meta.blind_idx
      entry[E.ENTRY_DISPLAY_TYPE] = meta.display_type
      entry[E.ENTRY_ORDINAL] = meta.ordinal
      return true
   end

   -- Fallback: unpack full save file (for saves without valid meta)
   local run_data = FileIO.load_save_file(entry[E.ENTRY_FILE], dir)
   if not run_data then return nil end

   local sig = StateSignature.get_signature(run_data)
   if not sig then return nil end

   -- Compute display_type from save file (detect start_of_round for fallback)
   local st = G and G.STATES
   local is_start_round = (st and sig.state == st.SELECTING_HAND and
                           sig.hands_played == 0 and sig.discards_used == 0)
   local display_type = M.compute_display_type(sig.state, nil, sig.is_opening_pack, false, is_start_round)
   entry[E.ENTRY_MONEY] = sig.money
   entry[E.ENTRY_SIGNATURE] = sig.signature
   entry[E.ENTRY_DISCARDS_USED] = sig.discards_used
   entry[E.ENTRY_HANDS_PLAYED] = sig.hands_played
   entry[E.ENTRY_BLIND_IDX] = M.blind_key_to_index(sig.blind_key)
   entry[E.ENTRY_DISPLAY_TYPE] = display_type
   entry[E.ENTRY_ORDINAL] = 1 -- Default ordinal for fallback entries

   -- Write .meta file for future fast reads
   MetaFile.write_meta_file(meta_path, {
      money = sig.money,
      signature = sig.signature,
      discards_used = sig.discards_used,
      hands_played = sig.hands_played,
      blind_idx = M.blind_key_to_index(sig.blind_key),
      display_type = display_type,
      ordinal = 1,
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
            -- 12-field entry: file, ante, round, index, money, sig, discards, hands, is_current, blind_idx, display_type, ordinal
            entries[#entries + 1] = {
               file, ante, round, index,
               nil, nil, nil, nil, false, nil, nil, nil
            }
         end
      end
   end

   -- Sort by index (unique timestamp) descending (newest first)
   table.sort(entries, function(a, b)
      return a[E.ENTRY_INDEX] > b[E.ENTRY_INDEX]
   end)
   return entries
end


function M._set_cache_current_file(file)
   _last_loaded_file_ref[1] = file
   M._last_loaded_file = file
   _set_cache_current_file_impl(file)
end

function M._update_cache_current_flags()
   _last_loaded_file_ref[1] = M._last_loaded_file
   _update_cache_current_flags_impl()
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

   M._update_cache_current_flags()
   return save_cache
end

function M.preload_all_metadata(force_reload)
   return M.get_save_files(force_reload, true)
end

-- Display type to label mapping for describe_save
local DISPLAY_TYPE_TO_LABEL = {
   S = "shop",
   F = "entering shop",
   O = "opening pack",
   R = "start of round",
   P = "selecting hand (play)",
   D = "selecting hand (discard)",
   H = "selecting hand",
   E = "end of round",
   B = "choose blind",
   ["?"] = "in run",
}

function M.describe_save(opts)
   opts = opts or {}
   local entry = opts.entry or (opts.file and M.get_entry_by_file(opts.file))
   if entry then
      local display_type = entry[E.ENTRY_DISPLAY_TYPE] or "?"
      local label = DISPLAY_TYPE_TO_LABEL[display_type] or "save"
      return string.format("Ante %s Round %s (%s)",
         tostring(entry[E.ENTRY_ANTE] or "?"),
         tostring(entry[E.ENTRY_ROUND] or "?"),
         label)
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
            M.pending_future_prune[#M.pending_future_prune + 1] = e[E.ENTRY_FILE]
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

   -- Initialize ordinal_state from loaded entry's values for correct detection after restore
   -- Since future saves are pruned, we can use entry's ordinal directly
   local entry = save_cache_by_file and save_cache_by_file[file]
   if entry then
      local blind_key = M.index_to_blind_key(entry[E.ENTRY_BLIND_IDX])
      _reset_ordinal_state(entry[E.ENTRY_ANTE], blind_key)
      ordinal_state.last_discards_used = entry[E.ENTRY_DISCARDS_USED] or 0
      ordinal_state.last_hands_played = entry[E.ENTRY_HANDS_PLAYED] or 0
      ordinal_state.last_display_type = entry[E.ENTRY_DISPLAY_TYPE]

      -- Set counter for this display_type from entry's ordinal
      -- (future saves are pruned, so this is the max for this type in this blind)
      local dtype = entry[E.ENTRY_DISPLAY_TYPE]
      if dtype and ordinal_state.counters[dtype] then
         ordinal_state.counters[dtype] = entry[E.ENTRY_ORDINAL] or 1
      end
   else
      _reset_ordinal_state(nil, nil)
   end
   if mark_restore then
      M.debug_log("restore", "Loading " .. M.describe_save({ file = file }))
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
      -- Allow skipping for shop restores (signature check will prevent skipping if money changed)
      M.skip_next_save = true
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
      [st.ROUND_EVAL] = "save_on_round_end",
      [st.HAND_PLAYED] = "save_on_round_end",
      [st.BLIND_SELECT] = "save_on_blind",
      [st.SELECTING_HAND] = "save_on_selecting_hand",
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
   if _should_skip_duplicate(sig) then
      return
   end
   M.get_save_files()
   local dir = M.get_save_dir()

   Pruning.prune_future_saves(dir, M.pending_future_prune, save_cache, E)
   _rebuild_file_index()
   local unique_id = math.floor(love.timer.getTime() * 1000)
   local filename = string.format("%d-%d-%d.jkr", sig.ante, sig.round, unique_id)

   -- Check if we need to reset ordinal state (new blind or new ante)
   local blind_key = sig.blind_key or "unknown"
   if ordinal_state.ante ~= sig.ante or ordinal_state.blind_key ~= blind_key then
      _reset_ordinal_state(sig.ante, blind_key)
   end
   -- O(1) action type detection using ordinal_state
   local action_type = nil
   local st = G and G.STATES
   if st and sig.state == st.SELECTING_HAND then
      if sig.discards_used > ordinal_state.last_discards_used then
         action_type = "discard"
      elseif sig.hands_played > ordinal_state.last_hands_played then
         action_type = "play"
      end
   end
   -- Update tracking for next save
   ordinal_state.last_discards_used = sig.discards_used or 0
   ordinal_state.last_hands_played = sig.hands_played or 0

   -- Compute display_type using ordinal_state for O(1) first_shop detection
   -- First shop: last save was End of round (E) or no saves yet for this blind
   local is_first_shop = false
   if st and sig.state == st.SHOP and not sig.is_opening_pack then
      is_first_shop = (ordinal_state.last_display_type == "E" or ordinal_state.last_display_type == nil)
   end

   -- Start of round: SELECTING_HAND with hands_played=0 and discards_used=0
   local is_start_round = (st and sig.state == st.SELECTING_HAND and
                           sig.hands_played == 0 and sig.discards_used == 0)

   local display_type = M.compute_display_type(sig.state, action_type, sig.is_opening_pack, is_first_shop, is_start_round)

   -- Compute ordinal using O(1) counter approach
   local ordinal = 1
   if ordinal_state.counters[display_type] then
      ordinal_state.counters[display_type] = ordinal_state.counters[display_type] + 1
      ordinal = ordinal_state.counters[display_type]
   end

   -- Update last_display_type for next save's first_shop detection
   ordinal_state.last_display_type = display_type

   -- 12-field entry: file, ante, round, index, money, signature,
   --                 discards_used, hands_played, is_current, blind_idx, display_type, ordinal
   local blind_idx = M.blind_key_to_index(sig.blind_key)
   local new_entry = {
      filename, sig.ante, sig.round, unique_id,
      sig.money, sig.signature, sig.discards_used, sig.hands_played,
      false, blind_idx, display_type, ordinal,
   }

   local full_path = dir .. "/" .. filename
   if not FileIO.write_save_file(run_data, full_path) then
      M.debug_log("error", "Failed to write save")
      return
   end

   MetaFile.write_meta_file(dir .. "/" .. filename:gsub("%.jkr$", ".meta"), {
      money = sig.money,
      signature = sig.signature,
      discards_used = sig.discards_used,
      hands_played = sig.hands_played,
      blind_idx = M.blind_key_to_index(sig.blind_key),
      display_type = display_type,
      ordinal = ordinal,
   })


   table.insert(save_cache, 1, new_entry)
   run_data._file = filename
   M.current_index = 1
   M._set_cache_current_file(filename)
   M._last_save_sig = sig
   M._last_save_time = love.timer.getTime()
   M.debug_log("save", "Created: " .. StateSignature.describe_signature({
      ante = sig.ante,
      round = sig.round,
      state = sig.state,
      action_type = action_type,
      is_opening_pack = sig.is_opening_pack or false,
      money = sig.money,
   }))
   Pruning.apply_retention_policy(dir, save_cache, E)
   _rebuild_file_index()
end

return M
