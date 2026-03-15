-- tests/unit/test_index_store.lua
-- Tests for Core/SaveModules/IndexStore.lua

local lu          = require("luaunit")
local CtxFactory  = require("ctx_factory")
local Fixtures    = require("fixtures")

local IndexStoreFactory = require("SaveManagerIndexStore")
local E_mod             = require("SaveManagerEntrySchema")

TestIndexStore = {}

function TestIndexStore:setUp()
   local ctx = CtxFactory.mk_save_module_ctx()
   ctx.S.save_cache = Fixtures.make_save_cache(5)
   self.api = IndexStoreFactory(ctx)
   self.ctx = ctx
   self.M   = ctx.M
   self.S   = ctx.S
   self.E   = ctx.E
end

-- ── rebuild_file_index ───────────────────────────────────────────────────────

function TestIndexStore:test_rebuild_builds_by_file_map()
   self.api.rebuild_file_index()
   lu.assertNotNil(self.S.save_cache_by_file)
   lu.assertEquals(#self.S.save_cache, 5)
   -- Entry 1 should be accessible by file name
   local file1 = self.S.save_cache[1][self.E.ENTRY_FILE]
   lu.assertNotNil(self.S.save_cache_by_file[file1])
end

function TestIndexStore:test_rebuild_builds_save_index_by_file()
   self.api.rebuild_file_index()
   -- index_by_file returns display index (reversed); entry at position 1 gets display index 5
   local file1 = self.S.save_cache[1][self.E.ENTRY_FILE]
   lu.assertEquals(self.S.save_index_by_file[file1], 5)
end

function TestIndexStore:test_rebuild_nil_cache_clears_indexes()
   self.S.save_cache = nil
   self.api.rebuild_file_index()
   lu.assertNil(self.S.save_cache_by_file)
   lu.assertNil(self.S.save_index_by_file)
   lu.assertNil(self.S.save_cache_by_id)
end

function TestIndexStore:test_rebuild_builds_by_id_map()
   self.api.rebuild_file_index()
   local entry1 = self.S.save_cache[1]
   local id = entry1[self.E.ENTRY_INDEX]
   local result = self.S.save_cache_by_id[id]
   lu.assertNotNil(result)
   lu.assertIs(result.entry, entry1)
end

-- ── get_save_cache_view / invalidate ────────────────────────────────────────

function TestIndexStore:test_get_save_cache_view_returns_reversed_order()
   local view = self.api.get_save_cache_view()
   lu.assertNotNil(view)
   lu.assertEquals(#view, 5)
   -- Last entry in cache should be first in view (reversed)
   lu.assertIs(view[1], self.S.save_cache[5])
   lu.assertIs(view[5], self.S.save_cache[1])
end

function TestIndexStore:test_get_save_cache_view_cached_on_second_call()
   local v1 = self.api.get_save_cache_view()
   local v2 = self.api.get_save_cache_view()
   lu.assertIs(v1, v2)
end

function TestIndexStore:test_invalidate_save_cache_view_clears_cache()
   local v1 = self.api.get_save_cache_view()
   self.api.invalidate_save_cache_view()
   local v2 = self.api.get_save_cache_view()
   lu.assertNotIs(v1, v2)  -- new table after invalidate
end

-- ── get_entry_by_file / get_entry_by_id / get_index_by_file ─────────────────

function TestIndexStore:test_get_entry_by_file_found()
   local file = self.S.save_cache[3][self.E.ENTRY_FILE]
   local entry = self.api.get_entry_by_file(file)
   lu.assertNotNil(entry)
   lu.assertIs(entry, self.S.save_cache[3])
end

function TestIndexStore:test_get_entry_by_file_missing_returns_nil()
   lu.assertNil(self.api.get_entry_by_file("nonexistent.jkr"))
end

function TestIndexStore:test_get_entry_by_id_found()
   local entry1 = self.S.save_cache[1]
   local id = entry1[self.E.ENTRY_INDEX]
   local found, idx = self.api.get_entry_by_id(id)
   lu.assertIs(found, entry1)
   lu.assertNotNil(idx)
end

function TestIndexStore:test_get_index_by_file()
   local file5 = self.S.save_cache[5][self.E.ENTRY_FILE]
   local idx = self.api.get_index_by_file(file5)
   lu.assertEquals(idx, 1)   -- most-recent entry → display index 1
end

-- ── update_cache_current_flags ───────────────────────────────────────────────

function TestIndexStore:test_update_cache_current_flags_sets_is_current()
   self.api.rebuild_file_index()
   local file3 = self.S.save_cache[3][self.E.ENTRY_FILE]
   self.M._last_loaded_file = file3
   self.api.update_cache_current_flags(true)
   lu.assertTrue(self.S.save_cache[3][self.E.ENTRY_IS_CURRENT])
end

function TestIndexStore:test_update_cache_current_flags_clears_old_current()
   self.api.rebuild_file_index()
   local file2 = self.S.save_cache[2][self.E.ENTRY_FILE]
   local file4 = self.S.save_cache[4][self.E.ENTRY_FILE]
   self.M._last_loaded_file = file2
   self.api.update_cache_current_flags(true)
   -- Change current to file4
   self.M._last_loaded_file = file4
   self.api.update_cache_current_flags(true)
   lu.assertFalse(self.S.save_cache[2][self.E.ENTRY_IS_CURRENT])
   lu.assertTrue(self.S.save_cache[4][self.E.ENTRY_IS_CURRENT])
end

-- ── async pending ────────────────────────────────────────────────────────────

function TestIndexStore:test_mark_async_pending_sets_flag()
   self.api.mark_async_pending("save_001.jkr")
   lu.assertTrue(self.api.is_async_pending("save_001.jkr"))
   lu.assertEquals(self.S.pending_async_count, 1)
end

function TestIndexStore:test_clear_async_pending_removes_flag()
   self.api.mark_async_pending("save_001.jkr")
   self.api.clear_async_pending("save_001.jkr")
   lu.assertFalse(self.api.is_async_pending("save_001.jkr"))
   lu.assertEquals(self.S.pending_async_count, 0)
end

-- ── remove_files_from_index ──────────────────────────────────────────────────

function TestIndexStore:test_remove_files_from_index_clears_entry()
   self.api.rebuild_file_index()
   local file1 = self.S.save_cache[1][self.E.ENTRY_FILE]
   self.api.mark_async_pending(file1)
   self.api.remove_files_from_index({ file1 })
   lu.assertNil(self.S.save_cache_by_file and self.S.save_cache_by_file[file1])
   lu.assertFalse(self.api.is_async_pending(file1))
end

-- ── find_current_index ───────────────────────────────────────────────────────

function TestIndexStore:test_find_current_index_via_last_loaded_file()
   self.api.rebuild_file_index()
   -- Last entry (index 5) is display index 1
   local file5 = self.S.save_cache[5][self.E.ENTRY_FILE]
   self.M._last_loaded_file = file5
   local idx = self.api.find_current_index()
   lu.assertEquals(idx, 1)
end

function TestIndexStore:test_find_current_index_via_is_current_scan()
   self.api.rebuild_file_index()
   self.S.save_cache[2][self.E.ENTRY_IS_CURRENT] = true
   -- No _last_loaded_file set
   local idx = self.api.find_current_index()
   lu.assertEquals(idx, 4)  -- entry 2 (1-based cache) → display index 5-2+1 = 4
end
