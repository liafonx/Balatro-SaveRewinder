return function(ctx)
   local M = ctx.M
   local S = ctx.S
   local E = ctx.E
   local MetaFile = ctx.MetaFile
   local FileIO = ctx.FileIO
   local Pruning = ctx.Pruning
   local StateSignature = ctx.StateSignature
   local Logger = ctx.Logger
   local ordinal = ctx.ordinal
   local retention = ctx.retention
   local skip = ctx.skip

   local api = {}

   local function _parse_last_sig_parts()
      if M._last_save_sig_parts then return M._last_save_sig_parts end
      if not M._last_save_sig then return nil end
      local ante, round, dtype = M._last_save_sig:match("^(%d+):(%d+):(%a+):")
      if not ante then return nil end
      M._last_save_sig_parts = {
         ante = tonumber(ante),
         round = tonumber(round),
         dtype = dtype,
      }
      return M._last_save_sig_parts
   end

   local function _should_skip_duplicate(signature, display_type, ante, round)
      if not signature then return false end
      if not M._last_save_sig or not M._last_save_time then return false end

      local now = love.timer.getTime()
      local elapsed = now - M._last_save_time

      if M._last_save_sig == signature and elapsed < 0.5 then
         return true
      end

      local parts = _parse_last_sig_parts()
      if elapsed < 0.3 and parts and parts.ante == ante and parts.round == round then
         if display_type ~= "O" then
            if Logger.is_verbose() then M.debug_log("debug", "Skip rapid save at same ante/round") end
            return true
         end
      end

      if display_type == "E" and elapsed < 1.0 and parts and parts.dtype == "E" and parts.ante == ante and parts.round == round then
         if Logger.is_verbose() then M.debug_log("debug", "Skip duplicate end of round") end
         return true
      end

      return false
   end

   local function _should_save_state(state, config)
      if not config then return true end
      if not S.state_filters then
         local st = G and G.STATES
         if not st then return true end
         S.state_filters = {
            [st.ROUND_EVAL] = "save_on_round_end",
            [st.HAND_PLAYED] = "save_on_round_end",
            [st.BLIND_SELECT] = "save_on_blind",
            [st.SELECTING_HAND] = "save_on_selecting_hand",
            [st.SHOP] = "save_on_shop",
         }
      end
      local key = S.state_filters[state]
      return not key or config[key] ~= false
   end

   local function _update_last_sig_cache(state_info, display_type)
      M._last_save_sig_parts = {
         ante = state_info and state_info.ante or nil,
         round = state_info and state_info.round or nil,
         dtype = display_type,
      }
   end

   function M.create_save(run_data)
      ctx.index.process_async_save_results()
      if M.consume_skip_on_save(run_data) then return end

      local state_info = skip.consume_cached_state_info() or StateSignature.get_state_info(run_data)
      if not state_info then return end
      if not _should_save_state(state_info.state, REWINDER and REWINDER.config) then
         skip.align_save_id_to_current(run_data, "filtered")
         if Logger.is_verbose() then M.debug_log("debug", "Skipped save: state not configured for auto-save") end
         return
      end

      local blind_key = state_info.blind_key or "unknown"
      local ante_changed = S.ordinal_state.ante ~= state_info.ante
      local round_changed = S.ordinal_state.last_saved_round ~= state_info.round
      if ante_changed or round_changed then
         ordinal.reset_ordinal_state(state_info.ante, blind_key, state_info.round)
      else
         S.ordinal_state.blind_key = blind_key
      end

      local display_type = ordinal.compute_display_type(state_info)
      local signature = ordinal.create_signature(state_info, display_type)

      if _should_skip_duplicate(signature, display_type, state_info.ante, state_info.round) then
         skip.align_save_id_to_current(run_data, "duplicate")
         return
      end

      if not S.save_cache then M.get_save_files() end
      local dir = M.get_save_dir()

      if M.pending_future_prune_boundary then
         M.invalidate_async_saves()
         Pruning.prune_future_saves(dir, M.pending_future_prune_boundary, S.save_cache, E)
         M.pending_future_prune_boundary = nil
         ctx.index.invalidate_save_cache_view()
         ctx.index.rebuild_file_index()
      end

      local unique_id = run_data._rewinder_id or M.generate_unique_id()
      local filename = string.format("%d-%d-%d.jkr", state_info.ante, state_info.round, unique_id)

      S.ordinal_state.last_discards_used = state_info.discards_used or 0
      S.ordinal_state.last_hands_played = state_info.hands_played or 0

      local ordinal_num = 1
      if S.ordinal_state.counters[display_type] then
         S.ordinal_state.counters[display_type] = S.ordinal_state.counters[display_type] + 1
         ordinal_num = S.ordinal_state.counters[display_type]
      end
      S.ordinal_state.last_display_type = display_type

      local actual_blind_idx = M.blind_key_to_index(state_info.blind_key)
      if display_type == "E" then
         S.ordinal_state.last_round = state_info.round
         if state_info.round == 3 or actual_blind_idx > 2 then
            S.ordinal_state.defeated_boss_idx = (actual_blind_idx > 2) and actual_blind_idx or S.ordinal_state.defeated_boss_idx
         end
      end

      if display_type == "B" then
         S.ordinal_state.defeated_boss_idx = nil
         S.ordinal_state.last_round = nil
      end

      local is_shop_state = display_type == "F" or display_type == "S" or display_type == "O" or display_type == "A"
      local blind_idx = 0
      if display_type == "B" then
         blind_idx = 0
      elseif is_shop_state and S.ordinal_state.defeated_boss_idx then
         blind_idx = S.ordinal_state.defeated_boss_idx
      elseif is_shop_state and S.ordinal_state.last_round == 3 and actual_blind_idx > 2 then
         blind_idx = actual_blind_idx
      else
         blind_idx = actual_blind_idx
      end

      local new_entry = {
         filename, state_info.ante, state_info.round, unique_id,
         state_info.money, signature, state_info.discards_used, state_info.hands_played,
         false, blind_idx, display_type, ordinal_num, false,
      }

      local full_path = dir .. "/" .. filename
      local meta_table = {
         money = state_info.money,
         signature = signature,
         discards_used = state_info.discards_used,
         hands_played = state_info.hands_played,
         blind_idx = blind_idx,
         display_type = display_type,
         ordinal = ordinal_num,
      }
      MetaFile.write_meta_file(dir .. "/" .. filename:gsub("%.jkr$", ".meta"), meta_table)
      ctx.meta.cache_meta(filename, meta_table)

      local wrote_async = false
      if G and G.ARGS then
         G.ARGS.rewinder_copy_path = full_path
         wrote_async = true
      end
      if not wrote_async then
         M.debug_log("warning", "Piggyback path unavailable, using sync fallback")
         local write_ok, write_err, compressed_bytes = FileIO.write_save_file(run_data, full_path)
         if not write_ok then
            M.debug_log("error", "Failed to write save: " .. tostring(write_err))
            return
         end
         if compressed_bytes then
            FileIO.write_bytes_to_main(compressed_bytes)
         else
            FileIO.copy_save_to_main(filename, dir)
         end
      end

      S.save_cache[#S.save_cache + 1] = new_entry
      new_entry[E.ENTRY_IS_CURRENT] = true
      if S.save_cache_by_file then S.save_cache_by_file[filename] = new_entry end
      ctx.index.prepend_save_view_entry(new_entry)

      if wrote_async then ctx.index.mark_async_pending(filename) end
      run_data._file = filename
      M.current_index = 1
      M._last_save_sig = signature
      M._last_save_time = love.timer.getTime()
      _update_last_sig_cache(state_info, display_type)
      if Logger.is_verbose() then
         M.debug_log("info", "Created: " .. StateSignature.describe_save(state_info.ante, state_info.round, display_type))
      end

      if ante_changed then
         retention.apply_retention_policy(dir, S.save_cache)
         ctx.index.invalidate_save_cache_view()
         ctx.index.rebuild_file_index()
      else
         ctx.index.invalidate_derived_indexes()
      end
      M._set_cache_current_file(filename)
   end

   api.should_save_state = _should_save_state
   return api
end
