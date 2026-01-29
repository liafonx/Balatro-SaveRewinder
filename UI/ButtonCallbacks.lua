--- Save Rewinder - UI/ButtonCallbacks.lua
--
-- Button callbacks for the saves UI.
if not REWINDER then REWINDER = {} end
local Logger = require("Logger")
local log = Logger.create("UI")

local function _log_ui(action, start, finish, size)
   if start and finish then
      log("step", string.format("Saves UI: %s (meta %d-%d/%d)", action, start, finish, size))
   else
      log("step", "Saves UI: " .. action)
   end
end

local function _log_ui_action(action)
   log("step", "Saves UI: " .. action)
end

local function _recenter_meta_on_open()
   if not (REWINDER and REWINDER._SaveManager and REWINDER._SaveManager.ensure_meta_window_for_page and REWINDER._saves_ui_refs) then
      return nil, nil, nil
   end
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

function G.FUNCS.rewinder_save_close(e)
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
local function _snap_saves_focus_to_current()
   if not (G and G.CONTROLLER and REWINDER and REWINDER._saves_ui_refs and REWINDER._saves_ui_refs.saves_box) then return end
   local idx = REWINDER.find_current_index and REWINDER.find_current_index()
   if not idx then return end
   local node = REWINDER._saves_ui_refs.saves_box:get_UIE_by_ID("rewinder_save_entry_" .. tostring(idx))
   if node then
      G.CONTROLLER:snap_to({ node = node })
      if G.CONTROLLER.update_cursor then
         G.CONTROLLER:update_cursor()
      end
   end
end
function G.FUNCS.rewinder_save_open(e)
   if not G.FUNCS or not G.FUNCS.overlay_menu then return end
   _ensure_exit_overlay_wrapped()
   if REWINDER and REWINDER._SaveManager and REWINDER._SaveManager.set_overlay_open then
      REWINDER._SaveManager.set_overlay_open(true)
   end
   
   -- Cache flags are updated automatically by get_save_files() in rewinder_saves()
   G.FUNCS.overlay_menu({
      definition = G.UIDEF.rewinder_saves(),
   })
   local start, finish, size = _recenter_meta_on_open()
   _log_ui("opened", start, finish, size)
   if G and G.E_MANAGER and Event then
      G.E_MANAGER:add_event(Event({
         trigger = "after",
         delay = 0,
         func = function()
            _snap_saves_focus_to_current()
            return true
         end,
      }))
   else
      _snap_saves_focus_to_current()
   end
end
function G.FUNCS.rewinder_save_jump_to_current(e)
   local refs = REWINDER._saves_ui_refs
   if not refs or not refs.saves_box then return end
   _log_ui_action("jump to current")
   
   -- Refresh entries to ensure current flags are up to date
   local entries = REWINDER.get_save_files()
   local per_page = refs.per_page or 8
   local target_page = 1
   
   local idx = REWINDER.find_current_index and REWINDER.find_current_index()
   if idx then
      target_page = math.ceil(idx / per_page)
   end
   
   -- Use stored cycle_config or reconstruct it
   local cycle_config = refs.cycle_config
   if not cycle_config then
      cycle_config = {
         options = refs.page_numbers or {},
         current_option = target_page,
         opt_callback = "rewinder_save_update_page",
         opt_args = { ui = refs.saves_box, per_page = per_page, entries = entries },
      }
   end
   
   -- Update the opt_args with fresh entries
   if cycle_config.opt_args then
      cycle_config.opt_args.entries = entries
      cycle_config.opt_args.ui = refs.saves_box
   end
   
   G.FUNCS.rewinder_save_update_page({
      cycle_config = cycle_config,
      to_key = target_page,
   })
   if G and G.E_MANAGER and Event then
      G.E_MANAGER:add_event(Event({
         trigger = "after",
         delay = 0,
         func = function()
            _snap_saves_focus_to_current()
            return true
         end,
      }))
   else
      _snap_saves_focus_to_current()
   end
end
function REWINDER.rewinder_save_jump_to_current()
   if G.FUNCS.rewinder_save_jump_to_current then
      G.FUNCS.rewinder_save_jump_to_current()
   end
end

-- Helper for Keybinds.lua to access page navigation
local function _navigate_page(dir)
   local refs = REWINDER._saves_ui_refs
   if not refs or not refs.saves_box then return end
   
   local current_page = refs.cycle_config and refs.cycle_config.current_option or 1
   local total_pages = refs.cycle_config and refs.cycle_config.options and #refs.cycle_config.options or 1
   local per_page = refs.per_page or 8
   local entries = REWINDER.get_save_files()
   
   local target_page = current_page + dir
   if target_page < 1 then target_page = total_pages
   elseif target_page > total_pages then target_page = 1 end
   
    -- Use stored cycle_config or reconstruct it
   local cycle_config = refs.cycle_config
   if not cycle_config then
      cycle_config = {
         options = refs.page_numbers or {},
         current_option = current_page,
         opt_callback = "rewinder_save_update_page",
         opt_args = { ui = refs.saves_box, per_page = per_page, entries = entries },
      }
   end
   
    -- Update the opt_args with fresh entries
   if cycle_config.opt_args then
      cycle_config.opt_args.entries = entries
      cycle_config.opt_args.ui = refs.saves_box
   end
   
   G.FUNCS.rewinder_save_update_page({
      cycle_config = cycle_config,
      to_key = target_page,
   })
end

function REWINDER.rewinder_prev_page()
   _navigate_page(-1)
end

function REWINDER.rewinder_next_page()
   _navigate_page(1)
end
function G.FUNCS.rewinder_save_reload(e)
   if REWINDER and REWINDER.preload_all_metadata then
      REWINDER.preload_all_metadata(true) -- Force a full reload + meta window warm
   elseif REWINDER and REWINDER.get_save_files then
      REWINDER.get_save_files(true) -- Force a reload from the filesystem
   end
   if not G.FUNCS or not G.FUNCS.exit_overlay_menu or not G.FUNCS.overlay_menu or not G.E_MANAGER then return end
   G.FUNCS.exit_overlay_menu()
   -- Defer re-opening the menu to the next frame.
   -- This prevents an infinite loop where the mouse click that triggered the delete
   -- is immediately processed again by the newly created UI.
   G.E_MANAGER:add_event(Event({
      trigger = 'after',
      delay = 0,
      func = function()
         G.FUNCS.overlay_menu({
            definition = G.UIDEF.rewinder_saves(),
         })
         if REWINDER and REWINDER._SaveManager and REWINDER._SaveManager.set_overlay_open then
            REWINDER._SaveManager.set_overlay_open(true)
         end
         return true
      end
   }))
end
function G.FUNCS.rewinder_save_delete_all(e)
   if REWINDER and REWINDER.clear_all_saves then
      REWINDER.clear_all_saves()
   end
   _log_ui_action("deleted all saves")
   G.FUNCS.rewinder_save_reload(e)
end
function G.FUNCS.rewinder_save_restore(e)
   if not e or not e.config or not e.config.ref_table then return end
   local file = e.config.ref_table.file
   if not file then return end
   local desc = (REWINDER.describe_save and REWINDER.describe_save({ file = file })) or "save"
   _log_ui_action("restore -> " .. desc)
   -- Update cache flags immediately when clicking (before loading)
   if REWINDER and REWINDER._SaveManager and REWINDER._SaveManager._set_cache_current_file then
      REWINDER._SaveManager._set_cache_current_file(file)
   end
   -- Set pending_index so that start_from_file can use it for timeline consistency
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
function G.FUNCS.rewinder_save_update_page(args)
   if not args or not args.cycle_config then return end
   
   local callback_args = args.cycle_config.opt_args
   local saves_object = callback_args.ui
   local saves_wrap = saves_object.parent
   local entries = REWINDER.get_save_files()
   if REWINDER.ensure_meta_window_for_page then
      REWINDER.ensure_meta_window_for_page(args.to_key, callback_args.per_page, 4)
   end
   local total = args.cycle_config.options and #args.cycle_config.options or 1
   _log_ui_action(string.format("page %d/%d", args.to_key or 1, total))
   saves_wrap.config.object:remove()
   saves_wrap.config.object = UIBox({
      definition = REWINDER.get_saves_page({
         entries = entries,
         per_page = callback_args.per_page,
         page_num = args.to_key,
      }),
      config = { parent = saves_wrap, type = "cm" },
   })
   saves_wrap.UIBox:recalculate()
   
   -- Calculate new values once
   local new_val = args.cycle_config.options and args.cycle_config.options[args.to_key] or nil
   
   -- Find the cycle node and DynaText ref_table (what it actually reads from)
   local cycle_node = G.OVERLAY_MENU and G.OVERLAY_MENU:get_UIE_by_ID("rewinder_page_cycle")
   local cycle_args = nil
   
   if cycle_node and cycle_node.children then
      -- Search for DynaText ref_table (what it reads current_option_val from)
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
   
   -- Update config references (avoid loop if cycle_args == args.cycle_config)
   if cycle_args and cycle_args ~= args.cycle_config then
      -- Different references, update both
      cycle_args.current_option = args.to_key
      if new_val then cycle_args.current_option_val = new_val end
   end
   args.cycle_config.current_option = args.to_key
   if new_val then args.cycle_config.current_option_val = new_val end
   
   -- Update stored references
   if REWINDER._saves_ui_refs then
      REWINDER._saves_ui_refs.saves_box = saves_wrap.config.object
      REWINDER._saves_ui_refs.entries = entries
      if REWINDER._saves_ui_refs.cycle_config then
         REWINDER._saves_ui_refs.cycle_config.current_option = args.to_key
         if new_val then REWINDER._saves_ui_refs.cycle_config.current_option_val = new_val end
      end
   end
   
   -- Force UI recalculation to update display
   if cycle_node and cycle_node.UIBox then
            cycle_node.UIBox:recalculate()
   end
end
