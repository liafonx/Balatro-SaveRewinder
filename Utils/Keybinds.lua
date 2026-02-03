--- Save Rewinder - Keybinds.lua
--
-- Adds an in-game hotkey to open the saves window.

if not REWINDER then REWINDER = {} end
local Logger = require("Logger")
local log = Logger.create("UI")

-- Keybind manager (multi-key combos, configurable)
local Keybinds = {}
REWINDER.keybinds = Keybinds

local DEFAULT_KEYBINDS = {
   step_back = {
      keyboard = { s = true },
      controller = { gp_leftstick = true },
   },
   toggle_saves = {
      keyboard = { ctrl = true, s = true },
      controller = { gp_x = true },
   },
   quick_saveload = {
      keyboard = { l = true },
      controller = { gp_rightstick = true },
   },
}

local function _clone_binding(binding)
   if not binding then return nil end
   local copy = {}
   for key, value in pairs(binding) do
      copy[key] = value
   end
   return copy
end

local function _get_os()
   if love and love.system and love.system.getOS then
      return love.system.getOS()
   end
   return ""
end

local _os_name = _get_os()
local _is_mac = (_os_name == "OS X" or _os_name == "macOS" or _os_name == "iOS")
local _is_windows = (_os_name == "Windows")

local function _normalize_key_name(key)
   if key == "lctrl" or key == "rctrl" then return "ctrl" end
   if key == "lshift" or key == "rshift" then return "shift" end
   if key == "lalt" or key == "ralt" then return "alt" end
   if key == "lgui" or key == "rgui" then return "cmd" end
   return key
end

local function _is_key_down(controller, key)
   if key:sub(1, 3) == "gp_" then
      local btn = key:sub(4)
      return controller.held_buttons and controller.held_buttons[btn]
   end
   if key == "ctrl" then
      return controller.held_keys["lctrl"] or controller.held_keys["rctrl"]
   elseif key == "shift" then
      return controller.held_keys["lshift"] or controller.held_keys["rshift"]
   elseif key == "alt" then
      return controller.held_keys["lalt"] or controller.held_keys["ralt"]
   elseif key == "cmd" or key == "gui" then
      return controller.held_keys["lgui"] or controller.held_keys["rgui"]
   end
   return controller.held_keys[key]
end

local function _normalize_button_name(button)
   return "gp_" .. tostring(button)
end

local function _ensure_config_keybinds()
   local mod_config = SMODS and SMODS.current_mod and SMODS.current_mod.config
   if mod_config then
      REWINDER.config = mod_config
   else
      REWINDER.config = REWINDER.config or {}
   end
   REWINDER.config.keybinds = REWINDER.config.keybinds or {}

   -- Migration check: if any keybind is missing "keyboard" or "controller" keys (old format), reset to defaults
   local needs_reset = false
   for name, val in pairs(REWINDER.config.keybinds) do
      if not val.keyboard and not val.controller then
         needs_reset = true
         break
      end
   end
   if needs_reset then
      log("info", "Old keybind config detected, migrating to defaults")
      for name, def in pairs(DEFAULT_KEYBINDS) do
         REWINDER.config.keybinds[name] = _clone_binding(def)
      end
      return
   end

   -- Specific migration for toggle_saves controller default (v1.5 change)
   -- If current config has toggle_saves.controller as [none] OR gp_y (previous default), update to gp_x.
   local ts_conf = REWINDER.config.keybinds.toggle_saves
   local ts_def = DEFAULT_KEYBINDS.toggle_saves
   
   local should_migrate_ts = false
   if ts_conf and ts_conf.controller then
      if ts_conf.controller["[none]"] then should_migrate_ts = true end
      if ts_conf.controller["gp_y"] then should_migrate_ts = true end
   end
   
   if should_migrate_ts and ts_def and ts_def.controller and ts_def.controller.gp_x then
       log("info", "Migrating toggle_saves controller bind to X")
       ts_conf.controller = _clone_binding(ts_def.controller)
   end

   for name, def in pairs(DEFAULT_KEYBINDS) do
      if not REWINDER.config.keybinds[name] then
         REWINDER.config.keybinds[name] = _clone_binding(def)
      end
   end
end

local function _is_keybind_pressed(controller, binding, check_type)
   if not binding then return false end
   local target_bind = binding[check_type]
   if not target_bind or target_bind["[none]"] then return false end
   if next(target_bind) == nil then return false end

   for key, _ in pairs(target_bind) do
      if not _is_key_down(controller, key) then
         return false
      end
   end
   
   -- Modifiers check only relevant for keyboard
   if check_type == "keyboard" then
      local has_ctrl = target_bind["ctrl"] or target_bind["lctrl"] or target_bind["rctrl"]
      local has_shift = target_bind["shift"] or target_bind["lshift"] or target_bind["rshift"]
      local has_alt = target_bind["alt"] or target_bind["lalt"] or target_bind["ralt"]
      local has_cmd = target_bind["cmd"] or target_bind["gui"] or target_bind["lgui"] or target_bind["rgui"]
      if not has_ctrl and _is_key_down(controller, "ctrl") then return false end
      if not has_shift and _is_key_down(controller, "shift") then return false end
      if not has_alt and _is_key_down(controller, "alt") then return false end
      if not has_cmd and _is_key_down(controller, "cmd") then return false end
   end

   return true
end

local function _sorted_keys(binding)
   local keys = {}
   if not binding then return keys end
   for k, _ in pairs(binding) do
      keys[#keys + 1] = k
   end
   local order = { ctrl = 1, shift = 2, alt = 3, cmd = 4, gui = 4 }
   table.sort(keys, function(a, b)
      local oa = order[a] or 50
      local ob = order[b] or 50
      if oa ~= ob then return oa < ob end
      return tostring(a) < tostring(b)
   end)
   return keys
end

local function _binding_size(binding, check_type)
   if not binding then return 0 end
   local target = binding[check_type]
   if not target or target["[none]"] then return 0 end
   local count = 0
   for _ in pairs(target) do
      count = count + 1
   end
   return count
end

local function _format_key_name(key)
   if key:sub(1, 3) == "gp_" then
      local btn = key:sub(4)
      local map = {
         a = "A",
         b = "B",
         x = "X",
         y = "Y",
         back = "Back",
         start = "Start",
         guide = "Guide",
         leftshoulder = "LB",
         rightshoulder = "RB",
         leftstick = "L3",
         rightstick = "R3",
         dpup = "DPad Up",
         dpdown = "DPad Down",
         dpleft = "DPad Left",
         dpright = "DPad Right",
      }
      return map[btn] or btn
   end
   if key == "ctrl" or key == "lctrl" or key == "rctrl" then return "Ctrl" end
   if key == "shift" or key == "lshift" or key == "rshift" then return "Shift" end
   if key == "alt" or key == "lalt" or key == "ralt" then
      return _is_mac and "Option" or "Alt"
   end
   if key == "cmd" or key == "gui" or key == "lgui" or key == "rgui" then
      if _is_mac then return "Cmd" end
      if _is_windows then return "Win" end
      return "Super"
   end
   if #key == 1 then return string.upper(key) end
   return key
end

function Keybinds.format_binding(binding)
   if not binding then return "[none]" end -- Should not happen with defaults
   
   local function fmt_sub(sub_bind)
      if not sub_bind or sub_bind["[none]"] then return "[none]" end
      local keys = _sorted_keys(sub_bind)
      if #keys == 0 then return "[none]" end
      local parts = {}
      for _, key in ipairs(keys) do
         parts[#parts + 1] = _format_key_name(key)
      end
      return table.concat(parts, "+")
   end
   
   -- Special case: Flat binding (used during recording preview or legacy config)
   if not binding.keyboard and not binding.controller then
      return fmt_sub(binding)
   end
   
   local kb_str = fmt_sub(binding.keyboard)
   local gp_str = fmt_sub(binding.controller)
   
   local kb_str = fmt_sub(binding.keyboard)
   local gp_str = fmt_sub(binding.controller)
   
   -- Context sensitive display
   local mode = Keybinds.last_input_type or "keyboard"
   if mode == "controller" then
      return gp_str
   end
   return kb_str
end

function Keybinds.get_binding(name)
   _ensure_config_keybinds()
   return REWINDER.config.keybinds[name]
end

function Keybinds.set_binding(name, binding)
   if Keybinds.update_binding then
      Keybinds.update_binding(name, binding)
   else
      _ensure_config_keybinds()
      REWINDER.config.keybinds[name] = binding
   end
end

function Keybinds.update_binding(name, new_keys)
   _ensure_config_keybinds()
   local current = REWINDER.config.keybinds[name] or { keyboard = {}, controller = {} }
   -- Ensure structure
   if not current.keyboard then current.keyboard = {} end
   if not current.controller then current.controller = {} end
   
   -- Analyze new_keys to determine type
   local has_controller = false
   local has_keyboard = false
   local is_none = new_keys["[none]"]
   
   local kb_part = {}
   local gp_part = {}
   
   for k, v in pairs(new_keys) do
      if k ~= "[none]" then
         if string.sub(k, 1, 3) == "gp_" then
            has_controller = true
            gp_part[k] = v
         else
            has_keyboard = true
            kb_part[k] = v
         end
      end
   end
   
   if is_none then
      -- Clear the last used input type
      local mode = Keybinds.last_input_type or "keyboard"
      if mode == "controller" then
         current.controller = { ["[none]"] = true }
      else
         current.keyboard = { ["[none]"] = true }
      end
   else
      if has_controller then
         current.controller = gp_part
      end
      if has_keyboard then
         current.keyboard = kb_part
      end
   end
   
   REWINDER.config.keybinds[name] = current
end

function Keybinds.reset_defaults()
   _ensure_config_keybinds()
   -- Deep copy defaults
   for name, def in pairs(DEFAULT_KEYBINDS) do
      local copy = { keyboard = {}, controller = {} }
      if def.keyboard then
          for k, v in pairs(def.keyboard) do copy.keyboard[k] = v end
      end
      if def.controller then
          for k, v in pairs(def.controller) do copy.controller[k] = v end
      end
      REWINDER.config.keybinds[name] = copy
   end
end

Keybinds._actions = {}
Keybinds._activated = {}
Keybinds._recording = nil
Keybinds.last_input_type = "keyboard"

function Keybinds.register(args)
   if type(args) ~= "table" then return end
   if type(args.name) ~= "string" then return end
   if type(args.func) ~= "function" then return end
   Keybinds._actions[args.name] = args.func
end

function Keybinds.record(args)
   if type(args) ~= "table" then return end
   if type(args.name) ~= "string" then return end
   if Keybinds._recording then
      if Keybinds._recording.callback then
         Keybinds._recording.callback(Keybinds._recording.pressed)
      end
      Keybinds._recording = nil
   end
   Keybinds._recording = {
      name = args.name,
      pressed = {},
      callback = args.callback,
      press_callback = args.press_callback,
   }
end

local function _record_key_press(key)
   local rec = Keybinds._recording
   if not rec then return end
   if key == "escape" then
      if rec.callback then rec.callback({ ["[none]"] = true }) end
      Keybinds._recording = nil
      return true
   end
   local normalized = _normalize_key_name(key)
   rec.pressed[normalized] = true
   if rec.press_callback then rec.press_callback(rec.pressed) end
   return true
end

local function _record_key_release(key)
   local rec = Keybinds._recording
   if not rec then return false end
   local normalized = _normalize_key_name(key)
   if rec.pressed[normalized] then
      if rec.callback then rec.callback(rec.pressed) end
      Keybinds._recording = nil
      return true
   end
   return false
end

local function _can_use_keybinds()
   if Keybinds._recording then return false end
   if G and G.CONTROLLER and G.CONTROLLER.text_input_hook then return false end
   if Handy and Handy.controller and Handy.controller.bind_button then return false end
   return true
end

local function _in_run_stage()
   return G and G.STAGE and G.STAGES and G.STAGE == G.STAGES.RUN
end

function Keybinds._on_key_press(controller, key)
   Keybinds.last_input_type = "keyboard"
   if Keybinds._recording then
      _record_key_press(key)
      return
   end
   if not _can_use_keybinds() then return end
   if not _in_run_stage() then return end
   local matches = {}
   local max_size = 0
   for name, func in pairs(Keybinds._actions) do
      if not Keybinds._activated[name] then
         local binding = Keybinds.get_binding(name)
         -- Check KEYBOARD bindings
         if _is_keybind_pressed(controller, binding, "keyboard") then
            local size = _binding_size(binding, "keyboard")
            if size > max_size then
               max_size = size
               matches = { { name = name, func = func } }
            elseif size == max_size then
               matches[#matches + 1] = { name = name, func = func }
            end
         end
      end
   end
   for _, match in ipairs(matches) do
      match.func(controller)
      Keybinds._activated[match.name] = true
   end
end

function Keybinds._on_key_release(controller, key)
   if Keybinds._recording then
      _record_key_release(key)
      return
   end
   for name, _ in pairs(Keybinds._activated) do
      local binding = Keybinds.get_binding(name)
      -- Check if release happened for EITHER input type
      local still_pressed_kb = _is_keybind_pressed(controller, binding, "keyboard")
      local still_pressed_gp = _is_keybind_pressed(controller, binding, "controller")
      
      if not still_pressed_kb and not still_pressed_gp then
         Keybinds._activated[name] = nil
      end
   end
end

function Keybinds._on_button_press(controller, button)
   Keybinds.last_input_type = "controller"
   local key = _normalize_button_name(button)
   if Keybinds._recording then
      _record_key_press(key)
      return
   end
   if not _can_use_keybinds() then return end
   if not _in_run_stage() then return end
   
   -- 1. Hardcoded Controller Navigation
   local SM = REWINDER and REWINDER._SaveManager
   local is_overlay_open = (SM and SM.is_overlay_open and SM.is_overlay_open()) or REWINDER.saves_open
   if is_overlay_open then
      if button == "leftshoulder" then
         if REWINDER.rewinder_prev_page then REWINDER.rewinder_prev_page() return end
      elseif button == "rightshoulder" then
         if REWINDER.rewinder_next_page then REWINDER.rewinder_next_page() return end
      elseif button == "y" then
         if REWINDER.rewinder_save_jump_to_current then REWINDER.rewinder_save_jump_to_current() return end
      end
   end

   -- 2. Configurable Controller Actions
   local matches = {}
   local max_size = 0
   for name, func in pairs(Keybinds._actions) do
      if not Keybinds._activated[name] then
         local binding = Keybinds.get_binding(name)
         -- Check CONTROLLER bindings
         if _is_keybind_pressed(controller, binding, "controller") then
            -- Controller bindings usually simple 1-button, but keep size check structure
            local size = _binding_size(binding, "controller")
            if size > max_size then
               max_size = size
               matches = { { name = name, func = func } }
            elseif size == max_size then
               matches[#matches + 1] = { name = name, func = func }
            end
         end
      end
   end
   for _, match in ipairs(matches) do
      match.func(controller)
      Keybinds._activated[match.name] = true
   end
end

function Keybinds._on_button_release(controller, button)
   local key = _normalize_button_name(button)
   if Keybinds._recording then
      _record_key_release(key)
      return
   end
   -- Re-use logic from _on_key_release since we abstracted check_type in _is_keybind_pressed
   Keybinds._on_key_release(controller, key)
end

-- Helper functions for Controller navigation
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

_ensure_config_keybinds()

local function hook_keybind_controller()
   if not Controller then return false end
   if not Controller._rewinder_key_press then
      Controller._rewinder_key_press = Controller.key_press
      function Controller:key_press(key)
         local ret = Controller._rewinder_key_press(self, key)
         Keybinds._on_key_press(self, key)
         return ret
      end
   end
   if not Controller._rewinder_key_release then
      Controller._rewinder_key_release = Controller.key_release
      function Controller:key_release(key)
         local ret = Controller._rewinder_key_release(self, key)
         Keybinds._on_key_release(self, key)
         return ret
      end
   end
   return true
end

if not hook_keybind_controller() and G and G.E_MANAGER and Event then
   G.E_MANAGER:add_event(Event({
      trigger = "after",
      delay = 0,
      func = function()
         hook_keybind_controller()
         return true
      end,
   }))
end

-- NOTE: REWINDER.load_save_at_index is already defined in SaveManager.lua
-- and exported via Init.lua. Do NOT redefine it here.

local function revert_to_previous_save()
   if REWINDER and REWINDER.revert_to_previous_save then
      return REWINDER.revert_to_previous_save()
   end
end

local function quick_saveload_from_menu()
   if REWINDER and REWINDER.quick_continue_from_menu then
      return REWINDER.quick_continue_from_menu()
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

local _last_quick_saveload_time = nil
local function can_trigger_quick_saveload()
   if not love or not love.timer then return true end
   local now = love.timer.getTime()
   if _last_quick_saveload_time and (now - _last_quick_saveload_time) < 0.25 then
      return false
   end
   _last_quick_saveload_time = now
   return true
end

local function toggle_saves_window()
   if not (G and G.FUNCS) then return end
   if not G.STAGE or G.STAGE ~= G.STAGES.RUN then return end

   local SM = REWINDER and REWINDER._SaveManager
   local is_open = (SM and SM.is_overlay_open and SM.is_overlay_open()) or REWINDER.saves_open
   if is_open then
      if G.FUNCS.rewinder_save_close then
         G.FUNCS.rewinder_save_close()
      elseif G.FUNCS.exit_overlay_menu then
         G.FUNCS.exit_overlay_menu()
      end
      return
   end

   if not (G.UIDEF and G.UIDEF.rewinder_saves) then
      log("error", "G.UIDEF.rewinder_saves not available yet")
      return
   end
   if G.FUNCS.overlay_menu then
      G.FUNCS.overlay_menu({ definition = G.UIDEF.rewinder_saves() })
      if SM and SM.set_overlay_open then
         SM.set_overlay_open(true)
      end
   end
end

Keybinds.register({
   name = "step_back",
   func = function()
      if not _in_run_stage() then return end
      if can_trigger_quick_revert() then
         revert_to_previous_save()
      end
   end,
})

Keybinds.register({
   name = "toggle_saves",
   func = function()
      if not _in_run_stage() then return end
      
      -- Controller Restriction: Only allow in Pause Menu
      if Keybinds.last_input_type == "controller" then
         if not G.SETTINGS.paused then return end
      end
      
      toggle_saves_window()
   end,
})

Keybinds.register({
   name = "quick_saveload",
   func = function()
      if not _in_run_stage() then return end
      if can_trigger_quick_saveload() then
         log("step", "Keybind -> saveload")
         quick_saveload_from_menu()
      end
   end,
})

local function hook_controller_leftstick()
   if not Controller or not Controller.button_press or Controller._rewinder_button_press then return end

   Controller._rewinder_button_press = Controller.button_press
   function Controller:button_press(button)
      local ret = Controller._rewinder_button_press(self, button)
      if Keybinds and Keybinds._on_button_press then
         Keybinds._on_button_press(self, button)
      end
      return ret
   end
end

local function hook_controller_button_release()
   if not Controller or not Controller.button_release or Controller._rewinder_button_release then return end
   Controller._rewinder_button_release = Controller.button_release
   function Controller:button_release(button)
      local ret = Controller._rewinder_button_release(self, button)
      if Keybinds and Keybinds._on_button_release then
         Keybinds._on_button_release(self, button)
      end
      return ret
   end
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
          if snap_to_id(self, "rewinder_btn_current") then return end
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

      -- 2) Paging: left/right page as normal, down goes to Current save, Up goes to last entry
      if id == "rewinder_page_cycle" then
         if dir == "D" then
            snap_to_id(self, "rewinder_btn_current")
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
                -- Fallback blind check if refs missing
                for k=1, 100 do -- Check reasonable range backwards? unlikely to work well without refs
                   -- Just try generic safety snap
                   if snap_to_current_save_entry(self) then return end 
                end
             end
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
hook_controller_button_release()
hook_controller_navigate_focus()
if (not Controller or not Controller.button_press) and G and G.E_MANAGER and Event then
   G.E_MANAGER:add_event(Event({
      trigger = "after",
      delay = 0,
      func = function()
         hook_controller_leftstick()
         hook_controller_button_release()
         hook_controller_navigate_focus()
         return true
      end,
   }))
end
