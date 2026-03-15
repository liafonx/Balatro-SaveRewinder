-- tests/unit/test_button_callback_helpers.lua
-- Tests for UI/ButtonCallbackHelpers.lua exposed private helpers.

local lu  = require("luaunit")

-- UIButtonCallbackHelpers requires UIShared, UILayout, ScaleNumberHook,
-- UIIconFactory, KeySaves — all pre-loaded via test_env.lua preloads.
-- We also need G.C stubs for any call-time access.
G.C = G.C or {}
G.C.UI = G.C.UI or { TEXT_LIGHT = {0.85,0.85,0.85,1}, TEXT_INACTIVE = {0.5,0.5,0.5,1} }
G.C.RED   = G.C.RED   or {0.9, 0.2, 0.2, 1}
G.C.BLUE  = G.C.BLUE  or {0.2, 0.4, 0.9, 1}
G.C.WHITE = G.C.WHITE or {1, 1, 1, 1}
G.C.BLACK = G.C.BLACK or {0, 0, 0, 1}
G.C.ORANGE = G.C.ORANGE or {1, 0.6, 0.2, 1}
G.FUNCS = G.FUNCS or {}

local BCH = require("UIButtonCallbackHelpers")

TestButtonCallbackHelpers = {}

function TestButtonCallbackHelpers:setUp()
   -- Reset REWINDER mode state
   REWINDER._mark_active           = false
   REWINDER._rename_active         = false
   REWINDER._export_active         = false
   REWINDER._filter_active         = false
   REWINDER._rename_pending        = {}
   REWINDER._rename_pending_clear  = {}
   REWINDER._export_selection      = {}
   REWINDER._rename_editing_file   = nil
   -- Expose normalize_custom_state_name so _normalize_custom_name delegates to it
   REWINDER.normalize_custom_state_name = nil
end

-- ── _normalize_custom_name ────────────────────────────────────────────────────

function TestButtonCallbackHelpers:test_normalize_custom_name_trims_whitespace()
   lu.assertEquals(BCH._normalize_custom_name("  hello  "), "hello")
end

function TestButtonCallbackHelpers:test_normalize_custom_name_nil_for_empty()
   lu.assertNil(BCH._normalize_custom_name("   "))
   lu.assertNil(BCH._normalize_custom_name(""))
end

function TestButtonCallbackHelpers:test_normalize_custom_name_nil_for_non_string()
   lu.assertNil(BCH._normalize_custom_name(nil))
   lu.assertNil(BCH._normalize_custom_name(42))
end

function TestButtonCallbackHelpers:test_normalize_custom_name_delegates_to_rewinder()
   REWINDER.normalize_custom_state_name = function(name) return "delegated:" .. (name or "") end
   lu.assertEquals(BCH._normalize_custom_name("test"), "delegated:test")
   REWINDER.normalize_custom_state_name = nil
end

-- ── rename_has_pending_drafts ─────────────────────────────────────────────────

function TestButtonCallbackHelpers:test_rename_has_pending_drafts_false_initially()
   lu.assertFalse(BCH.rename_has_pending_drafts())
end

function TestButtonCallbackHelpers:test_rename_has_pending_drafts_true_when_pending()
   REWINDER._rename_pending["some_file.jkr"] = "New Name"
   lu.assertTrue(BCH.rename_has_pending_drafts())
end

-- ── _entry_has_pending_badge ──────────────────────────────────────────────────

function TestButtonCallbackHelpers:test_entry_has_pending_badge_false_for_nil()
   lu.assertFalse(BCH._entry_has_pending_badge(nil))
end

function TestButtonCallbackHelpers:test_entry_has_pending_badge_export_pending()
   local entry = { [require("SaveManager").ENTRY_FILE] = "x.jkr" }
   REWINDER._export_active = true
   REWINDER._export_selection["x.jkr"] = true
   lu.assertTrue(BCH._entry_has_pending_badge(entry))
end

function TestButtonCallbackHelpers:test_entry_has_pending_badge_rename_pending()
   local entry = { [require("SaveManager").ENTRY_FILE] = "y.jkr" }
   REWINDER._rename_active = true
   REWINDER._rename_editing_file = nil  -- not currently editing this file
   REWINDER._rename_pending["y.jkr"] = "Some Name"
   lu.assertTrue(BCH._entry_has_pending_badge(entry))
end

function TestButtonCallbackHelpers:test_entry_has_pending_badge_false_when_no_modes()
   local entry = { [require("SaveManager").ENTRY_FILE] = "z.jkr" }
   lu.assertFalse(BCH._entry_has_pending_badge(entry))
end
