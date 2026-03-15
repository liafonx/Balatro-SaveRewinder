-- tests/unit/test_keybinds.lua
-- Tests for Utils/Keybinds.lua private helpers (exposed via Keybinds._xxx).
-- Uses dofile with stubs because Keybinds hooks Controller at load time.

local lu = require("luaunit")

-- Stubs required before dofile --
-- ControllerNavigation is already in package.preload (stub from test_env.lua).
-- Controller is nil in tests; hooks in Keybinds are guarded with `if not Controller`.

-- Reset config keybinds so each run sees a clean state.
REWINDER.config = REWINDER.config or {}
REWINDER.config.keybinds = nil

dofile("Utils/Keybinds.lua")

local Keybinds = REWINDER.keybinds

TestKeybinds = {}

function TestKeybinds:setUp()
   -- Fresh keybind config for each test
   REWINDER.config.keybinds = nil
   Keybinds._ensure_config_keybinds()
end

-- ── _normalize_key_name ───────────────────────────────────────────────────────

function TestKeybinds:test_normalize_lctrl_to_ctrl()
   lu.assertEquals(Keybinds._normalize_key_name("lctrl"), "ctrl")
   lu.assertEquals(Keybinds._normalize_key_name("rctrl"), "ctrl")
end

function TestKeybinds:test_normalize_lgui_rgui_to_cmd()
   lu.assertEquals(Keybinds._normalize_key_name("lgui"), "cmd")
   lu.assertEquals(Keybinds._normalize_key_name("rgui"), "cmd")
end

function TestKeybinds:test_normalize_passthrough_for_other_keys()
   lu.assertEquals(Keybinds._normalize_key_name("a"), "a")
   lu.assertEquals(Keybinds._normalize_key_name("space"), "space")
end

-- ── _normalize_button_name ────────────────────────────────────────────────────

function TestKeybinds:test_normalize_button_name_prepends_gp()
   lu.assertEquals(Keybinds._normalize_button_name("a"), "gp_a")
   lu.assertEquals(Keybinds._normalize_button_name("start"), "gp_start")
end

-- ── _format_key_name ─────────────────────────────────────────────────────────

function TestKeybinds:test_format_key_name_ctrl()
   lu.assertEquals(Keybinds._format_key_name("ctrl"), "Ctrl")
end

function TestKeybinds:test_format_key_name_single_char_uppercased()
   lu.assertEquals(Keybinds._format_key_name("s"), "S")
   lu.assertEquals(Keybinds._format_key_name("l"), "L")
end

function TestKeybinds:test_format_key_name_gamepad_mapped()
   lu.assertEquals(Keybinds._format_key_name("gp_a"), "A")
   lu.assertEquals(Keybinds._format_key_name("gp_x"), "X")
   lu.assertEquals(Keybinds._format_key_name("gp_leftstick"), "L3")
end

function TestKeybinds:test_format_key_name_shift()
   lu.assertEquals(Keybinds._format_key_name("shift"), "Shift")
end

-- ── _sorted_keys ──────────────────────────────────────────────────────────────

function TestKeybinds:test_sorted_keys_modifiers_first()
   local binding = { ctrl = true, s = true }
   local keys = Keybinds._sorted_keys(binding)
   lu.assertEquals(keys[1], "ctrl")
   lu.assertEquals(keys[2], "s")
end

function TestKeybinds:test_sorted_keys_nil_returns_empty()
   local keys = Keybinds._sorted_keys(nil)
   lu.assertEquals(#keys, 0)
end

-- ── _binding_size ─────────────────────────────────────────────────────────────

function TestKeybinds:test_binding_size_counts_keys()
   local binding = { keyboard = { ctrl = true, s = true } }
   lu.assertEquals(Keybinds._binding_size(binding, "keyboard"), 2)
end

function TestKeybinds:test_binding_size_zero_for_nil()
   lu.assertEquals(Keybinds._binding_size(nil, "keyboard"), 0)
end

function TestKeybinds:test_binding_size_zero_for_none_binding()
   local binding = { keyboard = { ["[none]"] = true } }
   lu.assertEquals(Keybinds._binding_size(binding, "keyboard"), 0)
end

-- ── _clone_binding ────────────────────────────────────────────────────────────

function TestKeybinds:test_clone_binding_shallow_copy_independent()
   local orig = { ctrl = true, s = true }
   local copy = Keybinds._clone_binding(orig)
   lu.assertNotIs(orig, copy)
   lu.assertTrue(copy.ctrl)
   lu.assertTrue(copy.s)
   -- Mutation to copy doesn't affect orig
   copy.x = true
   lu.assertNil(orig.x)
end

function TestKeybinds:test_clone_binding_nil_returns_nil()
   lu.assertNil(Keybinds._clone_binding(nil))
end

-- ── _is_keybind_pressed ───────────────────────────────────────────────────────

function TestKeybinds:test_is_keybind_pressed_all_held_true()
   local ctrl = { held_keys = { ctrl = true, s = true }, held_buttons = {} }
   -- Controller uses normalized "ctrl" to check for lctrl/rctrl
   ctrl.held_keys.lctrl = true
   ctrl.held_keys.s     = true
   local binding = { keyboard = { ctrl = true, s = true } }
   lu.assertTrue(Keybinds._is_keybind_pressed(ctrl, binding, "keyboard"))
end

function TestKeybinds:test_is_keybind_pressed_missing_key_false()
   local ctrl = { held_keys = { s = true }, held_buttons = {} }
   local binding = { keyboard = { ctrl = true, s = true } }
   lu.assertFalse(Keybinds._is_keybind_pressed(ctrl, binding, "keyboard"))
end

function TestKeybinds:test_is_keybind_pressed_none_binding_false()
   local ctrl = { held_keys = { s = true }, held_buttons = {} }
   local binding = { keyboard = { ["[none]"] = true } }
   lu.assertFalse(Keybinds._is_keybind_pressed(ctrl, binding, "keyboard"))
end

-- ── _cooldown_gate ────────────────────────────────────────────────────────────

function TestKeybinds:test_cooldown_gate_first_call_passes()
   local ok, t = Keybinds._cooldown_gate(nil, 0.25)
   lu.assertTrue(ok)
   lu.assertNotNil(t)
end

function TestKeybinds:test_cooldown_gate_within_cooldown_blocked()
   local _, last = Keybinds._cooldown_gate(nil, 0.25)
   -- Immediately call again — still within cooldown
   local ok2, _ = Keybinds._cooldown_gate(last, 100)  -- 100s cooldown
   lu.assertFalse(ok2)
end

-- ── _ensure_config_keybinds ───────────────────────────────────────────────────

function TestKeybinds:test_ensure_config_keybinds_populates_missing_defaults()
   REWINDER.config.keybinds = {}
   Keybinds._ensure_config_keybinds()
   lu.assertNotNil(REWINDER.config.keybinds.step_back)
   lu.assertNotNil(REWINDER.config.keybinds.toggle_saves)
   lu.assertNotNil(REWINDER.config.keybinds.quick_saveload)
end

-- ── _is_enter_key ─────────────────────────────────────────────────────────────

function TestKeybinds:test_is_enter_key_return()
   lu.assertTrue(Keybinds._is_enter_key("return"))
end

function TestKeybinds:test_is_enter_key_kpenter()
   lu.assertTrue(Keybinds._is_enter_key("kpenter"))
end

function TestKeybinds:test_is_enter_key_other_false()
   lu.assertFalse(Keybinds._is_enter_key("space"))
   lu.assertFalse(Keybinds._is_enter_key("a"))
end
