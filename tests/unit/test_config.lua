-- tests/unit/test_config.lua
-- Validates the config.lua schema: required keys, types, and default values.

local lu = require("luaunit")

TestConfig = {}

local config = dofile("config.lua")

function TestConfig:test_config_is_table()
   lu.assertIsTable(config)
end

function TestConfig:test_save_flags_are_boolean()
   lu.assertIsBoolean(config.save_on_blind)
   lu.assertIsBoolean(config.save_on_selecting_hand)
   lu.assertIsBoolean(config.save_on_round_end)
   lu.assertIsBoolean(config.save_on_shop)
end

function TestConfig:test_debug_saves_is_false_by_default()
   lu.assertIsBoolean(config.debug_saves)
   lu.assertFalse(config.debug_saves)
end

function TestConfig:test_keep_antes_is_valid_index()
   lu.assertIsNumber(config.keep_antes)
   lu.assertTrue(config.keep_antes >= 1 and config.keep_antes <= 7,
      "keep_antes must be 1-7, got " .. tostring(config.keep_antes))
end

function TestConfig:test_max_saves_per_type_is_valid_index()
   lu.assertIsNumber(config.max_saves_per_type_per_round)
   lu.assertTrue(config.max_saves_per_type_per_round >= 1 and
                 config.max_saves_per_type_per_round <= 5,
      "max_saves_per_type_per_round must be 1-5")
end

function TestConfig:test_clamp_infinity_is_boolean()
   lu.assertIsBoolean(config.clamp_infinity_scores)
end

function TestConfig:test_export_seed_mode_is_number()
   lu.assertIsNumber(config.export_seed_mode)
end

function TestConfig:test_keybinds_is_table_with_required_keys()
   lu.assertIsTable(config.keybinds)
   lu.assertIsTable(config.keybinds.step_back)
   lu.assertIsTable(config.keybinds.toggle_saves)
   lu.assertIsTable(config.keybinds.quick_saveload)
end

function TestConfig:test_keybinds_have_keyboard_and_controller()
   for name, bind in pairs(config.keybinds) do
      lu.assertIsTable(bind.keyboard,    name .. ".keyboard must be a table")
      lu.assertIsTable(bind.controller,  name .. ".controller must be a table")
   end
end
