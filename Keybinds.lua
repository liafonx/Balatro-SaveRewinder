--- Faster Save Loader - Keybinds.lua
--
-- Adds an in-game hotkey to open the saves window.

if not LOADER then LOADER = {} end

-- NOTE: LOADER.load_save_at_index is already defined in SaveManager.lua
-- and exported via Init.lua. Do NOT redefine it here.

local function revert_to_previous_save()
   if LOADER and LOADER.revert_to_previous_save then
      return LOADER.revert_to_previous_save()
   end
end

LOADER._love_keypressed = love.keypressed

function love.keypressed(key, scancode, isrepeat)
   if key == "s" and G and G.FUNCS then
      -- Only handle our shortcuts while a run is active; in other
      -- menus we defer entirely to the original handler so that a
      -- previous press cannot desync our internal `saves_open`
      -- flag from the actual UI.
      if not G.STAGE or G.STAGE ~= G.STAGES.RUN then
         if LOADER._love_keypressed then
            return LOADER._love_keypressed(key, scancode, isrepeat)
         end
         return
      end

      local ctrl_down = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
      if ctrl_down then
         -- Ctrl + S: toggle the saves window
         if isrepeat then return end
         if LOADER.saves_open then
            if G.FUNCS.exit_overlay_menu then
               G.FUNCS.exit_overlay_menu()
            end
            LOADER.saves_open = false
            return
         else
            -- Ensure UI function exists before trying to open
            if not G.UIDEF then
               if LOADER.debug_log then
                  LOADER.debug_log("error", "G.UIDEF not available yet")
               end
               return
            end
            if not G.UIDEF.fast_loader_saves then
               if LOADER.debug_log then
                  LOADER.debug_log("error", "G.UIDEF.fast_loader_saves not available yet")
               end
               return
            end
            if G.FUNCS.overlay_menu then
               G.FUNCS.overlay_menu({ definition = G.UIDEF.fast_loader_saves() })
               LOADER.saves_open = true
               return
            else
               if LOADER.debug_log then
                  LOADER.debug_log("error", "G.FUNCS.overlay_menu not available")
               end
            end
         end
      else
         -- Plain 'S': step back to the previous save in the timeline
         if not isrepeat then
            revert_to_previous_save()
            return
         end
      end
   end

   if LOADER._love_keypressed then
      LOADER._love_keypressed(key, scancode, isrepeat)
   end
end
