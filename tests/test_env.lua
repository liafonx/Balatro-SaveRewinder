-- tests/test_env.lua
-- Bootstrap environment for off-game unit tests.
-- Must be executed (via dofile) before any module require.
-- Sets up: Layer 0 globals, package.preload module map.

-- ── Layer 0 globals ─────────────────────────────────────────────────────────
-- These are the minimum ambient state that most modules expect to exist at load
-- time or at the call-sites exercised by Tier 1/2 tests.

REWINDER = { config = dofile("config.lua") }

G = {
   STATES = {
      SHOP            = 1,
      SELECTING_HAND  = 2,
      ROUND_EVAL      = 3,
      HAND_PLAYED     = 4,
      BLIND_SELECT    = 5,
   },
   -- G.STATE and G.GAME are nil by default; tests set them as needed.
}

love = {
   filesystem = {
      -- Minimal stubs so modules load without errors.
      -- Tests that need real filesystem behaviour install love_fs.lua mocks.
      getInfo           = function() return nil end,
      read              = function() return nil end,
      write             = function() return true end,
      remove            = function() return true end,
      getDirectoryItems = function() return {} end,
      getSaveDirectory  = function() return "/mock/save" end,
      createDirectory   = function() return true end,
   },
   timer = {
      getTime = os.clock,
      sleep   = function() end,
   },
   data = {
      compress   = function(_, _, data) return data end,
      decompress = function(_, _, data) return data end,
   },
}

-- Stubs for Balatro built-ins referenced by BlindRecovery / NaNProtection
number_format = tostring
scale_number  = function(v) return v end

-- Explicitly nil — no big-number mods in test env
SMODS  = nil
Big    = nil
to_big = nil

-- ── LuaJIT compatibility shims ───────────────────────────────────────────────
-- These restore LuaJIT behaviours absent in standard Lua 5.4/5.5 so that
-- production code written for LuaJIT runs correctly under the test harness.

-- math.log10: removed in Lua 5.2+; present in LuaJIT and Lua 5.1.
if not math.log10 then
   math.log10 = function(x) return math.log(x) / math.log(10) end
end

-- tonumber(s, base): LuaJIT silently returns nil (or the parsed number) when
-- base is 0 or 1.  Standard Lua 5.4/5.5 raises an error.  BlindRecovery uses
-- `tonumber(str:gsub(",", ""))` which passes the replacement count as `base`;
-- for strings without commas base=0, for one comma base=1, etc.
-- Shim: treat base < 2 as "no-base" (auto-detect), matching LuaJIT semantics.
local _orig_tonumber = tonumber
function tonumber(v, base) -- luacheck: ignore 121
   if base ~= nil then
      local b = type(base) == "number" and base or _orig_tonumber(base)
      if not b or b < 2 then
         return _orig_tonumber(v)   -- base=0/1 → auto-detect
      end
      if b > 36 then return nil end
      return _orig_tonumber(v, b)
   end
   return _orig_tonumber(v)
end

-- ── Helpers path ────────────────────────────────────────────────────────────
-- Allow require("ctx_factory"), require("fixtures"), etc. from tests/helpers/.
package.path = "tests/helpers/?.lua;" .. package.path

-- ── Module map ──────────────────────────────────────────────────────────────
-- Maps Lovely module names → relative source paths (project root as CWD).
-- Must match lovely.toml [patches.module] entries for all tested modules.

local MODULE_MAP = {
   Logger                      = "Utils/Logger.lua",
   MetaFile                    = "Utils/MetaFile.lua",
   FileIO                      = "Utils/FileIO.lua",
   Pruning                     = "Utils/Pruning.lua",
   StateSignature              = "Utils/StateSignature.lua",
   NaNProtection               = "Utils/NaNProtection.lua",
   BlindRecovery               = "Utils/BlindRecovery.lua",
   SaveManagerEntrySchema      = "Core/SaveModules/EntrySchema.lua",
   SaveManagerRuntimeState     = "Core/SaveModules/RuntimeState.lua",
   SaveManagerQueueService     = "Core/SaveModules/QueueService.lua",
   SaveManager                 = "Core/SaveManager.lua",
   KeySaves                    = "Core/KeySaves.lua",
   SerializationGuard          = "Core/SerializationGuard.lua",
   ExportService               = "Core/ExportService.lua",
   -- Registered for transitive requires; not directly tested in Phase 1:
   SaveManagerIndexStore       = "Core/SaveModules/IndexStore.lua",
   SaveManagerMetaCache        = "Core/SaveModules/MetaCache.lua",
   SaveManagerOrdinalTracker   = "Core/SaveModules/OrdinalTracker.lua",
   SaveManagerRetentionService = "Core/SaveModules/RetentionService.lua",
   SaveManagerSkipService      = "Core/SaveModules/SkipService.lua",
   SaveManagerLoadService      = "Core/SaveModules/LoadService.lua",
   SaveManagerCreateService    = "Core/SaveModules/CreateService.lua",
}

for name, path in pairs(MODULE_MAP) do
   package.preload[name] = function() return dofile(path) end
end

-- ── UI / Utils preloads (outside MODULE_MAP; game-coupled in prod) ───────────
-- These allow UI-module tests to require("UIShared") etc. without the Balatro
-- game runtime. Stubs replicate only the interface surface needed by tests.

-- Real source — no game-object dependencies at load time.
package.preload["UIShared"]  = function() return dofile("UI/Shared.lua") end
package.preload["UILayout"]  = function() return dofile("UI/Layout.lua") end

-- Real source — pure Lua, no game-object dependencies at load time.
package.preload["SaveListSync"] = function() return dofile("UI/SaveListSync.lua") end

-- Real sources for UI modules under test; their game-object deps are stubbed below.
package.preload["UISaveRows"]              = function() return dofile("UI/SaveRows.lua") end
package.preload["UIButtonCallbackHelpers"] = function() return dofile("UI/ButtonCallbackHelpers.lua") end

-- Stubs for game-coupled helpers (no Balatro runtime in test env).
package.preload["UIIconFactory"]      = function() return {} end
package.preload["ScaleNumberHook"]    = function() return { install = function() end, installed = false } end
package.preload["ControllerNavigation"] = function() return { install = function() end } end
