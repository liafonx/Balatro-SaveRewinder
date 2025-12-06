--- Fast Save Loader - GamePatches.lua
--
-- Contains the overrides for Game:start_run and Game:write_save_file.
-- These functions are injected into the game via lovely.toml.

-- Assume LOADER is already defined and populated by Init.lua

-- Global Shim for ensure_shop_areas.
-- Some patched versions of the game's globals call a global
-- ensure_shop_areas(run_data) helper before starting a run from
-- saved data. Older Fast Save Loader builds provided a more
-- invasive implementation that toggled rooms; to avoid crashes
-- while also keeping shop restores stable we provide a minimal
-- no-op here. Shop cardAreas are now handled safely inside our
-- Game:start_run wrapper below.
function ensure_shop_areas(run_data)
   if LOADER.debug_log then
      LOADER.debug_log("shop", "ensure_shop_areas called (no-op)")
   end
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

function Game:start_run(args)
   args = args or {}

   -- 1. Mark the loaded state
   if args and args.savetext and LOADER.mark_loaded_state then
      local need_mark = (not LOADER._loaded_mark_applied)
      if need_mark then
         LOADER.mark_loaded_state(args.savetext, {
            reason = LOADER._pending_skip_reason or "continue",
            last_loaded_file = args.savetext._file or "save.jkr",
            set_skip = true,
         })
      end
   end

   -- 2. Fix Shop Card Areas (deferred loading)
   if args.savetext and args.savetext.cardAreas then
      local cardAreas = args.savetext.cardAreas
      -- Ensure config exists
      for name, area in pairs(cardAreas) do
         if type(area) == "table" and area.cards and area.config == nil then
            area.config = {}
         end
      end

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
   -- These variables are directly exposed from BackupManager, no longer internal state of GamePatches.
   LOADER.backups_open = false
   LOADER._save_counter = 0 -- LOADER._save_counter is used by SaveManager.lua, so Init.lua must maintain it
   LOADER._debug_alert = nil

   if not args or not args.savetext then
      -- Brand new run
      LOADER._pending_skip_reason = nil
      LOADER._loaded_mark_applied = nil
      LOADER._loaded_meta = nil
      LOADER.current_index = nil
      LOADER._restore_active = nil
      LOADER._last_loaded_file = nil
      LOADER.skip_next_backup = false
      
      -- Prune all backups (new run destroys future of previous run)
      if LOADER.get_backup_dir then
          LOADER.pending_future_prune = {}
          local dir = LOADER.get_backup_dir()
          if love.filesystem.getInfo(dir) then
             for _, file in ipairs(love.filesystem.getDirectoryItems(dir)) do
                love.filesystem.remove(dir .. "/" .. file)
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

LOADER._Game_write_save_file = Game.write_save_file
function Game:write_save_file(slot, quick)
    local save_table = self.SAVED_GAME
    
    if save_table and LOADER.consume_skip_on_save then
        LOADER.consume_skip_on_save(save_table)
    elseif save_table and LOADER.skip_next_backup then
        save_table.LOADER_SKIP_BACKUP = true
        LOADER.skip_next_backup = false
        LOADER._pending_skip_reason = nil
    elseif save_table then
        save_table.LOADER_SKIP_BACKUP = nil
        LOADER.current_index = nil
    end

    -- Pass the prune list to the save manager thread.
    if LOADER.pending_future_prune and next(LOADER.pending_future_prune) then
        self.SAVED_GAME.LOADER_PRUNE_LIST = LOADER.pending_future_prune
        LOADER.pending_future_prune = {}
    else
        self.SAVED_GAME.LOADER_PRUNE_LIST = nil
    end

    -- Pass config settings to the save manager thread.
    if LOADER.config then
        if LOADER.config.keep_antes then
            local option_text = (G.OPTION_CYCLE_TEXT and G.OPTION_CYCLE_TEXT["fastsl_max_antes_per_run"]) or {}
            self.SAVED_GAME.LOADER_KEEP_ANTES = (LOADER.config.keep_antes < 7 and
                tonumber(option_text[LOADER.config.keep_antes]))
                or nil
        end
    end
    -- Pass the StateSignature API for .meta file generation in the save manager thread.
    self.SAVED_GAME.LOADER_STATE_SIGNATURE_API = {
        get_signature = LOADER.StateSignature.get_signature,
        describe_state_label = LOADER.StateSignature.describe_state_label,
        is_shop_signature = LOADER.StateSignature.is_shop_signature,
        signatures_equal = LOADER.StateSignature.signatures_equal,
        describe_signature = LOADER.StateSignature.describe_signature,
    }

    return LOADER._Game_write_save_file(self, slot, quick)
end