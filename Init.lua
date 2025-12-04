--- Fast Save Loader - Init.lua
--
-- Shared globals and helpers used by the UI and callbacks.

if not ANTIHYP then ANTIHYP = {} end

if not ANTIHYP.PATHS then
   ANTIHYP.PATHS = {
      BACKUPS = "FastSaveLoader",
   }
end

function ANTIHYP.get_profile()
   if G and G.SETTINGS and G.SETTINGS.profile then
      return tostring(G.SETTINGS.profile)
   end
   return "1"
end

function ANTIHYP.get_backup_dir()
   local profile = ANTIHYP.get_profile()
   local dir = profile .. "/" .. ANTIHYP.PATHS.BACKUPS

   if not love.filesystem.getInfo(profile) then
      love.filesystem.createDirectory(profile)
   end
   if not love.filesystem.getInfo(dir) then
      love.filesystem.createDirectory(dir)
   end

   return dir
end

function ANTIHYP.load_backup(file)
   local dir = ANTIHYP.get_backup_dir()
   local full_path = dir .. "/" .. file

   local data = get_compressed(full_path)
   if data ~= nil then
      return STR_UNPACK(data)
   end

   return nil
end

function ANTIHYP.load_and_start_from_file(file)
   local run_data = ANTIHYP.load_backup(file)
   if not run_data then return end

   -- Work out which index this file currently has in the backup list.
   -- This keeps stepping behaviour in sync even if the list changes
   -- or if the save was loaded via the UI or s+number hotkeys. While
   -- we are here, prune any more recent backups so that loading an
   -- older state discards the "future" timeline.
   local idx_from_list = nil
   local entries = nil
   if ANTIHYP.get_backup_files then
      entries = ANTIHYP.get_backup_files()
      for i, e in ipairs(entries) do
         if e.file == file then
            idx_from_list = i
            break
         end
      end
   end

   if entries and idx_from_list and idx_from_list > 1 and ANTIHYP.get_backup_dir then
      local dir = ANTIHYP.get_backup_dir()
      for i = 1, idx_from_list - 1 do
         local e = entries[i]
         if e and e.file ~= file then
            pcall(love.filesystem.remove, dir .. "/" .. e.file)
         end
      end
   end

   -- Remember which backup index we just loaded (for sequential stepping).
   ANTIHYP.current_index = ANTIHYP.pending_index or idx_from_list or 1
   ANTIHYP.pending_index = nil

   -- Mark that the next automatic save should not create a backup.
   ANTIHYP.skip_next_backup = true

   -- Match QuickLoad's transition style.
   if G then
      G.SETTINGS = G.SETTINGS or {}
      G.SETTINGS.current_setup = "Continue"
   end

   if G and G.OVERLAY_MENU and G.FUNCS and G.FUNCS.exit_overlay_menu then
      G.FUNCS.exit_overlay_menu()
   end
   ANTIHYP.backups_open = false

   G.SAVED_GAME = run_data

   if G and G.FUNCS and G.FUNCS.start_run then
      G.FUNCS.start_run(nil, { savetext = G.SAVED_GAME })
   elseif G and G.start_run then
      G:start_run({
         savetext = G.SAVED_GAME,
      })
   end
end

function ANTIHYP.hook_key_hold()
   -- Previously used to hook long-press behaviour; kept as a no-op
   -- initializer so existing calls from Game:start_run remain safe.
   if ANTIHYP._key_hold_hooked then return end
   ANTIHYP._key_hold_hooked = true
end

ANTIHYP._start_run = Game.start_run

function Game:start_run(args)
   -- If we are starting from an existing save text (continue, quick
   -- load, or this mod's own load), skip the very next automatic
   -- backup to avoid duplicating the state we just loaded.
   if args and args.savetext and ANTIHYP then
      ANTIHYP.skip_next_backup = true
   end

   -- Any time a run starts, ensure our backups window state is reset
   -- so the first press of 's' in-run always opens it.
   if ANTIHYP then
      ANTIHYP.backups_open = false
      ANTIHYP._seq_by_key = {}
      ANTIHYP._last_hash_by_trigger = {}
   end

   -- For a brand new run (no savetext), clear any leftovers from the
   -- previous run *before* the game starts and saves, so that the
   -- very first save of the new run is kept instead of being deleted.
   if (not args or not args.savetext) and ANTIHYP then
      local dir = ANTIHYP.get_backup_dir()
      if love.filesystem.getInfo(dir) then
         for _, file in ipairs(love.filesystem.getDirectoryItems(dir)) do
            love.filesystem.remove(dir .. "/" .. file)
         end
      end
   end

   ANTIHYP._start_run(self, args)

   ANTIHYP.hook_key_hold()
end

G.FUNCS = G.FUNCS or {}
G.FUNCS.fastsl_config_change = function(args)
   args = args or {}
   if args.cycle_config and args.cycle_config.ref_table and args.cycle_config.ref_value then
      args.cycle_config.ref_table[args.cycle_config.ref_value] = args.to_key
   end
end
