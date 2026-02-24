return function(ctx)
   local M = ctx.M
   local S = ctx.S
   local E = ctx.E
   local StateSignature = ctx.StateSignature
   local Logger = ctx.Logger
   local ordinal = ctx.ordinal

   local api = {}

   local function _assign_loaded_fields(entry, run_data)
      if entry then
         M.get_save_meta(entry, { force = true })
         M._loaded_ante = entry[E.ENTRY_ANTE]
         M._loaded_round = entry[E.ENTRY_ROUND]
         M._loaded_money = entry[E.ENTRY_MONEY]
         M._loaded_discards = entry[E.ENTRY_DISCARDS_USED]
         M._loaded_hands = entry[E.ENTRY_HANDS_PLAYED]
         M._loaded_display_type = entry[E.ENTRY_DISPLAY_TYPE]
         ordinal.init_ordinal_state_from_entry(entry)
         return
      end

      local state_info = StateSignature.get_state_info(run_data)
      if not state_info then
         M._loaded_ante = nil
         M._loaded_round = nil
         M._loaded_money = nil
         M._loaded_discards = nil
         M._loaded_hands = nil
         M._loaded_display_type = nil
         return
      end
      local display_type = ordinal.compute_display_type(state_info)
      M._loaded_ante = state_info.ante
      M._loaded_round = state_info.round
      M._loaded_money = state_info.money
      M._loaded_discards = state_info.discards_used
      M._loaded_hands = state_info.hands_played
      M._loaded_display_type = display_type
   end

   local function _align_save_id_to_current(save_table, reason)
      if not save_table then return end
      local file = save_table._file or M._last_loaded_file
      if not file then return end
      local entry = M.get_entry_by_file and M.get_entry_by_file(file)
      if entry and entry[E.ENTRY_INDEX] then
         save_table._rewinder_id = entry[E.ENTRY_INDEX]
         save_table._file = entry[E.ENTRY_FILE]
         if Logger.is_verbose() then M.debug_log("debug", "Align id: " .. (reason or "")) end
      end
   end

   function M.reset_loaded_state_if_stale()
      if M._pending_skip_reason then return end
      M._loaded_mark_applied = nil
      M._loaded_ante = nil
      M._loaded_round = nil
      M._loaded_money = nil
      M._loaded_discards = nil
      M._loaded_hands = nil
      M._loaded_display_type = nil
      M.skip_next_save = false
      M._restore_active = false
      if M.reset_ordinal_state then M.reset_ordinal_state() end
   end

   function M.set_skip_context(context)
      context = context or {}
      if context.reason ~= nil then M._pending_skip_reason = context.reason end
      if context.restore ~= nil then M._restore_active = context.restore and true or false end
      if context.last_loaded_file ~= nil then M._last_loaded_file = context.last_loaded_file end
      if context.skip_next_save ~= nil then M.skip_next_save = context.skip_next_save and true or false end
   end

   function M.set_pending_index(idx)
      M.pending_index = idx
   end

   function M.mark_loaded_state(run_data, opts)
      opts = opts or {}
      if M._loaded_mark_applied then
         M.skip_next_save = true
         return
      end

      if not M._pending_skip_reason then M._pending_skip_reason = opts.reason end
      M._restore_active = (M._pending_skip_reason == "restore")
      if opts.last_loaded_file then
         M._last_loaded_file = opts.last_loaded_file
         local idx = M.get_index_by_file and M.get_index_by_file(opts.last_loaded_file)
         if idx then M.current_index = idx end
      end

      local entry = M._last_loaded_file and ctx.index.get_entry_by_file(M._last_loaded_file)
      _assign_loaded_fields(entry, run_data)

      M._loaded_mark_applied = true
      M.skip_next_save = (opts.set_skip ~= false)
   end

   function M.consume_skip_on_save(save_table)
      S.skip_check_state_info = nil
      if M._force_skip_next_save then
         M._force_skip_next_save = nil
         M.skip_next_save = false
         return true
      end
      if not M.skip_next_save then return false end

      if save_table and not save_table._file then
         if save_table._rewinder_id then
            local entry = M.get_entry_by_id(save_table._rewinder_id)
            if entry then save_table._file = entry[E.ENTRY_FILE] end
         end
         if not save_table._file and M._last_loaded_file then
            save_table._file = M._last_loaded_file
         end
      end

      local state_info = StateSignature.get_state_info(save_table)
      S.skip_check_state_info = state_info
      local display_type = ordinal.compute_display_type(state_info)

      local should_skip = (
         state_info.ante == M._loaded_ante and
         state_info.round == M._loaded_round and
         state_info.money == M._loaded_money and
         state_info.discards_used == M._loaded_discards and
         state_info.hands_played == M._loaded_hands and
         display_type == M._loaded_display_type
      )

      if not should_skip and M._loaded_display_type == "O" then
         if M.skipping_pack_open then
            should_skip = true
            M.skipping_pack_open = nil
         else
            local ca = save_table.cardAreas
            if ca and ca.pack_cards and ca.pack_cards.cards and next(ca.pack_cards.cards) then
               should_skip = true
            end
         end
      end
      M.skipping_pack_open = nil

      if save_table and should_skip then save_table.REWINDER_SKIP_SAVE = true end
      if should_skip then
         _align_save_id_to_current(save_table, "skip")
         if not M.pending_future_prune_boundary and M._last_loaded_file then
            local entry = M.get_entry_by_file and M.get_entry_by_file(M._last_loaded_file)
            if entry and entry[E.ENTRY_INDEX] and S.save_cache and #S.save_cache > 0 then
               local last_entry = S.save_cache[#S.save_cache]
               if last_entry and last_entry[E.ENTRY_INDEX]
                  and last_entry[E.ENTRY_INDEX] > entry[E.ENTRY_INDEX] then
                  M.pending_future_prune_boundary = entry[E.ENTRY_INDEX]
               end
            end
         end
      end
      if not should_skip and Logger.is_verbose() then
         M.debug_log("info", "Saving: " .. StateSignature.describe_save(state_info.ante, state_info.round, display_type))
      end

      M.skip_next_save = false
      M._restore_active = false
      M._pending_skip_reason = nil
      M._loaded_mark_applied = nil
      M._loaded_ante = nil
      M._loaded_round = nil
      M._loaded_money = nil
      M._loaded_discards = nil
      M._loaded_hands = nil
      M._loaded_display_type = nil
      return should_skip
   end

   api.assign_loaded_fields = _assign_loaded_fields
   api.align_save_id_to_current = _align_save_id_to_current
   api.consume_cached_state_info = function()
      local v = S.skip_check_state_info
      S.skip_check_state_info = nil
      return v
   end

   return api
end
