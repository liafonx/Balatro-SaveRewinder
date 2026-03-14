-- tests/unit/test_state_signature.lua
-- Tests for Utils/StateSignature.lua

local lu = require("luaunit")
local SS = require("StateSignature")

TestStateSignature = {}

-- ── encode_signature ────────────────────────────────────────────────────────

function TestStateSignature:test_encode_all_args()
   lu.assertEquals(SS.encode_signature(1, 2, "S", 0, 0, 5), "1:2:S:0:0:5")
end

function TestStateSignature:test_encode_nil_args_use_defaults()
   lu.assertEquals(SS.encode_signature(nil, nil, nil, nil, nil, nil), "0:0:?:0:0:0")
end

function TestStateSignature:test_encode_is_deterministic()
   local a = SS.encode_signature(3, 1, "P", 2, 5, 100)
   local b = SS.encode_signature(3, 1, "P", 2, 5, 100)
   lu.assertEquals(a, b)
end

function TestStateSignature:test_encode_different_inputs_differ()
   local a = SS.encode_signature(1, 1, "S", 0, 0, 0)
   local b = SS.encode_signature(1, 1, "S", 1, 0, 0)
   lu.assertNotEquals(a, b)
end

-- ── has_action ──────────────────────────────────────────────────────────────

function TestStateSignature:test_has_action_nil_run_data_returns_nil()
   -- run_data=nil → action=nil → `nil and ...` short-circuits to nil
   lu.assertIsNil(SS.has_action(nil))
end

function TestStateSignature:test_has_action_no_action_field_returns_nil()
   -- No ACTION field → action=nil → same short-circuit
   lu.assertIsNil(SS.has_action({}))
end

function TestStateSignature:test_has_action_empty_action_returns_false()
   lu.assertFalse(SS.has_action({ ACTION = {} }))
end

function TestStateSignature:test_has_action_populated_action_returns_true()
   lu.assertTrue(SS.has_action({ ACTION = { type = "open" } }))
end

-- ── get_label_from_display_type ─────────────────────────────────────────────

function TestStateSignature:test_label_S_is_shop()
   lu.assertEquals(SS.get_label_from_display_type("S"), "shop")
end

function TestStateSignature:test_label_unknown_code_is_save()
   lu.assertEquals(SS.get_label_from_display_type("Z"), "save")
end

function TestStateSignature:test_label_nil_is_in_run()
   lu.assertEquals(SS.get_label_from_display_type(nil), "in run")
end

function TestStateSignature:test_label_question_mark_is_in_run()
   lu.assertEquals(SS.get_label_from_display_type("?"), "in run")
end

function TestStateSignature:test_all_defined_codes_return_non_empty()
   local codes = { "S", "A", "F", "O", "R", "P", "D", "H", "E", "B", "?" }
   for _, code in ipairs(codes) do
      local label = SS.get_label_from_display_type(code)
      lu.assertIsString(label)
      lu.assertTrue(#label > 0, "label for '" .. code .. "' is empty")
   end
end

-- ── describe_save ───────────────────────────────────────────────────────────

function TestStateSignature:test_describe_save_contains_ante()
   local desc = SS.describe_save(3, 2, "S")
   lu.assertStrContains(desc, "3")
end

function TestStateSignature:test_describe_save_contains_round()
   local desc = SS.describe_save(3, 2, "S")
   lu.assertStrContains(desc, "2")
end

-- ── compute_display_type (requires G.STATES) ────────────────────────────────

function TestStateSignature:test_compute_shop_state_returns_S()
   local st = G.STATES
   lu.assertEquals(SS.compute_display_type(st.SHOP, nil, false, false, false, false), "S")
end

function TestStateSignature:test_compute_opening_pack_returns_O()
   local st = G.STATES
   lu.assertEquals(SS.compute_display_type(st.SHOP, nil, true, false, false, false), "O")
end

function TestStateSignature:test_compute_first_shop_returns_F()
   local st = G.STATES
   lu.assertEquals(SS.compute_display_type(st.SHOP, nil, false, true, false, false), "F")
end

function TestStateSignature:test_compute_selecting_hand_start_round_returns_R()
   local st = G.STATES
   lu.assertEquals(SS.compute_display_type(st.SELECTING_HAND, nil, false, false, true, false), "R")
end

function TestStateSignature:test_compute_selecting_hand_play_returns_P()
   local st = G.STATES
   lu.assertEquals(SS.compute_display_type(st.SELECTING_HAND, "play", false, false, false, false), "P")
end

function TestStateSignature:test_compute_round_eval_returns_E()
   local st = G.STATES
   lu.assertEquals(SS.compute_display_type(st.ROUND_EVAL, nil, false, false, false, false), "E")
end

function TestStateSignature:test_compute_blind_select_returns_B()
   local st = G.STATES
   lu.assertEquals(SS.compute_display_type(st.BLIND_SELECT, nil, false, false, false, false), "B")
end

function TestStateSignature:test_compute_no_G_STATES_returns_question_mark()
   local saved = G.STATES
   G.STATES = nil
   local result = SS.compute_display_type(1, nil, false, false, false, false)
   G.STATES = saved
   lu.assertEquals(result, "?")
end

-- ── get_state_info ──────────────────────────────────────────────────────────

function TestStateSignature:test_get_state_info_nil_returns_nil()
   lu.assertIsNil(SS.get_state_info(nil))
end

function TestStateSignature:test_get_state_info_non_table_returns_nil()
   lu.assertIsNil(SS.get_state_info("bad"))
end

function TestStateSignature:test_get_state_info_returns_table()
   local info = SS.get_state_info({
      STATE = G.STATES.SHOP,
      GAME  = {
         round = 1,
         round_resets = { ante = 2 },
         dollars = 5,
         current_round = { discards_used = 0, hands_played = 0 },
      },
   })
   lu.assertIsTable(info)
   lu.assertEquals(info.ante, 2)
   lu.assertEquals(info.round, 1)
   lu.assertEquals(info.money, 5)
end
