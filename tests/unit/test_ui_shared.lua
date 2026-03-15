-- tests/unit/test_ui_shared.lua
-- Tests for UI/Shared.lua pure helper functions.

local lu      = require("luaunit")
local UIShared = require("UIShared")

TestUIShared = {}

function TestUIShared:setUp()
   -- Reset REWINDER mode flags
   REWINDER._rename_active  = false
   REWINDER._mark_active    = false
   REWINDER._export_active  = false
   REWINDER._filter_active  = false
end

-- ── clamp_page ────────────────────────────────────────────────────────────────

function TestUIShared:test_clamp_page_within_range()
   lu.assertEquals(UIShared.clamp_page(3, 5), 3)
end

function TestUIShared:test_clamp_page_below_1_clamps_to_1()
   lu.assertEquals(UIShared.clamp_page(0, 5), 1)
   lu.assertEquals(UIShared.clamp_page(-3, 5), 1)
end

function TestUIShared:test_clamp_page_above_total_clamps_to_total()
   lu.assertEquals(UIShared.clamp_page(10, 5), 5)
end

function TestUIShared:test_clamp_page_nil_defaults_to_1()
   lu.assertEquals(UIShared.clamp_page(nil, 5), 1)
end

function TestUIShared:test_clamp_page_nil_total_defaults_to_1()
   lu.assertEquals(UIShared.clamp_page(3, nil), 1)
end

-- ── build_page_numbers ────────────────────────────────────────────────────────

function TestUIShared:test_build_page_numbers_count()
   local pages = UIShared.build_page_numbers(4)
   lu.assertEquals(#pages, 4)
end

function TestUIShared:test_build_page_numbers_format_contains_numbers()
   local pages = UIShared.build_page_numbers(3)
   -- Each entry should contain "1", "2", "3" somewhere
   for i, pg in ipairs(pages) do
      lu.assertStrContains(pg, tostring(i))
      lu.assertStrContains(pg, "3")   -- total is always present
   end
end

-- ── dim_colour ────────────────────────────────────────────────────────────────

function TestUIShared:test_dim_colour_multiplies_rgb()
   local c = { 1, 0.5, 0.25, 1 }
   local dimmed = UIShared.dim_colour(c, 0.5)
   lu.assertAlmostEquals(dimmed[1], 0.5,  1e-9)
   lu.assertAlmostEquals(dimmed[2], 0.25, 1e-9)
   lu.assertAlmostEquals(dimmed[3], 0.125, 1e-9)
   lu.assertEquals(dimmed[4], 1)   -- alpha preserved
end

function TestUIShared:test_dim_colour_preserves_alpha()
   local c = { 1, 1, 1, 0.7 }
   local dimmed = UIShared.dim_colour(c, 0.45)
   lu.assertEquals(dimmed[4], 0.7)
end

function TestUIShared:test_dim_colour_non_table_passthrough()
   lu.assertEquals(UIShared.dim_colour("not_a_colour"), "not_a_colour")
   lu.assertNil(UIShared.dim_colour(nil))
end

-- ── compute_mode_enabled_flags ────────────────────────────────────────────────

function TestUIShared:test_compute_mode_enabled_flags_all_enabled_default()
   local flags = UIShared.compute_mode_enabled_flags(false)
   lu.assertTrue(flags.mark_enabled)
   lu.assertTrue(flags.rename_enabled)
   lu.assertTrue(flags.jump_enabled)
   lu.assertTrue(flags.filter_enabled)
   lu.assertTrue(flags.export_enabled)
end

function TestUIShared:test_compute_mode_enabled_flags_loading_mode_disables_all()
   local flags = UIShared.compute_mode_enabled_flags(true)
   lu.assertFalse(flags.mark_enabled)
   lu.assertFalse(flags.rename_enabled)
   lu.assertFalse(flags.jump_enabled)
   lu.assertFalse(flags.filter_enabled)
   lu.assertFalse(flags.export_enabled)
end

function TestUIShared:test_compute_mode_enabled_flags_mark_active_disables_rename()
   REWINDER._mark_active = true
   local flags = UIShared.compute_mode_enabled_flags(false)
   lu.assertFalse(flags.rename_enabled)
   lu.assertTrue(flags.mark_enabled)
end

function TestUIShared:test_compute_mode_enabled_flags_rename_active_disables_mark()
   REWINDER._rename_active = true
   local flags = UIShared.compute_mode_enabled_flags(false)
   lu.assertFalse(flags.mark_enabled)
   lu.assertTrue(flags.rename_enabled)
end
