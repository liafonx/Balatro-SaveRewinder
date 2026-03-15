-- tests/unit/test_game_patches.lua
-- Tests for _save_gate_equal in Core/GamePatches.lua.
-- Uses dofile with stubs because GamePatches hooks Game globals via lovely injection.

local lu = require("luaunit")

-- Stub Game global before dofile to prevent nil-index errors at load time.
Game = Game or {}                   -- luacheck: ignore 111
Game.start_run = Game.start_run or function() end
Game.update    = Game.update    or function() end

-- Reset the load-guard so dofile re-executes cleanly each time the suite is reloaded.
REWINDER._game_patches_loaded = nil

dofile("Core/GamePatches.lua")

local equal = REWINDER._save_gate_equal

TestGamePatches = {}

local function snap(overrides)
   local s = {
      state         = 1,
      ante          = 1,
      round         = 1,
      blind         = "Small",
      hands_played  = 0,
      discards_used = 0,
      dollars       = 5,
      action_type   = nil,
      action_card   = nil,
   }
   if overrides then
      for k, v in pairs(overrides) do s[k] = v end
   end
   return s
end

-- ── equal snapshots ───────────────────────────────────────────────────────────

function TestGamePatches:test_equal_identical_snapshots()
   lu.assertTrue(equal(snap(), snap()))
end

-- ── nil guards ───────────────────────────────────────────────────────────────

function TestGamePatches:test_nil_a_returns_false()
   lu.assertFalse(equal(nil, snap()))
end

function TestGamePatches:test_nil_b_returns_false()
   lu.assertFalse(equal(snap(), nil))
end

-- ── field-level differences ───────────────────────────────────────────────────

function TestGamePatches:test_differs_on_state()
   lu.assertFalse(equal(snap({ state = 1 }), snap({ state = 2 })))
end

function TestGamePatches:test_differs_on_ante()
   lu.assertFalse(equal(snap({ ante = 1 }), snap({ ante = 2 })))
end

function TestGamePatches:test_differs_on_round()
   lu.assertFalse(equal(snap({ round = 1 }), snap({ round = 2 })))
end

function TestGamePatches:test_differs_on_blind()
   lu.assertFalse(equal(snap({ blind = "Small" }), snap({ blind = "Big" })))
end

function TestGamePatches:test_differs_on_hands_played()
   lu.assertFalse(equal(snap({ hands_played = 0 }), snap({ hands_played = 1 })))
end

function TestGamePatches:test_differs_on_discards_used()
   lu.assertFalse(equal(snap({ discards_used = 0 }), snap({ discards_used = 1 })))
end

function TestGamePatches:test_differs_on_dollars()
   lu.assertFalse(equal(snap({ dollars = 5 }), snap({ dollars = 10 })))
end

function TestGamePatches:test_differs_on_action_type()
   lu.assertFalse(equal(snap({ action_type = nil }), snap({ action_type = "play" })))
end

function TestGamePatches:test_differs_on_action_card()
   lu.assertFalse(equal(snap({ action_card = nil }), snap({ action_card = "c_ace" })))
end
