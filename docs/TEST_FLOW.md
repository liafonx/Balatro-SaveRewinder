# Test System Flow

Describes the off-game unit test harness: how it works, how agents use it during development, and how to extend it.

---

## Quick Start

```bash
lua tests/run_tests.lua          # run all tests
make test                        # same via Makefile
make check                       # lint + validate + test
lua scripts/validate_module_map.lua  # check MODULE_MAP ↔ lovely.toml parity
```

All commands must be run from the **project root**.

---

## Why Off-Game Testing

Balatro mods load inside a LuaJIT/LÖVE runtime. Most of the game's globals (`G`, `love`, `STR_PACK`, `to_big`, …) are unavailable outside it. However, ~45 functions in `Utils/` and `Core/SaveModules/` are pure Lua logic that don't actually need the game running. The test harness provides a minimal shim layer so those functions can be exercised with `lua tests/run_tests.lua` in any standard Lua 5.4/5.5 installation.

**Benefit for agents:** regressions in signature computation, NaN handling, pruning, queue semantics, and meta serialization are caught in seconds, not after a full in-game test cycle.

---

## Architecture

```
tests/
  lib/
    luaunit.lua              -- vendored test framework (single file, no deps)
  run_tests.lua              -- entry point: wires environment, loads all suites
  test_env.lua               -- bootstrap: module shim + Layer 0 globals
  mocks/
    love_fs.lua              -- configurable love.filesystem stub
  helpers/
    fixtures.lua             -- sample entry / meta / run_data factories
  unit/
    test_entry_schema.lua
    test_runtime_state.lua
    test_state_signature.lua
    test_nan_protection.lua
    test_blind_recovery.lua
    test_meta_file.lua
    test_pruning.lua
    test_config.lua
    test_export_service.lua
    test_queue_service.lua

scripts/
  validate_module_map.lua    -- CI: verify MODULE_MAP matches lovely.toml
```

---

## How the Shim Works

Lovely's `[patches.module]` system maps `require("Logger")` → `Utils/Logger.lua` at game runtime. Outside the game, standard `require` knows nothing about this mapping.

`tests/test_env.lua` reproduces the mapping manually via `package.preload`:

```lua
local MODULE_MAP = {
  Logger               = "Utils/Logger.lua",
  SaveManagerQueueService = "Core/SaveModules/QueueService.lua",
  -- ... all 21 testable modules
}
for name, path in pairs(MODULE_MAP) do
  package.preload[name] = function() return dofile(path) end
end
```

`dofile` resolves paths relative to the CWD (project root). The first `require("Logger")` call loads the file, caches it in `package.loaded["Logger"]`, and returns it — exactly as the game runtime does. Subsequent calls return the cached module.

`run_tests.lua` calls `dofile("tests/test_env.lua")` before loading any test file, ensuring the mapping is in place before any module is `require`d.

---

## Layer 0 Globals

Modules reference game globals at call-time (not at load-time). `test_env.lua` installs the minimum set:

| Global | Value | Why |
|--------|-------|-----|
| `REWINDER` | `{ config = dofile("config.lua") }` | NaNProtection, Pruning, BlindRecovery, Logger read config |
| `G` | `{ STATES = { SHOP=1, … } }` | StateSignature, BlindRecovery use G.STATES; G.GAME set per-test |
| `love` | table with `filesystem`, `timer`, `data` stubs | FileIO, MetaFile, QueueService |
| `love.timer.getTime` | `os.clock` | QueueService timestamps |
| `number_format` | `tostring` | BlindRecovery.recover_blind_chip_text |
| `scale_number` | `function(v) return v end` | BlindRecovery.scale_continue_best_hand |
| `SMODS`, `Big`, `to_big` | `nil` | Disables big-number backend in NaNProtection |

Tests that need `G.GAME` set it directly in `setUp` / the test body and clear it in `tearDown`.

---

## Mock Layer (love.filesystem)

Tests that touch `love.filesystem` install `tests/mocks/love_fs.lua` in `setUp`:

```lua
local LoveFs = dofile("tests/mocks/love_fs.lua")

function TestMetaFile:setUp()
  self.fs = LoveFs.new()
  love.filesystem = self.fs
end
```

`LoveFs.new()` returns a fresh mock object with:
- `_files` table — pre-populate to make files "readable"
- `_calls` array — inspectable call log (`{ method, path, … }`)
- `remove_ok`, `write_ok` flags — simulate failures
- All five `love.filesystem` methods stubbed

```lua
-- Pre-populate a file before the test reads it:
self.fs._files["1/SaveRewinder/save_001.meta"] = "signature=abc\ndisplay_type=S\n..."
```

`tearDown` restores the minimal Layer 0 stubs so unrelated tests are unaffected.

---

## QueueService Factory Pattern

`QueueService` is a factory function, not a plain module. `require("SaveManagerQueueService")` returns the factory. Tests call it with a fresh `ctx` per test to get isolated state:

```lua
local qs_factory = require("SaveManagerQueueService")

local function mk_queue_ctx()
  local M = {
    _rw_queue = {}, _rw_queue_head = 1, _rw_queue_tail = 0,
    _rw_cancelled_files = {},
    debug_log = function() end,
  }
  return { M = M, Logger = require("Logger"), FileIO = { write_save_file = function() return true end } }
end

function TestQueueService:setUp()
  local ctx = mk_queue_ctx()
  qs_factory(ctx)
  self.M = ctx.M   -- all queue functions live on ctx.M after factory call
end
```

---

## LuaJIT Compatibility Shims

The production code targets LuaJIT (Balatro's runtime). Standard Lua 5.4/5.5 is missing two behaviors that test_env.lua patches:

### math.log10

Removed in Lua 5.2+. Used by `NaNProtection._format_scientific` for large-number display. Shim:

```lua
if not math.log10 then
  math.log10 = function(x) return math.log(x) / math.log(10) end
end
```

### tonumber with low base

`BlindRecovery.recover_blind_chips` uses `tonumber(chip_text:gsub(",", ""))`. `string.gsub` returns `(result, count)`, so the replacement count is passed as `base` to `tonumber`. For a string with no commas, base=0; one comma, base=1. Standard Lua errors on base < 2. LuaJIT treats base=0 and base=1 as auto-detect.

Shim in `test_env.lua`:

```lua
local _orig_tonumber = tonumber
function tonumber(v, base)
  if base ~= nil then
    local b = type(base) == "number" and base or _orig_tonumber(base)
    if not b or b < 2 then return _orig_tonumber(v) end  -- auto-detect
    if b > 36 then return nil end
    return _orig_tonumber(v, b)
  end
  return _orig_tonumber(v)
end
```

Both shims are in `tests/test_env.lua` only — production code is unchanged.

---

## Test Tiers

### Tier 1 — Pure Logic (~70 tests)

No ambient state needed beyond what `test_env.lua` provides. These always run cleanly.

| Module | Key invariants tested |
|--------|-----------------------|
| `EntrySchema` | blind key↔index bijection, E alias table mirrors M, meta_filename |
| `RuntimeState` | `new()` structure, `reset_ordinal_state()` counter wipe |
| `StateSignature` | `encode_signature` determinism, `compute_display_type` all codes, `get_state_info` parsing |
| `NaNProtection` | `is_nan`/`is_inf` primitives, `sanitize_inline` nil→0, `score_gt` NaN semantics, `sanitize_number_format` never throws |
| `BlindRecovery` | chip recovery from text/fallback, round-score sanitize, `chips_met_target`, scale helpers |
| `MetaFile` | `serialize_meta` field presence, `is_key` flag, newline stripping |
| `Pruning` | `get_type_round_limit` mapping, future-save pruning boundary |
| `config` | schema shape, field types, index range validation |
| `ExportService` | `format_seed` seeded/abbreviated/full-seed paths |

### Tier 2 — Mock-Assisted (~50 tests)

Require `love.filesystem` mock or per-test ctx factories.

| Module | Mock needed | Key invariants tested |
|--------|-----------|-----------------------|
| `MetaFile` | `love_fs` | `read_meta_file` parse, round-trip with `serialize_meta` |
| `Pruning` | `love_fs` | retention removes oldest antes, key saves preserved, trim bucket oldest-first |
| `QueueService` | queue ctx | FIFO order, depth cap=16, cancellation skip, `freeze_save_table` deep copy, `build_rewinder_push_request` |

---

## What Is NOT Testable

These require the full LÖVE/LuaJIT runtime and must be verified in-game:

| Module / Feature | Reason |
|-----------------|--------|
| `Core/Init.lua`, `Core/GamePatches.lua` | Live game hooks, `G.E` events |
| `Utils/SaveThread.lua` | LÖVE thread channels |
| All `UI/` modules | UIBox constructors, rendering pipeline |
| `Utils/Keybinds.lua`, `Utils/ControllerNavigation.lua` | Input system |
| `MetaCache`, `IndexStore` | Complex cross-service ctx wiring |
| `NaNProtection.has_big_backend()` big paths | Requires actual Talisman/Amulet loaded |
| `StateSignature._safe_number` cdata branch | Requires LuaJIT FFI |
| `BlindRecovery.safe_ease_chips` | Deep G.GAME + SMODS.calculate_round_score coupling |

---

## MODULE_MAP Drift Check

`scripts/validate_module_map.lua` parses `lovely.toml` and cross-checks it against `MODULE_MAP` in `tests/test_env.lua`:

- **TOML → MAP**: every `[patches.module]` entry must be in MODULE_MAP or `EXCLUDED_MODULES`
- **MAP → TOML**: every MODULE_MAP entry must exist in lovely.toml

Run: `lua scripts/validate_module_map.lua`
Exit 0 = OK, exit 1 = drift detected with specific names printed.

`EXCLUDED_MODULES` covers game-coupled modules that are intentionally absent from the harness: `SaveThread`, `ControllerNavigation`, `ScaleNumberHook`, `SaveListSync`, all `UI*` modules.

---

## CI

`.github/workflows/test.yml` runs on every push:

1. Install Lua 5.4 (`leafo/gh-actions-lua`)
2. Install luacheck via luarocks
3. `luacheck --config .luacheck .` — lint (warnings are informational; only errors fail CI)
4. `lua scripts/validate_module_map.lua` — drift check
5. `lua tests/run_tests.lua` — unit tests

---

## Adding a Test to an Existing File

Each test method follows luaunit's OOP style:

```lua
function TestPruning:test_my_new_case()
  -- arrange
  local entries = { make_entry(1, "a.jkr") }
  -- act
  Pruning.prune_future_saves("sd", 0, entries, E)
  -- assert
  lu.assertEquals(#entries, 0)
end
```

Rules:
- Method names must start with `test`
- Use `setUp` / `tearDown` for per-test state (love.filesystem mock, G.GAME, config overrides)
- Always restore mutated globals in `tearDown` — don't rely on test order

---

## Adding a New Test File

1. Create `tests/unit/test_<module>.lua`
2. Declare a global suite table: `TestMyModule = {}`
3. Add the suite name to `run_tests.lua`'s `lu.LuaUnit.run(...)` call
4. Add the suite name to `.luacheck` → `globals` list

```lua
-- run_tests.lua — append to the run() call:
os.exit(lu.LuaUnit.run(
  ...
  "TestMyModule"
))
```

```lua
-- .luacheck — append to globals:
"TestMyModule",
```

---

## Adding a New Module to the Harness

When a new `[patches.module]` entry is added to `lovely.toml`:

1. Add the entry to `MODULE_MAP` in `tests/test_env.lua`
2. Add the same entry to `MODULE_MAP` in `scripts/validate_module_map.lua`
3. If the module is game-coupled and cannot be tested, add its name to `EXCLUDED_MODULES` in `scripts/validate_module_map.lua` instead
4. Run `lua scripts/validate_module_map.lua` — should print `OK`

Failing to do step 1 or 3 will cause CI to fail with a clear error message naming the missing module.

---

## Practical Patterns for Agents

### After modifying a testable function

```bash
lua tests/run_tests.lua
```

A failing test immediately tells you which invariant broke and in which test. No in-game session needed.

### After adding a new module to lovely.toml

```bash
lua scripts/validate_module_map.lua
```

If it exits non-zero, update `tests/test_env.lua` and `scripts/validate_module_map.lua`.

### After changing config.lua defaults

`test_config.lua` validates field presence and type. Run `make test` to verify the schema is intact.

### Before writing tests for a new module

Check the tier:
- Does the module `require` love.filesystem at call-time? → Tier 2, use `LoveFs.new()` in `setUp`
- Does it need `G.GAME`? → Set it in `setUp`, clear in `tearDown`
- Does it use a factory pattern like QueueService? → Write a `mk_ctx()` helper, call the factory in `setUp`
- Does it require `REWINDER.config`? → Layer 0 already provides it from `config.lua`; override specific fields in tests and restore in `tearDown`

### Checking a config override pattern

```lua
function TestFoo:test_with_flag_enabled()
  local orig = REWINDER.config.some_flag
  REWINDER.config.some_flag = true
  -- ... test ...
  REWINDER.config.some_flag = orig  -- always restore
end
```

---

## Known Test Gaps

| Gap | Why | How to Verify |
|-----|-----|---------------|
| `NaNProtection` big-backend paths | `_big_backend_cached` persists; requires actual Talisman/Amulet loaded | In-game with Talisman enabled |
| `StateSignature._safe_number` cdata branch (line 33) | Requires LuaJIT FFI `cdata` type | In-game only |
| `BlindRecovery.safe_ease_chips` | Deep `G.GAME` + `SMODS.calculate_round_score` coupling | In-game scoring path |
| `MetaCache` / `IndexStore` public API | Complex cross-service ctx — deferred | Future test phase |
| All UI modules | UIBox rendering pipeline | In-game only |

---

## Related Files

- `tests/test_env.lua` — shim bootstrap (edit when adding modules)
- `tests/run_tests.lua` — suite registration (edit when adding test files)
- `scripts/validate_module_map.lua` — CI drift check (edit alongside lovely.toml)
- `.luacheck` — lint config (edit `globals` when adding suite names)
- `Makefile` — `make test`, `make lint`, `make check`
- `.github/workflows/test.yml` — CI pipeline
