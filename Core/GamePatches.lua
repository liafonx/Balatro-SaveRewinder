--- Fast Save Loader - GamePatches.lua
--
-- Contains the overrides for Game:start_run and Game:write_save_file.
-- These functions are injected into the game via lovely.toml.
if not LOADER then LOADER = {} end

-- Guard against double-execution (e.g., if this file is patched multiple times)
if LOADER._game_patches_loaded then return end
LOADER._game_patches_loaded = true

-- Use centralized deepcopy utility
local Utils = require("Utils")
local deepcopy = Utils.deepcopy

-- Assume LOADER is already defined and populated by Init.lua

-- LOADER.hook_key_hold from Init.lua, now defined here.
function LOADER.hook_key_hold()
   -- Previously used to hook long-press behaviour; kept as a no-op
   -- initializer so existing calls from Game:start_run remain safe.
   if LOADER._key_hold_hooked then return end
   LOADER._key_hold_hooked = true
end

LOADER._start_run = Game.start_run
LOADER._update_shop = Game.update_shop

function Game:start_run(args)
   args = args or {}

   -- 1. Mark the loaded state
   if args and args.savetext and LOADER.mark_loaded_state then
      -- Access SaveManager directly for internal state (scalars are copied by value)
      local BM = LOADER._SaveManager
      
      -- If continuing from system UI, try to find matching save file
      if args.savetext and not args.savetext._file and BM then
         local entries = BM.get_save_files and BM.get_save_files() or {}
         if entries and #entries > 0 then
            -- Try to match by signature
            local current_sig = LOADER.StateSignature and LOADER.StateSignature.get_signature(args.savetext)
            if current_sig then
               for _, entry in ipairs(entries) do
                  -- Compare using signature string for fast comparison
                  if entry[LOADER.ENTRY_SIGNATURE] and current_sig.signature and entry[LOADER.ENTRY_SIGNATURE] == current_sig.signature then
                     args.savetext._file = entry[LOADER.ENTRY_FILE]
                     if BM then
                        -- Find index and update cache flags
                        for i, e in ipairs(entries) do
                           if e[LOADER.ENTRY_FILE] == entry[LOADER.ENTRY_FILE] then
                              BM.current_index = i
                              break
                           end
                        end
                        -- Update cache flags using helper function
                        if BM._set_cache_current_file then
                           BM._set_cache_current_file(entry[LOADER.ENTRY_FILE])
                        end
                     end
                     break
                  end
               end
            end
         end
      end
      
      local need_mark = BM and (not BM._loaded_mark_applied)
      if need_mark then
         local pending_reason = BM and BM._pending_skip_reason or "continue"
         LOADER.mark_loaded_state(args.savetext, {
            reason = pending_reason,
            last_loaded_file = args.savetext._file or "save.jkr",
            set_skip = true,
         })
      end
   end

   -- 2. Suppress noisy "Card area 'shop_*' not instantiated" logs on shop restores.
   -- In vanilla `Game:start_run`, missing areas are moved to `G.load_shop_*` and later
   -- consumed in `Game:update_shop`, but it prints an error-level log while doing so.
   -- We pre-stash these areas into `G.load_*` and remove them from `cardAreas` so the
   -- vanilla loader doesn't emit the warning.
   if args.savetext and args.savetext.cardAreas and G then
      local cardAreas = args.savetext.cardAreas
      local function stash_if_missing(area_key)
         if not cardAreas[area_key] then return end
         if G[area_key] then return end
         G["load_" .. area_key] = cardAreas[area_key]
         cardAreas[area_key] = nil
      end

      stash_if_missing("shop_jokers")
      stash_if_missing("shop_booster")
      stash_if_missing("shop_vouchers")
   end

   -- 3. Reset Loader State for new run
   LOADER.saves_open = false
   LOADER._save_counter = 0
   LOADER._debug_alert = nil

   if not args or not args.savetext then
      -- Brand new run - reset SaveManager internal state directly
      local BM = LOADER._SaveManager
      if BM then
         BM._pending_skip_reason = nil
         BM._loaded_mark_applied = nil
         BM._loaded_meta = nil
         BM.current_index = nil
         BM._restore_active = nil
         BM._last_loaded_file = nil
         if LOADER.debug_log then
            LOADER.debug_log("cache", "Reset _last_loaded_file (new run)")
         end
         BM.skip_next_save = false
         BM.pending_future_prune = {}
         BM.skipping_pack_open = nil
         BM._last_save_sig = nil  -- Reset duplicate detection
         BM._last_save_time = nil
      end
      
      -- Prune all saves (new run destroys future of previous run)
      if LOADER.clear_all_saves then
          -- Defer the cleanup to the next frame to avoid recursive crashes
          -- caused by other mods hooking filesystem operations. This breaks the
          -- synchronous call chain (start_run -> clear -> getInfo -> hook -> start_run).
          if G and G.E_MANAGER and Event then
              G.E_MANAGER:add_event(Event({
                  trigger = 'after',
                  delay = 0,
                  func = function()
                      LOADER.clear_all_saves()
                      return true
                  end
              }))
          else
              -- Fallback for safety, though G.E_MANAGER should exist here.
              LOADER.clear_all_saves()
          end
      end
   else
      -- Preserve _last_loaded_file if savetext has _file set
      -- This ensures highlight works after restore
      local BM = LOADER._SaveManager
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
            if LOADER.debug_log then
               LOADER.debug_log("cache", string.format("preserving _last_loaded_file=%s", BM._last_loaded_file))
            end
         end
      end
   end

   LOADER._start_run(self, args)

   -- Call the LOADER.hook_key_hold defined in this file.
   LOADER.hook_key_hold()
end

-- The Game:write_save_file patch is no longer needed with the new save_run hook.
-- The original function will be called automatically.
-- You can remove the LOADER._Game_write_save_file and the function override.
 
-- This function is called via a regex patch in lovely.toml,
-- injecting it directly into the game's save_run function.
function LOADER.defer_save_creation()
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
      else
         -- Fallback for safety, though this path is unlikely and might still crash.
         require("SaveManager").create_save(run_data_copy)
      end
   end
end
