--- Fast Save Loader - UI/ButtonCallbacks.lua
--
-- Button callbacks for the saves UI.

if not LOADER then LOADER = {} end

local function _snap_saves_focus_to_current()
   if not (G and G.CONTROLLER and LOADER and LOADER._saves_ui_refs and LOADER._saves_ui_refs.saves_box) then return end

   local entries = LOADER.get_save_files and LOADER.get_save_files() or {}
   local idx = nil
   if LOADER._SaveManager and LOADER._SaveManager.get_index_by_file and LOADER._SaveManager._last_loaded_file then
      idx = LOADER._SaveManager.get_index_by_file(LOADER._SaveManager._last_loaded_file)
   end
   if not idx then
      for i, entry in ipairs(entries) do
         if entry and entry[LOADER.ENTRY_IS_CURRENT] == true then
            idx = i
            break
         end
      end
   end
   if not idx then return end

   local node = LOADER._saves_ui_refs.saves_box:get_UIE_by_ID("fastsl_save_entry_" .. tostring(idx))
   if node then
      G.CONTROLLER:snap_to({ node = node })
      if G.CONTROLLER.update_cursor then
         G.CONTROLLER:update_cursor()
      end
   end
end

function G.FUNCS.loader_save_open(e)
   if not G.FUNCS or not G.FUNCS.overlay_menu then return end
   
   -- Cache flags are updated automatically by get_save_files() in fast_loader_saves()
   G.FUNCS.overlay_menu({
      definition = G.UIDEF.fast_loader_saves(),
   })
   LOADER.saves_open = true

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

function G.FUNCS.loader_save_jump_to_current(e)
   LOADER.debug_log("UI", "jump_to_current: Starting")
   local refs = LOADER._saves_ui_refs
   if not refs or not refs.saves_box then
      LOADER.debug_log("UI", "jump_to_current: No stored refs")
      return
   end
   
   -- Refresh entries to ensure current flags are up to date
   local entries = LOADER.get_save_files()
   local per_page = refs.per_page or 8
   local target_page = 1
   
   for i, entry in ipairs(entries) do
      if entry and entry[LOADER.ENTRY_IS_CURRENT] == true then
         target_page = math.ceil(i / per_page)
         LOADER.debug_log("UI", string.format("jump_to_current: Found current at index %d, target_page=%d", i, target_page))
         break
      end
   end
   
   -- Use stored cycle_config or reconstruct it
   local cycle_config = refs.cycle_config
   if not cycle_config then
      -- Reconstruct cycle_config from stored refs
      cycle_config = {
         options = refs.page_numbers or {},
         current_option = target_page,
         opt_callback = "loader_save_update_page",
         opt_args = { ui = refs.saves_box, per_page = per_page, entries = entries },
      }
   end
   
   -- Update the opt_args with fresh entries
   if cycle_config.opt_args then
      cycle_config.opt_args.entries = entries
      cycle_config.opt_args.ui = refs.saves_box
   end
   
   LOADER.debug_log("UI", string.format("jump_to_current: Calling update_page with to_key=%d", target_page))
   G.FUNCS.loader_save_update_page({
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

function G.FUNCS.loader_save_reload(e)
   if LOADER and LOADER.preload_all_metadata then
      LOADER.preload_all_metadata(true) -- Force a full reload + meta preload
   elseif LOADER and LOADER.get_save_files then
      LOADER.get_save_files(true) -- Force a reload from the filesystem
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
            definition = G.UIDEF.fast_loader_saves(),
         })
         LOADER.saves_open = true
         return true
      end
   }))
end

function G.FUNCS.loader_save_delete_all(e)
   if LOADER and LOADER.clear_all_saves then
      LOADER.clear_all_saves()
   end
   G.FUNCS.loader_save_reload(e)
end

function G.FUNCS.loader_save_restore(e)
   if not e or not e.config or not e.config.ref_table then return end
   local file = e.config.ref_table.file
   if not file then return end

   -- Update cache flags immediately when clicking (before loading)
   if LOADER and LOADER._SaveManager and LOADER._SaveManager._set_cache_current_file then
      LOADER.debug_log("UI", "restore click: " .. file)
      LOADER._SaveManager._set_cache_current_file(file)
   end

   -- Set pending_index so that start_from_file can use it for timeline consistency
   if LOADER and LOADER.get_save_files then
      local idx = nil
      if LOADER._SaveManager and LOADER._SaveManager.get_index_by_file then
         idx = LOADER._SaveManager.get_index_by_file(file)
      end
      if not idx then
         local entries = LOADER.get_save_files()
         for i, entry in ipairs(entries) do
            if entry[LOADER.ENTRY_FILE] == file then
               idx = i
               break
            end
         end
      end
      if idx then
         -- Use setter or direct module access since scalars are copied by value
         if LOADER.set_pending_index then
            LOADER.set_pending_index(idx)
         elseif LOADER._SaveManager then
            LOADER._SaveManager.pending_index = idx
         end
      end
   end

   local label = file
   if LOADER and LOADER.describe_save then
     label = LOADER.describe_save({ file = file })
   end
   if LOADER and LOADER.debug_log then
      LOADER.debug_log("UI", "restore -> loading " .. label)
   end
   LOADER.load_and_start_from_file(file)
end

function G.FUNCS.loader_save_update_page(args)
   if not args or not args.cycle_config then
      LOADER.debug_log("UI", "update_page: No args or cycle_config")
      return
   end
   
   LOADER.debug_log("UI", string.format("update_page: Starting, to_key=%s, current_option before=%s", 
      tostring(args.to_key), tostring(args.cycle_config.current_option)))
   
   local callback_args = args.cycle_config.opt_args

   local saves_object = callback_args.ui
   local saves_wrap = saves_object.parent

   local entries = LOADER.get_save_files()

   saves_wrap.config.object:remove()
   saves_wrap.config.object = UIBox({
      definition = LOADER.get_saves_page({
         entries = entries,
         per_page = callback_args.per_page,
         page_num = args.to_key,
      }),
      config = { parent = saves_wrap, type = "cm" },
   })
   saves_wrap.UIBox:recalculate()
   
   -- Update stored references
   if LOADER._saves_ui_refs then
      LOADER._saves_ui_refs.saves_box = saves_wrap.config.object
      LOADER._saves_ui_refs.entries = entries
      -- Update cycle_config reference if it exists
      if LOADER._saves_ui_refs.cycle_config then
         LOADER._saves_ui_refs.cycle_config.current_option = args.to_key
         if args.cycle_config.options and args.cycle_config.options[args.to_key] then
            LOADER._saves_ui_refs.cycle_config.current_option_val = args.cycle_config.options[args.to_key]
         end
      end
   end
   
   -- Update cycle config - this is what makes the cycle display update
   local old_option = args.cycle_config.current_option
   args.cycle_config.current_option = args.to_key
   if args.cycle_config.options and args.cycle_config.options[args.to_key] then
      args.cycle_config.current_option_val = args.cycle_config.options[args.to_key]
      LOADER.debug_log("UI", string.format("update_page: Updated current_option from %s to %s, current_option_val=%s", 
         tostring(old_option), tostring(args.to_key), tostring(args.cycle_config.current_option_val)))
   else
      LOADER.debug_log("UI", string.format("update_page: Updated current_option from %s to %s, but no option value found", 
         tostring(old_option), tostring(args.to_key)))
   end
   
   -- Force recalculation of the cycle's UIBox to update the display
   -- Find the cycle node in the parent's siblings and update its config directly
   local parent = saves_wrap.parent
   if parent and parent.children then
      for _, sibling in ipairs(parent.children) do
         if sibling and sibling.config and sibling.config.cycle_config then
            local sibling_cycle_config = sibling.config.cycle_config
            if sibling_cycle_config.opt_callback == "loader_save_update_page" then
               -- Update the sibling's cycle_config directly
               sibling_cycle_config.current_option = args.to_key
               if sibling_cycle_config.options and sibling_cycle_config.options[args.to_key] then
                  sibling_cycle_config.current_option_val = sibling_cycle_config.options[args.to_key]
               end
               LOADER.debug_log("UI", string.format("update_page: Updated sibling cycle_config, current_option=%s, current_option_val=%s", 
                  tostring(sibling_cycle_config.current_option), tostring(sibling_cycle_config.current_option_val)))
               if sibling.UIBox then
                  sibling.UIBox:recalculate()
                  LOADER.debug_log("UI", "update_page: Cycle UIBox recalculated")
               else
                  LOADER.debug_log("UI", "update_page: Cycle sibling has no UIBox")
               end
               break
            end
         end
      end
   else
      LOADER.debug_log("UI", "update_page: No parent or children to find cycle")
   end
end

-- Callback for the "Delete All Saves" button in the main mod config menu.
function G.FUNCS.fastsl_save_delete_all(e)
   if LOADER and LOADER.clear_all_saves then
      LOADER.clear_all_saves()
   end
   -- Show a simple confirmation toast
   if G.FUNCS.show_tarot_reward then
      G.FUNCS.show_tarot_reward({
         config = { text = (localize and localize("fastsl_all_saves_deleted")) or "All saves deleted" }
      })
   end
end
