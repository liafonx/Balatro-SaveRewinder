-- tests/unit/test_pruning.lua
-- Tests for Utils/Pruning.lua

local lu = require("luaunit")
local Pruning = require("Pruning")
local Schema  = require("SaveManagerEntrySchema")
local LoveFs  = dofile("tests/mocks/love_fs.lua")

local E = Schema   -- alias

TestPruning = {}

function TestPruning:setUp()
   self.fs = LoveFs.new()
   love.filesystem = self.fs
end

function TestPruning:tearDown()
   love.filesystem = {
      getInfo = function() return nil end, read = function() return nil end,
      write = function() return true end, remove = function() return true end,
      getDirectoryItems = function() return {} end,
      getSaveDirectory  = function() return "/mock/save" end,
      createDirectory   = function() return true end,
   }
end

local function make_entry(ante, file, is_key, round, dtype, index)
   local entry = {}
   entry[E.ENTRY_FILE]         = file  or ("save_" .. ante .. ".jkr")
   entry[E.ENTRY_ANTE]         = ante  or 1
   entry[E.ENTRY_ROUND]        = round or 1
   entry[E.ENTRY_INDEX]        = index or ante or 1
   entry[E.ENTRY_DISPLAY_TYPE] = dtype or "S"
   entry[E.ENTRY_IS_KEY]       = is_key or false
   return entry
end

-- ── get_type_round_limit ────────────────────────────────────────────────────

function TestPruning:test_limit_index_1_is_8()
   lu.assertEquals(Pruning.get_type_round_limit(1), 8)
end

function TestPruning:test_limit_index_4_is_128()
   lu.assertEquals(Pruning.get_type_round_limit(4), 128)
end

function TestPruning:test_limit_index_5_is_nil()
   lu.assertIsNil(Pruning.get_type_round_limit(5))
end

-- ── apply_retention_policy ──────────────────────────────────────────────────

function TestPruning:test_retention_all_option_preserves_everything()
   REWINDER.config.keep_antes = 7   -- "All"
   local entries = {
      make_entry(1, "a.jkr"),
      make_entry(2, "b.jkr"),
      make_entry(3, "c.jkr"),
   }
   local removed, _ = Pruning.apply_retention_policy("save_dir", entries, E, {})
   lu.assertIsNil(removed)   -- early-return when keep_all
   lu.assertEquals(#entries, 3)
   REWINDER.config.keep_antes = 3
end

function TestPruning:test_retention_removes_old_antes()
   REWINDER.config.keep_antes = 1   -- keep only 1 ante
   self.fs._files["save_dir/a.jkr"] = "data"
   self.fs._files["save_dir/b.jkr"] = "data"
   local entries = {
      make_entry(1, "a.jkr"),
      make_entry(2, "b.jkr"),
   }
   local removed_count, _ = Pruning.apply_retention_policy("save_dir", entries, E, {})
   lu.assertEquals(removed_count, 1)
   lu.assertEquals(#entries, 1)
   -- The surviving entry should be ante 2 (most recent).
   lu.assertEquals(entries[1][E.ENTRY_ANTE], 2)
   REWINDER.config.keep_antes = 3
end

function TestPruning:test_retention_preserves_key_saves_beyond_limit()
   REWINDER.config.keep_antes = 1   -- keep only most recent ante
   self.fs._files["save_dir/key.jkr"] = "data"
   self.fs._files["save_dir/new.jkr"] = "data"
   local entries = {
      make_entry(1, "key.jkr", true),   -- key save, old ante
      make_entry(2, "new.jkr", false),  -- new ante
   }
   Pruning.apply_retention_policy("save_dir", entries, E, {})
   -- Both should survive: key saves are never pruned by retention.
   lu.assertEquals(#entries, 2)
   REWINDER.config.keep_antes = 3
end

-- ── trim_type_round_bucket ───────────────────────────────────────────────────

function TestPruning:test_trim_removes_oldest_non_key_saves()
   REWINDER.config.max_saves_per_type_per_round = 1   -- limit = 8
   -- Put 10 entries in the same bucket (type="S", round=1).
   local entries = {}
   for i = 1, 10 do
      local f = string.format("save_%02d.jkr", i)
      self.fs._files["sd/" .. f] = "d"
      entries[i] = make_entry(1, f, false, 1, "S", i)
   end
   local removed, _ = Pruning.trim_type_round_bucket("sd", entries, E, "S", 1)
   lu.assertEquals(removed, 2)
   lu.assertEquals(#entries, 8)
end

function TestPruning:test_trim_never_removes_key_saves()
   REWINDER.config.max_saves_per_type_per_round = 1   -- limit = 8
   -- 10 entries: first is a key save, rest are normal (9 non-key > limit=8 → excess=1).
   local entries = {}
   for i = 1, 10 do
      local f = string.format("s%d.jkr", i)
      self.fs._files["sd/" .. f] = "d"
      entries[i] = make_entry(1, f, i == 1, 1, "S", i)
   end
   local removed, _ = Pruning.trim_type_round_bucket("sd", entries, E, "S", 1)
   lu.assertEquals(removed, 1)
   -- Verify key save was not removed.
   local key_still_present = false
   for _, e in ipairs(entries) do
      if e[E.ENTRY_IS_KEY] then key_still_present = true end
   end
   lu.assertTrue(key_still_present)
end

function TestPruning:test_trim_within_limit_no_removal()
   REWINDER.config.max_saves_per_type_per_round = 1   -- limit = 8
   local entries = {}
   for i = 1, 5 do
      entries[i] = make_entry(1, string.format("s%d.jkr", i), false, 1, "S", i)
   end
   local removed, _ = Pruning.trim_type_round_bucket("sd", entries, E, "S", 1)
   lu.assertEquals(removed, 0)
   lu.assertEquals(#entries, 5)
end

-- ── prune_future_saves ──────────────────────────────────────────────────────

function TestPruning:test_prune_future_removes_tail_beyond_boundary()
   local entries = {}
   for i = 1, 5 do
      local f = string.format("s%d.jkr", i)
      self.fs._files["sd/" .. f] = "d"
      entries[i] = make_entry(1, f, false, 1, "S", i)
   end
   Pruning.prune_future_saves("sd", 3, entries, E)
   lu.assertEquals(#entries, 3)
   -- Entries 4 and 5 should be gone.
   for _, e in ipairs(entries) do
      lu.assertTrue(e[E.ENTRY_INDEX] <= 3)
   end
end

function TestPruning:test_prune_future_nil_boundary_is_noop()
   local entries = { make_entry(1, "a.jkr"), make_entry(2, "b.jkr") }
   Pruning.prune_future_saves("sd", nil, entries, E)
   lu.assertEquals(#entries, 2)
end

function TestPruning:test_prune_future_all_within_boundary_unchanged()
   local entries = {}
   for i = 1, 3 do
      entries[i] = make_entry(1, string.format("s%d.jkr", i), false, 1, "S", i)
   end
   Pruning.prune_future_saves("sd", 10, entries, E)
   lu.assertEquals(#entries, 3)
end
