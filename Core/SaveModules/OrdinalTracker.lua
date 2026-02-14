local RuntimeState = require("SaveManagerRuntimeState")

return function(ctx)
   local M = ctx.M
   local S = ctx.S
   local E = ctx.E
   local StateSignature = ctx.StateSignature

   local api = {}

   local function _reset_ordinal_state(ante, blind_key, round)
      RuntimeState.reset_ordinal_state(S, ante, blind_key, round)
   end

   function M.reset_ordinal_state()
      _reset_ordinal_state(nil, nil, nil)
      S.ordinal_state.defeated_boss_idx = nil
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
      _reset_ordinal_state(nil, nil, nil)
      S.ordinal_state.defeated_boss_idx = nil
   end

   local function _init_ordinal_state_from_entry(entry)
      if not entry then
         _reset_ordinal_state(nil, nil, nil)
         S.ordinal_state.defeated_boss_idx = nil
         return
      end

      local blind_key = M.index_to_blind_key(entry[E.ENTRY_BLIND_IDX]) or "unknown"
      _reset_ordinal_state(entry[E.ENTRY_ANTE], blind_key, entry[E.ENTRY_ROUND])

      local dtype = entry[E.ENTRY_DISPLAY_TYPE]
      if dtype == "P" then
         S.ordinal_state.last_hands_played = (entry[E.ENTRY_HANDS_PLAYED] or 1) - 1
         S.ordinal_state.last_discards_used = entry[E.ENTRY_DISCARDS_USED] or 0
      elseif dtype == "D" then
         S.ordinal_state.last_discards_used = (entry[E.ENTRY_DISCARDS_USED] or 1) - 1
         S.ordinal_state.last_hands_played = entry[E.ENTRY_HANDS_PLAYED] or 0
      else
         S.ordinal_state.last_discards_used = entry[E.ENTRY_DISCARDS_USED] or 0
         S.ordinal_state.last_hands_played = entry[E.ENTRY_HANDS_PLAYED] or 0
      end
      S.ordinal_state.last_display_type = dtype

      local load_ante = entry[E.ENTRY_ANTE]
      local load_round = entry[E.ENTRY_ROUND]
      local load_id = entry[E.ENTRY_INDEX]
      if S.save_cache and load_ante and load_round then
         for _, e in ipairs(S.save_cache) do
            if e[E.ENTRY_ANTE] == load_ante and e[E.ENTRY_ROUND] == load_round
               and (not load_id or not e[E.ENTRY_INDEX] or e[E.ENTRY_INDEX] <= load_id) then
               local dt = e[E.ENTRY_DISPLAY_TYPE]
               local ord = e[E.ENTRY_ORDINAL]
               if dt and ord and S.ordinal_state.counters[dt] ~= nil and ord > S.ordinal_state.counters[dt] then
                  S.ordinal_state.counters[dt] = ord
               end
            end
         end
      end

      if (dtype == "F" or dtype == "S" or dtype == "O" or dtype == "A") and
         entry[E.ENTRY_BLIND_IDX] and entry[E.ENTRY_BLIND_IDX] > 2 then
         S.ordinal_state.defeated_boss_idx = entry[E.ENTRY_BLIND_IDX]
         S.ordinal_state.last_round = 3
      else
         S.ordinal_state.defeated_boss_idx = nil
         S.ordinal_state.last_round = nil
      end
   end

   local function _compute_display_type(state_info)
      if not state_info then return "?" end

      local st = G and G.STATES
      if not st then return "?" end

      local state = state_info.state
      local action_type = nil
      if state == st.SELECTING_HAND then
         if state_info.discards_used > S.ordinal_state.last_discards_used then
            action_type = "discard"
         elseif state_info.hands_played > S.ordinal_state.last_hands_played then
            action_type = "play"
         end
      end

      local is_first_shop = false
      local is_after_pack = false
      if state == st.SHOP and not state_info.is_opening_pack then
         is_first_shop = (S.ordinal_state.last_display_type == "E" or S.ordinal_state.last_display_type == nil)
         is_after_pack = (S.ordinal_state.last_display_type == "O")
      end

      local is_start_round = (state == st.SELECTING_HAND and
         state_info.hands_played == 0 and
         state_info.discards_used == 0)

      return StateSignature.compute_display_type(state, action_type, state_info.is_opening_pack, is_first_shop, is_start_round, is_after_pack)
   end

   local function _create_signature(state_info, display_type)
      if not state_info then return nil end
      return StateSignature.encode_signature(
         state_info.ante,
         state_info.round,
         display_type,
         state_info.discards_used,
         state_info.hands_played,
         state_info.money
      )
   end

   api.reset_ordinal_state = _reset_ordinal_state
   api.init_ordinal_state_from_entry = _init_ordinal_state_from_entry
   api.compute_display_type = _compute_display_type
   api.create_signature = _create_signature

   return api
end
