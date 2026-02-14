local M = {}

local function _new_ordinal_state()
   return {
      ante = nil,
      blind_key = nil,
      last_display_type = nil,
      last_discards_used = 0,
      last_hands_played = 0,
      last_round = nil,
      last_saved_round = nil,
      counters = {
         S = 0,
         F = 0,
         O = 0,
         A = 0,
         R = 0,
         P = 0,
         D = 0,
         H = 0,
         E = 0,
         B = 0,
         ["?"] = 0,
      },
      defeated_boss_idx = nil,
   }
end

function M.new(base_meta_limit)
   return {
      save_cache = nil,
      save_cache_view = nil,
      save_cache_by_file = nil,
      save_index_by_file = nil,
      save_cache_by_id = nil,

      meta_cache = {},
      meta_cache_size = 0,
      meta_lru_ts = {},
      meta_lru_clock = 0,
      meta_cache_limit = base_meta_limit,
      last_meta_window_start = nil,
      last_meta_window_finish = nil,
      last_eviction_log_time = 0,

      pending_async_files = {},
      pending_async_count = 0,

      ordinal_state = _new_ordinal_state(),
      last_current_file = false,

      skip_check_state_info = nil,
      state_filters = nil,

      last_sig_ante = nil,
      last_sig_round = nil,
      last_sig_dtype = nil,
   }
end

function M.reset_ordinal_state(state, ante, blind_key, round)
   local ord = state.ordinal_state
   ord.ante = ante
   ord.blind_key = blind_key
   ord.last_saved_round = round
   ord.last_display_type = nil
   ord.last_discards_used = 0
   ord.last_hands_played = 0
   ord.last_round = nil
   ord.counters = { S = 0, F = 0, O = 0, A = 0, R = 0, P = 0, D = 0, H = 0, E = 0, B = 0, ["?"] = 0 }
end

return M
