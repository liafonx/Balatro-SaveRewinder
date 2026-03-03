--- Save Rewinder - UI/ButtonCallbacks.lua
--
-- Public callback handlers. Heavy helper logic lives in UIButtonCallbackHelpers.lua.

if not REWINDER then REWINDER = {} end

REWINDER._filter_active = REWINDER._filter_active or false
REWINDER._mark_active = REWINDER._mark_active or false
REWINDER._rename_active = REWINDER._rename_active or false
REWINDER._rename_editing_file = REWINDER._rename_editing_file or nil
REWINDER._rename_input_ref = REWINDER._rename_input_ref or nil
REWINDER._rename_pending = REWINDER._rename_pending or {}
REWINDER._rename_pending_clear = REWINDER._rename_pending_clear or {}
REWINDER._export_active       = REWINDER._export_active       or false
REWINDER._export_selection    = REWINDER._export_selection    or {}

local UIShared = require("UIShared")
local SaveListSync = require("SaveListSync")
local Helpers = require("UIButtonCallbackHelpers")
local ExportService = require("ExportService")
local KeySaves = Helpers.KeySaves
local log = Helpers.log

Helpers.bootstrap()
REWINDER._saves_open_sync = REWINDER._saves_open_sync or nil

local function _rewinder_queue_depth()
   local SM = REWINDER and REWINDER._SaveManager
   if not (SM and SM.rewinder_queue_depth) then return 0 end
   return tonumber(SM.rewinder_queue_depth()) or 0
end

local function _is_saves_overlay_open()
   return UIShared.is_saves_overlay_open()
end

local function _open_saves_overlay(definition, action_label, loading_mode)
   G.FUNCS.overlay_menu({ definition = definition })

   Helpers.update_mode_button_labels()
   if not loading_mode then
      Helpers.refresh_pending_badges()
   end
   Helpers.update_paging_arrow_visuals((REWINDER._saves_ui_refs and REWINDER._saves_ui_refs.page_numbers and #REWINDER._saves_ui_refs.page_numbers) or 1)
   if loading_mode then
      Helpers.log_ui(action_label or "opened")
      return
   end
   local start, finish, size = Helpers.recenter_meta_on_open()
   Helpers.log_ui(action_label or "opened", start, finish, size)
end

local function _swap_overlay_without_animation(definition)
   if not (G and UIBox and G.ROOM_ATTACH) then return false end
   if G.OVERLAY_MENU then
      G.OVERLAY_MENU:remove()
   end

   G.OVERLAY_MENU = UIBox({
      definition = definition,
      config = {
         align = "cm",
         offset = { x = 0, y = 0 },
         major = G.ROOM_ATTACH,
         bond = "Weak",
      },
   })

   if G.OVERLAY_MENU and G.OVERLAY_MENU.alignment then
      G.OVERLAY_MENU.alignment.offset.y = 0
   end
   if G.OVERLAY_MENU and G.OVERLAY_MENU.align_to_major then
      G.OVERLAY_MENU:align_to_major()
   end
   return G.OVERLAY_MENU ~= nil
end

local function _rebuild_saves_overlay_after_loading(action_label)
   if not _is_saves_overlay_open() then return end
   local definition = G.UIDEF.rewinder_saves()
   local swapped = _swap_overlay_without_animation(definition)
   if not swapped then
      _open_saves_overlay(definition, action_label or "opened (sync complete)", false)
   else
      Helpers.update_mode_button_labels()
      Helpers.update_paging_arrow_visuals((REWINDER._saves_ui_refs and REWINDER._saves_ui_refs.page_numbers and #REWINDER._saves_ui_refs.page_numbers) or 1)
      local start, finish, size = Helpers.recenter_meta_on_open()
      Helpers.log_ui(action_label or "opened (sync complete)", start, finish, size)
   end
   UIShared.run_after_frame(Helpers.refresh_pending_badges)
   UIShared.run_after_frame(Helpers.snap_saves_focus_to_current)
end

local function _start_saves_open_sync(queue_depth)
   return SaveListSync.start(queue_depth, function()
      _rebuild_saves_overlay_after_loading("opened (sync complete)")
   end)
end

local function _update_path_ref(path_ref, text)
   if not path_ref then return end
   path_ref.full_text = text
   local split = REWINDER and REWINDER.split_export_dir_display
   if type(split) == "function" then
      path_ref.text, path_ref.suffix_text = split(text)
   else
      local fmt = REWINDER and REWINDER.format_export_dir_display
      path_ref.text = (type(fmt) == "function") and fmt(text) or text
      path_ref.suffix_text = ""
   end
end

local function _load_save_file(file)
   if REWINDER and REWINDER._SaveManager and REWINDER._SaveManager._set_cache_current_file then
      REWINDER._SaveManager._set_cache_current_file(file)
   end

   if REWINDER and REWINDER._SaveManager then
      local idx = REWINDER._SaveManager.get_index_by_file and REWINDER._SaveManager.get_index_by_file(file)
      if idx then
         if REWINDER.set_pending_index then
            REWINDER.set_pending_index(idx)
         else
            REWINDER._SaveManager.pending_index = idx
         end
      end
   end

   REWINDER.load_and_start_from_file(file)
end

function G.FUNCS.rewinder_save_close(e)
   SaveListSync.cancel()
   Helpers.reset_key_save_state(true, true)
   Helpers.reset_export_state()
   if REWINDER and REWINDER._SaveManager and REWINDER._SaveManager.set_overlay_open then
      REWINDER._SaveManager.set_overlay_open(false)
   end
   REWINDER._saves_ui_refs = nil
   local start, finish, size = Helpers.recenter_meta_on_close()
   Helpers.log_ui("closed", start, finish, size)
   if G and G.FUNCS and G.FUNCS._rewinder_exit_overlay_menu then
      return G.FUNCS._rewinder_exit_overlay_menu(e)
   end
   if G and G.FUNCS and G.FUNCS.exit_overlay_menu then
      return G.FUNCS.exit_overlay_menu(e)
   end
end

function G.FUNCS.rewinder_save_open(e)
   if not G.FUNCS or not G.FUNCS.overlay_menu then return end
   Helpers.ensure_exit_overlay_wrapped()
   local SM = REWINDER and REWINDER._SaveManager
   if SM and SM.set_overlay_open then
      SM.set_overlay_open(true)
   end

   local queue_depth = _rewinder_queue_depth()
   local should_defer_entries = queue_depth > 0 and SM and SM.flush_all_pending_rewinder
   if should_defer_entries then
      local loading_message = UIShared.loc("rewinder_syncing_saves", "Syncing pending saves...")
      local loading_detail = string.format(
         UIShared.loc("rewinder_syncing_saves_detail", "Queued saves: %d"),
         queue_depth
      )

      _open_saves_overlay(
         G.UIDEF.rewinder_saves({
            loading_state = {
               queued = queue_depth,
               message = loading_message,
               detail = loading_detail,
            },
         }),
         "opened (sync pending)",
         true
      )
      if not _start_saves_open_sync(queue_depth) then
         if SM and SM.flush_all_pending_rewinder then
            SM.flush_all_pending_rewinder("pre_overlay_open_fallback")
         end
         _rebuild_saves_overlay_after_loading("opened (sync fallback)")
      end
      return
   end

   _open_saves_overlay(G.UIDEF.rewinder_saves(), "opened")
   UIShared.run_after_frame(Helpers.refresh_pending_badges)
   UIShared.run_after_frame(Helpers.snap_saves_focus_to_current)
end

function G.FUNCS.rewinder_save_jump_to_current(e)
   local refs = REWINDER._saves_ui_refs
   if not refs or not refs.saves_box then return end

   Helpers.log_ui("jump to current")

   Helpers.get_displayed_entries()
   local per_page = refs.per_page or 8
   local idx = REWINDER.find_current_index and REWINDER.find_current_index() or nil
   if REWINDER._filter_active and idx then
      idx = REWINDER._key_save_reverse_map and REWINDER._key_save_reverse_map[idx] or nil
   end

   local target_page = 1
   if idx then
      target_page = math.ceil(idx / per_page)
   end

   Helpers.refresh_saves_view(target_page)
   UIShared.run_after_frame(Helpers.snap_saves_focus_to_current)
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
   local entries = Helpers.get_displayed_entries()
   local total_pages = math.max(1, math.ceil(#entries / per_page))
   local current_page = refs.cycle_config and refs.cycle_config.current_option or 1

   local target_page = current_page + dir
   if target_page < 1 then
      target_page = total_pages
   elseif target_page > total_pages then
      target_page = 1
   end

   Helpers.refresh_saves_view(target_page)
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

   Helpers.refresh_saves_if_open(1)
end

function G.FUNCS.rewinder_save_delete_all(e)
   if REWINDER and REWINDER.clear_all_saves then
      REWINDER.clear_all_saves()
   end
   Helpers.log_ui("deleted all saves")
   Helpers.refresh_saves_if_open(1)
end

function G.FUNCS.rewinder_save_restore(e)
   if not e or not e.config or not e.config.ref_table then return end
   local file = e.config.ref_table.file
   if not file then return end

   if REWINDER._rename_active then
      if REWINDER._rename_editing_file == file and REWINDER._rename_input_ref then
         Helpers.store_rename_pending(file, REWINDER._rename_input_ref.text)
         REWINDER._rename_editing_file = nil
         REWINDER._rename_input_ref = nil
         Helpers.refresh_saves_view(nil)
         return
      end

      if REWINDER._rename_editing_file and
         REWINDER._rename_editing_file ~= file and
         REWINDER._rename_input_ref then
         Helpers.store_rename_pending(REWINDER._rename_editing_file, REWINDER._rename_input_ref.text)
      end

      REWINDER._rename_editing_file = file
      local pending = REWINDER._rename_pending[file]
      local pending_clear = REWINDER._rename_pending_clear and REWINDER._rename_pending_clear[file]
      if pending_clear then
         REWINDER._rename_input_ref = { text = "" }
      elseif pending ~= nil then
         REWINDER._rename_input_ref = { text = pending }
      else
         local current_name = REWINDER.get_custom_state_name and REWINDER.get_custom_state_name(file) or nil
         REWINDER._rename_input_ref = { text = current_name or "" }
      end

      Helpers.refresh_saves_view(nil)
      UIShared.run_after_frame(Helpers.focus_rename_text_input)
      return
   end

   local desc = (REWINDER.describe_save and REWINDER.describe_save({ file = file })) or "save"
   Helpers.log_ui("restore -> " .. desc)
   _load_save_file(file)
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
   Helpers.refresh_saves_view(nil)
end

function G.FUNCS.rewinder_btn_mark_keys(e)
   if not REWINDER._mark_active and REWINDER._rename_active then
      Helpers.reset_rename_state({ reason = "mark mode switch" })
   end
   if not REWINDER._mark_active and REWINDER._export_active then
      Helpers.reset_export_state()
   end

   if REWINDER._mark_active then
      local success, fail = KeySaves.commit_pending()
      REWINDER._mark_active = false
      if fail > 0 then
         log("warning", string.format("Key-save commit partial failure: success=%d fail=%d", success, fail))
      else
         log("info", string.format("Key-save commit complete: %d", success))
      end
      Helpers.refresh_saves_view(nil)
      UIShared.run_after_frame(Helpers.update_mode_button_labels)
      return
   end

   REWINDER._mark_active = true
   log("info", "Key-save mark mode enabled")
   Helpers.refresh_saves_view(nil)
   UIShared.run_after_frame(Helpers.update_mode_button_labels)
end

function G.FUNCS.rewinder_btn_filter_keys(e)
   if REWINDER._rename_active then
      Helpers.reset_rename_state({ reason = "filter toggle" })
   end

   REWINDER._filter_active = not REWINDER._filter_active
   local per_page = (REWINDER._saves_ui_refs and REWINDER._saves_ui_refs.per_page) or 8
   local target_page = Helpers.page_with_current_save(per_page)
   log("info", string.format(
      "Key-save filter mode %s -> target page %d",
      (REWINDER._filter_active and "enabled" or "disabled"),
      target_page
   ))
   Helpers.refresh_saves_view(target_page)
   UIShared.run_after_frame(Helpers.update_mode_button_labels)
end

function G.FUNCS.rewinder_btn_toggle_rename(e)
   if not e or not e.config or not e.config.ref_table then return end
   local mode = e.config.ref_table.mode
   if mode ~= "rename" then return end

   if not REWINDER._rename_active and REWINDER._mark_active then
      log("warning", "Cannot enter rename mode while mark mode active")
      return
   end

   if REWINDER._rename_active then
      Helpers.snapshot_active_rename_edit()
      local committed = Helpers.commit_pending_rename_drafts()
      Helpers.reset_rename_state()
      log("info", "Rename committed entries: " .. tostring(committed))
      log("info", "Rename mode disabled")
   else
      if REWINDER._export_active then
         Helpers.reset_export_state()
      end
      REWINDER._rename_active = true
      Helpers.reset_rename_state({ keep_active = true })
      log("info", "Rename mode enabled")
   end

   Helpers.refresh_saves_view(nil)
   UIShared.run_after_frame(Helpers.update_mode_button_labels)
end

function G.FUNCS.rewinder_save_update_page(args)
   if REWINDER and REWINDER._saves_ui_refs and REWINDER._saves_ui_refs.loading_state then return end
   if not args or not args.cycle_config then return end

   local callback_args = args.cycle_config.opt_args
   if not callback_args or not callback_args.ui then return end

   local previous_page = args.cycle_config.current_option
   local per_page = callback_args.per_page or 8
   local saves_object = callback_args.ui
   local saves_wrap = saves_object.parent
   if not saves_wrap or not saves_wrap.config or not saves_wrap.config.object then return end

   local entries = args._entries or Helpers.get_displayed_entries()
   local total_pages = math.max(1, math.ceil(#entries / per_page))
   local page = UIShared.clamp_page(args.to_key, total_pages)
   if REWINDER._rename_active and previous_page and previous_page ~= page and
      (REWINDER._rename_editing_file or Helpers.rename_has_pending_drafts()) then
      Helpers.reset_rename_state({ reason = "page change", log_level = "debug" })
   end

   if REWINDER.ensure_meta_window_for_page and not REWINDER._filter_active then
      REWINDER.ensure_meta_window_for_page(page, per_page, 4)
   end

   local options = args._page_numbers or args.cycle_config.options or {}
   if #options ~= total_pages then
      options = UIShared.build_page_numbers(total_pages)
      if REWINDER._saves_ui_refs then
         REWINDER._saves_ui_refs.page_numbers = options
      end
   end
   args.cycle_config.options = options

   local total = #options
   Helpers.log_ui(string.format("page %d/%d", page, total > 0 and total or 1))

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

   Helpers.update_paging_arrow_visuals(total_pages)
   Helpers.update_mode_button_labels()
   Helpers.refresh_pending_row_badges(entries, page, per_page)

   if cycle_node and cycle_node.UIBox then
      cycle_node.UIBox:recalculate()
   end
end

function G.FUNCS.rewinder_game_over_rewind(e)
   if not REWINDER then return end
   local entries = REWINDER.get_save_files and REWINDER.get_save_files()
   if not entries or #entries == 0 then
      log("warning", "Game over rewind: no saves available")
      return
   end

   local file = entries[1][REWINDER.ENTRY_FILE or 1]
   if not file then return end

   log("info", "Game over: loading latest save -> " .. tostring(file))
   _load_save_file(file)
end

-- Toggle export mode on/off, or commit the current selection.
function G.FUNCS.rewinder_btn_toggle_export(e)
   -- Entering export resets other exclusive modes
   if REWINDER._mark_active then
      Helpers.reset_key_save_state(true, true)
   end
   if REWINDER._rename_active then
      Helpers.reset_rename_state({ reason = "export mode" })
   end

   if REWINDER._export_active then
      -- No selection: leave export mode immediately
      if not next(REWINDER._export_selection) then
         Helpers.reset_export_state()
         _rebuild_saves_overlay_after_loading("export_exit")
         return
      end
      -- Commit export
      local ok, fail_count = ExportService.export_selected(REWINDER._export_selection)
      if fail_count > 0 then
         log("warning", string.format("Export complete with failures: ok=%d fail=%d", ok, fail_count))
      else
         log("info", string.format("Export complete: ok=%d", ok))
      end
      Helpers.reset_export_state()
      _rebuild_saves_overlay_after_loading("export_complete")
   else
      -- Enter export mode
      REWINDER._export_active    = true
      REWINDER._export_selection = {}
      _rebuild_saves_overlay_after_loading("export_enter")
   end
end

-- Toggle selection of a single save row in export mode.
function G.FUNCS.rewinder_save_toggle_export_select(e)
   if not REWINDER._export_active then return end
   if not e or not e.config or not e.config.ref_table then return end
   local file = e.config.ref_table.file
   if not file then return end
   if REWINDER._export_selection[file] then
      REWINDER._export_selection[file] = nil
   else
      REWINDER._export_selection[file] = true
   end
   Helpers.refresh_saves_view(nil)
end

-- Paste clipboard text as the export directory path.
function G.FUNCS.rewinder_export_paste_dir(e)
   if not (e and e.config and e.config.ref_table) then return end
   local text = love.system.getClipboardText()
   if type(text) ~= "string" then return end
   text = text:match("^%s*(.-)%s*$") or text
   if text == "" then return end
   REWINDER.config.export_dir = text
   _update_path_ref(e.config.ref_table.path_ref, ExportService.get_export_dir())
end

-- Reset the export directory to the computed default.
function G.FUNCS.rewinder_export_reset_dir(e)
   if not (e and e.config and e.config.ref_table) then return end
   REWINDER.config.export_dir = ""
   _update_path_ref(e.config.ref_table.path_ref, ExportService.get_export_dir())
end

function G.FUNCS.rewinder_config_change(args)
   args = args or {}
   if args.cycle_config and args.cycle_config.ref_table and args.cycle_config.ref_value then
      local ref_value = args.cycle_config.ref_value
      args.cycle_config.ref_table[ref_value] = args.to_key

      if ref_value == "keep_antes" then
         local SM = REWINDER and REWINDER._SaveManager
         if SM and SM.apply_retention_policy_now then
            SM.apply_retention_policy_now()
         end
      end
   end
end

return {}
