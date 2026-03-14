-- tests/unit/test_export_service.lua
-- Tests for Core/ExportService.lua — only format_seed is tested here since
-- build_run_folder_name / export_selected require full G.GAME state.

local lu = require("luaunit")
local ES = require("ExportService")

TestExportService = {}

-- ── format_seed (seeded runs always get full seed) ───────────────────────────

function TestExportService:test_seeded_run_returns_full_seed()
   lu.assertEquals(ES.format_seed("ABCDEFGH", true), "ABCDEFGH")
end

function TestExportService:test_seeded_empty_seed_returns_empty()
   lu.assertEquals(ES.format_seed("", true), "")
end

-- ── format_seed (non-seeded, default config: abbreviate) ─────────────────────

function TestExportService:test_non_seeded_short_seed_unchanged()
   -- seeds with fewer than 3 chars are returned as-is
   lu.assertEquals(ES.format_seed("AB", false), "AB")
   lu.assertEquals(ES.format_seed("A",  false), "A")
   lu.assertEquals(ES.format_seed("",   false), "")
end

function TestExportService:test_non_seeded_masks_positions_3_to_6()
   -- "ABCDEF" → chars[3..6] masked with 'X' → "ABXXXX" (only 6 chars)
   lu.assertEquals(ES.format_seed("ABCDEF", false), "ABXXXX")
end

function TestExportService:test_non_seeded_long_seed_masks_only_3_to_6()
   -- "ABCDEFGH" → "ABXXXXGH" (positions 3-6 masked, 7-8 intact)
   lu.assertEquals(ES.format_seed("ABCDEFGH", false), "ABXXXXGH")
end

function TestExportService:test_non_seeded_3_char_seed_masks_just_pos_3()
   -- "ABC" → "ABX"
   lu.assertEquals(ES.format_seed("ABC", false), "ABX")
end

-- ── format_seed (non-seeded, show full via export_full_seed_non_seeded) ──────

function TestExportService:test_non_seeded_full_when_flag_true()
   local orig = REWINDER.config.export_full_seed_non_seeded
   REWINDER.config.export_full_seed_non_seeded = true
   lu.assertEquals(ES.format_seed("ABCDEFGH", false), "ABCDEFGH")
   REWINDER.config.export_full_seed_non_seeded = orig
end

-- ── format_seed (non-seeded, show full via legacy export_seed_mode=2) ────────

function TestExportService:test_non_seeded_full_when_seed_mode_2()
   local orig_flag = REWINDER.config.export_full_seed_non_seeded
   local orig_mode = REWINDER.config.export_seed_mode
   -- Remove the boolean flag so the code falls through to the numeric mode check.
   REWINDER.config.export_full_seed_non_seeded = nil
   REWINDER.config.export_seed_mode = 2
   lu.assertEquals(ES.format_seed("ABCDEFGH", false), "ABCDEFGH")
   REWINDER.config.export_full_seed_non_seeded = orig_flag
   REWINDER.config.export_seed_mode = orig_mode
end

-- ── format_seed nil seed ─────────────────────────────────────────────────────

function TestExportService:test_nil_seed_treated_as_empty_string()
   lu.assertEquals(ES.format_seed(nil, true), "")
end
