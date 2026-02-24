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

   local function _bucket_key(display_type, round)
      return tostring(display_type or "?") .. ":" .. tostring(round or 0)
   end

   local function _rebuild_bucket_counts()
      local counts = {}
      local stats = {
         total = 0,
         counted = 0,
         missing_display_type = 0,
         recovered_display_type = 0,
         unresolved_display_type = 0,
      }
      local entries = S.save_cache
      if entries then
         for i = 1, #entries do
            local entry = entries[i]
            if entry and entry[E.ENTRY_IS_KEY] ~= true then
               stats.total = stats.total + 1
               local round = entry[E.ENTRY_ROUND]
               local display_type = entry[E.ENTRY_DISPLAY_TYPE]
               if display_type == nil and M.get_save_meta then
                  -- After restart, many entries may not have display_type loaded yet.
                  -- Load metadata lazily so per-type-per-round limits count existing saves correctly.
                  stats.missing_display_type = stats.missing_display_type + 1
                  M.get_save_meta(entry)
                  display_type = entry[E.ENTRY_DISPLAY_TYPE]
                  if display_type ~= nil then
                     stats.recovered_display_type = stats.recovered_display_type + 1
                  else
                     stats.unresolved_display_type = stats.unresolved_display_type + 1
                  end
               end
               if round ~= nil and display_type ~= nil then
                  local key = _bucket_key(display_type, round)
                  counts[key] = (counts[key] or 0) + 1
                  stats.counted = stats.counted + 1
               end
            end
         end
      end
      S.bucket_counts = counts
      if Logger.is_verbose() then
         local bucket_total = 0
         for _ in pairs(counts) do bucket_total = bucket_total + 1 end
         M.debug_log("debug", string.format(
            "bucket_rebuild: entries=%d counted=%d buckets=%d missing_dtype=%d recovered=%d unresolved=%d",
            stats.total, stats.counted, bucket_total,
            stats.missing_display_type, stats.recovered_display_type, stats.unresolved_display_type
         ))
      end
      return counts
   end

   M._rebuild_bucket_counts = _rebuild_bucket_counts

   local function _count_bucket_live(display_type, round)
      local count = 0
      local unresolved = 0
      local entries = S.save_cache
      if not entries then return 0, 0 end

      for i = 1, #entries do
         local entry = entries[i]
         if entry and entry[E.ENTRY_IS_KEY] ~= true and entry[E.ENTRY_ROUND] == round then
            local dtype = entry[E.ENTRY_DISPLAY_TYPE]
            if dtype == nil and M.get_save_meta then
               M.get_save_meta(entry)
               dtype = entry[E.ENTRY_DISPLAY_TYPE]
            end
            if dtype == nil then
               unresolved = unresolved + 1
            elseif dtype == display_type then
               count = count + 1
            end
         end
      end

      return count, unresolved
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

   function M.create_save(run_data)
      ctx.index.process_async_save_results()

      if not S.save_cache then M.get_save_files() end
      local dir = M.get_save_dir()

      if M.pending_future_prune_boundary then
         M.invalidate_async_saves()
         Pruning.prune_future_saves(dir, M.pending_future_prune_boundary, S.save_cache, E)
         S.bucket_counts = nil
         M.pending_future_prune_boundary = nil
         ctx.index.invalidate_save_cache_view()
         ctx.index.rebuild_file_index()
      end

      if M.consume_skip_on_save(run_data) then return end
      local perf_t0 = Logger.is_verbose() and love.timer.getTime() or nil

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
         blind_idx = (state_info.round > 0) and actual_blind_idx or 0
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
      local meta_path = dir .. "/" .. filename:gsub("%.jkr$", ".meta")
      local meta_content = MetaFile.serialize_meta(meta_table)
      if not meta_content then
         M.debug_log("warning", "Failed to serialize meta for: " .. tostring(filename))
      end

      local wrote_async = false
      local enqueue_result = false
      local used_nonqueue_path = false
      local queue_depth_before = M.rewinder_queue_depth and M.rewinder_queue_depth() or nil
      if M.enqueue_pending_rewinder and not (REWINDER and REWINDER._rw_flush_fallback) then
         local frozen = (M.freeze_save_table and M.freeze_save_table(run_data)) or run_data
         enqueue_result = M.enqueue_pending_rewinder({
            save_table = frozen,
            rewinder_copy_path = full_path,
            rewinder_meta_path = meta_content and meta_path or nil,
            rewinder_meta_data = meta_content,
            file = filename,
            signature = signature,
         })
      end
      if enqueue_result == true then
         wrote_async = true
      else
         used_nonqueue_path = true

         -- Queue saturated: try direct SaveThread push before piggyback fallback.
         local direct_pushed = false
         local SaveThread = REWINDER and REWINDER._SaveThread
         if not (REWINDER and REWINDER._rw_flush_fallback)
            and SaveThread and SaveThread.push_save and SaveThread.start and SaveThread.start() then
            local req = M.build_rewinder_push_request and M.build_rewinder_push_request({
               save_table = run_data,
               rewinder_copy_path = full_path,
               rewinder_meta_path = meta_content and meta_path or nil,
               rewinder_meta_data = meta_content,
               file = filename,
            }, REWINDER and REWINDER.config)
            if req and req.path and req.save_table then
               direct_pushed = SaveThread.push_save(req) == true
            end
         end

         if direct_pushed then
            wrote_async = true
            if Logger.is_verbose() then
               M.debug_log("debug", string.format(
                  "create_save: queue fallback direct push file=%s q_before=%s",
                  tostring(filename), tostring(queue_depth_before)
               ))
            end
         elseif G and G.ARGS then
            if Logger.is_verbose() then
               M.debug_log("warning", string.format(
                  "create_save: queue fallback piggyback file=%s q_before=%s",
                  tostring(filename), tostring(queue_depth_before)
               ))
            end
            G.ARGS.rewinder_copy_path = full_path
            if meta_content then
               G.ARGS.rewinder_meta_path = meta_path
               G.ARGS.rewinder_meta_data = meta_content
            end
            if G.FILE_HANDLER then G.FILE_HANDLER.force = true end
            wrote_async = true
         end
      end
      if not wrote_async then
         if meta_content and not MetaFile.write_meta_file(meta_path, meta_table) then
            M.debug_log("warning", "Failed to write meta file: " .. tostring(meta_path))
         end
         M.debug_log("warning", "All async paths unavailable, using sync fallback")
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

      -- Cache metadata only once save is confirmed for async/sync write path.
      ctx.meta.cache_meta(filename, meta_table)

      S.save_cache[#S.save_cache + 1] = new_entry
      new_entry[E.ENTRY_IS_CURRENT] = true
      if S.save_cache_by_file then S.save_cache_by_file[filename] = new_entry end
      ctx.index.prepend_save_view_entry()

      if wrote_async then ctx.index.mark_async_pending(filename) end
      run_data._file = filename
      M.current_index = 1
      if REWINDER and REWINDER._save_gate_pending then
         REWINDER._save_gate_saved = REWINDER._save_gate_pending
         REWINDER._save_gate_pending = nil
      end
      if Logger.is_verbose() then
         M.debug_log("info", "Created: " .. StateSignature.describe_save(state_info.ante, state_info.round, display_type))
      end

      if REWINDER and REWINDER._new_run_dedup_armed then
         REWINDER._new_run_dedup_armed = nil
         M._force_skip_next_save = true
      end

      if ante_changed then
         local _, removed_files = retention.apply_retention_policy(dir, S.save_cache)
         if removed_files and M.cancel_pending_rewinder_by_files then
            M.cancel_pending_rewinder_by_files(removed_files)
         end
         S.bucket_counts = nil
         ctx.index.invalidate_save_cache_view()
         ctx.index.rebuild_file_index()
      else
         ctx.index.invalidate_derived_indexes()
      end

      local limit_config = (REWINDER and REWINDER.config and REWINDER.config.max_saves_per_type_per_round) or 5
      local bucket_limit = Pruning.get_type_round_limit and Pruning.get_type_round_limit(limit_config) or nil
      if bucket_limit then
         local bucket_key = _bucket_key(display_type, state_info.round)
         local counts_rebuilt = false
         if not S.bucket_counts then
            _rebuild_bucket_counts()
            counts_rebuilt = true
         end
         local before_count = S.bucket_counts[bucket_key] or 0
         if not counts_rebuilt then
            S.bucket_counts[bucket_key] = before_count + 1
         end
         local after_count = S.bucket_counts[bucket_key] or 0

         if Logger.is_verbose() then
            local live_count, unresolved = _count_bucket_live(display_type, state_info.round)
            M.debug_log("debug", string.format(
               "bucket_guard[%s r%s]: limit=%d cache=%d->%d live=%d unresolved=%d rebuilt=%s",
               tostring(display_type), tostring(state_info.round),
               bucket_limit, before_count, after_count, live_count, unresolved, tostring(counts_rebuilt)
            ))
         end

         if after_count > bucket_limit then
            local bucket_trimmed, removed_files = Pruning.trim_type_round_bucket(dir, S.save_cache, E, display_type, state_info.round)
            if bucket_trimmed > 0 then
               S.bucket_counts[bucket_key] = math.max(0, (S.bucket_counts[bucket_key] or 0) - bucket_trimmed)
               if M.cancel_pending_rewinder_by_files then
                  M.cancel_pending_rewinder_by_files(removed_files)
               end
               if ctx.index.remove_files_from_index then
                  ctx.index.remove_files_from_index(removed_files)
               else
                  ctx.index.invalidate_save_cache_view()
                  ctx.index.rebuild_file_index()
               end
               if Logger.is_verbose() then
                  local post_live_count, unresolved = _count_bucket_live(display_type, state_info.round)
                  M.debug_log("debug", string.format(
                     "bucket_trimmed[%s r%s]: removed=%d cache_now=%d live_now=%d unresolved=%d",
                     tostring(display_type), tostring(state_info.round),
                     bucket_trimmed, S.bucket_counts[bucket_key] or 0, post_live_count, unresolved
                  ))
               end
            end
         end
      elseif Logger.is_verbose() then
         M.debug_log("debug", string.format(
            "bucket_guard skipped: max_saves_per_type_per_round=%s (unbounded)",
            tostring(limit_config)
         ))
      end

      M._set_cache_current_file(filename)
      if perf_t0 then
         M.debug_log("debug", string.format("create_save: %.2fms (%s)", (love.timer.getTime() - perf_t0) * 1000, tostring(display_type)))
      end
   end

   api.should_save_state = _should_save_state
   return api
end
