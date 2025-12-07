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

-- Global Shim for ensure_shop_areas.
-- Some patched versions of the game's globals call a global ensure_shop_areas(run_data) helper before starting a run from saved data.
-- This is a no-op since shop areas are handled in Game:start_run wrapper.
function ensure_shop_areas(run_data)
   return run_data
end

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

   -- 2. Fix Shop Card Areas (deferred loading)
   if args.savetext and args.savetext.cardAreas then
      local cardAreas = args.savetext.cardAreas
      local is_opening_pack = args.savetext.ACTION and args.savetext.STATE == (G and G.STATES and G.STATES.SHOP)
      -- Preserve shop areas even when opening a pack so the ACTION card exists and can be replayed.
      -- Always defer their creation to avoid eager instantiation during start_run.
      if cardAreas.shop_jokers then
         self.load_shop_jokers = cardAreas.shop_jokers
         cardAreas.shop_jokers = nil
      end
      if cardAreas.shop_booster then
         self.load_shop_booster = cardAreas.shop_booster
         cardAreas.shop_booster = nil
      end
      if cardAreas.shop_vouchers then
         self.load_shop_vouchers = cardAreas.shop_vouchers
         cardAreas.shop_vouchers = nil
      end

      if cardAreas.pack_cards then
         self.load_pack_cards = cardAreas.pack_cards
         cardAreas.pack_cards = nil
      end
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

   -- 4. Rebuild deferred pack cards
   if self.load_pack_cards then
      local ca = self.load_pack_cards
      local count = #(ca.cards or {})
      local size = (ca.config and ca.config.card_limit) or (self.GAME and self.GAME.pack_size) or count or 3
      size = math.max(size or 3, count or 0)
      
      local w = (size or 3) * G.CARD_W
      local h = 1.05 * G.CARD_H
      local x = G.ROOM.T.x + 9 + G.hand.T.x
      local y = G.hand.T.y
      
      G.pack_cards = CardArea(x, y, w, h, { card_limit = size, type = "consumeable", highlight_limit = 1 })
      G.pack_cards:load(ca)
      self.load_pack_cards = nil
      G.load_pack_cards = nil
   elseif G.load_pack_cards then
       -- Fallback
      local ca = G.load_pack_cards
      local count = #(ca.cards or {})
      local size = (ca.config and ca.config.card_limit) or (self.GAME and self.GAME.pack_size) or count or 3
      size = math.max(size or 3, count or 0)
      local w = (size or 3) * G.CARD_W
      local h = 1.05 * G.CARD_H
      local x = G.ROOM.T.x + 9 + G.hand.T.x
      local y = G.hand.T.y
      G.pack_cards = CardArea(x, y, w, h, { card_limit = size, type = "consumeable", highlight_limit = 1 })
      G.pack_cards:load(ca)
      G.load_pack_cards = nil
   end

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

      -- Add a small delay for shop saves to avoid sharing the same frame as shop UI build.
      local save_delay = 0
      if run_data_copy and run_data_copy.STATE and G and G.STATES and run_data_copy.STATE == G.STATES.SHOP then
         save_delay = 0.12
      end
      
      if G and G.E_MANAGER and Event then
         G.E_MANAGER:add_event(Event({
            trigger = 'after',
            delay = save_delay,
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


