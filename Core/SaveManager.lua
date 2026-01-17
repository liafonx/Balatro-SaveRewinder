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

-- Internal alias 'E' uses local constants (same indices, avoids table lookup overhead)
local E = {
   ENTRY_FILE = ENTRY_FILE, ENTRY_ANTE = ENTRY_ANTE, ENTRY_ROUND = ENTRY_ROUND, ENTRY_INDEX = ENTRY_INDEX,
   ENTRY_MONEY = ENTRY_MONEY, ENTRY_SIGNATURE = ENTRY_SIGNATURE, ENTRY_DISCARDS_USED = ENTRY_DISCARDS_USED,
   ENTRY_HANDS_PLAYED = ENTRY_HANDS_PLAYED, ENTRY_IS_CURRENT = ENTRY_IS_CURRENT, ENTRY_BLIND_IDX = ENTRY_BLIND_IDX,
   ENTRY_DISPLAY_TYPE = ENTRY_DISPLAY_TYPE, ENTRY_ORDINAL = ENTRY_ORDINAL,
   -- Also expose ante/round without prefix for fallback code
   ANTE = ENTRY_ANTE, ROUND = ENTRY_ROUND,
}

M.PATHS = { SAVES = "SaveRewinder" }
M.debug_log = Logger.create("SaveManager")

-- Blind key <-> index mapping for compact storage (string "bl_small" -> number 1)
-- Index 0 is bl_undiscovered (for choose_blind state)
local BLIND_KEYS = {
   "bl_small", "bl_big", "bl_ox", "bl_hook", "bl_mouth", "bl_fish",
   "bl_club", "bl_manacle", "bl_tooth", "bl_wall", "bl_house", "bl_mark",
   "bl_final_bell", "bl_wheel", "bl_arm", "bl_psychic", "bl_goad", "bl_water",
   "bl_eye", "bl_plant", "bl_needle", "bl_head", "bl_final_leaf", "bl_final_vessel",
   "bl_window", "bl_serpent", "bl_pillar", "bl_flint", "bl_final_acorn", "bl_final_heart",
}

-- Build reverse lookup (key -> index)
local BLIND_KEY_TO_INDEX = {
   bl_undiscovered = 0,  -- Special index for undiscovered blind
}
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
   if not index then return nil end
   if index == 0 then return "bl_undiscovered" end
   return BLIND_KEYS[index]
end

-- Internal state
local save_cache, save_cache_by_file, save_index_by_file, save_cache_by_id = nil, nil, nil, nil

M._last_loaded_file = nil
M._pending_skip_reason = nil
M._loaded_mark_applied = nil
-- Individual fields for direct comparison (faster than signature string)
M._loaded_ante = nil
M._loaded_round = nil
M._loaded_money = nil
M._loaded_discards = nil
M._loaded_hands = nil
M._loaded_display_type = nil  -- Display type of loaded state
M._restore_active = false
M.skip_next_save = false
M.skipping_pack_open = nil
M.pending_future_prune_boundary = nil  -- Timestamp boundary for future prune (O(1) storage)
M.current_index = nil
M.pending_index = nil
M._last_save_sig = nil   -- Signature STRING of last created save (for duplicate detection)
M._last_save_time = nil


-- Ordinal state: in-memory counters per blind for O(1) ordinal computation
-- Reset when entering new blind (last_display_type == "B" or ante changes)
local ordinal_state = {
   ante = nil,              -- Current ante for this state
   blind_key = nil,         -- Current blind_key (nil treated as "unknown")
   last_display_type = nil, -- Last saved display_type (to detect first_shop)
   last_discards_used = 0,  -- For O(1) play/discard detection
   last_hands_played = 0,   -- For O(1) play/discard detection
   last_round = nil,        -- Last saved round (to detect post-boss shop)
   last_saved_round = nil,  -- Round when counters were last reset (for per-round ordinal)
   counters = {             -- Per-type ordinal counters (all display types)
      S = 0,                -- Shop (reroll)
      F = 0,                -- First shop (entering shop) - always ordinal 1
      O = 0,                -- Opening pack
      A = 0,                -- After pack (shop after pack closed)
      R = 0,                -- Start of round - always ordinal 1
      P = 0,                -- Play
      D = 0,                -- Discard
      H = 0,                -- Selecting hand (unknown)
      E = 0,                -- End of round - always ordinal 1
      B = 0,                -- Choose blind
      ["?"] = 0,            -- Unknown/other
   },
   -- Boss tracking: blind_idx of defeated boss (nil = not in post-boss phase)
   defeated_boss_idx = nil,
}

-- Reset ordinal counters for new round, blind, or ante
local function _reset_ordinal_state(ante, blind_key, round)
   ordinal_state.ante = ante
   ordinal_state.blind_key = blind_key
   ordinal_state.last_saved_round = round
   ordinal_state.last_display_type = nil
   ordinal_state.last_discards_used = 0
   ordinal_state.last_hands_played = 0
   ordinal_state.last_round = nil
   ordinal_state.counters = { S = 0, F = 0, O = 0, A = 0, R = 0, P = 0, D = 0, H = 0, E = 0, B = 0, ["?"] = 0 }
   -- Don't reset defeated_boss_idx here - it persists across blind changes within the shop phase
end

-- Export for GamePatches to reset on new run
function M.reset_ordinal_state()
   _reset_ordinal_state(nil, nil, nil)
   ordinal_state.defeated_boss_idx = nil
end

-- ============================================================================
-- Cache Manager
-- ============================================================================

-- Track previous current file for O(1) change detection
-- Use sentinel value to distinguish "never set" from "set to nil"
local _last_current_file = false  -- false = never initialized, nil = explicitly no current

-- Update is_current flag - O(1) via change detection and hash lookup
local function _update_cache_current_flags()
   if not save_cache then return end
   
   local current_file = M._last_loaded_file or (G and G.SAVED_GAME and G.SAVED_GAME._file)
   
   -- Skip if no change (O(1) check)
   -- Note: _last_current_file == false means first run, must process
   if _last_current_file ~= false and current_file == _last_current_file then return end
   
   -- Ensure index is built for O(1) lookup
   if not save_cache_by_file then _rebuild_file_index() end
   
   -- Clear old current (O(1) lookup) - only if not first run
   if _last_current_file and _last_current_file ~= false and save_cache_by_file then
      local old_entry = save_cache_by_file[_last_current_file]
      if old_entry then old_entry[ENTRY_IS_CURRENT] = false end
   end
   
   -- Set new current (O(1) lookup)
   if current_file and save_cache_by_file then
      local new_entry = save_cache_by_file[current_file]
      if new_entry then new_entry[ENTRY_IS_CURRENT] = true end
   end
   
   _last_current_file = current_file
end

-- ============================================================================
-- State Info & Signature Helpers
-- ============================================================================

-- Compute display_type from state_info using ordinal_state context
-- This unifies display_type computation for both comparison and save creation
local function _compute_display_type(state_info)
   if not state_info then return "?" end
   
   local st = G and G.STATES
   if not st then return "?" end
   
   local state = state_info.state
   
   -- For SELECTING_HAND: detect action type from ordinal_state comparison
   local action_type = nil
   if state == st.SELECTING_HAND then
      if state_info.discards_used > ordinal_state.last_discards_used then
         action_type = "discard"
      elseif state_info.hands_played > ordinal_state.last_hands_played then
         action_type = "play"
      end
   end
   
   -- Compute context-dependent flags
   local is_first_shop = false
   local is_after_pack = false
   if state == st.SHOP and not state_info.is_opening_pack then
      is_first_shop = (ordinal_state.last_display_type == "E" or ordinal_state.last_display_type == nil)
      is_after_pack = (ordinal_state.last_display_type == "O")
   end
   
   local is_start_round = (state == st.SELECTING_HAND and 
                           state_info.hands_played == 0 and 
                           state_info.discards_used == 0)
   
   return StateSignature.compute_display_type(state, action_type, state_info.is_opening_pack, is_first_shop, is_start_round, is_after_pack)
end

-- Create signature string from state_info and computed display_type
local function _create_signature(state_info, display_type)
   if not state_info then return nil end
   return StateSignature.encode_signature(
      state_info.ante,
      state_info.round,
      display_type,
      state_info.discards_used,
      state_info.hands_played,
      state_info.money
   )
end

-- ============================================================================
-- Duplicate Detector
-- ============================================================================

-- Checks if a save should be skipped due to being a duplicate
-- Takes signature STRING and display_type for comparison
local function _should_skip_duplicate(signature, display_type, ante, round)
   if not signature then return false end

   -- Prevent duplicate saves if same signature AND created very recently (<0.5s)
   if M._last_save_sig and M._last_save_time and
       M._last_save_sig == signature and
       (love.timer.getTime() - M._last_save_time) < 0.5 then
      return true
   end

   -- Prevent rapid-fire saves at same ante/round (even if money differs)
   -- Exception: Allow opening pack (O) saves even if recent shop save exists
   if M._last_save_sig and M._last_save_time and
       (love.timer.getTime() - M._last_save_time) < 0.3 then
      -- Extract ante:round from last signature for comparison
      local last_ante, last_round = M._last_save_sig:match("^(%d+):(%d+):")
      if last_ante and last_round and 
          tonumber(last_ante) == ante and tonumber(last_round) == round then
         -- Don't skip if this is an opening pack save
         if display_type ~= "O" then
            M.debug_log("filter", "Skipping rapid-fire save at same ante/round")
            return true
         end
      end
   end

   -- Special handling for end of round states (E)
   if display_type == "E" then
      if M._last_save_sig and M._last_save_time and
          (love.timer.getTime() - M._last_save_time) < 1.0 then
         local last_ante, last_round, last_dtype = M._last_save_sig:match("^(%d+):(%d+):(%a+):")
         if last_dtype == "E" and 
             tonumber(last_ante) == ante and tonumber(last_round) == round then
            M.debug_log("filter", "Skipping duplicate end of round save")
            return true
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
      save_cache_by_file, save_index_by_file, save_cache_by_id = nil, nil, nil
      return
   end
   save_cache_by_file, save_index_by_file, save_cache_by_id = {}, {}, {}
   for i, entry in ipairs(save_cache) do
      local file = entry and entry[E.ENTRY_FILE]
      local entry_id = entry and entry[E.ENTRY_INDEX]  -- ENTRY_INDEX is the unique ID
      if file then
         save_cache_by_file[file] = entry
         save_index_by_file[file] = i
      end
      if entry_id then
         save_cache_by_id[entry_id] = { entry = entry, index = i }
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

-- O(1) lookup by _rewinder_id (used for Continue matching)
function M.get_entry_by_id(id)
   if not id then return nil end
   if not save_cache_by_id then _rebuild_file_index() end
   local result = save_cache_by_id and save_cache_by_id[id]
   return result and result.entry, result and result.index
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
   _last_current_file = false  -- Reset sentinel for O(1) change detection
   _rebuild_file_index()
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

   -- Legacy save without .meta file - log warning and use defaults
   M.debug_log("list", "No .meta file for: " .. entry[E.ENTRY_FILE] .. " (legacy save)")
   entry[E.ENTRY_MONEY] = 0
   entry[E.ENTRY_SIGNATURE] = "0:0:?:0:0:0"
   entry[E.ENTRY_DISCARDS_USED] = 0
   entry[E.ENTRY_HANDS_PLAYED] = 0
   entry[E.ENTRY_BLIND_IDX] = 0
   entry[E.ENTRY_DISPLAY_TYPE] = "?"
   entry[E.ENTRY_ORDINAL] = 1
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
   M._last_loaded_file = file
   _update_cache_current_flags()
end

-- Returns sorted list of saves. Use sync=true to load all metadata synchronously.
function M.get_save_files(force_reload)
   if save_cache and not force_reload then
      _update_cache_current_flags()
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

   _update_cache_current_flags()
   return save_cache
end

-- Alias for backward compatibility
M.preload_all_metadata = M.get_save_files

function M.describe_save(opts)
   opts = opts or {}
   local entry = opts.entry or (opts.file and M.get_entry_by_file(opts.file))
   if entry then
      return StateSignature.describe_save(
         entry[E.ENTRY_ANTE],
         entry[E.ENTRY_ROUND],
         entry[E.ENTRY_DISPLAY_TYPE]
      )
   end
   if opts.run_data then
      local state_info = StateSignature.get_state_info(opts.run_data)
      if state_info then
         -- Use basic display_type for run_data (no ordinal context)
         local st = G and G.STATES
         local is_start_round = (st and state_info.state == st.SELECTING_HAND and
                                 state_info.hands_played == 0 and state_info.discards_used == 0)
         local display_type = StateSignature.compute_display_type(state_info.state, nil, state_info.is_opening_pack, false, is_start_round, false)
         return StateSignature.describe_save(state_info.ante, state_info.round, display_type)
      end
   end
   return "Save"
end

-- --- Loading & State Management ---
function M.sync_to_main_save(run_data) return FileIO.sync_to_main_save(run_data) end

function M.copy_save_to_main(file) return FileIO.copy_save_to_main(file, M.get_save_dir()) end

function M.load_save_file(file) return FileIO.load_save_file(file, M.get_save_dir()) end

-- start_from_file is now inlined into load_and_start_from_file for efficiency

function M.load_and_start_from_file(file, opts)
   opts = opts or {}
   local mark_restore = not opts.skip_restore_identical
   local reason = mark_restore and "restore" or "step"

   -- Get entry and ensure cache is loaded
   M.get_save_files()
   local entry = save_cache_by_file and save_cache_by_file[file]
   local idx_from_list = M.get_index_by_file(file)
   
   -- Reset state flags
   M._loaded_mark_applied = true  -- Pre-marked here, no need for Game:start_run to call mark_loaded_state
   M._pending_skip_reason = reason
   M._restore_active = (reason == "restore")
   M._last_loaded_file = file
   M.skip_next_save = true
   M._last_save_sig = nil
   M._last_save_time = nil
   
   -- Pre-store loaded fields for direct comparison (optimization: eliminates mark_loaded_state call)
   if entry then
      M._loaded_ante = entry[E.ENTRY_ANTE]
      M._loaded_round = entry[E.ENTRY_ROUND]
      M._loaded_money = entry[E.ENTRY_MONEY]
      M._loaded_discards = entry[E.ENTRY_DISCARDS_USED]
      M._loaded_hands = entry[E.ENTRY_HANDS_PLAYED]
      M._loaded_display_type = entry[E.ENTRY_DISPLAY_TYPE]
   else
      M._loaded_ante = nil
      M._loaded_round = nil
      M._loaded_money = nil
      M._loaded_discards = nil
      M._loaded_hands = nil
      M._loaded_display_type = nil
   end
   
   -- Calculate future prune boundary using timestamp (O(1) instead of O(N) list building)
   -- Entries with ENTRY_INDEX > this boundary are "future" saves to prune
   if entry and idx_from_list and idx_from_list > 1 then
      M.pending_future_prune_boundary = entry[E.ENTRY_INDEX]
   else
      M.pending_future_prune_boundary = nil
   end
   
   -- Initialize ordinal_state from loaded entry
   if entry then
      local blind_key = M.index_to_blind_key(entry[E.ENTRY_BLIND_IDX]) or "unknown"
      _reset_ordinal_state(entry[E.ENTRY_ANTE], blind_key, entry[E.ENTRY_ROUND])
      
      local dtype = entry[E.ENTRY_DISPLAY_TYPE]
      
      -- For P/D saves: set counters to value BEFORE the action
      -- This ensures next save comparison (hands_played > last) is true
      if dtype == "P" then
         ordinal_state.last_hands_played = (entry[E.ENTRY_HANDS_PLAYED] or 1) - 1
         ordinal_state.last_discards_used = entry[E.ENTRY_DISCARDS_USED] or 0
      elseif dtype == "D" then
         ordinal_state.last_discards_used = (entry[E.ENTRY_DISCARDS_USED] or 1) - 1
         ordinal_state.last_hands_played = entry[E.ENTRY_HANDS_PLAYED] or 0
      else
         ordinal_state.last_discards_used = entry[E.ENTRY_DISCARDS_USED] or 0
         ordinal_state.last_hands_played = entry[E.ENTRY_HANDS_PLAYED] or 0
      end
      ordinal_state.last_display_type = dtype

      if dtype and ordinal_state.counters[dtype] then
         ordinal_state.counters[dtype] = entry[E.ENTRY_ORDINAL] or 1
      end
      
      -- Restore boss tracking for shop saves
      if (dtype == "F" or dtype == "S" or dtype == "O" or dtype == "A") and 
         entry[E.ENTRY_BLIND_IDX] and entry[E.ENTRY_BLIND_IDX] > 2 then
         ordinal_state.defeated_boss_idx = entry[E.ENTRY_BLIND_IDX]
         ordinal_state.last_round = 3
      else
         ordinal_state.defeated_boss_idx = nil
         ordinal_state.last_round = nil
      end
   else
      _reset_ordinal_state(nil, nil, nil)
      ordinal_state.defeated_boss_idx = nil
   end
   
   if mark_restore then
      M.debug_log("restore", "Loading " .. M.describe_save({ file = file }))
   end
   
   -- === Inlined start_from_file logic ===
   M.current_index = M.pending_index or idx_from_list or 1
   M.pending_index = nil
   if REWINDER then REWINDER.saves_open = false end
   M._set_cache_current_file(file)
   
   -- Copy our save file to save.jkr (game's standard save location)
   if not M.copy_save_to_main(file) then
      M.debug_log("error", "Failed to copy save to save.jkr")
      return false
   end
   
   -- Let the game read from save.jkr using its built-in functions
   -- This uses the same code path as normal "Continue" flow
   G.SAVED_GAME = nil  -- Clear stale cache
   local profile = (G.SETTINGS and G.SETTINGS.profile) or "1"
   local save_path = profile .. "/save.jkr"
   local data = get_compressed(save_path)
   if not data then
      M.debug_log("error", "Failed to read save.jkr")
      return false
   end
   local ok, run_data = pcall(STR_UNPACK, data)
   if not ok or not run_data then
      M.debug_log("error", "Failed to unpack save.jkr")
      return false
   end
   
   G.SAVED_GAME = run_data
   G.SETTINGS = G.SETTINGS or {}
   G.SETTINGS.current_setup = "Continue"
   run_data._file = file
   G.SAVED_GAME._file = file
   
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

function M.revert_to_previous_save()
   -- Use existing cache if available (skip full reload)
   local entries = save_cache or M.get_save_files()
   if not entries or #entries == 0 then return end
   
   -- Use current_index as primary source (always updated by load/save operations)
   -- Fallback to index lookup only if current_index is invalid
   local current_idx = M.current_index or 0
   if current_idx == 0 or current_idx > #entries then
      -- Fallback: try to find by file reference
      local current_file = (G and G.SAVED_GAME and G.SAVED_GAME._file) or M._last_loaded_file
      current_idx = current_file and M.get_index_by_file(current_file) or 0
   end
   
   -- Target is index + 1 (older save), or index 1 if unknown
   local target_idx = (current_idx == 0) and 1 or (current_idx + 1)
   if target_idx > #entries then return end  -- Already at oldest
   
   -- Direct entry access (no lookup needed)
   local target_entry = entries[target_idx]
   if not target_entry or not target_entry[E.ENTRY_FILE] then return end
   
   M.debug_log("step", "hotkey S -> loading " .. M.describe_save({ entry = target_entry }))
   M.load_and_start_from_file(target_entry[E.ENTRY_FILE], { skip_restore_identical = true, no_wipe = true })
end

function M.load_save_at_index(index)
   -- Use existing cache if available
   local entries = save_cache or M.get_save_files()
   if not entries or index < 1 or index > #entries then return end
   local entry = entries[index]
   if not entry or not entry[E.ENTRY_FILE] then return end
   M.pending_index = index
   M.load_and_start_from_file(entry[E.ENTRY_FILE])
end

-- --- Logic Hook for Save Skipping ---
-- Called by Game:start_run for Continue path (when not using our UI)
-- If load_and_start_from_file was called, fields are already set
function M.mark_loaded_state(run_data, opts)
   opts = opts or {}
   
   -- If already marked by load_and_start_from_file, just set skip flag
   if M._loaded_mark_applied then
      M.skip_next_save = true
      return
   end
   
   if not M._pending_skip_reason then M._pending_skip_reason = opts.reason end
   M._restore_active = (M._pending_skip_reason == "restore")
   if opts.last_loaded_file and not M._last_loaded_file then
      M._last_loaded_file = opts.last_loaded_file
   end

   -- Get loaded fields from entry or run_data
   local entry = M._last_loaded_file and save_cache_by_file and save_cache_by_file[M._last_loaded_file]
   if entry then
      M._loaded_ante = entry[E.ENTRY_ANTE]
      M._loaded_round = entry[E.ENTRY_ROUND]
      M._loaded_money = entry[E.ENTRY_MONEY]
      M._loaded_discards = entry[E.ENTRY_DISCARDS_USED]
      M._loaded_hands = entry[E.ENTRY_HANDS_PLAYED]
      M._loaded_display_type = entry[E.ENTRY_DISPLAY_TYPE]
   else
      local state_info = StateSignature.get_state_info(run_data)
      local display_type = _compute_display_type(state_info)
      M._loaded_ante = state_info.ante
      M._loaded_round = state_info.round
      M._loaded_money = state_info.money
      M._loaded_discards = state_info.discards_used
      M._loaded_hands = state_info.hands_played
      M._loaded_display_type = display_type
   end
   M._loaded_mark_applied = true
   M.skip_next_save = (opts.set_skip ~= false)
end

function M.consume_skip_on_save(save_table)
   if not M.skip_next_save then return false end
   
   -- Derive _file from _rewinder_id if not set
   if save_table and not save_table._file then
      if save_table._rewinder_id then
         local entry = M.get_entry_by_id(save_table._rewinder_id)
         if entry then
            save_table._file = entry[E.ENTRY_FILE]
         end
      end
      if not save_table._file and M._last_loaded_file then
         save_table._file = M._last_loaded_file
      end
   end
   
   -- Get current state info and compute display_type
   local state_info = StateSignature.get_state_info(save_table)
   local display_type = _compute_display_type(state_info)
   
   -- Direct field comparison (faster than signature string format + compare)
   local should_skip = (
      state_info.ante == M._loaded_ante and
      state_info.round == M._loaded_round and
      state_info.money == M._loaded_money and
      state_info.discards_used == M._loaded_discards and
      state_info.hands_played == M._loaded_hands and
      display_type == M._loaded_display_type
   )
   
   -- Shop Pack Open Skip Logic: if loaded was O, skip if pack is still open
   if not should_skip and M._loaded_display_type == "O" then
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
      M.debug_log("save", "Saving: " .. StateSignature.describe_save(state_info.ante, state_info.round, display_type))
   end
   
   M.skip_next_save = false
   M._restore_active = false
   M._pending_skip_reason = nil
   M._loaded_mark_applied = nil
   M._loaded_ante = nil
   M._loaded_round = nil
   M._loaded_money = nil
   M._loaded_discards = nil
   M._loaded_hands = nil
   M._loaded_display_type = nil
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
   
   -- Get state info and check if we should save this state
   local state_info = StateSignature.get_state_info(run_data)
   if not state_info then return end
   if not _should_save_state(state_info.state, REWINDER and REWINDER.config) then return end
   
   local st = G and G.STATES
   
   -- Check if we need to reset ordinal state
   -- Counters reset on ante or round change, NOT on blind change
   -- This allows B counter to increment when skipping blinds within same round
   local blind_key = state_info.blind_key or "unknown"
   local ante_changed = ordinal_state.ante ~= state_info.ante
   local round_changed = ordinal_state.last_saved_round ~= state_info.round
   
   if ante_changed or round_changed then
      _reset_ordinal_state(state_info.ante, blind_key, state_info.round)
   else
      -- Update blind_key without resetting counters
      ordinal_state.blind_key = blind_key
   end
   
   -- Compute display_type using ordinal_state context
   -- This must be done BEFORE signature creation for unified comparison
   local display_type = _compute_display_type(state_info)
   
   -- Create signature string with display_type included
   -- Format: "ante:round:display_type:discards_used:hands_played:money"
   local signature = _create_signature(state_info, display_type)
   
   -- Check for duplicates using signature STRING
   if _should_skip_duplicate(signature, display_type, state_info.ante, state_info.round) then
      return
   end
   
   M.get_save_files()
   local dir = M.get_save_dir()

   -- Prune future saves using timestamp boundary (O(1) setup vs O(N) list building)
   if M.pending_future_prune_boundary then
      Pruning.prune_future_saves(dir, M.pending_future_prune_boundary, save_cache, E)
      M.pending_future_prune_boundary = nil  -- Clear after use
      _rebuild_file_index()
   end
   -- Use _rewinder_id from run_data if available (injected by defer_save_creation)
   -- This ensures the filename matches the ID stored in save.jkr for exact Continue matching
   local unique_id = run_data._rewinder_id or math.floor(love.timer.getTime() * 1000)
   local filename = string.format("%d-%d-%d.jkr", state_info.ante, state_info.round, unique_id)

   -- Update tracking for next save's action type detection
   ordinal_state.last_discards_used = state_info.discards_used or 0
   ordinal_state.last_hands_played = state_info.hands_played or 0

   -- Compute ordinal using O(1) counter approach
   local ordinal = 1
   if ordinal_state.counters[display_type] then
      ordinal_state.counters[display_type] = ordinal_state.counters[display_type] + 1
      ordinal = ordinal_state.counters[display_type]
   end

   -- Update last_display_type for next save's first_shop/after_pack detection
   ordinal_state.last_display_type = display_type

   -- 12-field entry: file, ante, round, index, money, signature,
   --                 discards_used, hands_played, is_current, blind_idx, display_type, ordinal
   
   -- Get the actual blind_idx for current state
   local actual_blind_idx = M.blind_key_to_index(state_info.blind_key)
   
   -- Track boss defeat: when end of round (E) for a boss round
   -- A round is "boss round" if round==3 OR the blind is a boss (idx > 2)
   if display_type == "E" then
      ordinal_state.last_round = state_info.round
      -- Set defeated_boss_idx if this looks like a boss round
      if state_info.round == 3 or actual_blind_idx > 2 then
         ordinal_state.defeated_boss_idx = (actual_blind_idx > 2) and actual_blind_idx or ordinal_state.defeated_boss_idx
      end
   end
   
   -- Reset boss tracking when entering choose blind screen
   if display_type == "B" then
      ordinal_state.defeated_boss_idx = nil
      ordinal_state.last_round = nil
   end
   
   -- Compute which blind icon to display (determined at save time, not display time)
   -- B=undiscovered(0), shop after boss=defeated boss, else=actual blind
   local is_shop_state = display_type == "F" or display_type == "S" or display_type == "O" or display_type == "A"
   local blind_idx = 0
   if display_type == "B" then
      blind_idx = 0  -- Undiscovered
   elseif is_shop_state and ordinal_state.defeated_boss_idx then
      blind_idx = ordinal_state.defeated_boss_idx  -- Use tracked boss
   elseif is_shop_state and ordinal_state.last_round == 3 and actual_blind_idx > 2 then
      blind_idx = actual_blind_idx  -- Fallback: use current if it's a boss
   else
      blind_idx = actual_blind_idx  -- Default: use current blind
   end
   
   local new_entry = {
      filename, state_info.ante, state_info.round, unique_id,
      state_info.money, signature, state_info.discards_used, state_info.hands_played,
      false, blind_idx, display_type, ordinal,
   }

   local full_path = dir .. "/" .. filename
   if not FileIO.write_save_file(run_data, full_path) then
      M.debug_log("error", "Failed to write save")
      return
   end

   MetaFile.write_meta_file(dir .. "/" .. filename:gsub("%.jkr$", ".meta"), {
      money = state_info.money,
      signature = signature,
      discards_used = state_info.discards_used,
      hands_played = state_info.hands_played,
      blind_idx = blind_idx,
      display_type = display_type,
      ordinal = ordinal,
   })

   table.insert(save_cache, 1, new_entry)
   new_entry[ENTRY_IS_CURRENT] = true  -- Set directly on new entry (before rebuild)
   run_data._file = filename
   M.current_index = 1
   M._last_save_sig = signature
   M._last_save_time = love.timer.getTime()
   M.debug_log("save", "Created: " .. StateSignature.describe_save(state_info.ante, state_info.round, display_type))
   
   Pruning.apply_retention_policy(dir, save_cache, E)
   _rebuild_file_index()
   M._set_cache_current_file(filename)  -- Update tracking variable AFTER index built
end

return M
