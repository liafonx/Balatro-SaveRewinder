return function(ctx)
   local M = ctx.M
   local S = ctx.S
   local E = ctx.E
   local FileIO = ctx.FileIO
   local Logger = ctx.Logger
   local skip = ctx.skip

   local api = {}

   function M.sync_to_main_save(run_data)
      return FileIO.sync_to_main_save(run_data)
   end

   function M.copy_save_to_main(file)
      return FileIO.copy_save_to_main(file, M.get_save_dir())
   end

   function M.load_save_file(file)
      return FileIO.load_save_file(file, M.get_save_dir())
   end

   function M.reset_for_new_run()
      M.invalidate_async_saves()
      M._pending_skip_reason = nil
      M._loaded_mark_applied = nil
      M._loaded_display_type = nil
      M.current_index = nil
      M._restore_active = nil
      M._last_loaded_file = nil
      M.skip_next_save = false
      M.pending_future_prune_boundary = nil
      M.skipping_pack_open = nil
      M._last_save_sig = nil
      M._last_save_time = nil
      M._last_save_sig_parts = nil
      if M.set_overlay_open then M.set_overlay_open(false) end
      if M.reset_ordinal_state then M.reset_ordinal_state() end
   end

   function M.set_current_file(file, idx)
      if file then
         if idx then
            M.current_index = idx
         else
            local found = M.get_index_by_file and M.get_index_by_file(file)
            if found then M.current_index = found end
         end
      end
      ctx.index.set_cache_current_file(file)
   end

   local function _load_main_save()
      local profile = (G.SETTINGS and G.SETTINGS.profile) or "1"
      local save_path = profile .. "/save.jkr"
      local data = get_compressed(save_path)
      if not data then return nil, "read" end
      local ok, run_data = pcall(STR_UNPACK, data)
      if not ok or not run_data then return nil, "unpack" end
      return run_data
   end

   local function _pre_restore_compat_guard(opts)
      opts = opts or {}
      if not opts.no_wipe then return true end

      if not (DV and DV.PRE and G and G.SETTINGS and G.SETTINGS.DV) then return true end
      if G.SETTINGS.DV.manual_preview ~= true then return true end
      if DV.PRE.previewing ~= true then return true end

      local ok, err = pcall(function()
         if G.HUD and G.HUD.get_UIE_by_ID then
            local score_node = G.HUD:get_UIE_by_ID("dv_pre_score")
            if score_node and score_node.parent and score_node.parent.remove then
               score_node.parent:remove()
            end
         end
         DV.PRE.previewing = false
      end)
      if not ok then
         M.debug_log("warning", "DVPreview guard failed, using safe restore path: " .. tostring(err))
         return false
      end
      return true
   end

   function M.load_and_start_from_file(file, opts)
      opts = opts or {}
      local mark_restore = not opts.skip_restore_identical
      local reason = mark_restore and "restore" or "step"
      ctx.index.process_async_save_results()

      M.get_save_files()
      local entry = ctx.index.get_entry_by_file(file)
      if entry then M.get_save_meta(entry, { force = true }) end

      local idx_from_list = M.get_index_by_file(file)
      if idx_from_list and M.ensure_meta_window then
         M.ensure_meta_window(idx_from_list, M.META_CACHE_BASE_LIMIT)
      end

      if ctx.index.is_async_pending(file) then
         ctx.index.process_async_save_results()
         if ctx.index.is_async_pending(file) then
            M.debug_log("warning", "Save still writing, try again: " .. tostring(file))
            return false
         end
      elseif not ctx.index.is_async_save_ready(file) then
         M.debug_log("warning", "Save file missing or not ready: " .. tostring(file))
         return false
      end

      M._loaded_mark_applied = true
      M._pending_skip_reason = reason
      M._restore_active = (reason == "restore")
      M._last_loaded_file = file
      M.skip_next_save = true
      M._last_save_sig = nil
      M._last_save_time = nil
      M._last_save_sig_parts = nil

      skip.assign_loaded_fields(entry)

      if entry and idx_from_list and idx_from_list > 1 then
         M.pending_future_prune_boundary = entry[E.ENTRY_INDEX]
      else
         M.pending_future_prune_boundary = nil
      end

      if mark_restore and Logger.is_verbose() then
         M.debug_log("info", "Loading " .. M.describe_save({ file = file }))
      end

      M.current_index = M.pending_index or idx_from_list or 1
      M.pending_index = nil
      if REWINDER then REWINDER.saves_open = false end
      M._set_cache_current_file(file)

      if not M.copy_save_to_main(file) then
         M.debug_log("error", "Failed to copy save to save.jkr")
         return false
      end

      G.SAVED_GAME = nil
      local run_data, err = _load_main_save()
      if not run_data then
         if err == "read" then
            M.debug_log("error", "Failed to read save.jkr")
         else
            M.debug_log("error", "Failed to unpack save.jkr")
         end
         return false
      end

      G.SAVED_GAME = run_data
      G.SETTINGS = G.SETTINGS or {}
      G.SETTINGS.current_setup = "Continue"
      run_data._file = file
      G.SAVED_GAME._file = file
      local allow_no_wipe = _pre_restore_compat_guard(opts)

      if opts.no_wipe and allow_no_wipe and G.delete_run and G.start_run then
         if G.STATES and G.STATES.MENU then G.STATE = G.STATES.MENU end
         if G.E_MANAGER and G.E_MANAGER.clear_queue then G.E_MANAGER:clear_queue() end
         G:delete_run()
         G:start_run({ savetext = G.SAVED_GAME })
      elseif G.FUNCS and G.FUNCS.start_run then
         G.FUNCS.start_run(nil, { savetext = G.SAVED_GAME })
      else
         M.debug_log("error", "start_run not found!")
      end
      return true
   end

   function M.revert_to_previous_save()
      local entries = M.get_save_files()
      if not entries or #entries == 0 then
         M.debug_log("warning", "Cannot step back: no saves available")
         return
      end

      local current_idx = M.current_index or 0
      if current_idx == 0 or current_idx > #entries then
         local current_file = (G and G.SAVED_GAME and G.SAVED_GAME._file) or M._last_loaded_file
         current_idx = current_file and M.get_index_by_file(current_file) or 0
      end

      local target_idx = (current_idx == 0) and 1 or (current_idx + 1)
      if target_idx > #entries then return end

      local target_entry = nil
      while target_idx <= #entries do
         local candidate = entries[target_idx]
         local candidate_file = candidate and candidate[E.ENTRY_FILE]
         if candidate_file then
            if ctx.index.is_async_pending(candidate_file) then
               ctx.index.process_async_save_results()
            end
            if ctx.index.is_async_save_ready(candidate_file) then
               target_entry = candidate
               break
            end
            M.debug_log("warning", "Skipping missing save file: " .. tostring(candidate_file))
         end
         target_idx = target_idx + 1
      end
      if not target_entry then return end

      M.debug_log("info", "Step back -> " .. M.describe_save({ entry = target_entry }))
      M.load_and_start_from_file(target_entry[E.ENTRY_FILE], { skip_restore_identical = true, no_wipe = true })
   end

   function M.load_save_at_index(index)
      local entries = M.get_save_files()
      if not entries or index < 1 or index > #entries then
         M.debug_log("warning", "Cannot load save at index " .. tostring(index) .. ": out of bounds")
         return
      end
      local entry = entries[index]
      if not entry or not entry[E.ENTRY_FILE] then return end
      M.pending_index = index
      M.load_and_start_from_file(entry[E.ENTRY_FILE])
   end

   function M.quick_continue_from_menu()
      if not (G and G.FUNCS and G.STAGES and G.SETTINGS) then return end
      if G.STAGE ~= G.STAGES.RUN then return end

      M.debug_log("info", "Saveload -> continue")
      if G.OVERLAY_MENU and G.FUNCS.exit_overlay_menu then
         G.FUNCS.exit_overlay_menu()
      end
      if not G.SAVED_GAME then
         local run_data = _load_main_save()
         if run_data then G.SAVED_GAME = run_data end
      end
      if not G.SAVED_GAME then
         M.debug_log("error", "No save.jkr to continue")
         return
      end
      G.SETTINGS.current_setup = "Continue"
      if G.FUNCS.start_run then
         G.FUNCS.start_run(nil, { savetext = G.SAVED_GAME })
      else
         M.debug_log("error", "start_run not found for continue")
      end
   end

   api.pre_restore_compat_guard = _pre_restore_compat_guard
   return api
end
