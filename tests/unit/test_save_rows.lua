-- tests/unit/test_save_rows.lua
-- Tests for UI/SaveRows.lua pure logic: get_round_color and _build_default_state_title.

local lu      = require("luaunit")

-- G.C stubs needed at call time
G.C = G.C or {}
G.C.UI = G.C.UI or { TEXT_LIGHT = {0.85,0.85,0.85,1} }
G.C.ORANGE = G.C.ORANGE or {1, 0.6, 0.2, 1}
G.C.YELLOW = G.C.YELLOW or {1, 0.9, 0.2, 1}
G.C.CLEAR  = G.C.CLEAR  or {0, 0, 0, 0}

local SaveRows = require("UISaveRows")
local E        = require("SaveManagerEntrySchema")

-- Copy ENTRY_* constants from SaveManager to REWINDER (normally done by Init.lua).
local SM = require("SaveManager")
for k, v in pairs(SM) do
   if k:match("^ENTRY_") then REWINDER[k] = v end
end

TestSaveRows = {}

-- ── get_round_color ───────────────────────────────────────────────────────────

function TestSaveRows:test_get_round_color_nil_returns_text_light()
   local c = REWINDER.get_round_color(nil)
   lu.assertIs(c, G.C.UI.TEXT_LIGHT)
end

function TestSaveRows:test_get_round_color_even_returns_orange()
   local c = REWINDER.get_round_color(2)
   lu.assertIs(c, G.C.ORANGE)
end

function TestSaveRows:test_get_round_color_odd_returns_yellow()
   local c = REWINDER.get_round_color(1)
   lu.assertIs(c, G.C.YELLOW)
end

function TestSaveRows:test_get_round_color_zero_returns_orange()
   -- 0 % 2 == 0 → even → orange
   local c = REWINDER.get_round_color(0)
   lu.assertIs(c, G.C.ORANGE)
end

-- ── _build_default_state_title ────────────────────────────────────────────────

function TestSaveRows:test_build_state_title_nil_entry_returns_empty()
   lu.assertEquals(SaveRows._build_default_state_title(nil), "")
end

function TestSaveRows:test_build_state_title_no_display_type_returns_in_run()
   local entry = {}
   entry[E.ENTRY_DISPLAY_TYPE] = nil
   entry[E.ENTRY_ORDINAL]      = nil
   lu.assertEquals(SaveRows._build_default_state_title(entry), "in run")
end

function TestSaveRows:test_build_state_title_shop_with_ordinal()
   local entry = {}
   entry[E.ENTRY_DISPLAY_TYPE] = "S"
   entry[E.ENTRY_ORDINAL]      = 3
   local title = SaveRows._build_default_state_title(entry)
   -- "rewinder_state_shop" (loc fallback) + " " + "3"
   lu.assertStrContains(title, "3")
   lu.assertStrContains(title, "rewinder_state_shop")
end

function TestSaveRows:test_build_state_title_ordinal_zero_suppressed()
   local entry = {}
   entry[E.ENTRY_DISPLAY_TYPE] = "S"
   entry[E.ENTRY_ORDINAL]      = 0
   local title = SaveRows._build_default_state_title(entry)
   -- ordinal 0 should not appear
   lu.assertNotStrContains(title, "0")
end

function TestSaveRows:test_build_state_title_P_type_uses_card_number_spacing()
   local entry = {}
   entry[E.ENTRY_DISPLAY_TYPE] = "P"
   entry[E.ENTRY_ORDINAL]      = 2
   local title = SaveRows._build_default_state_title(entry)
   lu.assertStrContains(title, "2")
end
