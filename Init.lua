--- Fast Save Loader - Init.lua
--
-- Shared globals and helpers used by the UI and callbacks.

if not LOADER then LOADER = {} end

if not LOADER.PATHS then
   LOADER.PATHS = {
      BACKUPS = "FastSaveLoader",
   }
end

LOADER._debug_alert = nil
LOADER._debug_prefix = "[FastSL]"
LOADER.restore_skip_count = 0

local function debug_log(tag, msg)
   -- Always log timeline stepping and list dumps to make debugging
   -- easier, even if debug_backups is disabled in config.
   local always_log = (tag == "step" or tag == "list")
   if not always_log then
      if not LOADER or not LOADER.config or not LOADER.config.debug_backups then return end
   end

   local prefix = LOADER._debug_prefix or "[FastSL]"
   if tag and tag ~= "" then
      print(prefix .. "[" .. tostring(tag) .. "] " .. tostring(msg))
   else
      print(prefix .. " " .. tostring(msg))
   end
end
LOADER.debug_log = debug_log

-- Some patched versions of the game's globals call a global
-- ensure_shop_areas(run_data) helper before starting a run from
-- saved data. Older Fast Save Loader builds provided a more
-- invasive implementation that toggled rooms; to avoid crashes
-- while also keeping shop restores stable we provide a minimal
-- no-op here. Shop cardAreas are now handled safely inside our
-- Game:start_run wrapper below.
function ensure_shop_areas(run_data)
   if debug_log then
      debug_log("shop", "ensure_shop_areas called (no-op)")
   end
   return run_data
end

LOADER._pending_skip_reason = nil
LOADER._loaded_mark_applied = nil
LOADER._loaded_meta = nil
LOADER._shop_pack_skip_arm = nil
LOADER._shop_pack_skip_window = nil

local function normalize_reason(reason)
   if reason == "restore" or reason == "step" or reason == "continue" then
      return reason
   end
   return nil
end

local function state_signature(run_data)
   if not run_data or type(run_data) ~= "table" then return nil end
   local game = run_data.GAME or {}
   local ante = (game.round_resets and tonumber(game.round_resets.ante)) or tonumber(game.ante) or 0
   local round = tonumber(game.round or 0) or 0
   local state = run_data.STATE
   local label = LOADER.describe_state_label and LOADER.describe_state_label(state) or "state"
   
   -- robust money check
   local money = 0
   if game.dollars then money = tonumber(game.dollars) end
   if game.money then money = tonumber(game.money) end
   if game.current_round and game.current_round.dollars then 
        -- Prefer current_round dollars if available as it is often the active state
        money = tonumber(game.current_round.dollars) 
   end
   
   local sig = {
      ante = ante,
      round = round,
      state = state,
      label = label,
      money = money or 0,
   }

   return sig
end

local function signatures_equal(a, b)
   if not a or not b then return false end
   local keys = {
      "ante", "round", "state", "label", "money",
   }
   for _, k in ipairs(keys) do
      local va, vb = a[k], b[k]
      if (va ~= nil or vb ~= nil) and va ~= vb then
         return false
      end
   end
   return true
end

local function describe_signature(sig)
   if not sig then return "save" end
   local state = sig.label or "state"
   return string.format("Ante %s Round %s (%s)", tostring(sig.ante or "?"), tostring(sig.round or "?"), tostring(state))
end

local function is_shop_signature(sig)
   if not sig then return false end
   local state = sig.state
   if state and G and G.STATES and G.STATES.SHOP and state == G.STATES.SHOP then
      return true
   end
   local label = sig.label or sig.debug_label
   if label and type(label) == "string" then
      return label:lower() == "shop"
   end
   return false
end

local function find_card_in_area(area, target_sort_id)
   if not area or not area.cards or not target_sort_id then return nil end
   for _, card in pairs(area.cards) do
      if tonumber(card and card.sort_id) == tonumber(target_sort_id) then
         return card
      end
   end
   return nil
end

local function find_shop_pack_card(cardAreas, target_sort_id)
   if not cardAreas or not target_sort_id then return nil end
   local preferred = { "shop_booster", "pack_cards" }
   for _, name in ipairs(preferred) do
      local card = find_card_in_area(cardAreas[name], target_sort_id)
      if card then
         return card, name
      end
   end
   return nil
end

function LOADER.mark_loaded_state(run_data, opts)
   opts = opts or {}

   local incoming_reason = normalize_reason(opts.reason)
   if not LOADER._pending_skip_reason then
      LOADER._pending_skip_reason = incoming_reason
   end
   LOADER._restore_active = (LOADER._pending_skip_reason == "restore")

   if opts.last_loaded_file and not LOADER._last_loaded_file then
      LOADER._last_loaded_file = opts.last_loaded_file
   end

   -- Always skip exactly the first post-load save.
   if opts.set_skip ~= false then
      LOADER.skip_next_backup = true
   end
   LOADER._loaded_meta = state_signature(run_data)
   LOADER._loaded_mark_applied = true
   local loaded_sig = LOADER._loaded_meta
   if incoming_reason and (incoming_reason == "restore" or incoming_reason == "step") and is_shop_signature(loaded_sig) then
      LOADER._shop_pack_skip_arm = true
   else
      LOADER._shop_pack_skip_arm = nil
   end
   LOADER._shop_pack_skip_window = nil

   if debug_log then
      local label = (LOADER.describe_backup and LOADER.describe_backup({ file = opts.last_loaded_file or (run_data and run_data._file), run_data = run_data })) or tostring(opts.last_loaded_file or (run_data and run_data._file) or "save")
      local reason = normalize_reason(incoming_reason) or "unknown"
      local tag = (reason == "step") and "step" or "restore"
      debug_log(tag, "Marking loaded state (" .. label .. "); reason=" .. reason .. "; skip_next_backup=" .. tostring(LOADER.skip_next_backup))
   end
end

function LOADER.consume_skip_on_save(save_table)
   if not LOADER or not LOADER.skip_next_backup then return false end

   -- Attach the source filename to the save payload if we know it.
   if save_table and (not save_table._file) and LOADER._last_loaded_file then
      save_table._file = LOADER._last_loaded_file
   end

   local reason = normalize_reason(LOADER._pending_skip_reason) or (LOADER._restore_active and "restore") or "step"
   local incoming_sig = LOADER._loaded_meta
   local current_sig = state_signature(save_table)
   local should_skip = signatures_equal(incoming_sig, current_sig)

   -- Special handling for Shop "Pack Open" auto-save.
   -- This save has different Money (pack cost) so signatures_equal returns false,
   -- but it is effectively the "post-load" state (just with pack animation),
   -- so we want to consume the skip flag and skip this save.
   if not should_skip and incoming_sig and incoming_sig.state == (G and G.STATES and G.STATES.SHOP) then
      if LOADER.skipping_pack_open then
         should_skip = true
         if LOADER.debug_log then
            debug_log("skip", "Forcing skip on Shop Pack Open (flag detected)")
         end
         LOADER.skipping_pack_open = nil
      else
         local ca = save_table.cardAreas
         if ca and ca.pack_cards and ca.pack_cards.cards and next(ca.pack_cards.cards) then
            should_skip = true
            if LOADER.debug_log then
               debug_log("skip", "Forcing skip on Shop Pack Open auto-save (fallback)")
            end
         end
      end
   end

   -- Skip only if the run has not advanced to a different ante/round/state.
   if save_table and should_skip then
      save_table.LOADER_SKIP_BACKUP = true
      if LOADER._shop_pack_skip_arm and is_shop_signature(incoming_sig) then
         LOADER._shop_pack_skip_window = true
         if debug_log then
            debug_log("skip", "Armed booster-pack skip window for restored shop state")
         end
      else
         LOADER._shop_pack_skip_window = nil
      end
      LOADER._shop_pack_skip_arm = nil
   else
      LOADER._shop_pack_skip_window = nil
      LOADER._shop_pack_skip_arm = nil
   end

   local label = nil
   if save_table and LOADER.describe_backup then
      label = LOADER.describe_backup({ file = save_table._file, run_data = save_table })
   end
   label = label or tostring((save_table and save_table._file) or "save")

   if LOADER.debug_log then
      if should_skip then
         if reason == "restore" then
            debug_log("restore", "Skipping first post-restore save; " .. label)
         elseif reason == "continue" then
            debug_log("restore", "Skipping first post-continue save; " .. label)
         elseif reason == "step" then
            debug_log("step", "Skipping backup after step; " .. label)
         else
            debug_log("step", "Skipping backup after load; " .. label)
         end
      else
         local from = describe_signature(incoming_sig)
         local into = describe_signature(current_sig)
         local tag = (reason == "step") and "step" or "restore"
         debug_log(tag, "Post-load state changed; keeping backup (" .. from .. " -> " .. into .. ")")
      end
   end

   LOADER.skip_next_backup = false
   LOADER._restore_active = false
   LOADER._pending_skip_reason = nil
   LOADER._last_loaded_file = nil
   LOADER._loaded_mark_applied = nil
   LOADER._loaded_meta = nil

   return should_skip
end

function LOADER.apply_shop_pack_skip(save_table)
   if not LOADER or not LOADER._shop_pack_skip_window then return false end
   LOADER._shop_pack_skip_window = nil
   LOADER._shop_pack_skip_arm = nil
   if not save_table or type(save_table) ~= "table" then return false end

   local action = save_table.ACTION
   if not action or action.type ~= "use_card" then return false end
   local sort_id = tonumber(action.card)
   if not sort_id then return false end

   local cardAreas = save_table.cardAreas
   local card, area_name = find_shop_pack_card(cardAreas, sort_id)
   if not card then return false end
   local ability = card.ability or {}
   if ability.set ~= "Booster" then return false end

   save_table.LOADER_SKIP_BACKUP = true
   if debug_log then
      local label = card.label or ability.name or area_name or tostring(sort_id)
      debug_log("skip", "Skipping restored shop booster action; card=" .. tostring(label))
   end
   return true
end

function LOADER.describe_state_label(state)
   if not state then return nil end

   -- Primary mapping via G.STATES.
   local st = G and G.STATES
   if st then
      if state == st.SHOP then return "shop" end
      if state == st.BLIND_SELECT then return "choose blind" end
      if state == st.SELECTING_HAND then return "selecting hand" end
      if state == st.ROUND_EVAL or state == st.HAND_PLAYED then return "end of round" end
      if state == st.DRAW_TO_HAND then return "start of round" end
   end
   return nil
end

function LOADER.describe_backup(opts)
   opts = opts or {}
   local file = opts.file
   local entry = opts.entry
   local run_data = opts.run_data
   local meta = opts.meta

   local function resolve_meta()
      if meta then return meta end
      if entry and LOADER.get_backup_meta then
         local ok, res = pcall(LOADER.get_backup_meta, entry)
         if ok then return res end
      end
      if file and LOADER.get_backup_files and LOADER.get_backup_meta then
         local entries = LOADER.get_backup_files()
         for _, e in ipairs(entries) do
            if e.file == file then
               local ok, res = pcall(LOADER.get_backup_meta, e)
               if ok then return res end
               break
            end
         end
      end
      if run_data and type(run_data) == "table" then
         local game = run_data.GAME or {}
         local ante = (game.round_resets and game.round_resets.ante) or game.ante
         local round = game.round
         local label = LOADER.describe_state_label and LOADER.describe_state_label(run_data.STATE) or nil
         return { ante = ante, round = round, label = label, state = run_data.STATE, debug_label = label }
      end
      return nil
   end

   meta = resolve_meta()

   local ante = meta and meta.ante or "?"
   local round = meta and meta.round or "?"
   local state = (meta and meta.debug_label) or (LOADER.describe_state_label and LOADER.describe_state_label(meta and meta.state)) or ""
   if state == "" then state = "state" end

   local label = string.format("Ante %s Round %s%s",
      tostring(ante),
      tostring(round),
      (state ~= "" and (" (" .. state .. ")") or "")
   )

   return label
end

function LOADER.show_backup_debug(ante, round, label)
   if not G or not G.ROOM_ATTACH or not UIBox or not G.UIT then return end
   label = label or ""

   local text = string.format("Backup: Ante %d  Round %d%s", ante or 0, round or 0,
      (label ~= "" and ("  (" .. label .. ")")) or "")

   -- Also log to console for quick visibility when debug_backups is enabled.
   debug_log("backup", text)

   if LOADER._debug_alert and LOADER._debug_alert.remove then
      LOADER._debug_alert:remove()
      LOADER._debug_alert = nil
   end

   local definition = {
      n = G.UIT.ROOT,
      config = { align = "tm", padding = 0.05, colour = G.C.CLEAR },
      nodes = {
         {
            n = G.UIT.R,
            config = {
               align = "cm",
               r = 0.1,
               padding = 0.12,
               minw = 3.8,
               colour = G.C.BLACK,
               shadow = true,
            },
            nodes = {
               {
                  n = G.UIT.T,
                  config = {
                     text = text,
                     scale = 0.32,
                     colour = G.C.UI.TEXT_LIGHT,
                     shadow = true,
                  },
               },
            },
         },
      },
   }

   local box = UIBox({
      definition = definition,
      config = {
         instance_type = "ALERT",
         align = "tm",
         major = G.ROOM_ATTACH,
         offset = { x = 0, y = -0.2 },
         bond = "Weak",
      },
   })

   LOADER._debug_alert = box

   if G.E_MANAGER and Event then
      G.E_MANAGER:add_event(Event({
         trigger = "after",
         delay = 1.6,
         no_delete = true,
         blocking = false,
         timer = "REAL",
         func = function()
            if LOADER._debug_alert == box then
               if box.remove then box:remove() end
               LOADER._debug_alert = nil
            end
            return true
         end,
      }))
   end
end

function LOADER.get_profile()
   if G and G.SETTINGS and G.SETTINGS.profile then
      return tostring(G.SETTINGS.profile)
   end
   return "1"
end

function LOADER.get_backup_dir()
   local profile = LOADER.get_profile()
   local dir = profile .. "/" .. LOADER.PATHS.BACKUPS

   if not love.filesystem.getInfo(profile) then
      love.filesystem.createDirectory(profile)
   end
   if not love.filesystem.getInfo(dir) then
      love.filesystem.createDirectory(dir)
   end

   return dir
end

function LOADER.load_backup(file)
   local dir = LOADER.get_backup_dir()
   local full_path = dir .. "/" .. file

   local data = get_compressed(full_path)
   if data ~= nil then
      return STR_UNPACK(data)
   end

   return nil
end

local function start_from_run_data(run_data)
   if not run_data then return false end

   -- Work out which index this file currently has in the backup list.
   -- This keeps stepping behaviour in sync even if the list changes
   -- or if the save was loaded via the UI or s+number hotkeys. While
   -- we are here, prune any more recent backups so that loading an
   -- older state discards the "future" timeline.
   local idx_from_list = nil
   local entries = nil
   if LOADER.get_backup_files and run_data._file then
      entries = LOADER.get_backup_files()
      for i, e in ipairs(entries) do
         if e.file == run_data._file then
            idx_from_list = i
            break
         end
      end
   end

   LOADER.pending_future_prune = {}
   if entries and idx_from_list and idx_from_list > 1 then
      for i = 1, idx_from_list - 1 do
         local e = entries[i]
         if e and e.file then
            table.insert(LOADER.pending_future_prune, e.file)
         end
      end
   end

   -- Remember which backup index we just loaded (for sequential stepping).
   LOADER.current_index = LOADER.pending_index or idx_from_list or 1
   LOADER.pending_index = nil
   LOADER._deferred_prune = nil

   -- Match QuickLoad's transition style.
   if G then
      G.SETTINGS = G.SETTINGS or {}
      G.SETTINGS.current_setup = "Continue"
   end

   if G and G.OVERLAY_MENU and G.FUNCS and G.FUNCS.exit_overlay_menu then
      G.FUNCS.exit_overlay_menu()
   end
   LOADER.backups_open = false

   G.SAVED_GAME = run_data

   if G and G.FUNCS and G.FUNCS.start_run then
      G.FUNCS.start_run(nil, { savetext = G.SAVED_GAME })
   elseif G and G.start_run then
      G:start_run({
         savetext = G.SAVED_GAME,
      })
   end

   return true
end

function LOADER.load_and_start_from_file(file, opts)
   opts = opts or {}
   local run_data = LOADER.load_backup(file)
   if run_data then
      run_data._file = file
   end
   local mark_restore = not opts.skip_restore_identical
   local reason = mark_restore and "restore" or "step"
   LOADER.restore_skip_count = 0
   -- Reset any previous load markers so the new load can be marked cleanly.
   LOADER._loaded_mark_applied = nil
   LOADER._loaded_meta = nil
   LOADER._pending_skip_reason = reason
   LOADER._restore_active = (reason == "restore")
   LOADER._last_loaded_file = file
   LOADER.skip_next_backup = true

   if mark_restore then
      local label = (LOADER.describe_backup and LOADER.describe_backup({ file = file, run_data = run_data })) or tostring(file)
      debug_log("restore", "Loaded backup " .. label)
   end
   start_from_run_data(run_data)
end

function LOADER.hook_key_hold()
   -- Previously used to hook long-press behaviour; kept as a no-op
   -- initializer so existing calls from Game:start_run remain safe.
   if LOADER._key_hold_hooked then return end
   LOADER._key_hold_hooked = true
end

function LOADER.load_backup_at_index(idx)
   if not LOADER or not LOADER.get_backup_files then return end
   local entries = LOADER.get_backup_files()
   local entry = entries[idx]
   if not entry then return end
   if LOADER.load_and_start_from_file then
      -- Tell the loader which index we are using so that
      -- subsequent long-presses continue from the right place.
      LOADER.pending_index = idx
      LOADER.load_and_start_from_file(entry.file)
   end
end

function LOADER.revert_to_previous_backup()
   if not LOADER or not LOADER.get_backup_files or not LOADER.get_backup_dir then return end

   local entries = LOADER.get_backup_files()
   if not entries or #entries == 0 then
      debug_log("step", "no entries; nothing to revert")
      return
   end

   -- Prefer the tracked index from our last restore/step, so that
   -- pressing 'S' after loading from the UI or a previous step
   -- always uses the same reference point even if filenames or
   -- ordering change slightly.
   local current_idx = tonumber(LOADER.current_index or 0) or 0
   if current_idx < 1 or current_idx > #entries then
      current_idx = 0
   end

   -- If we don't have a valid index, fall back to inferring the
   -- current position from the file name stored on the active
   -- run or the last backup we loaded.
   local current_file = nil
   if current_idx > 0 then
      local e = entries[current_idx]
      current_file = e and e.file or nil
   else
      if G and G.SAVED_GAME and G.SAVED_GAME._file then
         current_file = G.SAVED_GAME._file
      elseif LOADER._last_loaded_file then
         current_file = LOADER._last_loaded_file
      end

      if current_file then
         for i, e in ipairs(entries) do
            if e.file == current_file then
               current_idx = i
               break
            end
         end
      end
   end

   debug_log("step", "entries=" .. tostring(#entries) ..
      " current_idx=" .. tostring(current_idx) ..
      " current_file=" .. tostring(current_file))

   local target_idx
   local delete_from, delete_to

   if current_idx == 0 then
      -- No known current backup: treat the newest entry as "current"
      -- and step back to the one after it.
      if #entries < 2 then
         debug_log("step", "no known current; fewer than 2 entries, nothing to step")
         return
      end
      target_idx = 2
      delete_from, delete_to = 1, 1
      debug_log("step", "no match; treating index 1 as current, deleting 1..1, target_idx=" .. tostring(target_idx))
   else
      -- We are playing from a known backup at `current_idx`. Delete all
      -- newer-or-equal entries so that this becomes the branch point,
      -- then step back to the next older backup after it.
      if current_idx >= #entries then
         -- Already at the oldest backup; nothing older to load.
         debug_log("step", "current_idx at oldest (" .. tostring(current_idx) .. "); nothing older")
         return
      end
      target_idx = current_idx + 1
      delete_from, delete_to = 1, current_idx
      debug_log("step", "match at index " .. tostring(current_idx) .. "; deleting 1.." .. tostring(current_idx) .. " target_idx=" .. tostring(target_idx))
   end

   local target_entry = entries[target_idx]
   if not target_entry or not target_entry.file then
      debug_log("step", "no target entry at index " .. tostring(target_idx))
      return
   end

   -- Physically remove the pruned backups now so that the backup list
   -- matches the new timeline immediately.
   local dir = LOADER.get_backup_dir()
   if delete_from and delete_to then
      for i = delete_from, delete_to do
         local e = entries[i]
         if e and e.file then
            local path = dir .. "/" .. e.file
            if love.filesystem.getInfo(path) then
               love.filesystem.remove(path)
            end
         end
      end
   end

   -- After deletion the target file will become the newest entry, so
   -- align the stepping index with the new top of the list.
   LOADER.pending_index = 1
   local label = (LOADER.describe_backup and LOADER.describe_backup({ entry = target_entry })) or tostring(target_entry.file)
   debug_log("step", "hotkey S -> loading " .. label .. " (deleted newer/equal)")
   if LOADER.load_and_start_from_file then
      LOADER.load_and_start_from_file(target_entry.file, { skip_restore_identical = true })
   end
end

LOADER._start_run = Game.start_run

function Game:start_run(args)
   args = args or {}

   -- Mark the loaded state so the first post-load save is skipped
   -- (restores, timeline steps, and vanilla "Continue" all land here).
   if LOADER and args and args.savetext and LOADER.mark_loaded_state then
      local need_mark = (not LOADER._loaded_mark_applied)
      if need_mark then
         LOADER.mark_loaded_state(args.savetext, {
            reason = LOADER._pending_skip_reason or "continue",
            last_loaded_file = args.savetext._file or "save.jkr",
            set_skip = true,
         })
      elseif debug_log then
         local tag = normalize_reason(LOADER._pending_skip_reason) == "step" and "step" or "restore"
         debug_log(tag, "Loaded state already marked; skipping duplicate mark")
      end
   end

   -- Defer shop card areas to the game's shop builder so they load at
   -- the correct time (avoids instantiation warnings and keeps pack state).
   if args.savetext and args.savetext.cardAreas then
      local cardAreas = args.savetext.cardAreas
      for name, area in pairs(cardAreas) do
         if type(area) == "table" and area.cards and area.config == nil then
            area.config = {}
            if debug_log then
               debug_log("restore", "Inserted missing config for card area " .. tostring(name))
            end
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
      -- Pack selection area while a booster is open; defer and rebuild
      -- after the base game constructs the shop UI.
      if cardAreas.pack_cards then
         self.load_pack_cards = cardAreas.pack_cards
         cardAreas.pack_cards = nil
      end
   end

   -- Any time a run starts, ensure our backups window state is reset
   -- so the first press of 's' in-run always opens it.
   if LOADER then
      LOADER.backups_open = false
      LOADER._save_counter = 0
      LOADER._debug_alert = nil

      if not args or not args.savetext then
         LOADER._pending_skip_reason = nil
         LOADER._loaded_mark_applied = nil
         LOADER._loaded_meta = nil
         -- Only reset the stepping index for brand new runs; when
         -- loading from a backup we keep the index so that repeated
         -- presses of 's' continue stepping back through history.
         LOADER.current_index = nil
         LOADER._restore_active = nil
         LOADER._last_loaded_file = nil
         LOADER.skip_next_backup = false
      end
   end

   -- For a brand new run (no savetext), clear any leftovers from the
   -- previous run *before* the game starts and saves, so that the
   -- very first save of the new run is kept instead of being deleted.
   if (not args or not args.savetext) and LOADER then
      LOADER.pending_future_prune = {}
      local dir = LOADER.get_backup_dir()
      if love.filesystem.getInfo(dir) then
         for _, file in ipairs(love.filesystem.getDirectoryItems(dir)) do
            love.filesystem.remove(dir .. "/" .. file)
         end
      end
   end

   LOADER._start_run(self, args)

   -- Rebuild deferred pack cards (booster open) after the base shop UI exists.
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
      if debug_log then
         debug_log("restore", "Restored pack_cards area with " .. tostring(count) .. " cards (limit " .. tostring(size) .. ")")
      end
   elseif G.load_pack_cards then
      -- Fallback in case base loader captured it.
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
      if debug_log then
         debug_log("restore", "Restored pack_cards area (fallback) with " .. tostring(count) .. " cards (limit " .. tostring(size) .. ")")
      end
   end

   LOADER.hook_key_hold()
end

LOADER._Game_write_save_file = Game.write_save_file
function Game:write_save_file(slot, quick)
    if LOADER then
        local save_table = self.SAVED_GAME
        if save_table and LOADER.consume_skip_on_save then
            LOADER.consume_skip_on_save(save_table)
        elseif save_table and LOADER.skip_next_backup then
            save_table.LOADER_SKIP_BACKUP = true
            debug_log("skip", "Marking save to skip due to pending skip_next_backup")
            LOADER.skip_next_backup = false
            LOADER._pending_skip_reason = nil
        elseif save_table then
            save_table.LOADER_SKIP_BACKUP = nil
            -- This is a new save, not from loading a backup.
            -- Reset the index to ensure 's' loads the most recent previous save.
            LOADER.current_index = nil
            debug_log("save", "Accepting backup; skip_next_backup not set")
        end

        -- Pass the prune list to the save manager thread.
   if LOADER.pending_future_prune and next(LOADER.pending_future_prune) then
       self.SAVED_GAME.LOADER_PRUNE_LIST = LOADER.pending_future_prune
        debug_log("prune", "Passing prune list with " .. tostring(#LOADER.pending_future_prune) .. " entries")
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
    end

    return LOADER._Game_write_save_file(self, slot, quick)
end

G.FUNCS = G.FUNCS or {}
G.FUNCS.fastsl_config_change = function(args)
   args = args or {}
   if args.cycle_config and args.cycle_config.ref_table and args.cycle_config.ref_value then
      args.cycle_config.ref_table[args.cycle_config.ref_value] = args.to_key
   end
end
