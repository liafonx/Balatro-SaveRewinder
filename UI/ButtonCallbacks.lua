--- Save Rewinder - UI/ButtonCallbacks.lua
--
-- Button callbacks for the saves UI.
if not REWINDER then REWINDER = {} end
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
   
   -- Cache flags are updated automatically by get_save_files() in rewinder_saves()
   G.FUNCS.overlay_menu({
      definition = G.UIDEF.rewinder_saves(),
   })
   REWINDER.saves_open = true
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
   REWINDER.debug_log("UI", "jump_to_current: Starting")
   local refs = REWINDER._saves_ui_refs
   if not refs or not refs.saves_box then
      REWINDER.debug_log("UI", "jump_to_current: No stored refs")
      return
   end
   
   -- Refresh entries to ensure current flags are up to date
   local entries = REWINDER.get_save_files()
   local per_page = refs.per_page or 8
   local target_page = 1
   
   local idx = REWINDER.find_current_index and REWINDER.find_current_index()
   if idx then
      target_page = math.ceil(idx / per_page)
      REWINDER.debug_log("UI", string.format("jump_to_current: Found current at index %d, target_page=%d", idx, target_page))
   end
   
   -- Use stored cycle_config or reconstruct it
   local cycle_config = refs.cycle_config
   if not cycle_config then
      -- Reconstruct cycle_config from stored refs
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
   
   REWINDER.debug_log("UI", string.format("jump_to_current: Calling update_page with to_key=%d", target_page))
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
function G.FUNCS.rewinder_save_reload(e)
   if REWINDER and REWINDER.preload_all_metadata then
      REWINDER.preload_all_metadata(true) -- Force a full reload + meta preload
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
         REWINDER.saves_open = true
         return true
      end
   }))
end
function G.FUNCS.rewinder_save_delete_all(e)
   if REWINDER and REWINDER.clear_all_saves then
      REWINDER.clear_all_saves()
   end
   G.FUNCS.rewinder_save_reload(e)
end
function G.FUNCS.rewinder_save_restore(e)
   if not e or not e.config or not e.config.ref_table then return end
   local file = e.config.ref_table.file
   if not file then return end
   -- Update cache flags immediately when clicking (before loading)
   if REWINDER and REWINDER._SaveManager and REWINDER._SaveManager._set_cache_current_file then
      REWINDER.debug_log("UI", "restore click: " .. file)
      REWINDER._SaveManager._set_cache_current_file(file)
   end
   -- Set pending_index so that start_from_file can use it for timeline consistency
   if REWINDER and REWINDER._SaveManager then
      local idx = REWINDER._SaveManager.get_index_by_file and REWINDER._SaveManager.get_index_by_file(file)
      if idx then
         -- Use setter or direct module access since scalars are copied by value
         if REWINDER.set_pending_index then
            REWINDER.set_pending_index(idx)
         elseif REWINDER._SaveManager then
            REWINDER._SaveManager.pending_index = idx
         end
      end
   end
   local label = file
   if REWINDER and REWINDER.describe_save then
     label = REWINDER.describe_save({ file = file })
   end
   if REWINDER and REWINDER.debug_log then
      REWINDER.debug_log("UI", "restore -> loading " .. label)
   end
   REWINDER.load_and_start_from_file(file)
end
function G.FUNCS.rewinder_save_update_page(args)
   if not args or not args.cycle_config then
      REWINDER.debug_log("UI", "update_page: No args or cycle_config")
      return
   end
   
   REWINDER.debug_log("UI", string.format("update_page: Starting, to_key=%s, current_option before=%s", 
      tostring(args.to_key), tostring(args.cycle_config.current_option)))
   
   local callback_args = args.cycle_config.opt_args
   local saves_object = callback_args.ui
   local saves_wrap = saves_object.parent
   local entries = REWINDER.get_save_files()
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
   
   -- Update stored references
   if REWINDER._saves_ui_refs then
      REWINDER._saves_ui_refs.saves_box = saves_wrap.config.object
      REWINDER._saves_ui_refs.entries = entries
      -- Update cycle_config reference if it exists
      if REWINDER._saves_ui_refs.cycle_config then
         REWINDER._saves_ui_refs.cycle_config.current_option = args.to_key
         if args.cycle_config.options and args.cycle_config.options[args.to_key] then
            REWINDER._saves_ui_refs.cycle_config.current_option_val = args.cycle_config.options[args.to_key]
         end
      end
   end
   
   -- Update cycle config - this is what makes the cycle display update
   local old_option = args.cycle_config.current_option
   args.cycle_config.current_option = args.to_key
   if args.cycle_config.options and args.cycle_config.options[args.to_key] then
      args.cycle_config.current_option_val = args.cycle_config.options[args.to_key]
      REWINDER.debug_log("UI", string.format("update_page: Updated current_option from %s to %s, current_option_val=%s", 
         tostring(old_option), tostring(args.to_key), tostring(args.cycle_config.current_option_val)))
   else
      REWINDER.debug_log("UI", string.format("update_page: Updated current_option from %s to %s, but no option value found", 
         tostring(old_option), tostring(args.to_key)))
   end
   
   -- Force recalculation of the cycle's UIBox to update the display
   -- Find the cycle node in the parent's siblings and update its config directly
   local parent = saves_wrap.parent
   if parent and parent.children then
      for _, sibling in ipairs(parent.children) do
         if sibling and sibling.config and sibling.config.cycle_config then
            local sibling_cycle_config = sibling.config.cycle_config
            if sibling_cycle_config.opt_callback == "rewinder_save_update_page" then
               -- Update the sibling's cycle_config directly
               sibling_cycle_config.current_option = args.to_key
               if sibling_cycle_config.options and sibling_cycle_config.options[args.to_key] then
                  sibling_cycle_config.current_option_val = sibling_cycle_config.options[args.to_key]
               end
               REWINDER.debug_log("UI", string.format("update_page: Updated sibling cycle_config, current_option=%s, current_option_val=%s", 
                  tostring(sibling_cycle_config.current_option), tostring(sibling_cycle_config.current_option_val)))
               if sibling.UIBox then
                  sibling.UIBox:recalculate()
                  REWINDER.debug_log("UI", "update_page: Cycle UIBox recalculated")
               else
                  REWINDER.debug_log("UI", "update_page: Cycle sibling has no UIBox")
               end
               break
            end
         end
      end
   else
      REWINDER.debug_log("UI", "update_page: No parent or children to find cycle")
   end
end