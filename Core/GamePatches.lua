--- Save Rewinder - GamePatches.lua
--
-- Contains the overrides for Game:start_run and Game:write_save_file.
-- These functions are injected into the game via lovely.toml.
if not REWINDER then REWINDER = {} end
-- Guard against double-execution (e.g., if this file is patched multiple times)
if REWINDER._game_patches_loaded then return end
REWINDER._game_patches_loaded = true
-- Local deepcopy utility for safely copying tables
local function deepcopy(orig)
    if type(orig) ~= 'table' then return orig end
    local copy = {}
    for k, v in pairs(orig) do
        copy[deepcopy(k)] = deepcopy(v)
    end
    return copy
end
-- Assume REWINDER is already defined and populated by Init.lua
-- REWINDER.hook_key_hold from Init.lua, now defined here.
function REWINDER.hook_key_hold()
   -- Previously used to hook long-press behaviour; kept as a no-op
   -- initializer so existing calls from Game:start_run remain safe.
   if REWINDER._key_hold_hooked then return end
   REWINDER._key_hold_hooked = true
end
REWINDER._start_run = Game.start_run
REWINDER._update_shop = Game.update_shop
function Game:start_run(args)
   args = args or {}
   -- 1. Mark the loaded state and use pre-matched save file from init phase
   if args and args.savetext and REWINDER.mark_loaded_state then
      local BM = REWINDER._SaveManager
      -- Use pre-matched file from init phase (if save.jkr was matched during loading)
      -- Only need to set _file on savetext if not already set
      if args.savetext and not args.savetext._file and BM and BM._last_loaded_file then
         args.savetext._file = BM._last_loaded_file
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
   REWINDER._save_counter = 0
   REWINDER._debug_alert = nil
   if not args or not args.savetext then
      -- Brand new run - reset SaveManager internal state directly
      local BM = REWINDER._SaveManager
      if BM then
         BM._pending_skip_reason = nil
         BM._loaded_mark_applied = nil
         BM._loaded_meta = nil
         BM.current_index = nil
         BM._restore_active = nil
         BM._last_loaded_file = nil
         if REWINDER.debug_log then
            REWINDER.debug_log("cache", "Reset _last_loaded_file (new run)")
         end
         BM.skip_next_save = false
         BM.pending_future_prune = {}
         BM.skipping_pack_open = nil
         BM._last_save_sig = nil  -- Reset duplicate detection
         BM._last_save_time = nil
         if BM.reset_ordinal_state then
            BM.reset_ordinal_state()  -- Reset ordinal counters for new run
         end
      end
      
      -- Prune all saves (new run destroys future of previous run)
      if REWINDER.clear_all_saves then
          -- Defer the cleanup to the next frame to avoid recursive crashes
          -- caused by other mods hooking filesystem operations. This breaks the
          -- synchronous call chain (start_run -> clear -> getInfo -> hook -> start_run).
          if G and G.E_MANAGER and Event then
              G.E_MANAGER:add_event(Event({
                  trigger = 'after',
                  delay = 0,
                  func = function()
                      REWINDER.clear_all_saves()
                      return true
                  end
              }))
          else
              -- Fallback for safety, though G.E_MANAGER should exist here.
              REWINDER.clear_all_saves()
          end
      end
   else
      -- Preserve _last_loaded_file if savetext has _file set
      -- This ensures highlight works after restore
      local BM = REWINDER._SaveManager
      if BM and args.savetext then
         if args.savetext._file then
            -- Ensure _last_loaded_file is set from savetext._file
            if BM._last_loaded_file ~= args.savetext._file then
               BM._last_loaded_file = args.savetext._file
               -- Also update cache flags immediately
               if BM._set_cache_current_file then
                  BM._set_cache_current_file(args.savetext._file)
               end
            end
         elseif BM._last_loaded_file then
            -- If savetext exists but _file is not set, preserve existing _last_loaded_file
            -- This handles cases where start_run is called multiple times
            -- Only reset if it's truly a new run (handled above)
            if REWINDER.debug_log then
               REWINDER.debug_log("cache", string.format("preserving _last_loaded_file=%s", BM._last_loaded_file))
            end
         end
      end
   end
   REWINDER._start_run(self, args)
   -- Call the REWINDER.hook_key_hold defined in this file.
   REWINDER.hook_key_hold()
end
-- The Game:write_save_file patch is no longer needed with the new save_run hook.
-- The original function will be called automatically.
-- You can remove the REWINDER._Game_write_save_file and the function override.
 
-- This function is called via a regex patch in lovely.toml,
-- injecting it directly into the game's save_run function.
function REWINDER.defer_save_creation()
   if G.culled_table then
      -- To prevent recursive crashes with other mods that hook filesystem
      -- operations, we defer the save creation to the next frame.
      -- This breaks the synchronous call chain that can lead to a stack overflow.
      
      -- We must create a deep copy of the data, because G.culled_table is ephemeral
      -- and will likely be gone or changed by the next frame.
      local run_data_copy = deepcopy(G.culled_table)
      
      if G and G.E_MANAGER and Event then
         G.E_MANAGER:add_event(Event({
            trigger = 'after',
            delay = 0,
            func = function()
               -- require here since this runs in a new context
               require("SaveManager").create_save(run_data_copy)
               return true
            end
         }))
      end
      -- If event manager isn't available, skip save creation (shouldn't happen during gameplay)
   end
end