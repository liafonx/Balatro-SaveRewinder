-- tests/unit/test_blind_recovery.lua
-- Tests for Utils/BlindRecovery.lua

local lu = require("luaunit")
local BR = require("BlindRecovery")
local NaN = require("NaNProtection")

local NAN = 0.0 / 0.0
local INF = math.huge

TestBlindRecovery = {}

-- ── recover_blind_chips ─────────────────────────────────────────────────────

function TestBlindRecovery:test_recover_chips_not_nil_returns_chips()
   lu.assertEquals(BR.recover_blind_chips(300, "300", nil), 300)
end

function TestBlindRecovery:test_recover_chips_nil_parses_chip_text()
   lu.assertEquals(BR.recover_blind_chips(nil, "300", nil), 300)
end

function TestBlindRecovery:test_recover_chips_nil_with_commas()
   lu.assertEquals(BR.recover_blind_chips(nil, "1,234", nil), 1234)
end

function TestBlindRecovery:test_recover_chips_nan_text()
   local result = BR.recover_blind_chips(nil, "NaN", nil)
   lu.assertTrue(result ~= result)   -- NaN ~= NaN
end

function TestBlindRecovery:test_recover_chips_inf_text()
   lu.assertEquals(BR.recover_blind_chips(nil, "Inf", nil), INF)
end

function TestBlindRecovery:test_recover_chips_nil_chip_text_uses_fallback()
   lu.assertEquals(BR.recover_blind_chips(nil, nil, 42), 42)
end

function TestBlindRecovery:test_recover_chips_unparseable_text_uses_fallback()
   lu.assertEquals(BR.recover_blind_chips(nil, "bad_text", 42), 42)
end

function TestBlindRecovery:test_recover_chips_zero_chips_returned()
   lu.assertEquals(BR.recover_blind_chips(0, "anything", nil), 0)
end

-- ── recover_blind_chip_text ─────────────────────────────────────────────────

function TestBlindRecovery:test_recover_chip_text_nil_formats_chips()
   -- number_format is stubbed to tostring in Layer 0.
   lu.assertEquals(BR.recover_blind_chip_text(nil, 300), "300")
end

function TestBlindRecovery:test_recover_chip_text_empty_formats_chips()
   lu.assertEquals(BR.recover_blind_chip_text("", 300), "300")
end

function TestBlindRecovery:test_recover_chip_text_existing_preserved()
   lu.assertEquals(BR.recover_blind_chip_text("existing", 300), "existing")
end

-- ── ensure_blind_chips ──────────────────────────────────────────────────────

function TestBlindRecovery:test_ensure_blind_chips_non_table_returns_0()
   lu.assertEquals(BR.ensure_blind_chips(nil), 0)
   lu.assertEquals(BR.ensure_blind_chips("bad"), 0)
end

function TestBlindRecovery:test_ensure_blind_chips_existing_chips_unchanged()
   local blind = { chips = 500 }
   lu.assertEquals(BR.ensure_blind_chips(blind), 500)
   lu.assertEquals(blind.chips, 500)
end

function TestBlindRecovery:test_ensure_blind_chips_from_chip_text()
   local blind = { chip_text = "300" }
   lu.assertEquals(BR.ensure_blind_chips(blind), 300)
   lu.assertEquals(blind.chips, 300)
end

function TestBlindRecovery:test_ensure_blind_chips_sets_zero_when_no_info()
   local blind = {}
   BR.ensure_blind_chips(blind)
   lu.assertEquals(blind.chips, 0)
end

-- ── sanitize_round_scores ───────────────────────────────────────────────────

function TestBlindRecovery:test_sanitize_round_scores_nil_game_no_crash()
   local ok = pcall(BR.sanitize_round_scores, nil)
   lu.assertTrue(ok)
end

function TestBlindRecovery:test_sanitize_round_scores_fixes_nil_amt()
   local game = { round_scores = { hand = { amt = nil }, chips = { amt = 100 } } }
   BR.sanitize_round_scores(game)
   lu.assertEquals(game.round_scores.hand.amt, 0)
   lu.assertEquals(game.round_scores.chips.amt, 100)   -- unchanged
end

-- ── sanitize_round_scores_presave ───────────────────────────────────────────

function TestBlindRecovery:test_sanitize_presave_no_clamp_inf_unchanged()
   local orig = REWINDER.config.clamp_infinity_scores
   REWINDER.config.clamp_infinity_scores = false
   local game = { round_scores = { hand = { amt = INF } } }
   BR.sanitize_round_scores_presave(game)
   lu.assertEquals(game.round_scores.hand.amt, INF)
   REWINDER.config.clamp_infinity_scores = orig
end

function TestBlindRecovery:test_sanitize_presave_clamp_inf_clamped()
   local orig = REWINDER.config.clamp_infinity_scores
   REWINDER.config.clamp_infinity_scores = true
   local game = { round_scores = { hand = { amt = INF } } }
   BR.sanitize_round_scores_presave(game)
   lu.assertTrue(game.round_scores.hand.amt < INF)
   lu.assertTrue(game.round_scores.hand.amt > 0)
   REWINDER.config.clamp_infinity_scores = orig
end

-- ── chips_met_target ────────────────────────────────────────────────────────

function TestBlindRecovery:test_chips_met_target_true_when_chips_exceed_blind()
   G.GAME = { chips = 500, blind = { chips = 300 } }
   lu.assertTrue(BR.chips_met_target())
   G.GAME = nil
end

function TestBlindRecovery:test_chips_met_target_false_when_chips_below_blind()
   G.GAME = { chips = 100, blind = { chips = 300 } }
   lu.assertFalse(BR.chips_met_target())
   G.GAME = nil
end

function TestBlindRecovery:test_chips_met_target_true_at_exact_match()
   G.GAME = { chips = 300, blind = { chips = 300 } }
   lu.assertTrue(BR.chips_met_target())
   G.GAME = nil
end

function TestBlindRecovery:test_chips_met_target_no_game_does_not_crash()
   G.GAME = nil
   local ok = pcall(BR.chips_met_target)
   lu.assertTrue(ok)
end

-- ── scale_continue_best_hand ────────────────────────────────────────────────

function TestBlindRecovery:test_scale_continue_best_hand_nan_returns_base()
   lu.assertEquals(BR.scale_continue_best_hand(NAN, 0.3, 1e11), 0.3)
end

function TestBlindRecovery:test_scale_continue_best_hand_inf_returns_base()
   lu.assertEquals(BR.scale_continue_best_hand(INF, 0.3, 1e11), 0.3)
end

function TestBlindRecovery:test_scale_continue_best_hand_huge_returns_base()
   lu.assertEquals(BR.scale_continue_best_hand(1e291, 0.3, 1e11), 0.3)
end

function TestBlindRecovery:test_scale_continue_best_hand_non_number_returns_base()
   lu.assertEquals(BR.scale_continue_best_hand("bad", 0.3, 1e11), 0.3)
end

function TestBlindRecovery:test_scale_continue_best_hand_nil_base_uses_default()
   -- base_scale defaults to 0.3 when non-number provided
   lu.assertEquals(BR.scale_continue_best_hand(NAN, nil, 1e11), 0.3)
end
