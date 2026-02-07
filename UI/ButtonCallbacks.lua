--- Save Rewinder - UI/ButtonCallbacks.lua
--
-- Button callbacks for the saves UI.
if not REWINDER then REWINDER = {} end
local Logger = require("Logger")
local KeySaves = require("KeySaves")
local log = Logger.create("UI")
REWINDER._filter_active = REWINDER._filter_active or false
REWINDER._mark_active = REWINDER._mark_active or false

-- Install ScaleNumberHook here (after scale_number is defined in button_callbacks.lua)
-- This file is appended to button_callbacks.lua via lovely.toml
-- NOTE: Must use require() - lovely modules are NOT globals!
local ScaleNumberHook = require("ScaleNumberHook")
if ScaleNumberHook and not ScaleNumberHook.installed then
    ScaleNumberHook.install()
end

local function _loc(key, fallback)
   if localize then
      return localize(key) or fallback
   end
   return fallback
end

local function _log_ui(action, start, finish, size)
   if start and finish then
      log("debug", string.format("Saves UI: %s (meta %d-%d/%d)", action, start, finish, size))
   else
      log("debug", "Saves UI: " .. action)
   end
end

local function _log_ui_action(action)
   log("debug", "Saves UI: " .. action)
end

local function _update_mode_button_labels()
   local refs = REWINDER and REWINDER._saves_ui_refs
   if not refs then return end

   local mark_active_colour = G.C.RED or {0.9, 0.2, 0.2, 1}
   local blue_colour = G.C.BLUE
   local key_colour = REWINDER.KEY_SAVE_COLOR or {0.2, 0.7, 0.7, 1}

   if refs.mark_button_ref and refs.mark_button_ref.label then
      refs.mark_button_ref.label.text = REWINDER._mark_active and _loc("rewinder_mark_keys_active", "Save marking changes")
         or _loc("rewinder_mark_keys", "Edit key saves")
   end

   if refs.filter_button_ref and refs.filter_button_ref.label then
      refs.filter_button_ref.label.text = REWINDER._filter_active and _loc("rewinder_filter_keys_active", "Return to all saves")
         or _loc("rewinder_filter_keys", "Check key saves")
   end

   local mark_btn = G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID and G.OVERLAY_MENU:get_UIE_by_ID("rewinder_btn_mark_keys")
   local mark_fill = G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID and G.OVERLAY_MENU:get_UIE_by_ID("rewinder_btn_mark_keys_fill")
   if mark_fill and mark_fill.config then
      mark_fill.config.colour = REWINDER._mark_active and mark_active_colour or key_colour
   elseif mark_btn and mark_btn.config then
      mark_btn.config.colour = REWINDER._mark_active and mark_active_colour or key_colour
   end

   local filter_btn = G and G.OVERLAY_MENU and G.OVERLAY_MENU.get_UIE_by_ID and G.OVERLAY_MENU:get_UIE_by_ID("rewinder_btn_filter_keys")
   if filter_btn and filter_btn.config then
      filter_btn.config.colour = blue_colour
   end
end

local function _reset_key_save_state(discard_pending, preserve_filter_mode)
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
   log("debug", string.format(
      "Key-save UI state reset discard=%s preserve_filter=%s had_pending=%s filter=%s",
      tostring(discard_pending), tostring(preserve_filter_mode), tostring(had_pending), tostring(REWINDER._filter_active)
   ))
end

local function _get_displayed_entries()
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

REWINDER._get_displayed_entries = _get_displayed_entries

local function _recenter_meta_on_open()
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

local function _recenter_meta_on_close()
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

local function _ensure_exit_overlay_wrapped()
   if not (G and G.FUNCS and G.FUNCS.exit_overlay_menu) then return end
   if G.FUNCS._rewinder_exit_overlay_menu then return end

   G.FUNCS._rewinder_exit_overlay_menu = G.FUNCS.exit_overlay_menu
   G.FUNCS.exit_overlay_menu = function(...)
      if REWINDER and REWINDER.saves_open then
         _reset_key_save_state(true, true)
         if REWINDER._SaveManager and REWINDER._SaveManager.set_overlay_open then
            REWINDER._SaveManager.set_overlay_open(false)
         end
         REWINDER._saves_ui_refs = nil
         local start, finish, size = _recenter_meta_on_close()
         _log_ui("closed", start, finish, size)
      end
      return G.FUNCS._rewinder_exit_overlay_menu(...)
   end
end

local function _snap_saves_focus_to_current()
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

local function _run_after_frame(func)
   if G and G.E_MANAGER and Event then
      G.E_MANAGER:add_event(Event({
         trigger = "after",
         delay = 0,
         func = function()
            func()
            return true
         end,
      }))
   else
      func()
   end
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

   cycle_config.opt_args = cycle_config.opt_args or {}
   cycle_config.opt_args.ui = refs.saves_box
   cycle_config.opt_args.per_page = per_page
   cycle_config.opt_args.entries = entries
   return cycle_config
end

local function _clamp_page(page, total_pages)
   local p = tonumber(page) or 1
   local total = math.max(1, tonumber(total_pages) or 1)
   if p < 1 then p = 1 end
   if p > total then p = total end
   return p
end

local function _build_page_numbers(total_pages)
   local numbers = {}
   local pattern = _loc("rewinder_page_label", "Page %d/%d")
   for i = 1, total_pages do
      numbers[i] = string.format(pattern, i, total_pages)
   end
   return numbers
end

local function _page_with_current_save(per_page)
   local entries = _get_displayed_entries()
   local total_pages = math.max(1, math.ceil(#entries / per_page))
   local idx = REWINDER.find_current_index and REWINDER.find_current_index() or nil
   if REWINDER._filter_active and idx then
      idx = REWINDER._key_save_reverse_map and REWINDER._key_save_reverse_map[idx] or nil
   end
   if not idx or idx < 1 then
      return 1
   end
   return _clamp_page(math.ceil(idx / per_page), total_pages)
end

local function _refresh_saves_view(target_page)
   local refs = REWINDER and REWINDER._saves_ui_refs
   if not refs or not refs.saves_box then return end

   local per_page = refs.per_page or 8
   local entries = _get_displayed_entries()
   local total_pages = math.max(1, math.ceil(#entries / per_page))
   local page = _clamp_page(target_page or (refs.cycle_config and refs.cycle_config.current_option) or 1, total_pages)
   log("debug", string.format("Refresh saves view page=%d/%d entries=%d filter=%s mark=%s",
      page, total_pages, #entries, tostring(REWINDER._filter_active), tostring(REWINDER._mark_active)))

   local page_numbers = _build_page_numbers(total_pages)

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

REWINDER._refresh_saves_view = _refresh_saves_view

local function _refresh_saves_if_open(target_page)
   if REWINDER and REWINDER._saves_ui_refs and REWINDER._saves_ui_refs.saves_box then
      _refresh_saves_view(target_page)
      return true
   end
   return false
end

function G.FUNCS.rewinder_save_close(e)
   _reset_key_save_state(true, true)
   if REWINDER and REWINDER._SaveManager and REWINDER._SaveManager.set_overlay_open then
      REWINDER._SaveManager.set_overlay_open(false)
   end
   REWINDER._saves_ui_refs = nil
   local start, finish, size = _recenter_meta_on_close()
   _log_ui("closed", start, finish, size)
   if G and G.FUNCS and G.FUNCS._rewinder_exit_overlay_menu then
      return G.FUNCS._rewinder_exit_overlay_menu(e)
   end
   if G and G.FUNCS and G.FUNCS.exit_overlay_menu then
      return G.FUNCS.exit_overlay_menu(e)
   end
end

function G.FUNCS.rewinder_save_open(e)
   if not G.FUNCS or not G.FUNCS.overlay_menu then return end
   _ensure_exit_overlay_wrapped()
   if REWINDER and REWINDER._SaveManager and REWINDER._SaveManager.set_overlay_open then
      REWINDER._SaveManager.set_overlay_open(true)
   end

   G.FUNCS.overlay_menu({
      definition = G.UIDEF.rewinder_saves(),
   })

   _update_mode_button_labels()
   local start, finish, size = _recenter_meta_on_open()
   _log_ui("opened", start, finish, size)
   _run_after_frame(_snap_saves_focus_to_current)
end

function G.FUNCS.rewinder_save_jump_to_current(e)
   local refs = REWINDER._saves_ui_refs
   if not refs or not refs.saves_box then return end

   _log_ui_action("jump to current")

   _get_displayed_entries()
   local per_page = refs.per_page or 8
   local idx = REWINDER.find_current_index and REWINDER.find_current_index() or nil
   if REWINDER._filter_active and idx then
      idx = REWINDER._key_save_reverse_map and REWINDER._key_save_reverse_map[idx] or nil
   end

   local target_page = 1
   if idx then
      target_page = math.ceil(idx / per_page)
   end

   _refresh_saves_view(target_page)
   _run_after_frame(_snap_saves_focus_to_current)
end

function REWINDER.rewinder_save_jump_to_current()
   if G.FUNCS.rewinder_save_jump_to_current then
      G.FUNCS.rewinder_save_jump_to_current()
   end
end

local function _navigate_page(dir)
   local refs = REWINDER._saves_ui_refs
   if not refs or not refs.saves_box then return end

   local per_page = refs.per_page or 8
   local entries = _get_displayed_entries()
   local total_pages = math.max(1, math.ceil(#entries / per_page))
   local current_page = refs.cycle_config and refs.cycle_config.current_option or 1

   local target_page = current_page + dir
   if target_page < 1 then
      target_page = total_pages
   elseif target_page > total_pages then
      target_page = 1
   end

   _refresh_saves_view(target_page)
end

function REWINDER.rewinder_prev_page()
   _navigate_page(-1)
end

function REWINDER.rewinder_next_page()
   _navigate_page(1)
end

function G.FUNCS.rewinder_save_reload(e)
   if REWINDER and REWINDER.preload_all_metadata then
      REWINDER.preload_all_metadata(true)
   elseif REWINDER and REWINDER.get_save_files then
      REWINDER.get_save_files(true)
   end

   _refresh_saves_if_open(1)
end

function G.FUNCS.rewinder_save_delete_all(e)
   if REWINDER and REWINDER.clear_all_saves then
      REWINDER.clear_all_saves()
   end
   _log_ui_action("deleted all saves")
   _refresh_saves_if_open(1)
end

function G.FUNCS.rewinder_save_restore(e)
   if not e or not e.config or not e.config.ref_table then return end
   local file = e.config.ref_table.file
   if not file then return end

   local desc = (REWINDER.describe_save and REWINDER.describe_save({ file = file })) or "save"
   _log_ui_action("restore -> " .. desc)

   if REWINDER and REWINDER._SaveManager and REWINDER._SaveManager._set_cache_current_file then
      REWINDER._SaveManager._set_cache_current_file(file)
   end

   if REWINDER and REWINDER._SaveManager then
      local idx = REWINDER._SaveManager.get_index_by_file and REWINDER._SaveManager.get_index_by_file(file)
      if idx then
         if REWINDER.set_pending_index then
            REWINDER.set_pending_index(idx)
         elseif REWINDER._SaveManager then
            REWINDER._SaveManager.pending_index = idx
         end
      end
   end

   REWINDER.load_and_start_from_file(file)
end

function G.FUNCS.rewinder_save_toggle_key(e)
   if not REWINDER._mark_active then return end
   if not e or not e.config or not e.config.ref_table then return end

   local file = e.config.ref_table.file
   if not file then return end

   local effective = KeySaves.toggle_pending(file)
   if effective == nil then
      log("warning", "Failed to toggle key status for file=" .. tostring(file))
      return
   end
   log("debug", string.format("Toggled pending key file=%s effective=%s", tostring(file), tostring(effective)))
   _refresh_saves_view(nil)
end

function G.FUNCS.rewinder_btn_mark_keys(e)
   if REWINDER._mark_active then
      local success, fail = KeySaves.commit_pending()
      REWINDER._mark_active = false
      if fail > 0 then
         log("warning", string.format("Key-save commit partial failure: success=%d fail=%d", success, fail))
      else
         log("info", string.format("Key-save commit complete: %d", success))
      end
      _refresh_saves_view(nil)
      return
   end

   REWINDER._mark_active = true
   log("info", "Key-save mark mode enabled")
   _refresh_saves_view(nil)
end

function G.FUNCS.rewinder_btn_filter_keys(e)
   REWINDER._filter_active = not REWINDER._filter_active
   local per_page = (REWINDER._saves_ui_refs and REWINDER._saves_ui_refs.per_page) or 8
   local target_page = _page_with_current_save(per_page)
   log("info", string.format(
      "Key-save filter mode %s -> target page %d",
      (REWINDER._filter_active and "enabled" or "disabled"),
      target_page
   ))
   _refresh_saves_view(target_page)
end

function G.FUNCS.rewinder_save_update_page(args)
   if not args or not args.cycle_config then return end

   local callback_args = args.cycle_config.opt_args
   if not callback_args or not callback_args.ui then return end

   local per_page = callback_args.per_page or 8
   local saves_object = callback_args.ui
   local saves_wrap = saves_object.parent
   if not saves_wrap or not saves_wrap.config or not saves_wrap.config.object then return end

   local entries = args._entries or _get_displayed_entries()
   local total_pages = math.max(1, math.ceil(#entries / per_page))
   local page = _clamp_page(args.to_key, total_pages)

   if REWINDER.ensure_meta_window_for_page and not REWINDER._filter_active then
      REWINDER.ensure_meta_window_for_page(page, per_page, 4)
   end

   local options = args._page_numbers or args.cycle_config.options or {}
   if #options ~= total_pages then
      options = _build_page_numbers(total_pages)
      if REWINDER._saves_ui_refs then
         REWINDER._saves_ui_refs.page_numbers = options
      end
   end
   args.cycle_config.options = options

   local total = #options
   _log_ui_action(string.format("page %d/%d", page, total > 0 and total or 1))

   saves_wrap.config.object:remove()
   saves_wrap.config.object = UIBox({
      definition = REWINDER.get_saves_page({
         entries = entries,
         per_page = per_page,
         page_num = page,
      }),
      config = { parent = saves_wrap, type = "cm" },
   })
   saves_wrap.UIBox:recalculate()

   local new_val = args.cycle_config.options and args.cycle_config.options[page] or nil

   local cycle_node = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID("rewinder_page_cycle")
   local cycle_args = nil

   if cycle_node and cycle_node.children then
      local function find_dynatext_ref(nodes)
         if not nodes then return end
         for _, child in ipairs(nodes) do
            if child and child.config and child.config.object then
               local obj = child.config.object
               if obj.config and obj.config.string and obj.config.string[1] and
                  obj.config.string[1].ref_value == "current_option_val" then
                  cycle_args = obj.config.string[1].ref_table
                  return
               end
            end
            if child and child.children then
               find_dynatext_ref(child.children)
               if cycle_args then return end
            end
         end
      end
      find_dynatext_ref(cycle_node.children)
   end

   if cycle_args and cycle_args ~= args.cycle_config then
      cycle_args.options = args.cycle_config.options
      cycle_args.current_option = page
      if new_val then cycle_args.current_option_val = new_val end
   end

   args.cycle_config.opt_args.entries = entries
   args.cycle_config.current_option = page
   if new_val then args.cycle_config.current_option_val = new_val end

   if REWINDER._saves_ui_refs then
      REWINDER._saves_ui_refs.saves_box = saves_wrap.config.object
      REWINDER._saves_ui_refs.entries = entries
      if REWINDER._saves_ui_refs.cycle_config then
         REWINDER._saves_ui_refs.cycle_config.options = args.cycle_config.options
         REWINDER._saves_ui_refs.cycle_config.current_option = page
         if new_val then REWINDER._saves_ui_refs.cycle_config.current_option_val = new_val end
      end
   end

   _update_mode_button_labels()

   if cycle_node and cycle_node.UIBox then
      cycle_node.UIBox:recalculate()
   end
end
