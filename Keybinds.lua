--- Faster Save Loader - Keybinds.lua
--
-- Adds an in-game hotkey to open the backups window.

if not LOADER then LOADER = {} end

LOADER._love_keypressed = love.keypressed

local function step_debug(msg)
   if LOADER and LOADER.debug_log then
      LOADER.debug_log("step", msg)
   end
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

local function revert_to_previous_backup()
   if LOADER and LOADER.revert_to_previous_backup then
      return LOADER.revert_to_previous_backup()
   end
end

function love.keypressed(key, scancode, isrepeat)
   if key == "s" and G and G.FUNCS then
      -- Only handle our shortcuts while a run is active; in other
      -- menus we defer entirely to the original handler so that a
      -- previous press cannot desync our internal `backups_open`
      -- flag from the actual UI.
      if not G.STAGE or G.STAGE ~= G.STAGES.RUN then
         if LOADER._love_keypressed then
            return LOADER._love_keypressed(key, scancode, isrepeat)
         end
         return
      end

      local ctrl_down = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
      if ctrl_down then
         -- Ctrl + S: toggle the backups window
         if isrepeat then return end
         if LOADER.backups_open then
            if G.FUNCS.exit_overlay_menu then
               G.FUNCS.exit_overlay_menu()
            end
            LOADER.backups_open = false
            return
         else
            if G.FUNCS.overlay_menu and G.UIDEF and G.UIDEF.fast_loader_backups then
               G.FUNCS.overlay_menu({ definition = G.UIDEF.fast_loader_backups() })
               LOADER.backups_open = true
               return
            end
         end
      else
         -- Plain 'S': step back to the previous backup in the timeline
         if not isrepeat then
            revert_to_previous_backup()
            return
         end
      end
   end

   if LOADER._love_keypressed then
      LOADER._love_keypressed(key, scancode, isrepeat)
   end
end
