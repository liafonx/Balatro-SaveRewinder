-- tests/unit/test_key_saves.lua
-- Tests for Core/KeySaves.lua

local lu         = require("luaunit")
local Fixtures   = require("fixtures")

local KeySaves   = require("KeySaves")
local SaveManager = require("SaveManager")
local MetaFile   = require("MetaFile")

TestKeySaves = {}

-- Per-test helpers ─────────────────────────────────────────────────────────

local function make_entry(file, is_key)
   local e = Fixtures.make_entry({ file = file })
   e[SaveManager.ENTRY_IS_KEY] = is_key
   return e
end

function TestKeySaves:setUp()
   -- Reset pending state between tests
   KeySaves.discard_pending()

   -- Monkey-patch MetaFile for write tests (avoids real FS)
   self._orig_read  = MetaFile.read_meta_file
   self._orig_write = MetaFile.write_meta_file
   MetaFile.read_meta_file  = function() return { is_key = false } end
   MetaFile.write_meta_file = function() return true end

   -- Monkey-patch SaveManager to provide a simple in-memory entry store
   self._entries = {}
   self._orig_get_entry_with_meta = SaveManager.get_entry_with_meta
   self._orig_update_entry_is_key = SaveManager.update_entry_is_key
   SaveManager.get_entry_with_meta = function(file)
      return self._entries[file]
   end
   SaveManager.update_entry_is_key = function(file, val)
      if self._entries[file] then
         self._entries[file][SaveManager.ENTRY_IS_KEY] = val
      end
   end
end

function TestKeySaves:tearDown()
   MetaFile.read_meta_file  = self._orig_read
   MetaFile.write_meta_file = self._orig_write
   SaveManager.get_entry_with_meta = self._orig_get_entry_with_meta
   SaveManager.update_entry_is_key = self._orig_update_entry_is_key
   KeySaves.discard_pending()
end

-- ── effective_is_key ─────────────────────────────────────────────────────────

function TestKeySaves:test_effective_is_key_returns_committed_when_no_pending()
   local entry = make_entry("a.jkr", true)
   local val, is_pending = KeySaves.effective_is_key(entry)
   lu.assertTrue(val)
   lu.assertFalse(is_pending)
end

function TestKeySaves:test_effective_is_key_returns_pending_when_pending_exists()
   local entry = make_entry("b.jkr", false)
   self._entries["b.jkr"] = entry
   KeySaves.toggle_pending("b.jkr")   -- flips to true
   local val, is_pending = KeySaves.effective_is_key(entry)
   lu.assertTrue(val)
   lu.assertTrue(is_pending)
end

function TestKeySaves:test_effective_is_key_nil_entry_returns_false()
   local val = KeySaves.effective_is_key(nil)
   lu.assertFalse(val)
end

-- ── toggle_pending ────────────────────────────────────────────────────────────

function TestKeySaves:test_toggle_pending_flips_committed_false_to_true()
   local entry = make_entry("c.jkr", false)
   self._entries["c.jkr"] = entry
   local eff = KeySaves.toggle_pending("c.jkr")
   lu.assertTrue(eff)
   lu.assertTrue(KeySaves.has_pending())
end

function TestKeySaves:test_toggle_pending_second_call_clears_pending()
   local entry = make_entry("d.jkr", false)
   self._entries["d.jkr"] = entry
   KeySaves.toggle_pending("d.jkr")   -- flip to true
   KeySaves.toggle_pending("d.jkr")   -- flip back → same as committed → clear
   lu.assertFalse(KeySaves.has_pending())
end

function TestKeySaves:test_toggle_pending_missing_entry_returns_nil()
   local result = KeySaves.toggle_pending("missing.jkr")
   lu.assertNil(result)
end

-- ── has_pending ───────────────────────────────────────────────────────────────

function TestKeySaves:test_has_pending_false_initially()
   lu.assertFalse(KeySaves.has_pending())
end

function TestKeySaves:test_has_pending_true_after_toggle()
   local entry = make_entry("e.jkr", false)
   self._entries["e.jkr"] = entry
   KeySaves.toggle_pending("e.jkr")
   lu.assertTrue(KeySaves.has_pending())
end

-- ── commit_pending ────────────────────────────────────────────────────────────

function TestKeySaves:test_commit_pending_calls_write_and_clears()
   local entry = make_entry("f.jkr", false)
   self._entries["f.jkr"] = entry
   KeySaves.toggle_pending("f.jkr")
   local ok, fail = KeySaves.commit_pending()
   lu.assertEquals(ok, 1)
   lu.assertEquals(fail, 0)
   lu.assertFalse(KeySaves.has_pending())
end

-- ── discard_pending ───────────────────────────────────────────────────────────

function TestKeySaves:test_discard_pending_clears_all()
   local entry = make_entry("g.jkr", false)
   self._entries["g.jkr"] = entry
   KeySaves.toggle_pending("g.jkr")
   KeySaves.discard_pending()
   lu.assertFalse(KeySaves.has_pending())
end

-- ── get_key_saves ─────────────────────────────────────────────────────────────

function TestKeySaves:test_get_key_saves_filters_is_key_entries()
   local entries = {
      make_entry("h1.jkr", false),
      make_entry("h2.jkr", true),
      make_entry("h3.jkr", false),
      make_entry("h4.jkr", true),
   }
   local filtered, idx_map = KeySaves.get_key_saves(entries)
   lu.assertEquals(#filtered, 2)
   lu.assertEquals(idx_map[1], 2)
   lu.assertEquals(idx_map[2], 4)
end

function TestKeySaves:test_get_key_saves_empty_input_returns_empty()
   local filtered, idx_map = KeySaves.get_key_saves({})
   lu.assertEquals(#filtered, 0)
   lu.assertEquals(#idx_map, 0)
end
