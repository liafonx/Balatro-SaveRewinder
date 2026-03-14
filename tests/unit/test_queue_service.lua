-- tests/unit/test_queue_service.lua
-- Tests for Core/SaveModules/QueueService.lua
-- QueueService is a factory function; we call it with a ctx to wire up M.

local lu = require("luaunit")
local qs_factory = require("SaveManagerQueueService")

TestQueueService = {}

-- ── Per-test ctx factory ─────────────────────────────────────────────────────

local function mk_queue_ctx()
   local M = {
      _rw_queue          = {},
      _rw_queue_head     = 1,
      _rw_queue_tail     = 0,
      _rw_cancelled_files = {},
      debug_log          = function() end,
      get_save_dir       = function() return "1/SaveRewinder" end,
   }
   return {
      M      = M,
      Logger = require("Logger"),
      FileIO = { write_save_file = function() return true end },
   }
end

function TestQueueService:setUp()
   local ctx = mk_queue_ctx()
   qs_factory(ctx)
   self.M = ctx.M
   -- Reset volatile REWINDER fields used by health-tracking functions.
   REWINDER._rw_flush_fallback  = nil
   REWINDER._rw_flush_verified  = nil
   REWINDER._rw_first_flush_time = nil
   REWINDER._rw_first_flush_file = nil
   REWINDER._rw_last_shop_flush_t = nil
   REWINDER._rw_last_play_flush_t = nil
end

-- ── freeze_save_table ────────────────────────────────────────────────────────

function TestQueueService:test_freeze_non_table_passthrough()
   lu.assertEquals(self.M.freeze_save_table("hello"), "hello")
   lu.assertIsNil(self.M.freeze_save_table(nil))
end

function TestQueueService:test_freeze_cardAreas_deep_copied()
   local orig = { cardAreas = { hand = { cards = { 1, 2, 3 } } } }
   local frozen = self.M.freeze_save_table(orig)
   lu.assertNotIs(frozen.cardAreas, orig.cardAreas)
   lu.assertEquals(frozen.cardAreas.hand.cards[1], 1)
end

function TestQueueService:test_freeze_other_fields_shallow_copied()
   local shared_ref = { value = 42 }
   local orig = { cardAreas = {}, tags = {}, BLIND = {}, BACK = {}, shared = shared_ref }
   local frozen = self.M.freeze_save_table(orig)
   -- Non-deep-copied field keeps same reference.
   lu.assertIs(frozen.shared, shared_ref)
end

function TestQueueService:test_freeze_tags_deep_copied()
   local orig = { tags = { { key = "voucher" } } }
   local frozen = self.M.freeze_save_table(orig)
   lu.assertNotIs(frozen.tags, orig.tags)
end

-- ── build_rewinder_push_request ───────────────────────────────────────────────

function TestQueueService:test_build_request_nil_item_returns_nil()
   lu.assertIsNil(self.M.build_rewinder_push_request(nil, nil))
end

function TestQueueService:test_build_request_no_path_returns_nil()
   lu.assertIsNil(self.M.build_rewinder_push_request({}, nil))
end

function TestQueueService:test_build_request_valid_item()
   local item = {
      rewinder_copy_path = "1/SaveRewinder/save_001.jkr",
      save_table         = { GAME = {} },
      file               = "save_001.jkr",
      rewinder_meta_path = "1/SaveRewinder/save_001.meta",
      rewinder_meta_data = "sig=abc",
   }
   local req = self.M.build_rewinder_push_request(item, REWINDER.config)
   lu.assertIsTable(req)
   lu.assertEquals(req.path, "1/SaveRewinder/save_001.jkr")
   lu.assertEquals(req.file, "save_001.jkr")
   lu.assertEquals(req.meta_path, "1/SaveRewinder/save_001.meta")
end

function TestQueueService:test_build_request_extracts_basename_when_file_missing()
   local item = { rewinder_copy_path = "1/SaveRewinder/save_002.jkr", save_table = {} }
   local req = self.M.build_rewinder_push_request(item, nil)
   lu.assertEquals(req.file, "save_002.jkr")
end

-- ── Ring buffer: enqueue / dequeue ───────────────────────────────────────────

function TestQueueService:test_enqueue_nil_returns_false()
   lu.assertFalse(self.M.enqueue_pending_rewinder(nil))
end

function TestQueueService:test_enqueue_item_returns_true()
   lu.assertTrue(self.M.enqueue_pending_rewinder({ file = "a.jkr", save_table = {} }))
end

function TestQueueService:test_dequeue_empty_queue_returns_nil()
   lu.assertIsNil(self.M.dequeue_pending_rewinder())
end

function TestQueueService:test_queue_depth_starts_at_zero()
   lu.assertEquals(self.M.rewinder_queue_depth(), 0)
end

function TestQueueService:test_enqueue_increases_depth()
   self.M.enqueue_pending_rewinder({ file = "a.jkr", save_table = {} })
   lu.assertEquals(self.M.rewinder_queue_depth(), 1)
end

function TestQueueService:test_dequeue_returns_enqueued_item_and_decreases_depth()
   local item = { file = "a.jkr", save_table = { x = 1 } }
   self.M.enqueue_pending_rewinder(item)
   local got = self.M.dequeue_pending_rewinder()
   lu.assertEquals(got.file, "a.jkr")
   lu.assertEquals(self.M.rewinder_queue_depth(), 0)
end

function TestQueueService:test_fifo_order_preserved()
   local items = { "a.jkr", "b.jkr", "c.jkr" }
   for _, f in ipairs(items) do
      self.M.enqueue_pending_rewinder({ file = f, save_table = {} })
   end
   for _, expected in ipairs(items) do
      local got = self.M.dequeue_pending_rewinder()
      lu.assertEquals(got.file, expected)
   end
end

function TestQueueService:test_queue_depth_capped_at_16()
   for i = 1, 20 do
      self.M.enqueue_pending_rewinder({ file = "s" .. i .. ".jkr", save_table = {} })
   end
   lu.assertEquals(self.M.rewinder_queue_depth(), 16)
end

function TestQueueService:test_enqueue_over_limit_returns_false()
   for i = 1, 16 do
      self.M.enqueue_pending_rewinder({ file = "s" .. i .. ".jkr", save_table = {} })
   end
   lu.assertFalse(self.M.enqueue_pending_rewinder({ file = "extra.jkr", save_table = {} }))
end

-- ── Cancellation ─────────────────────────────────────────────────────────────

function TestQueueService:test_cancelled_file_skipped_on_dequeue()
   self.M.enqueue_pending_rewinder({ file = "skip.jkr", save_table = {} })
   self.M.enqueue_pending_rewinder({ file = "keep.jkr", save_table = {} })
   self.M.cancel_pending_rewinder_by_files({ "skip.jkr" })
   local got = self.M.dequeue_pending_rewinder()
   lu.assertEquals(got.file, "keep.jkr")
   lu.assertEquals(self.M.rewinder_queue_depth(), 0)
end

function TestQueueService:test_discard_clears_entire_queue()
   for i = 1, 5 do
      self.M.enqueue_pending_rewinder({ file = "s" .. i .. ".jkr", save_table = {} })
   end
   self.M.discard_pending_rewinder()
   lu.assertEquals(self.M.rewinder_queue_depth(), 0)
   lu.assertIsNil(self.M.dequeue_pending_rewinder())
end
