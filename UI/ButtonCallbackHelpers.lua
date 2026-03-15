if not REWINDER then REWINDER = {} end

local Logger = require("Logger")
local KeySaves = require("KeySaves")
local ScaleNumberHook = require("ScaleNumberHook")
local UIShared = require("UIShared")
local Layout = require("UILayout")
require("UIIconFactory")

local log = Logger.create("UIHelpers")
local M = {}
local PENDING_BADGE_SIZE = 0.17
local PENDING_BADGE_ALIGN = "cr"
local PENDING_BADGE_OFFSET_X = 0.12
local PENDING_BADGE_OFFSET_Y = 0

local function _create_pending_dot_icon()
   if REWINDER and REWINDER.create_pending_dot_icon then
      return REWINDER.create_pending_dot_icon(G.C.WHITE, nil, PENDING_BADGE_SIZE, PENDING_BADGE_SIZE)
   end
   return nil
end

local function _is_rename_text_input_active(controller)
   if not (controller and controller.text_input_hook and controller.text_input_hook.config and controller.text_input_hook.config.ref_table) then
      return false
   end
   return controller.text_input_hook.config.ref_table.rewinder_rename_input == true
end

local function _clear_rename_repeat_state(controller, key)
   if not controller or not controller._rewinder_rename_repeat then return end
   if key then
      controller._rewinder_rename_repeat[key] = nil
      return
   end
   controller._rewinder_rename_repeat = {}
end

local function _install_rename_delete_repeat_hook()
   if not Controller or Controller._rewinder_rename_delete_repeat_installed then return end
   Controller._rewinder_rename_delete_repeat_installed = true

   Controller._rewinder_key_hold_update = Controller._rewinder_key_hold_update or Controller.key_hold_update
   function Controller:key_hold_update(key, dt)
      if (key == "backspace" or key == "delete") and _is_rename_text_input_active(self) then
         self._rewinder_rename_repeat = self._rewinder_rename_repeat or {}
         local state = self._rewinder_rename_repeat[key] or { t = 0, repeating = false }
         state.t = (state.t or 0) + (dt or 0)
         local threshold = state.repeating and 0.055 or 0.35
         if state.t >= threshold then
            state.t = state.t - threshold
            state.repeating = true
            if G and G.FUNCS and G.FUNCS.text_input_key then
               G.FUNCS.text_input_key({
                  key = key,
                  caps = self.held_keys and (self.held_keys["lshift"] or self.held_keys["rshift"]) or false,
               })
            end
         end
         self._rewinder_rename_repeat[key] = state
      elseif key == "backspace" or key == "delete" then
         _clear_rename_repeat_state(self, key)
      end
      return Controller._rewinder_key_hold_update(self, key, dt)
   end

   Controller._rewinder_key_release_update = Controller._rewinder_key_release_update or Controller.key_release_update
   function Controller:key_release_update(key, dt)
      if key == "backspace" or key == "delete" then
         _clear_rename_repeat_state(self, key)
      end
      return Controller._rewinder_key_release_update(self, key, dt)
   end
end

function M.bootstrap()
   if ScaleNumberHook and not ScaleNumberHook.installed then
      ScaleNumberHook.install()
   end

   _install_rename_delete_repeat_hook()
   if (not Controller or not Controller.key_hold_update) and G and G.E_MANAGER and Event then
      G.E_MANAGER:add_event(Event({
         trigger = "after",
         delay = 0,
         func = function()
            _install_rename_delete_repeat_hook()
            return true
         end,
      }))
   end
end

function M.log_ui(action, start, finish, size)
   if start and finish then
      log("debug", string.format("Saves UI: %s (meta %d-%d/%d)", action, start, finish, size))
   else
      log("debug", "Saves UI: " .. action)
   end
end

function M.rename_has_pending_drafts()
   return next(REWINDER._rename_pending or {}) ~= nil or next(REWINDER._rename_pending_clear or {}) ~= nil
end

function M.reset_export_state()
   REWINDER._export_active    = false
   REWINDER._export_selection = {}
end

function M.reset_rename_state(opts)
   opts = opts or {}
   local had_state = REWINDER._rename_active or REWINDER._rename_editing_file ~= nil or M.rename_has_pending_drafts()
   if not opts.keep_active then
      REWINDER._rename_active = false
   end
   REWINDER._rename_editing_file = nil
   REWINDER._rename_input_ref = nil
   REWINDER._rename_pending = {}
   REWINDER._rename_pending_clear = {}
   if opts.reason and had_state then
      log(opts.log_level or "info", "Rename mode aborted: " .. tostring(opts.reason))
   end
end

function M.update_mode_button_labels()
   local refs = REWINDER and REWINDER._saves_ui_refs
   if not refs then return end

   local rename_inactive_colour = UIShared.get_pillar_namebox_colour()
   local key_colour = REWINDER.KEY_SAVE_COLOR or {0.2, 0.7, 0.7, 1}
   local icon_border_colour = UIShared.get_icon_button_border_colour()
   local disabled_icon_border_colour = UIShared.get_icon_button_disabled_border_colour()
   local icon_colour = UIShared.get_icon_button_icon_colour()
   local disabled_icon_colour = UIShared.get_icon_button_disabled_icon_colour()
   local loading_mode = refs.loading_state ~= nil
   local flags = UIShared.compute_mode_enabled_flags(loading_mode)
   local dim_colour = UIShared.dim_colour

   local function apply_button_enabled(node, enabled, active_button_name)
      if not (node and node.config) then return end
      node.config.button = enabled and active_button_name or nil
      node.config.can_collide = enabled
      node.config.hover = enabled
      node.config.shadow = enabled
   end

   local function apply_icon_enabled(icon_id, enabled)
      if not (G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID) then return end
      local icon_node = G.OVERLAY_MENU:get_UIE_by_ID(icon_id)
      local icon_obj = icon_node and icon_node.config and icon_node.config.object
      if not (icon_obj and type(icon_obj.colour) == "table") then return end
      local c = enabled and icon_colour or disabled_icon_colour
      icon_obj.colour[1] = c[1] or icon_obj.colour[1]
      icon_obj.colour[2] = c[2] or icon_obj.colour[2]
      icon_obj.colour[3] = c[3] or icon_obj.colour[3]
      icon_obj.colour[4] = c[4] or icon_obj.colour[4]
   end

   -- Dynamic label updates
   if refs.mark_button_ref and refs.mark_button_ref.label then
      refs.mark_button_ref.label.text = REWINDER._mark_active and UIShared.loc("rewinder_mark_keys_active", "Save marking changes")
         or UIShared.loc("rewinder_mark_keys", "Edit key saves")
   end
   if refs.filter_button_ref and refs.filter_button_ref.label then
      refs.filter_button_ref.label.text = REWINDER._filter_active and UIShared.loc("rewinder_filter_keys_active", "Return to all saves")
         or UIShared.loc("rewinder_filter_keys", "Check key saves")
   end

   -- Filter button (text-only, no fill/icon)
   local filter_btn = G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID and G.OVERLAY_MENU:get_UIE_by_ID("rewinder_btn_filter_keys")
   apply_button_enabled(filter_btn, flags.filter_enabled, "rewinder_btn_filter_keys")
   if filter_btn and filter_btn.config then
      filter_btn.config.colour = flags.filter_enabled and G.C.BLUE or dim_colour(G.C.BLUE)
   end

   -- Icon buttons config table: { id, fill_id, icon_id, callback, enabled, fill_colour_fn }
   local active_red = G.C.RED or Layout.MODE_ACTIVE_COLOUR
   local icon_buttons = {
      {
         id = "rewinder_btn_mark_keys",
         fill_id = "rewinder_btn_mark_keys_fill",
         icon_id = "rewinder_btn_mark_keys_icon",
         callback = "rewinder_btn_mark_keys",
         enabled = flags.mark_enabled,
         fill_colour = REWINDER._mark_active and active_red or key_colour,
      },
      {
         id = "rewinder_btn_toggle_rename",
         fill_id = "rewinder_btn_toggle_rename_fill",
         icon_id = "rewinder_btn_toggle_rename_icon",
         callback = "rewinder_btn_toggle_rename",
         enabled = flags.rename_enabled,
         fill_colour = REWINDER._rename_active and active_red or rename_inactive_colour,
      },
      {
         id = "rewinder_btn_jump_to_current",
         fill_id = "rewinder_btn_jump_to_current_fill",
         icon_id = "rewinder_btn_jump_to_current_icon",
         callback = "rewinder_save_jump_to_current",
         enabled = flags.jump_enabled,
         fill_colour = G.C.ORANGE or {1, 0.6, 0.2, 1},
      },
      {
         id = "rewinder_btn_export",
         fill_id = "rewinder_btn_export_fill",
         icon_id = "rewinder_btn_export_icon",
         callback = "rewinder_btn_toggle_export",
         enabled = flags.export_enabled,
         fill_colour = REWINDER._export_active and active_red or Layout.EXPORT_BUTTON_COLOUR,
      },
   }

   for _, cfg in ipairs(icon_buttons) do
      local btn = G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID and G.OVERLAY_MENU:get_UIE_by_ID(cfg.id)
      local fill = G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID and G.OVERLAY_MENU:get_UIE_by_ID(cfg.fill_id)
      apply_button_enabled(btn, cfg.enabled, cfg.callback)
      if btn and btn.config then
         btn.config.colour = cfg.enabled and icon_border_colour or disabled_icon_border_colour
      end
      if fill and fill.config then
         fill.config.colour = cfg.enabled and cfg.fill_colour or dim_colour(cfg.fill_colour)
      end
      apply_icon_enabled(cfg.icon_id, cfg.enabled)
   end

   M.update_saves_outline_colour()
end

function M.update_saves_outline_colour()
   if not (G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID) then return end
   local saves_node = G.OVERLAY_MENU:get_UIE_by_ID("rewinder_saves")
   if not saves_node then return end

   local target = saves_node
   while target do
      if target.config and target.config.emboss == 0.1 and target.config.padding == 0.07 then
         target.config.colour = UIShared.get_saves_outline_colour()
         if target.UIBox then
            target.UIBox:recalculate(true)
         elseif target.parent and target.parent.UIBox then
            target.parent.UIBox:recalculate(true)
         end
         return
      end
      target = target.parent
   end
end

function M.update_paging_arrow_visuals(total_pages)
   if not (G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID) then return end
   local cycle_node = G.OVERLAY_MENU:get_UIE_by_ID("rewinder_page_cycle")
   if not (cycle_node and cycle_node.children) then return end

   local enabled = (total_pages or 1) >= 2
   local arrow_colour = enabled and G.C.BLUE or G.C.BLACK
   local text_colour = enabled and G.C.UI.TEXT_LIGHT or G.C.UI.TEXT_INACTIVE

   -- children[1] = left arrow, children[3] = right arrow
   for _, idx in ipairs({1, 3}) do
      local arrow = cycle_node.children[idx]
      if arrow and arrow.config then
         arrow.config.colour = arrow_colour
         arrow.config.hover = enabled
         arrow.config.shadow = enabled
         arrow.config.button = enabled and 'option_cycle' or nil
      end
      -- Each arrow has one text child (the '<' / '>' character)
      if arrow and arrow.children and arrow.children[1] and arrow.children[1].config then
         arrow.children[1].config.colour = text_colour
      end
   end
end

function M.reset_key_save_state(discard_pending, preserve_filter_mode)
   local had_pending = KeySaves.has_pending and KeySaves.has_pending() or false
   if discard_pending and REWINDER._mark_active then
      KeySaves.discard_pending()
   end
   if not preserve_filter_mode then
      REWINDER._filter_active = false
   end
   REWINDER._mark_active = false
   REWINDER._key_save_index_map = nil
   REWINDER._key_save_reverse_map = nil
   M.reset_rename_state()
   log("debug", string.format(
      "Key-save UI state reset discard=%s preserve_filter=%s had_pending=%s filter=%s",
      tostring(discard_pending), tostring(preserve_filter_mode), tostring(had_pending), tostring(REWINDER._filter_active)
   ))
end

function M.get_displayed_entries()
   local all = REWINDER.get_save_files()
   if REWINDER._filter_active then
      local filtered, idx_map = KeySaves.get_key_saves(all)
      REWINDER._key_save_index_map = idx_map
      local reverse = {}
      for fi, oi in ipairs(idx_map) do
         reverse[oi] = fi
      end
      REWINDER._key_save_reverse_map = reverse
      return filtered
   end

   REWINDER._key_save_index_map = nil
   REWINDER._key_save_reverse_map = nil
   return all
end

REWINDER._get_displayed_entries = M.get_displayed_entries

function M.recenter_meta_on_open()
   if not (REWINDER and REWINDER._SaveManager and REWINDER._SaveManager.ensure_meta_window_for_page and REWINDER._saves_ui_refs) then
      return nil, nil, nil
   end
   if REWINDER._filter_active then return nil, nil, nil end

   local per_page = REWINDER._saves_ui_refs.per_page or 8
   local current_page = REWINDER._saves_ui_refs.cycle_config and REWINDER._saves_ui_refs.cycle_config.current_option or 1
   REWINDER._SaveManager.ensure_meta_window_for_page(current_page, per_page, 4, false, true)
   if REWINDER._SaveManager.calc_meta_window_bounds_for_page then
      return REWINDER._SaveManager.calc_meta_window_bounds_for_page(current_page, per_page, 4)
   end
   return nil, nil, nil
end

function M.recenter_meta_on_close()
   if not (REWINDER and REWINDER._SaveManager and REWINDER._SaveManager.ensure_meta_window) then
      return nil, nil, nil
   end
   local current_idx = REWINDER.get_current_index and REWINDER.get_current_index()
   if not current_idx then return nil, nil, nil end
   REWINDER._SaveManager.ensure_meta_window(current_idx, REWINDER._SaveManager.META_CACHE_BASE_LIMIT, false, true)
   if REWINDER._SaveManager.calc_meta_window_bounds then
      return REWINDER._SaveManager.calc_meta_window_bounds(current_idx, REWINDER._SaveManager.META_CACHE_BASE_LIMIT)
   end
   return nil, nil, nil
end

function M.ensure_exit_overlay_wrapped()
   if not (G and G.FUNCS and G.FUNCS.exit_overlay_menu) then return end
   if G.FUNCS._rewinder_exit_overlay_menu then return end

   G.FUNCS._rewinder_exit_overlay_menu = G.FUNCS.exit_overlay_menu
   G.FUNCS.exit_overlay_menu = function(...)
      if REWINDER and REWINDER.saves_open then
         M.reset_key_save_state(true, true)
         M.reset_export_state()
         if REWINDER._SaveManager and REWINDER._SaveManager.set_overlay_open then
            REWINDER._SaveManager.set_overlay_open(false)
         end
         REWINDER._saves_ui_refs = nil
         local start, finish, size = M.recenter_meta_on_close()
         M.log_ui("closed", start, finish, size)
      end
      return G.FUNCS._rewinder_exit_overlay_menu(...)
   end
end

function M.snap_saves_focus_to_current()
   if not (G and G.CONTROLLER and REWINDER and REWINDER._saves_ui_refs and REWINDER._saves_ui_refs.saves_box) then return end

   local full_idx = REWINDER.find_current_index and REWINDER.find_current_index()
   local display_idx = full_idx
   if REWINDER._filter_active then
      display_idx = full_idx and REWINDER._key_save_reverse_map and REWINDER._key_save_reverse_map[full_idx] or nil
   end

   local node
   if display_idx then
      node = REWINDER._saves_ui_refs.saves_box:get_UIE_by_ID("rewinder_save_entry_" .. tostring(display_idx))
   end
   if not node then
      node = REWINDER._saves_ui_refs.saves_box:get_UIE_by_ID("rewinder_save_entry_1")
   end
   if not node then
      node = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID("rewinder_page_cycle")
   end

   if node then
      G.CONTROLLER:snap_to({ node = node })
      if G.CONTROLLER.update_cursor then
         G.CONTROLLER:update_cursor()
      end
   end
end

local function _entry_has_pending_badge(entry)
   if not entry then return false end

   local key_pending = false
   if REWINDER._mark_active then
      local _, is_pending = KeySaves.effective_is_key(entry)
      key_pending = (is_pending == true)
   end

   local rename_pending = false
   local file = entry[REWINDER.ENTRY_FILE]
   if REWINDER._rename_active and file and REWINDER._rename_editing_file ~= file then
      rename_pending = (REWINDER._rename_pending and REWINDER._rename_pending[file] ~= nil)
         or (REWINDER._rename_pending_clear and REWINDER._rename_pending_clear[file] == true)
   end

   local export_pending = false
   if REWINDER._export_active and file then
      export_pending = (REWINDER._export_selection and REWINDER._export_selection[file] == true)
   end

   return key_pending or rename_pending or export_pending
end

local function _remove_pending_badge(row)
   if row and row.children and row.children.rewinder_pending_badge then
      row.children.rewinder_pending_badge:remove()
      row.children.rewinder_pending_badge = nil
   end
end

local function _attach_pending_badge(row)
   if not (row and row.children) then return end
   if row.children.rewinder_pending_badge then return end

   local pending_icon = _create_pending_dot_icon()

   row.children.rewinder_pending_badge = UIBox({
      definition = {
         n = G.UIT.ROOT,
         config = { align = "cm", colour = G.C.CLEAR, refresh_movement = true },
         nodes = {
            {
               n = G.UIT.R,
               config = {
                  align = "cm",
                  minw = PENDING_BADGE_SIZE,
                  minh = PENDING_BADGE_SIZE,
                  colour = G.C.CLEAR,
                  refresh_movement = true,
               },
               nodes = {
                  {
                     n = pending_icon and G.UIT.O or G.UIT.R,
                     config = pending_icon and {
                        draw_layer = 1,
                        object = pending_icon,
                     } or {
                        align = "cm",
                        minw = PENDING_BADGE_SIZE,
                        minh = PENDING_BADGE_SIZE,
                        r = 0.5,
                        colour = G.C.WHITE,
                     },
                     nodes = pending_icon and nil or {},
                  },
               },
            },
         },
      },
      config = {
         instance_type = "ALERT",
         align = PENDING_BADGE_ALIGN,
         offset = { x = PENDING_BADGE_OFFSET_X, y = PENDING_BADGE_OFFSET_Y },
         major = row,
         parent = row,
      },
   })
   row.children.rewinder_pending_badge.states.collide.can = false
end

function M.refresh_pending_row_badges(entries, page, per_page)
   local refs = REWINDER and REWINDER._saves_ui_refs
   if not (refs and refs.saves_box and refs.saves_box.get_UIE_by_ID) then return end

   entries = entries or refs.entries or {}
   page = page or (refs.cycle_config and refs.cycle_config.current_option) or 1
   per_page = per_page or refs.per_page or 8

   local start_idx = math.max(1, (page - 1) * per_page + 1)
   local finish_idx = math.min(#entries, start_idx + per_page - 1)

   for idx = start_idx, finish_idx do
      local row = refs.saves_box:get_UIE_by_ID("rewinder_save_entry_" .. tostring(idx))
      if row then
         if _entry_has_pending_badge(entries[idx]) then
            _attach_pending_badge(row)
         else
            _remove_pending_badge(row)
         end
      end
   end
end

function M.refresh_pending_badges()
   local refs = REWINDER and REWINDER._saves_ui_refs
   if not refs then return end
   M.refresh_pending_row_badges(refs.entries, refs.cycle_config and refs.cycle_config.current_option, refs.per_page)
end

local function _ensure_rename_cursor_flash_callback()
   if not (G and G.FUNCS) then return false end
   if G.FUNCS.rewinder_rename_cursor_flash then return true end

   G.FUNCS.rewinder_rename_cursor_flash = function(e)
      if not (e and e.config and type(e.config.colour) == "table") then return end
      local cfg = e.config
      local rgb = cfg.rewinder_cursor_rgb
      if type(rgb) == "table" then
         cfg.colour[1] = rgb[1] or cfg.colour[1]
         cfg.colour[2] = rgb[2] or cfg.colour[2]
         cfg.colour[3] = rgb[3] or cfg.colour[3]
      end

      local hook = G and G.CONTROLLER and G.CONTROLLER.text_input_hook
      local hook_ref = hook and hook.config and hook.config.ref_table
      local rename_hooked = hook_ref and hook_ref.rewinder_rename_input == true

      if rename_hooked then
         local visible_alpha = cfg.rewinder_cursor_alpha or 1
         cfg.colour[4] = ((math.floor(G.TIMERS.REAL * 2)) % 2 == 1) and 0 or visible_alpha
         if cfg.w ~= 0.1 then
            cfg.w = 0.1
            if e.UIBox then e.UIBox:recalculate(true) end
         end
      else
         cfg.colour[4] = 0
         if cfg.w ~= 0 then
            cfg.w = 0
            if e.UIBox then e.UIBox:recalculate(true) end
         end
      end
   end

   return true
end

local function _find_rename_entry_colour()
   local file = REWINDER and REWINDER._rename_editing_file
   local refs = REWINDER and REWINDER._saves_ui_refs
   if not (file and refs and refs.entries and refs.saves_box and refs.saves_box.get_UIE_by_ID) then return nil end

   local display_idx = nil
   for i, entry in ipairs(refs.entries) do
      if entry and entry[REWINDER.ENTRY_FILE] == file then
         display_idx = i
         break
      end
   end
   if not display_idx then return nil end

   local row = refs.saves_box:get_UIE_by_ID("rewinder_save_entry_" .. tostring(display_idx))
   if row and row.config and type(row.config.colour) == "table" then
      return row.config.colour
   end
   return nil
end

local function _cursor_rgb_from_base(base)
   local c = (type(base) == "table") and copy_table(base) or copy_table(G.C.BLUE)
   local light = lighten(c, 0.4)
   return {
      light[1] or 1,
      light[2] or 1,
      light[3] or 1,
   }
end

local function _apply_live_rename_cursor_style()
   if not (G and G.CONTROLLER and G.CONTROLLER.text_input_hook and _ensure_rename_cursor_flash_callback()) then return end
   local hook = G.CONTROLLER.text_input_hook
   local hook_ref = hook.config and hook.config.ref_table
   if not (hook_ref and hook_ref.rewinder_rename_input == true) then return end

   local cursor = nil
   for _, child in ipairs(hook.children or {}) do
      if child and child.config and (
         child.config.id == "position" or
         child.config.func == "flash" or
         child.config.func == "rewinder_rename_cursor_flash"
      ) then
         cursor = child
         break
      end
   end
   if not (cursor and cursor.config) then return end

   local base = _find_rename_entry_colour() or G.C.BLUE
   local rgb = _cursor_rgb_from_base(base)
   cursor.config.rewinder_cursor_rgb = { rgb[1] or 1, rgb[2] or 1, rgb[3] or 1 }
   cursor.config.rewinder_cursor_alpha = 1
   cursor.config.func = "rewinder_rename_cursor_flash"
   if type(cursor.config.colour) ~= "table" then
      cursor.config.colour = { rgb[1] or 1, rgb[2] or 1, rgb[3] or 1, 0 }
   else
      cursor.config.colour[1] = rgb[1] or cursor.config.colour[1]
      cursor.config.colour[2] = rgb[2] or cursor.config.colour[2]
      cursor.config.colour[3] = rgb[3] or cursor.config.colour[3]
   end

   log("debug", string.format(
      "Rename cursor style applied rgb=(%.3f, %.3f, %.3f) file=%s",
      cursor.config.rewinder_cursor_rgb[1], cursor.config.rewinder_cursor_rgb[2], cursor.config.rewinder_cursor_rgb[3], tostring(REWINDER._rename_editing_file)
   ))
end

function M.focus_rename_text_input()
   if not (G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID and G.FUNCS and G.FUNCS.select_text_input) then
      return
   end
   local input = G.OVERLAY_MENU:get_UIE_by_ID("text_input")
   if input then
      G.FUNCS.select_text_input(input)
      _apply_live_rename_cursor_style()
      UIShared.run_after_frame(_apply_live_rename_cursor_style)
   end
end

local function _get_default_rename_title(file)
   local title = REWINDER.get_default_state_title and REWINDER.get_default_state_title(file) or nil
   if title and title ~= "" then return title end
   local entries = M.get_displayed_entries()
   for _, entry in ipairs(entries) do
      if entry and entry[REWINDER.ENTRY_FILE] == file then
         local from_entry = REWINDER.get_default_state_title and REWINDER.get_default_state_title(entry) or nil
         if from_entry and from_entry ~= "" then
            return from_entry
         end
         break
      end
   end
   return ""
end

local function _normalize_custom_name(name)
   if REWINDER.normalize_custom_state_name then
      return REWINDER.normalize_custom_state_name(name)
   end
   if type(name) ~= "string" then return nil end
   local trimmed = name:match("^%s*(.-)%s*$")
   if trimmed == "" then return nil end
   return trimmed
end

local function _normalized_rename_value(file, raw_value)
   local name = _normalize_custom_name(raw_value)
   if not name then return nil end
   local default_title = _get_default_rename_title(file)
   local default_normalized = _normalize_custom_name(default_title)
   if default_normalized and name == default_normalized then
      return nil
   end
   return name
end

function M.store_rename_pending(file, raw_value)
   if not file then return end
   local current_name = REWINDER.get_custom_state_name and REWINDER.get_custom_state_name(file) or nil
   local normalized = _normalized_rename_value(file, raw_value)
   if normalized == current_name then
      REWINDER._rename_pending[file] = nil
      REWINDER._rename_pending_clear[file] = nil
      return
   end
   if normalized == nil then
      REWINDER._rename_pending[file] = nil
      REWINDER._rename_pending_clear[file] = (current_name ~= nil) or nil
      return
   end
   REWINDER._rename_pending[file] = raw_value
   REWINDER._rename_pending_clear[file] = nil
end

function M.snapshot_active_rename_edit()
   if REWINDER._rename_editing_file and REWINDER._rename_input_ref then
      M.store_rename_pending(REWINDER._rename_editing_file, REWINDER._rename_input_ref.text)
   end
end

function M.commit_pending_rename_drafts()
   local committed = 0
   local files_to_commit = {}

   for pending_file in pairs(REWINDER._rename_pending or {}) do
      files_to_commit[pending_file] = true
   end
   for pending_file in pairs(REWINDER._rename_pending_clear or {}) do
      files_to_commit[pending_file] = true
   end

   for pending_file in pairs(files_to_commit) do
      local pending_name = REWINDER._rename_pending and REWINDER._rename_pending[pending_file] or nil
      local normalized_name = _normalized_rename_value(pending_file, pending_name)
      local current_name = REWINDER.get_custom_state_name and REWINDER.get_custom_state_name(pending_file) or nil
      if current_name == normalized_name then
         log("debug", "Skip no-op rename commit for " .. tostring(pending_file))
      else
         local success = REWINDER.set_custom_state_name(pending_file, normalized_name)
         if success then
            committed = committed + 1
         else
            log("warning", "Failed to save custom name for " .. tostring(pending_file))
         end
      end
   end

   return committed
end

local function _resolve_cycle_config(refs, current_option, per_page, entries)
   if not refs or not refs.saves_box then return nil end

   local cycle_config = refs.cycle_config
   if not cycle_config then
      cycle_config = {
         options = refs.page_numbers or {},
         current_option = current_option,
         opt_callback = "rewinder_save_update_page",
         opt_args = {},
      }
   end

   -- Loading shell temporarily disables paging callback; restore it once real entries are rendered.
   cycle_config.opt_callback = cycle_config.opt_callback or "rewinder_save_update_page"
   cycle_config.opt_args = cycle_config.opt_args or {}
   cycle_config.opt_args.ui = refs.saves_box
   cycle_config.opt_args.per_page = per_page
   cycle_config.opt_args.entries = entries
   return cycle_config
end

function M.page_with_current_save(per_page)
   local entries = M.get_displayed_entries()
   local total_pages = math.max(1, math.ceil(#entries / per_page))
   local idx = REWINDER.find_current_index and REWINDER.find_current_index() or nil
   if REWINDER._filter_active and idx then
      idx = REWINDER._key_save_reverse_map and REWINDER._key_save_reverse_map[idx] or nil
   end
   if not idx or idx < 1 then
      return 1
   end
   return UIShared.clamp_page(math.ceil(idx / per_page), total_pages)
end

function M.refresh_saves_view(target_page)
   local refs = REWINDER and REWINDER._saves_ui_refs
   if not refs or not refs.saves_box then return end

   local per_page = refs.per_page or 8
   local entries = M.get_displayed_entries()
   local total_pages = math.max(1, math.ceil(#entries / per_page))
   local page = UIShared.clamp_page(target_page or (refs.cycle_config and refs.cycle_config.current_option) or 1, total_pages)
   log("debug", string.format("Refresh saves view page=%d/%d entries=%d filter=%s mark=%s",
      page, total_pages, #entries, tostring(REWINDER._filter_active), tostring(REWINDER._mark_active)))

   local page_numbers = UIShared.build_page_numbers(total_pages)

   refs.page_numbers = page_numbers
   refs.entries = entries
   local cycle_config = _resolve_cycle_config(refs, page, per_page, entries)
   if not cycle_config then return end

   cycle_config.options = page_numbers
   cycle_config.current_option = page
   cycle_config.current_option_val = page_numbers[page]
   refs.cycle_config = cycle_config

   if G and G.FUNCS and G.FUNCS.rewinder_save_update_page then
      G.FUNCS.rewinder_save_update_page({
         cycle_config = cycle_config,
         to_key = page,
         _entries = entries,
         _page_numbers = page_numbers,
      })
   end
end

REWINDER._refresh_saves_view = M.refresh_saves_view

function M.refresh_saves_if_open(target_page)
   if REWINDER and REWINDER._saves_ui_refs and REWINDER._saves_ui_refs.saves_box then
      M.refresh_saves_view(target_page)
      return true
   end
   return false
end

M.KeySaves = KeySaves
M.log = log

-- Expose private helpers for unit tests.
M._normalize_custom_name     = _normalize_custom_name
M._normalized_rename_value   = _normalized_rename_value
M._entry_has_pending_badge   = _entry_has_pending_badge

return M
