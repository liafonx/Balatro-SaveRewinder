-- tests/unit/test_serialization_guard.lua
-- Tests for Core/SerializationGuard.lua private helpers (exposed via return table).

local lu = require("luaunit")

-- Load module; it returns a table of exposed private functions.
local SG = require("SerializationGuard")

TestSerializationGuard = {}

-- ── _is_channel_serializable ─────────────────────────────────────────────────

function TestSerializationGuard:test_is_channel_serializable_nil()
   lu.assertTrue(SG._is_channel_serializable(nil))
end

function TestSerializationGuard:test_is_channel_serializable_bool()
   lu.assertTrue(SG._is_channel_serializable(true))
   lu.assertTrue(SG._is_channel_serializable(false))
end

function TestSerializationGuard:test_is_channel_serializable_number()
   lu.assertTrue(SG._is_channel_serializable(42))
   lu.assertTrue(SG._is_channel_serializable(3.14))
end

function TestSerializationGuard:test_is_channel_serializable_string()
   lu.assertTrue(SG._is_channel_serializable("hello"))
end

function TestSerializationGuard:test_is_channel_serializable_table()
   lu.assertTrue(SG._is_channel_serializable({}))
end

function TestSerializationGuard:test_is_channel_serializable_function_false()
   lu.assertFalse(SG._is_channel_serializable(function() end))
end

function TestSerializationGuard:test_is_channel_serializable_thread_false()
   lu.assertFalse(SG._is_channel_serializable(coroutine.create(function() end)))
end

-- ── _contains_object_ref_bounded ─────────────────────────────────────────────

function TestSerializationGuard:test_contains_object_ref_plain_table_false()
   local found, visited, truncated = SG._contains_object_ref_bounded({ a = 1, b = { c = 2 } }, 100)
   lu.assertFalse(found)
   lu.assertFalse(truncated)
end

function TestSerializationGuard:test_contains_object_ref_non_table_false()
   local found = SG._contains_object_ref_bounded("string", 100)
   lu.assertFalse(found)
end

function TestSerializationGuard:test_contains_object_ref_truncates_at_limit()
   -- Build a table large enough to trigger truncation at limit=2
   local big = {}
   for i = 1, 20 do
      big[i] = { value = i, nested = { deeper = i } }
   end
   local found, visited, truncated = SG._contains_object_ref_bounded(big, 2)
   lu.assertTrue(truncated)
end

function TestSerializationGuard:test_contains_object_ref_with_object_mock()
   -- Simulate a table with an :is() method (Object mock)
   Object = { is = function(self, cls) return cls == Object end }  -- luacheck: ignore 111
   local obj = {
      is = function(self, cls)
         return cls == Object
      end
   }
   local t = { obj = obj }
   local found = SG._contains_object_ref_bounded(t, 1000)
   lu.assertTrue(found)
   Object = nil  -- luacheck: ignore 111
end

-- ── _find_first_nonserializable_path ─────────────────────────────────────────

function TestSerializationGuard:test_find_first_nonserializable_clean_table()
   local clean = { a = 1, b = "hello", c = { d = true } }
   local path, t, truncated = SG._find_first_nonserializable_path(clean, 1000)
   lu.assertNil(path)
   lu.assertNil(t)
   lu.assertFalse(truncated)
end

function TestSerializationGuard:test_find_first_nonserializable_function_value()
   local bad = { a = 1, callback = function() end }
   local path, typ, truncated = SG._find_first_nonserializable_path(bad, 1000)
   lu.assertNotNil(path)
   lu.assertEquals(typ, "function")
   lu.assertFalse(truncated)
end

function TestSerializationGuard:test_find_first_nonserializable_truncated_at_limit()
   -- Build a tree that exceeds the node limit
   local big = {}
   local current = big
   for _ = 1, 30 do
      current.child = {}
      current = current.child
   end
   local path, _, truncated = SG._find_first_nonserializable_path(big, 5)
   lu.assertNil(path)   -- no bad value found before truncation
   lu.assertTrue(truncated)
end

function TestSerializationGuard:test_find_first_nonserializable_non_table_root()
   local path = SG._find_first_nonserializable_path("not a table", 100)
   lu.assertNil(path)
end

-- ── _is_back_center_nonserializable_path ─────────────────────────────────────

function TestSerializationGuard:test_is_back_center_path_matches()
   -- match() returns the matched string (truthy) when it matches
   lu.assertNotNil(SG._is_back_center_nonserializable_path("save_run.BACK.effect.center"))
   lu.assertNotNil(SG._is_back_center_nonserializable_path("save_run.BACK.effect.center.key"))
end

function TestSerializationGuard:test_is_back_center_path_no_match()
   -- match() returns nil for non-matching paths; type check returns false for non-strings
   lu.assertNil(SG._is_back_center_nonserializable_path("save_run.GAME.ante"))
   lu.assertFalse(SG._is_back_center_nonserializable_path(nil))
   lu.assertFalse(SG._is_back_center_nonserializable_path(42))
end

-- ── _get_back_center_desc ────────────────────────────────────────────────────

function TestSerializationGuard:test_get_back_center_desc_with_table()
   local save_table = {
      BACK = {
         effect = {
            center = { key = "c_anchor", mod = { id = "MyMod" } }
         }
      }
   }
   local desc = SG._get_back_center_desc(save_table)
   lu.assertStrContains(desc, "c_anchor")
   lu.assertStrContains(desc, "MyMod")
end

function TestSerializationGuard:test_get_back_center_desc_non_table_returns_fallback()
   local desc = SG._get_back_center_desc("not a table")
   lu.assertEquals(desc, "key=?, mod=?")
end

function TestSerializationGuard:test_get_back_center_desc_missing_center_returns_fallback()
   local desc = SG._get_back_center_desc({ BACK = {} })
   lu.assertEquals(desc, "key=?, mod=?")
end
