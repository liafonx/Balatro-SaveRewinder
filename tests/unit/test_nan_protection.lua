-- tests/unit/test_nan_protection.lua
-- Tests for Utils/NaNProtection.lua

local lu = require("luaunit")
local NaN = require("NaNProtection")

-- Use float division to produce NaN — avoids Lua 5.4 integer division crash.
local NAN = 0.0 / 0.0
local INF = math.huge

TestNaNProtection = {}

-- ── is_nan ──────────────────────────────────────────────────────────────────

function TestNaNProtection:test_is_nan_detects_nan()
   lu.assertTrue(NaN.is_nan(NAN))
end

function TestNaNProtection:test_is_nan_zero_is_false()
   lu.assertFalse(NaN.is_nan(0))
end

function TestNaNProtection:test_is_nan_inf_is_false()
   lu.assertFalse(NaN.is_nan(INF))
end

function TestNaNProtection:test_is_nan_string_is_false()
   lu.assertFalse(NaN.is_nan("nan"))
end

function TestNaNProtection:test_is_nan_nil_is_false()
   lu.assertFalse(NaN.is_nan(nil))
end

-- ── is_inf ──────────────────────────────────────────────────────────────────

function TestNaNProtection:test_is_inf_pos_inf()
   lu.assertTrue(NaN.is_inf(INF))
end

function TestNaNProtection:test_is_inf_neg_inf()
   lu.assertTrue(NaN.is_inf(-INF))
end

function TestNaNProtection:test_is_inf_normal_number()
   lu.assertFalse(NaN.is_inf(1))
end

function TestNaNProtection:test_is_inf_nan_is_false()
   lu.assertFalse(NaN.is_inf(NAN))
end

-- ── sanitize_inline ─────────────────────────────────────────────────────────

function TestNaNProtection:test_sanitize_inline_nil_returns_0()
   lu.assertEquals(NaN.sanitize_inline(nil), 0)
end

function TestNaNProtection:test_sanitize_inline_number_passthrough()
   lu.assertEquals(NaN.sanitize_inline(42), 42)
end

function TestNaNProtection:test_sanitize_inline_nan_preserved()
   -- NaN is preserved so overflow displays are not coerced mid-animation.
   local result = NaN.sanitize_inline(NAN)
   lu.assertTrue(result ~= result)   -- NaN ~= NaN
end

-- ── should_clamp_infinity ────────────────────────────────────────────────────

function TestNaNProtection:test_should_clamp_infinity_defaults_false()
   -- config.lua defaults clamp_infinity_scores = false
   lu.assertFalse(NaN.should_clamp_infinity())
end

function TestNaNProtection:test_should_clamp_infinity_when_enabled()
   local orig = REWINDER.config.clamp_infinity_scores
   REWINDER.config.clamp_infinity_scores = true
   lu.assertTrue(NaN.should_clamp_infinity())
   REWINDER.config.clamp_infinity_scores = orig
end

-- ── score_gt ────────────────────────────────────────────────────────────────

function TestNaNProtection:test_score_gt_basic_true()
   lu.assertTrue(NaN.score_gt(10, 5))
end

function TestNaNProtection:test_score_gt_basic_false()
   lu.assertFalse(NaN.score_gt(5, 10))
end

function TestNaNProtection:test_score_gt_equal_false()
   lu.assertFalse(NaN.score_gt(5, 5))
end

function TestNaNProtection:test_score_gt_nil_amount_false()
   lu.assertFalse(NaN.score_gt(nil, 5))
end

function TestNaNProtection:test_score_gt_nan_amount_vs_number()
   -- NaN is treated as "beats" finite values (see NaNProtection semantics).
   lu.assertTrue(NaN.score_gt(NAN, 5))
end

function TestNaNProtection:test_score_gt_number_vs_nan_false()
   lu.assertFalse(NaN.score_gt(5, NAN))
end

function TestNaNProtection:test_score_gt_inf_vs_finite()
   lu.assertTrue(NaN.score_gt(INF, 1e100))
end

function TestNaNProtection:test_score_gt_finite_vs_inf_false()
   lu.assertFalse(NaN.score_gt(1e100, INF))
end

-- ── sanitize_number_format ───────────────────────────────────────────────────

function TestNaNProtection:test_sanitize_number_format_nil_returns_zero_string()
   local v, early = NaN.sanitize_number_format(nil)
   lu.assertEquals(v, "0")
   lu.assertTrue(early)
end

function TestNaNProtection:test_sanitize_number_format_string_passthrough()
   local v, early = NaN.sanitize_number_format("hello")
   lu.assertEquals(v, "hello")
   lu.assertTrue(early)
end

function TestNaNProtection:test_sanitize_number_format_normal_number_no_early()
   local v, early = NaN.sanitize_number_format(5)
   lu.assertEquals(v, 5)
   lu.assertFalse(early)
end

function TestNaNProtection:test_sanitize_number_format_large_number_scientific()
   local v, early = NaN.sanitize_number_format(1e295)
   lu.assertTrue(early)
   lu.assertIsString(v)
   lu.assertStrContains(v, "e")
end

function TestNaNProtection:test_sanitize_number_format_never_throws_for_nan()
   -- Should not error even for NaN input.
   local ok, _ = pcall(NaN.sanitize_number_format, NAN)
   lu.assertTrue(ok)
end

function TestNaNProtection:test_sanitize_number_format_never_throws_for_inf()
   local ok, _ = pcall(NaN.sanitize_number_format, INF)
   lu.assertTrue(ok)
end
