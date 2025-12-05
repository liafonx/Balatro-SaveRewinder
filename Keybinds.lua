--- Antihypertensive Save Manager - Keybinds.lua
--
-- Adds an in-game hotkey to open the backups window.

if not ANTIHYP then ANTIHYP = {} end

ANTIHYP._love_keypressed = love.keypressed

local function revert_to_previous_backup()
   if not ANTIHYP or not ANTIHYP.get_backup_files or not ANTIHYP.get_backup_dir then return end
   local entries = ANTIHYP.get_backup_files()
   if not entries or #entries < 2 then
      -- Fall back to the latest in-memory save if available.
      if ANTIHYP.load_latest_live then
         ANTIHYP.load_latest_live()
      end
      return
   end

   local dir = ANTIHYP.get_backup_dir()
   local latest = entries[1]
   local second = entries[2]

   if dir and latest and latest.file then
      pcall(love.filesystem.remove, dir .. "/" .. latest.file)
   end

   if second and second.file and ANTIHYP.load_and_start_from_file then
      ANTIHYP.load_and_start_from_file(second.file)
   end
end

local function load_backup_at_index(idx)
   if not ANTIHYP or not ANTIHYP.get_backup_files then return end
   local entries = ANTIHYP.get_backup_files()
   local entry = entries[idx]
   if not entry then return end
   if ANTIHYP.load_and_start_from_file then
      -- Tell the loader which index we are using so that
      -- subsequent long-presses continue from the right place.
      ANTIHYP.pending_index = idx
      ANTIHYP.load_and_start_from_file(entry.file)
   end
end

function love.keypressed(key, scancode, isrepeat)
   if key == "s" and G and G.FUNCS then
      -- Only handle our shortcuts while a run is active; in other
      -- menus we defer entirely to the original handler so that a
      -- previous press cannot desync our internal `backups_open`
      -- flag from the actual UI.
      if not G.STAGE or G.STAGE ~= G.STAGES.RUN then
         if ANTIHYP._love_keypressed then
            return ANTIHYP._love_keypressed(key, scancode, isrepeat)
         end
         return
      end

      local ctrl_down = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
      if ctrl_down then
         -- Ctrl + S: toggle the backups window
         if isrepeat then return end
         if ANTIHYP.backups_open then
            if G.FUNCS.exit_overlay_menu then
               G.FUNCS.exit_overlay_menu()
            end
            ANTIHYP.backups_open = false
            return
         else
            if G.FUNCS.overlay_menu and G.UIDEF and G.UIDEF.antihypertensive_backups then
               G.FUNCS.overlay_menu({ definition = G.UIDEF.antihypertensive_backups() })
               ANTIHYP.backups_open = true
               return
            end
         end
      else
         -- Plain 'S': delete latest backup and load the previous one
         if not isrepeat then
            revert_to_previous_backup()
            return
         end
      end
   end

   if ANTIHYP._love_keypressed then
      ANTIHYP._love_keypressed(key, scancode, isrepeat)
   end
end
