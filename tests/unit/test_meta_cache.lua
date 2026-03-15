-- tests/unit/test_meta_cache.lua
-- Tests for Core/SaveModules/MetaCache.lua

local lu         = require("luaunit")
local CtxFactory = require("ctx_factory")
local Fixtures   = require("fixtures")

local MetaCacheFactory = require("SaveManagerMetaCache")
local E_mod            = require("SaveManagerEntrySchema")

TestMetaCache = {}

function TestMetaCache:setUp()
   local ctx = CtxFactory.mk_save_module_ctx()
   ctx.S.save_cache = Fixtures.make_save_cache(5)
   self.api = MetaCacheFactory(ctx)
   self.ctx = ctx
   self.M   = ctx.M
   self.S   = ctx.S
   self.E   = ctx.E
end

-- ── _normalize_custom_state_name (exposed as M.normalize_custom_state_name) ──

function TestMetaCache:test_normalize_custom_state_name_trims_whitespace()
   local fn = self.M.normalize_custom_state_name
   lu.assertEquals(fn("  hello  "), "hello")
end

function TestMetaCache:test_normalize_custom_state_name_nil_for_empty()
   local fn = self.M.normalize_custom_state_name
   lu.assertNil(fn("   "))
   lu.assertNil(fn(""))
end

function TestMetaCache:test_normalize_custom_state_name_nil_for_non_string()
   local fn = self.M.normalize_custom_state_name
   lu.assertNil(fn(nil))
   lu.assertNil(fn(42))
end

-- ── _apply_meta_to_entry ─────────────────────────────────────────────────────

function TestMetaCache:test_apply_meta_to_entry_populates_fields()
   local entry = {}
   local meta = {
      money = 99, signature = "2:1:S:0:0:99", discards_used = 3,
      hands_played = 2, blind_idx = 2, display_type = "S",
      ordinal = 5, is_key = true,
   }
   self.api._apply_meta_to_entry(entry, meta)
   lu.assertEquals(entry[self.E.ENTRY_MONEY], 99)
   lu.assertEquals(entry[self.E.ENTRY_DISPLAY_TYPE], "S")
   lu.assertEquals(entry[self.E.ENTRY_ORDINAL], 5)
   lu.assertTrue(entry[self.E.ENTRY_IS_KEY])
end

function TestMetaCache:test_apply_meta_to_entry_nil_is_key_gets_default_false()
   local entry = {}
   local meta = { money = 5, display_type = "S", ordinal = 1 }
   -- is_key missing → apply_default = false
   self.api._apply_meta_to_entry(entry, meta)
   lu.assertEquals(entry[self.E.ENTRY_IS_KEY], false)
end

function TestMetaCache:test_apply_meta_to_entry_nil_entry_is_noop()
   -- Should not raise
   self.api._apply_meta_to_entry(nil, { money = 5 })
end

-- ── _build_meta_from_entry ───────────────────────────────────────────────────

function TestMetaCache:test_build_meta_from_entry_returns_meta_table()
   local entry = Fixtures.make_entry({ money = 42, display_type = "S", ordinal = 2 })
   local meta = self.api._build_meta_from_entry(entry)
   lu.assertNotNil(meta)
   lu.assertEquals(meta.money, 42)
   lu.assertEquals(meta.display_type, "S")
   lu.assertEquals(meta.ordinal, 2)
end

function TestMetaCache:test_build_meta_from_entry_nil_when_no_display_type()
   local entry = Fixtures.make_entry()
   entry[self.E.ENTRY_DISPLAY_TYPE] = nil
   local meta = self.api._build_meta_from_entry(entry)
   lu.assertNil(meta)
end

function TestMetaCache:test_build_meta_from_entry_nil_entry_returns_nil()
   lu.assertNil(self.api._build_meta_from_entry(nil))
end

-- ── _clear_entry_meta ────────────────────────────────────────────────────────

function TestMetaCache:test_clear_entry_meta_zeroes_meta_fields()
   local entry = Fixtures.make_entry({ money = 99, display_type = "S" })
   self.api._clear_entry_meta(entry)
   lu.assertNil(entry[self.E.ENTRY_MONEY])
   lu.assertNil(entry[self.E.ENTRY_DISPLAY_TYPE])
   lu.assertNil(entry[self.E.ENTRY_SIGNATURE])
end

-- ── LRU cache: insert, eviction ──────────────────────────────────────────────

function TestMetaCache:test_cache_meta_increments_size()
   self.api.cache_meta("file_a.jkr", { display_type = "S", money = 5 })
   lu.assertEquals(self.S.meta_cache_size, 1)
end

function TestMetaCache:test_cache_meta_evicts_when_over_limit()
   -- Use a tiny limit to force eviction
   self.S.meta_cache_limit = 2
   -- Add 3 entries (first two should stay, oldest evicted when third added)
   self.api.cache_meta("f1.jkr", { display_type = "S", money = 1 })
   self.api.cache_meta("f2.jkr", { display_type = "S", money = 2 })
   self.api.cache_meta("f3.jkr", { display_type = "S", money = 3 })
   lu.assertTrue(self.S.meta_cache_size <= 2)
end

-- ── calc_meta_window_bounds ───────────────────────────────────────────────────

function TestMetaCache:test_calc_meta_window_bounds_clamps_to_total()
   -- M.get_save_files returns S.save_cache view; set it up
   local view = {}
   for i = 1, 10 do view[i] = { i } end
   self.M.get_save_files = function() return view end
   local start, finish, _ = self.M.calc_meta_window_bounds(5, 4)
   lu.assertNotNil(start)
   lu.assertNotNil(finish)
   lu.assertTrue(start >= 1)
   lu.assertTrue(finish <= 10)
end
