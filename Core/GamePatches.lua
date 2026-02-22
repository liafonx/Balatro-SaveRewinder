--- Save Rewinder - GamePatches.lua
--
-- Contains the override for Game:start_run and the save_run hook.
-- These functions are injected into the game via lovely.toml.
if not REWINDER then REWINDER = {} end
local Logger = require("Logger")
local log = Logger.create("GamePatches")
-- Guard against double-execution (e.g., if this file is patched multiple times)
if REWINDER._game_patches_loaded then return end
REWINDER._game_patches_loaded = true

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

function REWINDER.should_skip_save_run()
   local snapshot = _build_save_gate_snapshot()
   if not snapshot then return false end

   local last = REWINDER._save_gate_last
   local now = (love and love.timer and love.timer.getTime) and love.timer.getTime() or 0
   local duplicate_window = 0.05
   if _save_gate_equal(last, snapshot) then
      local last_t = REWINDER._save_gate_last_t or 0
      if (now - last_t) < duplicate_window then
         return true
      end
   end

   REWINDER._save_gate_last = snapshot
   REWINDER._save_gate_last_t = now
   return false
end

local function _contains_object_ref_bounded(root, max_nodes)
   if type(root) ~= "table" then return false, 0, false end
   local stack = { root }
   local seen = {}
   local visited = 0
   local truncated = false
   local limit = max_nodes or 12000

   while #stack > 0 do
      local node = stack[#stack]
      stack[#stack] = nil
      if type(node) == "table" and not seen[node] then
         seen[node] = true
         visited = visited + 1
         if visited >= limit then
            truncated = true
            break
         end
         if Object and node.is and type(node.is) == "function" and node:is(Object) then
            return true, visited, truncated
         end
         for _, value in pairs(node) do
            if type(value) == "table" and not seen[value] then
               stack[#stack + 1] = value
            end
         end
      end
   end
   return false, visited, truncated
end

local function _is_channel_serializable(v)
   local t = type(v)
   return t == "nil" or t == "boolean" or t == "number" or t == "string" or t == "table"
end

local function _find_first_nonserializable_path(root, max_nodes)
   if type(root) ~= "table" then return nil, nil, false end

   local seen = {}
   local stack = { { value = root, path = "save_run" } }
   local visited = 0
   local limit = max_nodes or 25000

   while #stack > 0 do
      local node = stack[#stack]
      stack[#stack] = nil
      local value = node.value

      if type(value) == "table" then
         if not seen[value] then
            seen[value] = true
            visited = visited + 1
            if visited >= limit then
               return nil, nil, true
            end
            for k, v in pairs(value) do
               local suffix
               if type(k) == "string" then
                  suffix = "." .. k
               else
                  suffix = "[" .. tostring(k) .. "]"
               end
               if type(v) == "table" then
                  stack[#stack + 1] = { value = v, path = node.path .. suffix }
               elseif not _is_channel_serializable(v) then
                  return node.path .. suffix, type(v), false
               end
            end
         end
      elseif not _is_channel_serializable(value) then
         return node.path, type(value), false
      end
   end

   return nil, nil, false
end

local function _is_back_center_nonserializable_path(path)
   return type(path) == "string" and path:match("^save_run%.BACK%.effect%.center")
end

local function _get_back_center_desc(save_table)
   if type(save_table) ~= "table" then return "key=?, mod=?" end
   local back = save_table.BACK
   local center = back and back.effect and back.effect.center
   if type(center) ~= "table" then return "key=?, mod=?" end
   local key = center.key or "?"
   local mod = center.mod
   local mod_id = (type(mod) == "table" and (mod.id or mod.name or mod.prefix)) or center.mod_id or "?"
   return string.format("key=%s mod=%s", tostring(key), tostring(mod_id))
end

local function _sanitize_back_snapshot_only(save_table)
   if type(save_table) ~= "table" or not recursive_table_cull then return false end
   local back = save_table.BACK
   if type(back) ~= "table" then return false end
   local ok, culled_back = pcall(recursive_table_cull, back)
   if not ok or type(culled_back) ~= "table" then return false end
   save_table.BACK = culled_back
   return true
end

function REWINDER.recover_save_run_payload(save_table, push_err)
   if type(save_table) ~= "table" or not recursive_table_cull then return save_table end
   local bad_path, bad_type = _find_first_nonserializable_path(save_table, 25000)
   if _is_back_center_nonserializable_path(bad_path) and _sanitize_back_snapshot_only(save_table) then
      local next_bad = _find_first_nonserializable_path(save_table, 25000)
      if not next_bad then
         if not REWINDER._back_snapshot_sanitize_noted then
            REWINDER._back_snapshot_sanitize_noted = true
            log("warning", string.format(
               "save_run push recovered by BACK-only sanitize (%s, %s)",
               _get_back_center_desc(save_table), tostring(push_err)
            ))
         end
         if G and G.ARGS and G.ARGS.save_run then G.ARGS.save_run.BACK = save_table.BACK end
         if G and G.culled_table then G.culled_table.BACK = save_table.BACK end
         return save_table
      end
   end
   local ok_recull, reculled = pcall(recursive_table_cull, save_table)
   if ok_recull and type(reculled) == "table" then
      REWINDER._force_save_run_recull = true
      if G and G.ARGS then G.ARGS.save_run = reculled end
      if G then G.culled_table = reculled end
      if not REWINDER._save_run_recull_noted then
         REWINDER._save_run_recull_noted = true
         if bad_path then
            log("warning", string.format(
               "save_run push recovered by recursive recull; root cause: non-serializable %s at %s (%s). Compatibility recull mode enabled.",
               tostring(bad_type), tostring(bad_path), tostring(push_err)
            ))
         else
            log("warning", "save_run push recovered by recursive recull (" .. tostring(push_err) .. "). Compatibility recull mode enabled.")
         end
      end
      return reculled
   end
   return save_table
end

function REWINDER.validate_culled_table_once(culled_table)
   if REWINDER._culled_validate_done then return end
   REWINDER._culled_validate_done = true
   if type(culled_table) ~= "table" then return end

   local bad_path, bad_type, truncated = _find_first_nonserializable_path(culled_table, 25000)
   if bad_path then
      if _is_back_center_nonserializable_path(bad_path) and _sanitize_back_snapshot_only(culled_table) then
         local next_bad = _find_first_nonserializable_path(culled_table, 25000)
         if not next_bad then
            if G and G.ARGS and G.ARGS.save_run then G.ARGS.save_run.BACK = culled_table.BACK end
            if G then G.culled_table = culled_table end
            log("warning", string.format(
               "Selective cull compatibility: sanitized BACK center snapshot (%s)",
               _get_back_center_desc(culled_table)
            ))
            return
         end
      end
      REWINDER._force_save_run_recull = true
      if recursive_table_cull then
         local ok, reculled = pcall(recursive_table_cull, culled_table)
         if ok and type(reculled) == "table" then
            if G and G.ARGS then G.ARGS.save_run = reculled end
            if G then G.culled_table = reculled end
         end
      end
      log("warning", string.format(
         "Selective cull compatibility mode: detected non-serializable %s at %s%s",
         tostring(bad_type), tostring(bad_path), truncated and " (bounded scan reached)" or ""
      ))
      return
   end

   if not Logger.is_verbose() then return end

   local has_object_ref, visited, truncated_obj = _contains_object_ref_bounded(culled_table.cardAreas, 20000)
   if has_object_ref then
      log("warning", "Selective cull check: Object ref found in cardAreas (unexpected)")
      return
   end
   local suffix = truncated_obj and " (bounded scan reached)" or ""
   log("debug", string.format("Selective cull check passed: cardAreas scanned=%d%s", visited, suffix))
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
   REWINDER._save_gate_last = nil
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
   -- vanilla REWINDER doesn't emit the warning.
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
