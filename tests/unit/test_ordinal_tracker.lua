-- tests/unit/test_ordinal_tracker.lua
-- Tests for Core/SaveModules/OrdinalTracker.lua

local lu          = require("luaunit")
local CtxFactory  = require("ctx_factory")
local Fixtures    = require("fixtures")

local OrdinalTrackerFactory = require("SaveManagerOrdinalTracker")

TestOrdinalTracker = {}

function TestOrdinalTracker:setUp()
   local ctx = CtxFactory.mk_save_module_ctx()
   ctx.S.save_cache = Fixtures.make_save_cache(3)
   self.api = OrdinalTrackerFactory(ctx)
   self.ctx = ctx
   self.M   = ctx.M
   self.S   = ctx.S
   self.E   = ctx.E
end

-- ── reset_ordinal_state ──────────────────────────────────────────────────────

function TestOrdinalTracker:test_reset_ordinal_state_clears_counters()
   self.S.ordinal_state.counters.S = 99
   self.api.reset_ordinal_state(nil, nil, nil)
   lu.assertEquals(self.S.ordinal_state.counters.S, 0)
   lu.assertEquals(self.S.ordinal_state.last_discards_used, 0)
   lu.assertEquals(self.S.ordinal_state.last_hands_played, 0)
end

-- ── init_ordinal_state_from_entry ────────────────────────────────────────────

function TestOrdinalTracker:test_init_from_entry_sets_ante_and_round()
   local entry = Fixtures.make_entry({ ante = 2, round = 3, display_type = "S" })
   self.api.init_ordinal_state_from_entry(entry)
   lu.assertEquals(self.S.ordinal_state.ante, 2)
end

function TestOrdinalTracker:test_init_from_entry_nil_resets_state()
   self.S.ordinal_state.ante = 99
   self.api.init_ordinal_state_from_entry(nil)
   lu.assertNil(self.S.ordinal_state.ante)
end

function TestOrdinalTracker:test_init_from_entry_P_type_sets_last_hands()
   local entry = Fixtures.make_entry({ display_type = "P", hands_played = 3, discards_used = 1 })
   self.api.init_ordinal_state_from_entry(entry)
   -- For P type: last_hands_played = hands_played - 1
   lu.assertEquals(self.S.ordinal_state.last_hands_played, 2)
end

function TestOrdinalTracker:test_init_from_entry_D_type_sets_last_discards()
   local entry = Fixtures.make_entry({ display_type = "D", hands_played = 1, discards_used = 4 })
   self.api.init_ordinal_state_from_entry(entry)
   -- For D type: last_discards_used = discards_used - 1
   lu.assertEquals(self.S.ordinal_state.last_discards_used, 3)
end

function TestOrdinalTracker:test_init_from_entry_scans_cache_for_max_ordinals()
   -- Entry 3 in cache has ordinal 3 and matching ante/round
   local entry = Fixtures.make_entry({
      ante = 1, round = 1, display_type = "S", ordinal = 3, index = 3
   })
   self.api.init_ordinal_state_from_entry(entry)
   -- ordinal counter for "S" should be at least 3 (from cache scan)
   lu.assertTrue(self.S.ordinal_state.counters.S >= 3)
end

-- ── compute_display_type ─────────────────────────────────────────────────────

function TestOrdinalTracker:test_compute_display_type_shop_returns_F_when_first()
   local state_info = {
      state = G.STATES.SHOP,
      ante = 1, round = 1, money = 5,
      discards_used = 0, hands_played = 0,
      is_opening_pack = false,
   }
   -- last_display_type nil → is_first_shop → returns "F" (entering shop first time)
   self.S.ordinal_state.last_display_type = nil
   local dt = self.api.compute_display_type(state_info)
   lu.assertEquals(dt, "F")
end

function TestOrdinalTracker:test_compute_display_type_shop_returns_S_when_reroll()
   local state_info = {
      state = G.STATES.SHOP,
      ante = 1, round = 1, money = 5,
      discards_used = 0, hands_played = 0,
      is_opening_pack = false,
   }
   -- last_display_type "S" → not first shop, not after pack → reroll shop "S"
   self.S.ordinal_state.last_display_type = "S"
   local dt = self.api.compute_display_type(state_info)
   lu.assertEquals(dt, "S")
end

function TestOrdinalTracker:test_compute_display_type_round_eval_returns_E()
   local state_info = {
      state = G.STATES.ROUND_EVAL,
      ante = 1, round = 1, money = 5,
      discards_used = 0, hands_played = 0,
      is_opening_pack = false,
   }
   local dt = self.api.compute_display_type(state_info)
   lu.assertEquals(dt, "E")
end

function TestOrdinalTracker:test_compute_display_type_blind_select_returns_B()
   local state_info = {
      state = G.STATES.BLIND_SELECT,
      ante = 1, round = 1, money = 5,
      discards_used = 0, hands_played = 0,
      is_opening_pack = false,
   }
   local dt = self.api.compute_display_type(state_info)
   lu.assertEquals(dt, "B")
end

-- ── create_signature ─────────────────────────────────────────────────────────

function TestOrdinalTracker:test_create_signature_returns_string()
   local state_info = {
      ante = 1, round = 1, money = 5,
      discards_used = 0, hands_played = 0,
   }
   local sig = self.api.create_signature(state_info, "S")
   lu.assertIsString(sig)
   lu.assertStrContains(sig, "1")
end

function TestOrdinalTracker:test_create_signature_nil_state_info_returns_nil()
   local sig = self.api.create_signature(nil, "S")
   lu.assertNil(sig)
end
