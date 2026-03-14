-- tests/unit/test_runtime_state.lua
-- Tests for Core/SaveModules/RuntimeState.lua

local lu = require("luaunit")
local RS = require("SaveManagerRuntimeState")

TestRuntimeState = {}

-- ── new() structure ─────────────────────────────────────────────────────────

function TestRuntimeState:test_new_returns_table()
   local s = RS.new(100)
   lu.assertIsTable(s)
end

function TestRuntimeState:test_new_sets_meta_cache_limit()
   local s = RS.new(50)
   lu.assertEquals(s.meta_cache_limit, 50)
end

function TestRuntimeState:test_new_save_cache_is_nil()
   lu.assertIsNil(RS.new(10).save_cache)
end

function TestRuntimeState:test_new_ordinal_state_counters_zero()
   local s = RS.new(10)
   lu.assertIsTable(s.ordinal_state.counters)
   lu.assertEquals(s.ordinal_state.counters.S, 0)
   lu.assertEquals(s.ordinal_state.counters["?"], 0)
end

function TestRuntimeState:test_new_pending_async_files_empty()
   lu.assertIsTable(RS.new(10).pending_async_files)
end

-- ── reset_ordinal_state() ───────────────────────────────────────────────────

function TestRuntimeState:test_reset_sets_ante_and_blind_key()
   local s = RS.new(10)
   s.ordinal_state.ante = 99
   RS.reset_ordinal_state(s, 3, "bl_small", 2)
   lu.assertEquals(s.ordinal_state.ante, 3)
   lu.assertEquals(s.ordinal_state.blind_key, "bl_small")
end

function TestRuntimeState:test_reset_clears_counters()
   local s = RS.new(10)
   s.ordinal_state.counters.S = 42
   RS.reset_ordinal_state(s, 1, "bl_big", 1)
   lu.assertEquals(s.ordinal_state.counters.S, 0)
   lu.assertEquals(s.ordinal_state.counters.H, 0)
end

function TestRuntimeState:test_reset_clears_display_type()
   local s = RS.new(10)
   s.ordinal_state.last_display_type = "S"
   RS.reset_ordinal_state(s, 1, "bl_small", 1)
   lu.assertIsNil(s.ordinal_state.last_display_type)
end

function TestRuntimeState:test_reset_sets_last_saved_round()
   local s = RS.new(10)
   RS.reset_ordinal_state(s, 2, "bl_big", 5)
   lu.assertEquals(s.ordinal_state.last_saved_round, 5)
end

function TestRuntimeState:test_reset_clears_discard_and_hand_counters()
   local s = RS.new(10)
   s.ordinal_state.last_discards_used = 3
   s.ordinal_state.last_hands_played  = 7
   RS.reset_ordinal_state(s, 1, "bl_small", 1)
   lu.assertEquals(s.ordinal_state.last_discards_used, 0)
   lu.assertEquals(s.ordinal_state.last_hands_played, 0)
end
