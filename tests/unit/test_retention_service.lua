-- tests/unit/test_retention_service.lua
-- Tests for Core/SaveModules/RetentionService.lua

local lu          = require("luaunit")
local CtxFactory  = require("ctx_factory")
local Fixtures    = require("fixtures")

local RetentionServiceFactory = require("SaveManagerRetentionService")

TestRetentionService = {}

function TestRetentionService:setUp()
   self.ctx = CtxFactory.mk_save_module_ctx()
   self.ctx.S.save_cache = Fixtures.make_save_cache(6, { ante = 1 })
   self.api = RetentionServiceFactory(self.ctx)
   self.E   = self.ctx.E
   self.M   = self.ctx.M
end

-- ── _compute_allowed_antes ───────────────────────────────────────────────────

function TestRetentionService:test_compute_allowed_antes_returns_nil_when_keep_all()
   -- keep_antes config index 7 → nil (keep all)
   REWINDER.config.keep_antes = 7
   local entries = Fixtures.make_save_cache(3, { ante = 2 })
   local allowed = self.api._compute_allowed_antes(entries)
   lu.assertNil(allowed)
end

function TestRetentionService:test_compute_allowed_antes_keeps_N_most_recent()
   -- Config index 1 → KEEP_ANTES_VALUES[1] = 1 (keep 1 most recent ante)
   REWINDER.config.keep_antes = 1
   -- Build entries with 3 distinct antes
   local entries = {}
   for _, ante in ipairs({ 1, 2, 3 }) do
      local e = {}
      e[self.E.ENTRY_ANTE] = ante
      entries[#entries + 1] = e
   end
   local allowed = self.api._compute_allowed_antes(entries)
   lu.assertNotNil(allowed)
   -- Only ante 3 (the largest/most recent) should be allowed
   lu.assertTrue(allowed[3])
   lu.assertNil(allowed[1])
   lu.assertNil(allowed[2])
end

function TestRetentionService:test_compute_allowed_antes_multiple_antes()
   -- Config index 2 → KEEP_ANTES_VALUES[2] = 2 (keep 2 most recent antes)
   REWINDER.config.keep_antes = 2
   local entries = {}
   for _, ante in ipairs({ 1, 2, 3, 4 }) do
      local e = {}
      e[self.E.ENTRY_ANTE] = ante
      entries[#entries + 1] = e
   end
   local allowed = self.api._compute_allowed_antes(entries)
   lu.assertNotNil(allowed)
   lu.assertTrue(allowed[3])
   lu.assertTrue(allowed[4])
   lu.assertNil(allowed[1])
   lu.assertNil(allowed[2])
end

-- ── _retention_should_preserve_entry ────────────────────────────────────────

function TestRetentionService:test_preserve_entry_true_for_is_key()
   local entry = Fixtures.make_entry({ is_key = true })
   lu.assertTrue(self.api._retention_should_preserve_entry(entry))
end

function TestRetentionService:test_preserve_entry_false_for_non_key()
   local entry = Fixtures.make_entry({ is_key = false })
   lu.assertFalse(self.api._retention_should_preserve_entry(entry))
end

function TestRetentionService:test_preserve_entry_falsy_for_nil()
   lu.assertNotTrue(self.api._retention_should_preserve_entry(nil))
end

-- ── apply_retention_policy ───────────────────────────────────────────────────

function TestRetentionService:test_apply_retention_policy_calls_pruning()
   REWINDER.config.keep_antes = 1  -- keep 1 ante → will trigger prune
   local pruning_calls = self.ctx.Pruning._calls
   local before = #pruning_calls
   self.api.apply_retention_policy("/mock/save", self.ctx.S.save_cache)
   -- Pruning.apply_retention_policy should have been called once
   lu.assertEquals(#pruning_calls, before + 1)
end
