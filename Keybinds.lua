--- Save Rewinder - Keybinds.lua
--
-- Adds an in-game hotkey to open the saves window.

if not REWINDER then REWINDER = {} end

-- NOTE: REWINDER.load_save_at_index is already defined in SaveManager.lua
-- and exported via Init.lua. Do NOT redefine it here.

local function revert_to_previous_save()
   if REWINDER and REWINDER.revert_to_previous_save then
      return REWINDER.revert_to_previous_save()
   end
end

local _last_quick_revert_time = nil
local function can_trigger_quick_revert()
   if not love or not love.timer then return true end
   local now = love.timer.getTime()
   if _last_quick_revert_time and (now - _last_quick_revert_time) < 0.25 then
      return false
   end
   _last_quick_revert_time = now
   return true
end

local function toggle_saves_window()
   if not (G and G.FUNCS) then return end
   if not G.STAGE or G.STAGE ~= G.STAGES.RUN then return end

   if REWINDER.saves_open then
      if G.FUNCS.exit_overlay_menu then
         G.FUNCS.exit_overlay_menu()
      end
      REWINDER.saves_open = false
      return
   end

   if not (G.UIDEF and G.UIDEF.rewinder_saves) then
      if REWINDER.debug_log then
         REWINDER.debug_log("error", "G.UIDEF.rewinder_saves not available yet")
      end
      return
   end
   if G.FUNCS.overlay_menu then
      G.FUNCS.overlay_menu({ definition = G.UIDEF.rewinder_saves() })
      REWINDER.saves_open = true
   end
end

local function hook_controller_leftstick()
   if not Controller or not Controller.button_press or Controller._rewinder_button_press then return end

   Controller._rewinder_button_press = Controller.button_press
   function Controller:button_press(button)
      if button == "leftstick" and G and G.STAGE and G.STAGE == G.STAGES.RUN and not G.SETTINGS.paused then
         if can_trigger_quick_revert() then
            revert_to_previous_save()
         end
      end
      if button == "rightstick" and G and G.STAGE and G.STAGE == G.STAGES.RUN and not G.SETTINGS.paused then
         toggle_saves_window()
      end
      return Controller._rewinder_button_press(self, button)
   end
end

local function hook_controller_navigate_focus()
   if not Controller or not Controller.navigate_focus or Controller._rewinder_navigate_focus then return end

   Controller._rewinder_navigate_focus = Controller.navigate_focus

   local function is_rewinder_saves_overlay_active()
      if not (REWINDER and REWINDER.saves_open) then return false end
      if not (G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID) then return false end
      return not not G.OVERLAY_MENU:get_UIE_by_ID("loader_saves")
   end

   local function resolve_id(node)
      local n = node
      while n do
         if n.config and n.config.id then return n.config.id end
         n = n.parent
      end
      return nil
   end

   local function snap_to_id(self, id)
      if not (G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID) then return false end
      local node = G.OVERLAY_MENU:get_UIE_by_ID(id)
      if node then
         self:snap_to({ node = node })
         if self.update_cursor then self:update_cursor() end
         return true
      end
      return false
   end

   local function snap_to_current_save_entry(self)
      if not (REWINDER and REWINDER.find_current_index and G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID) then return end
      local idx = REWINDER.find_current_index()
      if not idx then return end
      local node = G.OVERLAY_MENU:get_UIE_by_ID("rewinder_save_entry_" .. tostring(idx))
      if node then
         self:snap_to({ node = node })
         if self.update_cursor then self:update_cursor() end
      end
   end

   function Controller:navigate_focus(dir, ...)
      if not is_rewinder_saves_overlay_active() then
         return Controller._rewinder_navigate_focus(self, dir, ...)
      end

      local focused = self.focused and self.focused.target
      local id = focused and resolve_id(focused)

      -- If we can't identify the current focus, fall back to default navigation.
      if not id then
         return Controller._rewinder_navigate_focus(self, dir, ...)
      end

      -- 1) Save entry items: left/right pages.
      if id:match("^rewinder_save_entry_%d+$") then
         if dir == "L" or dir == "R" then
            local cycle = G.OVERLAY_MENU:get_UIE_by_ID("rewinder_page_cycle")
            if cycle and cycle.children then
               local target = (dir == "L") and cycle.children[1] or cycle.children[3]
               if target and target.click then
                  target:click()
                  if G and G.E_MANAGER and Event then
                     G.E_MANAGER:add_event(Event({
                        trigger = "after",
                        delay = 0,
                        func = function()
                           snap_to_current_save_entry(self)
                           return true
                        end,
                     }))
                  else
                     snap_to_current_save_entry(self)
                  end
               end
            end
            return
         end
         return Controller._rewinder_navigate_focus(self, dir, ...)
      end

      -- 2) Paging: left/right page as normal, down goes to Current save.
      if id == "rewinder_page_cycle" then
         if dir == "D" then
            snap_to_id(self, "rewinder_btn_current")
            return
         end
         return Controller._rewinder_navigate_focus(self, dir, ...)
      end

      -- 3) Current/Delete: left/right loop, up to paging, down to return.
      if id == "rewinder_btn_current" or id == "rewinder_btn_delete" then
         if dir == "U" then
            snap_to_id(self, "rewinder_page_cycle")
            return
         end
         if dir == "D" then
            snap_to_id(self, "rewinder_back")
            return
         end
         if dir == "L" or dir == "R" then
            if id == "rewinder_btn_current" then
               snap_to_id(self, "rewinder_btn_delete")
            else
               snap_to_id(self, "rewinder_btn_current")
            end
            return
         end
         return Controller._rewinder_navigate_focus(self, dir, ...)
      end

      -- 4) Return: left/right/down have no effect, up to Current save.
      if id == "rewinder_back" then
         if dir == "U" then
            snap_to_id(self, "rewinder_btn_current")
         end
         return
      end

      return Controller._rewinder_navigate_focus(self, dir, ...)
   end
end

hook_controller_leftstick()
hook_controller_navigate_focus()
if (not Controller or not Controller.button_press) and G and G.E_MANAGER and Event then
   G.E_MANAGER:add_event(Event({
      trigger = "after",
      delay = 0,
      func = function()
         hook_controller_leftstick()
         hook_controller_navigate_focus()
         return true
      end,
   }))
end

REWINDER._love_keypressed = love.keypressed

function love.keypressed(key, scancode, isrepeat)
   if key == "s" and G and G.FUNCS then
      -- Only handle our shortcuts while a run is active; in other
      -- menus we defer entirely to the original handler so that a
      -- previous press cannot desync our internal `saves_open`
      -- flag from the actual UI.
      if not G.STAGE or G.STAGE ~= G.STAGES.RUN then
         if REWINDER._love_keypressed then
            return REWINDER._love_keypressed(key, scancode, isrepeat)
         end
         return
      end

      local ctrl_down = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
      if ctrl_down then
         -- Ctrl + S: toggle the saves window
         if isrepeat then return end
         toggle_saves_window()
         return
      else
         -- Plain 'S': step back to the previous save in the timeline
         if not isrepeat then
            if can_trigger_quick_revert() then
               revert_to_previous_save()
            end
            return
         end
      end
   end

   if REWINDER._love_keypressed then
      REWINDER._love_keypressed(key, scancode, isrepeat)
   end
end
