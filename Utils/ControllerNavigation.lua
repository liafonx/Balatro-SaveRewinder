--- Save Rewinder - ControllerNavigation.lua
--
-- Controller navigate_focus override for the rewinder saves overlay.
-- Provides directional navigation between save entries, page cycle, and toolbar buttons.

local M = {}

local function is_rewinder_saves_overlay_active()
   -- Solely rely on the presence of the UI element.
   if not (G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID) then return false end
   return not not G.OVERLAY_MENU:get_UIE_by_ID("rewinder_saves")
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
   if node and id and id:match("^rewinder_btn_") and node.config and node.config.can_collide == false then
      return false
   end
   if node then
      self:snap_to({ node = node })
      if self.update_cursor then self:update_cursor() end
      return true
   end
   return false
end

local function snap_to_current_save_entry(self)
   if not (REWINDER and REWINDER.find_current_index and G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID) then return false end
   local full_idx = REWINDER.find_current_index()
   if not full_idx then return false end
   local display_idx = full_idx
   if REWINDER._filter_active then
      display_idx = REWINDER._key_save_reverse_map and REWINDER._key_save_reverse_map[full_idx] or nil
   end
   local node = nil
   if display_idx then
      node = G.OVERLAY_MENU:get_UIE_by_ID("rewinder_save_entry_" .. tostring(display_idx))
   end
   if not node and REWINDER and REWINDER._saves_ui_refs then
      local refs = REWINDER._saves_ui_refs
      local page = refs.cycle_config and refs.cycle_config.current_option or 1
      local per_page = refs.per_page or 8
      local entries = refs.entries or {}
      local first_on_page = (page - 1) * per_page + 1
      if first_on_page <= #entries then
         node = G.OVERLAY_MENU:get_UIE_by_ID("rewinder_save_entry_" .. tostring(first_on_page))
      end
   end
   if not node then
      node = G.OVERLAY_MENU:get_UIE_by_ID("rewinder_page_cycle")
   end
   if not node then return false end
   self:snap_to({ node = node })
   if self.update_cursor then self:update_cursor() end
   return true
end

local function hook_controller_navigate_focus()
   if not Controller or not Controller.navigate_focus or Controller._rewinder_navigate_focus then return end

   Controller._rewinder_navigate_focus = Controller.navigate_focus

   function Controller:navigate_focus(dir, ...)
      if not is_rewinder_saves_overlay_active() then
         return Controller._rewinder_navigate_focus(self, dir, ...)
      end

      local focused = self.focused and self.focused.target
      local id = focused and resolve_id(focused)

      -- If we can't identify the current focus, fall back to default navigation.
      if not id then
          -- CRITICAL: If we are definitely in our overlay but have lost track of ID,
          -- DO NOT fall back to vanilla navigation if it causes crashes.
          -- Instead, try to snap to a safe known element.
          if snap_to_id(self, "rewinder_btn_filter_keys") then return end
          return -- Consumed input to prevent crash
      end

      -- 1) Save entry items: left/right pages, down/up traversal
      local entry_idx = tonumber(id:match("^rewinder_save_entry_(%d+)$"))
      if entry_idx then
         -- Left/Right: Page Navigation
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

         -- Down: Next entry or Page Cycle
         if dir == "D" then
             local next_id = "rewinder_save_entry_" .. tostring(entry_idx + 1)
             if snap_to_id(self, next_id) then return end
             -- If next entry not found (end of list/page), go to page cycle
             snap_to_id(self, "rewinder_page_cycle")
             return
         end

         -- Up: Prev entry
         if dir == "U" then
             local prev_id = "rewinder_save_entry_" .. tostring(entry_idx - 1)
             if snap_to_id(self, prev_id) then return end
             -- If prev entry not found (top of list), stay put or go elsewhere?
             -- Usually top of list stops, or goes to header. We'll stop here to match standard behavior.
             return
         end

         -- Consume any other input to strictly prevent vanilla crash
         return
      end

      -- 2) Paging: left/right page as normal, down goes to filter button, Up goes to last entry
      if id == "rewinder_page_cycle" then
         if dir == "D" then
            snap_to_id(self, "rewinder_btn_filter_keys")
            return
         end
         if dir == "U" then
             -- Find last entry on current page
             if REWINDER and REWINDER._saves_ui_refs then
                local refs = REWINDER._saves_ui_refs
                local page = refs.cycle_config and refs.cycle_config.current_option or 1
                local per_page = refs.per_page or 8
                local entries = refs.entries or {}
                local total = #entries

                local last_on_page = math.min(total, page * per_page)
                local last_id = "rewinder_save_entry_" .. tostring(last_on_page)

                -- Try snapping to last one, if fail try one before (safety)
                if snap_to_id(self, last_id) then return end
             else
                -- Fallback to current save entry when page refs are unavailable
                if snap_to_current_save_entry(self) then return end
             end
             return
         end
         return Controller._rewinder_navigate_focus(self, dir, ...)
      end

      -- 3) Filter/Mark/Rename/Jump: left/right loop, up to paging, down to return.
      if id == "rewinder_btn_filter_keys" or id == "rewinder_btn_mark_keys" or id == "rewinder_btn_toggle_rename" or id == "rewinder_btn_jump_to_current" then
         if dir == "U" then
            snap_to_id(self, "rewinder_page_cycle")
            return
         end
         if dir == "D" then
            snap_to_id(self, "rewinder_back")
            return
         end
         if dir == "L" or dir == "R" then
            local order = { "rewinder_btn_filter_keys", "rewinder_btn_mark_keys", "rewinder_btn_toggle_rename", "rewinder_btn_jump_to_current" }
            local idx = nil
            for i, v in ipairs(order) do
               if v == id then
                  idx = i
                  break
               end
            end
            if idx then
               local delta = (dir == "R") and 1 or -1
               local target_idx = idx
               for _ = 1, #order do
                  target_idx = target_idx + delta
                  if target_idx < 1 then target_idx = #order end
                  if target_idx > #order then target_idx = 1 end
                  if snap_to_id(self, order[target_idx]) then
                     break
                  end
               end
            end
            return
         end
         return Controller._rewinder_navigate_focus(self, dir, ...)
      end

      -- 4) Return: left/right/down have no effect, up to filter button.
      if id == "rewinder_back" then
         if dir == "U" then
            snap_to_id(self, "rewinder_btn_filter_keys")
         end
         return
      end

      return Controller._rewinder_navigate_focus(self, dir, ...)
   end
end

function M.install()
   hook_controller_navigate_focus()
end

return M
