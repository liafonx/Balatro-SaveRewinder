-- tests/unit/test_entry_schema.lua
-- Tests for Core/SaveModules/EntrySchema.lua

local lu = require("luaunit")
local Schema = require("SaveManagerEntrySchema")

TestEntrySchema = {}

-- ── ENTRY_KEYS ordering ─────────────────────────────────────────────────────

function TestEntrySchema:test_entry_file_is_index_1()
   lu.assertEquals(Schema.ENTRY_FILE, 1)
end

function TestEntrySchema:test_entry_keys_are_sequential()
   for i, key in ipairs(Schema.ENTRY_KEYS) do
      lu.assertEquals(Schema["ENTRY_" .. key], i,
         "ENTRY_" .. key .. " should equal " .. i)
   end
end

function TestEntrySchema:test_entry_is_key_is_last()
   lu.assertEquals(Schema.ENTRY_IS_KEY, #Schema.ENTRY_KEYS)
end

-- ── E alias table ───────────────────────────────────────────────────────────

function TestEntrySchema:test_E_alias_matches_M_for_all_keys()
   for _, key in ipairs(Schema.ENTRY_KEYS) do
      local field = "ENTRY_" .. key
      lu.assertEquals(Schema.E[field], Schema[field],
         "E." .. field .. " does not match M." .. field)
   end
end

function TestEntrySchema:test_E_has_no_extra_keys()
   local e_count = 0
   for _ in pairs(Schema.E) do e_count = e_count + 1 end
   lu.assertEquals(e_count, #Schema.ENTRY_KEYS)
end

-- ── blind_key_to_index ──────────────────────────────────────────────────────

function TestEntrySchema:test_blind_key_to_index_nil_returns_0()
   lu.assertEquals(Schema.blind_key_to_index(nil), 0)
end

function TestEntrySchema:test_blind_key_to_index_undiscovered_returns_0()
   lu.assertEquals(Schema.blind_key_to_index("bl_undiscovered"), 0)
end

function TestEntrySchema:test_blind_key_to_index_small_returns_1()
   lu.assertEquals(Schema.blind_key_to_index("bl_small"), 1)
end

function TestEntrySchema:test_blind_key_to_index_unknown_returns_0()
   lu.assertEquals(Schema.blind_key_to_index("bl_does_not_exist"), 0)
end

-- ── index_to_blind_key ──────────────────────────────────────────────────────

function TestEntrySchema:test_index_to_blind_key_nil_returns_nil()
   lu.assertIsNil(Schema.index_to_blind_key(nil))
end

function TestEntrySchema:test_index_to_blind_key_0_returns_undiscovered()
   lu.assertEquals(Schema.index_to_blind_key(0), "bl_undiscovered")
end

function TestEntrySchema:test_index_to_blind_key_1_returns_small()
   lu.assertEquals(Schema.index_to_blind_key(1), "bl_small")
end

function TestEntrySchema:test_index_out_of_range_returns_nil()
   lu.assertIsNil(Schema.index_to_blind_key(9999))
end

-- ── bijection ───────────────────────────────────────────────────────────────

function TestEntrySchema:test_blind_key_index_bijection_round_trip()
   -- For every valid index, round-trip through index_to_blind_key and back.
   for i = 1, 30 do
      local key = Schema.index_to_blind_key(i)
      if key then
         lu.assertEquals(Schema.blind_key_to_index(key), i,
            "Round-trip failed at index " .. i)
      end
   end
end

-- ── meta_filename ───────────────────────────────────────────────────────────

function TestEntrySchema:test_meta_filename_replaces_jkr_extension()
   lu.assertEquals(Schema.meta_filename("save_001.jkr"), "save_001.meta")
end

function TestEntrySchema:test_meta_filename_no_extension_unchanged()
   lu.assertEquals(Schema.meta_filename("nodot"), "nodot")
end

function TestEntrySchema:test_meta_filename_wrong_extension_unchanged()
   lu.assertEquals(Schema.meta_filename("file.zip"), "file.zip")
end
