--- Save Rewinder - GamePatches.lua
--
-- Global overrides injected via lovely.toml:
--   Game:start_run override, Game:update override,
--   save_run hook, defer_save_creation, flush_pending_rewinder,
--   should_skip_save_run, and SerializationGuard bootstrap.
if not REWINDER then REWINDER = {} end
local Logger = require("Logger")
local log = Logger.create("GamePatches")
-- Guard against double-execution (e.g., if this file is patched multiple times)
if REWINDER._game_patches_loaded then return end
REWINDER._game_patches_loaded = true

-- Serialization safety (recover_save_run_payload, validate_culled_table_once, etc.)
require("SerializationGuard")

local function _build_save_gate_snapshot()
   local game = G and G.GAME
   if type(game) ~= "table" then return nil end

   local current_round = game.current_round or {}
   local round_resets = game.round_resets or {}
   local action = G and G.action
   local action_type, action_card = nil, nil
   if type(action) == "table" then
      action_type = action.type
      action_card = action.card or action.idx or action.key
   end

   return {
      state = G and G.STATE,
      ante = round_resets.ante,
      round = game.round,
      blind = game.blind_on_deck,
      hands_played = current_round.hands_played,
      discards_used = current_round.discards_used,
      dollars = game.dollars or game.money or current_round.dollars,
      action_type = action_type,
      action_card = action_card,
   }
end

local function _save_gate_equal(a, b)
   if not a or not b then return false end
   return a.state == b.state
      and a.ante == b.ante
      and a.round == b.round
      and a.blind == b.blind
      and a.hands_played == b.hands_played
      and a.discards_used == b.discards_used
      and a.dollars == b.dollars
      and a.action_type == b.action_type
      and a.action_card == b.action_card
end
REWINDER._save_gate_equal = _save_gate_equal

function REWINDER.should_skip_save_run()
   local snapshot = _build_save_gate_snapshot()
   if not snapshot then
      REWINDER._save_gate_pending = nil
      return false
   end
   if _save_gate_equal(REWINDER._save_gate_saved, snapshot) then
      return true
   end
   REWINDER._save_gate_pending = snapshot
   return false
end

local function derive_file_from_rewinder_id(bm, savetext)
   if not bm or not savetext or savetext._file or not savetext._rewinder_id or not bm.get_entry_by_id then
      return nil, nil
   end
   local entry, idx = bm.get_entry_by_id(savetext._rewinder_id)
   if not entry then return nil, nil end
   local file = entry[bm.ENTRY_FILE]
   savetext._file = file
   return file, idx
end

local function reset_save_manager_for_new_run(bm)
   if bm and bm.reset_for_new_run then bm.reset_for_new_run() end
end

local function clear_all_saves_next_frame()
   if not REWINDER.clear_all_saves then return end
   -- Defer cleanup to avoid recursive call chains through hooked filesystem operations.
   if G and G.E_MANAGER and Event then
      G.E_MANAGER:add_event(Event({
         trigger = 'after',
         delay = 0,
         func = function()
            REWINDER.clear_all_saves()
            return true
         end
      }))
      return
   end
   REWINDER.clear_all_saves()
end
-- Assume REWINDER is already defined and populated by Init.lua
REWINDER._start_run = Game.start_run
function Game:start_run(args)
   args = args or {}
   -- Reset semantic save gate state on every run entry.
   REWINDER._save_gate_saved = nil
   REWINDER._save_gate_pending = nil
   REWINDER._rw_last_shop_flush_t = nil
   REWINDER._rw_last_play_flush_t = nil
   REWINDER._force_save_run_recull = false
   REWINDER._save_run_recull_noted = nil
   REWINDER._back_snapshot_sanitize_noted = nil
   REWINDER._culled_validate_done = nil
   -- 1. Mark the loaded state and derive _file from _rewinder_id if needed
   if args.savetext and REWINDER.mark_loaded_state then
      local BM = REWINDER._SaveManager

      -- Clear stale load markers when this is a plain Continue (no restore/step pending).
      if BM and BM.reset_loaded_state_if_stale then
         BM.reset_loaded_state_if_stale()
      end
      
      -- Derive _file from _rewinder_id if not already set (enables O(1) file lookup)
      if not args.savetext._file then
         derive_file_from_rewinder_id(BM, args.savetext)
         -- Fallback to _last_loaded_file from init phase
         if not args.savetext._file and BM and BM._last_loaded_file then
            args.savetext._file = BM._last_loaded_file
         end
      end

      -- Mark loaded state for skip-duplicate logic
      local need_mark = BM and (not BM._loaded_mark_applied)
      if need_mark then
         local pending_reason = BM and BM._pending_skip_reason or "continue"
         REWINDER.mark_loaded_state(args.savetext, {
            reason = pending_reason,
            last_loaded_file = args.savetext._file or BM._last_loaded_file or "save.jkr",
            set_skip = true,
         })
      end
   end
   -- 2. Suppress noisy "Card area 'shop_*' not instantiated" logs on shop restores.
   -- In vanilla `Game:start_run`, missing areas are moved to `G.load_shop_*` and later
   -- consumed in `Game:update_shop`, but it prints an error-level log while doing so.
   -- We pre-stash shop areas into `G.load_*` and remove them from `cardAreas` so the
   -- vanilla code path doesn't emit the warning.
   -- Using dynamic prefix match for resilience to future game updates.
   if args.savetext and args.savetext.cardAreas and G then
      local cardAreas = args.savetext.cardAreas
      for area_key, area_data in pairs(cardAreas) do
         if area_key:match("^shop_") and not G[area_key] then
            G["load_" .. area_key] = area_data
            cardAreas[area_key] = nil
         end
      end
   end
   -- 3. Reset REWINDER State for new run
   REWINDER.saves_open = false
   REWINDER._debug_alert = nil
   if not args.savetext then
      REWINDER._rw_first_flush_file = nil
      REWINDER._rw_first_flush_time = nil
      REWINDER._rw_flush_verified = false
      REWINDER._rw_flush_fallback = false
      -- Brand new run - reset SaveManager internal state directly
      local BM = REWINDER._SaveManager
      reset_save_manager_for_new_run(BM)
      REWINDER._new_run_dedup_armed = true
      log("debug", "Reset state (new run)")
      
      -- Prune all saves (new run destroys future of previous run)
      clear_all_saves_next_frame()
   else
      -- Continue with existing savetext - derive file from _rewinder_id or use existing
      local BM = REWINDER._SaveManager
      if BM and args.savetext then
         local file_to_use = args.savetext._file
         local resolved_idx = nil
         
         -- If no _file, try to derive from _rewinder_id
         if not file_to_use then
            file_to_use, resolved_idx = derive_file_from_rewinder_id(BM, args.savetext)
            if resolved_idx and not BM.set_current_file then
               BM.current_index = resolved_idx
            end
         end
         
         -- Update tracking if we have a file
         if file_to_use then
            if BM.set_current_file then
               BM.set_current_file(file_to_use, resolved_idx)
            elseif BM._last_loaded_file ~= file_to_use then
               BM._last_loaded_file = file_to_use
               if BM._set_cache_current_file then
                  BM._set_cache_current_file(file_to_use)
               end
            end
         elseif BM._last_loaded_file then
            -- Preserve existing _last_loaded_file
            log("debug", string.format("preserving _last_loaded_file=%s", BM._last_loaded_file))
         end
      end
   end

   REWINDER._start_run(self, args)

end
-- This function is called via a regex patch in lovely.toml,
-- injecting it directly into the game's save_run function.
function REWINDER.defer_save_creation()
   if G.culled_table and not G.culled_table._rewinder_processed then
      G.culled_table._rewinder_processed = true
      -- Generate unique ID BEFORE game writes save.jkr
      -- This ID will be persisted in save.jkr by the game's save logic,
      -- enabling exact O(1) matching when user clicks "Continue"
      local unique_id = nil
      if REWINDER and REWINDER._SaveManager and REWINDER._SaveManager.generate_unique_id then
         unique_id = REWINDER._SaveManager.generate_unique_id()
      else
         unique_id = math.floor(os.time() * 1000)
      end
      G.culled_table._rewinder_id = unique_id
      -- Create a rewinder save entry from the current culled table.
      local SM = REWINDER and REWINDER._SaveManager
      if SM and SM.create_save then
         SM.create_save(G.culled_table)
      else
         require("SaveManager").create_save(G.culled_table)
      end
   end
end

-- Trickle flush: delegates to QueueService (installed on SaveManager).
-- Called from lovely.toml patch after each save_run.
function REWINDER.flush_pending_rewinder()
   local SM = REWINDER and REWINDER._SaveManager
   if SM and SM.flush_trickle_pending then SM.flush_trickle_pending() end
end

-- Periodic queue drain: flush queued saves independent of save_run.
-- Without this, saves enqueued during the last save_run of a state
-- (e.g. final shop reroll) never reach SaveThread until the next
-- state transition or overlay open.
REWINDER._game_update = Game.update
function Game:update(dt)
   REWINDER._game_update(self, dt)
   local SM = REWINDER._SaveManager
   if SM and SM.rewinder_queue_depth and SM.rewinder_queue_depth() > 0
      and REWINDER.flush_pending_rewinder then
      REWINDER.flush_pending_rewinder()
   end
end
