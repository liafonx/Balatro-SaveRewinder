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
   if not bm then return end
   bm._pending_skip_reason = nil
   bm._loaded_mark_applied = nil
   bm._loaded_signature = nil
   bm._loaded_display_type = nil
   bm.current_index = nil
   bm._restore_active = nil
   bm._last_loaded_file = nil
   bm.skip_next_save = false
   bm.pending_future_prune_boundary = nil
   bm.skipping_pack_open = nil
   bm._last_save_sig = nil
   bm._last_save_time = nil
   if bm.set_overlay_open then
      bm.set_overlay_open(false)
   end
   if bm.reset_ordinal_state then
      bm.reset_ordinal_state()
   end
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
         
         -- If no _file, try to derive from _rewinder_id
         if not file_to_use then
            file_to_use, BM.current_index = derive_file_from_rewinder_id(BM, args.savetext)
         end
         
         -- Update tracking if we have a file
         if file_to_use then
            if BM._last_loaded_file ~= file_to_use then
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
-- The Game:write_save_file patch is no longer needed with the new save_run hook.
-- The original function will be called automatically.
-- You can remove the REWINDER._Game_write_save_file and the function override.
 
-- This function is called via a regex patch in lovely.toml,
-- injecting it directly into the game's save_run function.
function REWINDER.defer_save_creation()
   if G.culled_table then
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
      -- Save immediately using the same table as the vanilla game save.
      local SM = REWINDER and REWINDER._SaveManager
      if SM and SM.create_save then
         SM.create_save(G.culled_table)
      else
         require("SaveManager").create_save(G.culled_table)
      end
   end
end
