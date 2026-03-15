-- tests/unit/test_save_list_sync.lua
-- Tests for UI/SaveListSync.lua _handle_sync_result helper.

local lu   = require("luaunit")
local Sync = require("SaveListSync")

TestSaveListSync = {}

function TestSaveListSync:setUp()
   -- Reset sync state between tests
   REWINDER._saves_open_sync = nil
   REWINDER._rw_flush_verified = nil
end

local function make_sync_state(opts)
   opts = opts or {}
   return {
      SM        = opts.SM        or nil,
      waiting   = opts.waiting   or {},
      inflight  = opts.inflight  or 0,
      completed = opts.completed or 0,
      pushed    = opts.pushed    or 0,
   }
end

-- ── nil / missing guards ──────────────────────────────────────────────────────

function TestSaveListSync:test_nil_result_is_noop()
   local ss = make_sync_state()
   -- Should not error
   Sync._handle_sync_result(ss, nil)
   lu.assertEquals(ss.inflight, 0)
end

function TestSaveListSync:test_nil_sync_state_is_noop()
   local result = { status = "ok", file = "save_001.jkr" }
   -- Should not error
   Sync._handle_sync_result(nil, result)
end

function TestSaveListSync:test_missing_waiting_is_noop()
   local ss = make_sync_state({ waiting = nil })
   Sync._handle_sync_result(ss, { status = "ok", file = "f.jkr" })
   -- Should not error
end

-- ── ok result handling ────────────────────────────────────────────────────────

function TestSaveListSync:test_ok_result_decrements_inflight()
   local item = { save_table = { GAME = {} } }
   local ss = make_sync_state({
      inflight = 1,
      waiting  = { ["save_001.jkr"] = { item } },
   })
   Sync._handle_sync_result(ss, { status = "ok", file = "save_001.jkr" })
   lu.assertEquals(ss.inflight, 0)
end

function TestSaveListSync:test_ok_result_increments_completed()
   local item = { save_table = { GAME = {} } }
   local ss = make_sync_state({
      inflight  = 1,
      completed = 0,
      waiting   = { ["save_002.jkr"] = { item } },
   })
   Sync._handle_sync_result(ss, { status = "ok", file = "save_002.jkr" })
   lu.assertEquals(ss.completed, 1)
end

function TestSaveListSync:test_ok_result_removes_item_from_waiting()
   local item = { save_table = {} }
   local ss = make_sync_state({
      inflight = 1,
      waiting  = { ["f.jkr"] = { item } },
   })
   Sync._handle_sync_result(ss, { status = "ok", file = "f.jkr" })
   lu.assertNil(ss.waiting["f.jkr"])
end

-- ── non-ok result triggers fallback write ────────────────────────────────────

function TestSaveListSync:test_non_ok_result_calls_sync_write_fallback()
   local sync_write_called = false
   local item = { save_table = {} }
   local sm = {
      sync_write_rewinder_item = function(_, _)
         sync_write_called = true
      end,
   }
   local ss = make_sync_state({
      SM       = sm,
      inflight = 1,
      waiting  = { ["g.jkr"] = { item } },
   })
   Sync._handle_sync_result(ss, { status = "error", file = "g.jkr" })
   lu.assertTrue(sync_write_called)
end

-- ── multi-item bucket removes only first item ─────────────────────────────────

function TestSaveListSync:test_multi_item_bucket_removes_only_first()
   local item1 = { save_table = {} }
   local item2 = { save_table = {} }
   local ss = make_sync_state({
      inflight = 2,
      waiting  = { ["h.jkr"] = { item1, item2 } },
   })
   Sync._handle_sync_result(ss, { status = "ok", file = "h.jkr" })
   -- Bucket should still have item2
   lu.assertNotNil(ss.waiting["h.jkr"])
   lu.assertEquals(#ss.waiting["h.jkr"], 1)
   lu.assertIs(ss.waiting["h.jkr"][1], item2)
end
