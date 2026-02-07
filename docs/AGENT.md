# Save Rewinder - AI Development Guide

Detailed guidance for AI agents working on this repo.

---

## 1. Big Picture

This is a Balatro mod that snapshots game state and supports instant rewind/restore via a cached `.jkr` + `.meta` timeline. It uses **static patching** (via `lovely.toml`) and same-frame save creation inside `save_run`.

**Core objectives:**
- Automatically create multiple saves during gameplay (sorted chronologically)
- Allow players to restore runs from any save point ("undo / step back")
- Provide save list UI with blind icons, hotkeys, and controller support
- Run transparently, compatible with popular mods (`Steamodded`, `debugplus`, etc.)

---

## 1.1 Recent Changes (Notable)

- **Save-path performance hardening (50+ saves)**:
  - `create_save` now avoids avoidable O(N) work (oldest-first append + cached newest-first view).
  - Retention runs only on ante changes, and timeline future-prune uses tail-trim deletion.
  - File/index maps stay hot with lazy rebuild of derived indices only when needed.
  - Save write path reuses compressed bytes directly for `save.jkr` sync (no extra file read).
- **Restore correctness fix**: loading a save now restores per-type ordinal counters for the whole ante/round window, eliminating duplicate ordinals after restore.
- **Key-save system completed**: key flag persisted in `.meta`, pending mark/commit/discard flow added, retention preserve rule moved behind SaveManager boundary helpers.
- **Save-list UX update**: key state is color-driven, pending edits show `[?]`, bottom bar uses filter + icon actions (`mark`, `jump`), filter persists across reopen while mark-mode pending edits do not.
- **Input/control cleanup**: dual keyboard/controller bindings plus stable overlay controller navigation (`LB/RB` page, `Y` jump, `X` open).
- **Stability/maintainability cleanup**: shared `Game:start_run` helpers, logger format unification, NaN protection centralization, and scale-number overflow handling simplified.

## 1.2 Unfinished / Open Requirements

- **Docs/UI**: Refine UI labels to clearly show both active bindings (currently context-sensitive based on last input).

---

## 2. File Structure & Relations

### Core/ — Core Modules

| File | Purpose | Key Exports | Dependencies |
|------|---------|-------------|--------------|
| `Init.lua` | Entry point. Sets up `REWINDER` namespace, hooks `Game:set_render_settings` for cache init at boot | `REWINDER` global | SaveManager |
| `SaveManager.lua` | Save management: create, load, list, prune. Contains `ordinal_state` for O(1) metadata. Single source of truth for entry constants | `ENTRY_*` constants, `get_save_files`, `create_save`, `load_and_start_from_file`, `blind_key_to_index`, `index_to_blind_key` | StateSignature, FileIO, MetaFile, Pruning |
| `KeySaves.lua` | Key-save (bookmark) facade with batched mark/commit/discard and key-only filtering | `toggle_pending`, `commit_pending`, `discard_pending`, `get_key_saves` | SaveManager, MetaFile |
| `GamePatches.lua` | Game function overrides. Hooks `Game:start_run` for loaded state marking, shop CardArea pre-loading | `defer_save_creation` | SaveManager |

**Module Dependency Graph:**
```
lovely.toml patches → GamePatches.defer_save_creation()
                    → NaNProtection (pre-save, post-load, serialization, display)
                              ↓
Init.lua → SaveManager.preload_all_metadata() (at boot; warms bounded meta window)
         → NaNProtection (exposed as global for patches)
                              ↓
SaveManager → StateSignature (state info extraction)
           → FileIO (file read/write)
           → MetaFile (fast .meta read/write)
           → Pruning (retention executor + future prune; preserve policy passed by SaveManager)
KeySaves → SaveManager (entry/meta access, cache update)
         → MetaFile (batched key-save commits)
                              ↓
UI (RewinderUI, ButtonCallbacks) → SaveManager (entry data, load functions)
                                → KeySaves (mark mode, key filter)
Keybinds → SaveManager (step back, UI toggle)
```

### Documentation Files

**IMPORTANT: User-facing docs hierarchy**
| File | Purpose | Style |
|------|---------|-------|
| `README.md` / `README_zh.md` | Full project overview (GitHub landing page) | Comprehensive with screenshots |
| `docs/description.md` | Concise feature summary (Thunderstore) | Short bullet points |
| `docs/NEXUSMODS_DESCRIPTION.txt` | NexusMods listing (BBCode format) | Full description with BBCode |
| `CHANGELOG.md` / `CHANGELOG_zh.md` | Version history | User-visible changes only |

**Guidelines for user docs:**
- Focus on **what users will notice**, not implementation details
- ✅ Good: "NaN Protection — Prevents crashes from extreme score overflows"
- ❌ Bad: "Added defense-in-depth patches to sanitize NaN values during serialization"
- Keep `description.md` the most concise (used for package descriptions)
- **IMPORTANT**: When adding features or changing behavior, **you must update ALL 4 user doc locations**:
  1. `README.md` + `README_zh.md` (English + Chinese)
  2. `docs/description.md` (concise Thunderstore version)
  3. `docs/NEXUSMODS_DESCRIPTION.txt` (BBCode format)
- All docs should have matching content, just different formats/lengths
- **NOTE**: `description.md` uses an extremely concise style (short bullets, minimal detail) because it's used for package managers. Do NOT apply this terse style to README or other docs.

**Developer docs:**
- `docs/AGENT.md`: This file - AI agent development guide
- `docs/*.md` (other): Technical flow diagrams and architecture

### Utils/ — Utilities

| File | Purpose | Key Functions | Used By |
|------|---------|---------------|---------|
| `StateSignature.lua` | Game state extraction and signature encoding | `get_state_info`, `encode_signature`, `signatures_equal`, `describe_save` | SaveManager, Init |
| `MetaFile.lua` | Fast `.meta` file read/write (core fields + optional `is_key`). Uses `NUMERIC_FIELDS` set for O(1) field type lookup | `read_meta_file`, `write_meta_file` | SaveManager, KeySaves |
| `FileIO.lua` | File operations for `.jkr` files | `copy_save_to_main`, `load_save_file`, `write_save_file` (returns compressed bytes as 3rd value), `write_bytes_to_main`, `get_save_dir` | SaveManager |
| `Pruning.lua` | Retention policy executor (max antes) + future save cleanup on restore | `apply_retention_policy(..., opts.should_preserve_entry)`, `prune_future_saves` | SaveManager |
| `Logger.lua` | Centralized logging with standard log levels | `Logger.create(module_name)` → returns logger function: `debug_log(level, msg)` where level is `"error"`, `"warning"`, `"info"`, or `"debug"`. **error/warning always show; info/debug only when debug_saves enabled** | All modules |
| `NaNProtection.lua` | Defense-in-depth sanitization for NaN/inf/nil values | `sanitize`, `sanitize_round_scores`, `sanitize_round_scores_presave`, `sanitize_number_format`, `sanitize_serialize` | lovely.toml patches, SaveManager |
| `ScaleNumberHook.lua` | Wraps `scale_number()` to return base scale for very large values (>1e290) | `install()`, `M.installed`, `M.LARGE_NUMBER_THRESHOLD` | ButtonCallbacks |
| `G.STATES.lua` | Reference file for `G.STATES` enum and `G.P_BLINDS` table | **Not loaded at runtime** — IDE autocomplete only | None |

### UI/ — User Interface

| File | Purpose | Key Functions | Dependencies |
|------|---------|---------------|--------------|
| `RewinderUI.lua` | Save list overlay with pagination, blind sprites, key-save visuals, custom icon buttons | `G.UIDEF.rewinder_saves`, `build_save_node`, `create_blind_sprite`, `create_star_icon`, `create_triangle_icon`, `get_saves_page` | SaveManager (`ENTRY_*` constants), KeySaves |
| `ButtonCallbacks.lua` | UI callbacks for restore, mark/filter modes, jump/page navigation, and dynamic button-state updates | `rewinder_save_restore`, `rewinder_save_toggle_key`, `rewinder_btn_mark_keys`, `rewinder_btn_filter_keys`, `rewinder_save_jump_to_current`, `_refresh_saves_view` | SaveManager, KeySaves |

### Root Files

| File | Purpose |
|------|---------|
| `Utils/Keybinds.lua` | Keybinds manager (Dual Binding system). Handles input hooks, restricted execution (Run stage), and UI formatting. Contains specific hooks for controller navigation (`navigate_focus`) and shortcuts. |
| `main.lua` | Steamodded config tab integration (auto-save toggles, display options) |
| `config.lua` | Default config values |
| `lovely.toml` | Lovely Loader patches: injects `REWINDER.defer_save_creation()` after `save_run`, NaN protection hooks |

**Important Config Options:**
- `debug_saves` (default: `false`) - Controls info/debug log visibility. See **Logging System** section below.
- `clamp_infinity_scores` (default: `false`) - Infinity handling: `false` = show as "inf" but reset to 0 on reload; `true` = clamp to 1.8e308 and preserve.

*Full config list: see `config.lua` or mod settings UI*

### Localization/

| File | Purpose |
|------|---------|
| `localization/en-us.lua` | English strings for UI labels, state names, config options |
| `localization/zh_CN.lua` | Chinese (Simplified) strings |

---

## 2.5. Logging System

**Architecture:** Centralized `Utils/Logger.lua` provides module-specific loggers with standard log levels.

**Log Levels:**

| Level | Purpose | Visibility | When to Use |
|-------|---------|------------|-------------|
| `error` | Critical failures (file I/O, missing resources) | Always visible | Save write failed, missing functions, corrupted data |
| `warning` | Unusual situations, invalid user actions | Always visible | Invalid index, no saves for step back, guard triggers |
| `info` | Normal operations users should know about | Only when `debug_saves = true` | Save creation, loading, pruning, initialization |
| `debug` | Internal details, technical information | Only when `debug_saves = true` | Cache operations, skip reasons, file write success |

**Usage Pattern:**
```lua
local Logger = require("Logger")
local M = {}
M.debug_log = Logger.create("ModuleName")  -- Creates module-specific logger

-- In functions:
M.debug_log("error", "Failed to write save: " .. err)
M.debug_log("warning", "Cannot step back: no saves available")
M.debug_log("info", "Created save: Ante 2 Round 3")
M.debug_log("debug", "Cache evicted 5 entries")
```

**Output Format:** `[Rewinder][ModuleName][level] message`  
**Example:** `[Rewinder][SaveManager][info] Created save: Ante 2 Round 3`

**Best Practices:**
- Use `error` for failures that users need to know about
- Use `warning` for recoverable issues or invalid actions  
- Use `info` for normal operation logging (save/load/prune)
- Use `debug` for internal details only developers care about
- Keep messages concise and actionable
- Include relevant context (file names, indices, counts)

**Per-Module Guidelines:**
- **SaveManager**: `error` for I/O failures, `warning` for invalid operations, `info` for saves/loads/steps, `debug` for cache
- **NaNProtection**: `warning` for guard triggers, `info` for fixes applied, `debug` for sanitization details
- **ScaleNumberHook**: Keep it lightweight; it should not depend on logger state or REWINDER config
- **Pruning**: `info` for pruning operations, `debug` for "no action needed"
- **FileIO**: `error` for I/O failures, `debug` for success confirmations
- **Init**: `error` for init failures, `info` for cache loading, `debug` for fallback matching

---

## 3. Documentation Files

| Doc | Content |
|-----|---------|
| `CACHE_ENTRY_EXAMPLE.md` | **13-field entry structure**, unified signature format, display type codes, meta file format, entry lifecycle |
| `INIT_FLOW.md` | Mod initialization: namespace setup, cache preload during loading screen, save.jkr matching |
| `CLICK_LOAD_FLOW.md` | Complete save loading flow from UI click to game restart |
| `PRESS_S_FLOW.md` | Step-back hotkey (`S`) flow: find previous save, load, and start |
| `SAVE_LIST_FLOW.md` | Save list UI rendering: pagination, lazy loading, entry node building |
| `KEY_SAVES_FLOW.md` | Key-save mark/filter lifecycle, commit/discard behavior, and retention semantics |

---

## 4. References (External, Not Part of Repo)

Reference game source and mod code is configured via `mod.config.json` `source_paths`:
- `game_desktop` / `game_mobile`: Vanilla Balatro source for understanding `save_run`, `start_run`, writing lovely.toml patterns
- `steamodded`: Steamodded loader source
- `lovely`: Lovely Loader source
- `mods`: Installed mods directory for pattern reference

---

## 5. Key Concepts

### Entry Structure (Unified)
13-field arrays for memory efficiency. Access via `REWINDER.ENTRY_*` constants.

**See `CACHE_ENTRY_EXAMPLE.md`** for:
- All 13 field indices and types
- Unified signature format (`"ante:round:display_type:discards_used:hands_played:money"`)
- Display type codes and their meanings
- Meta file format
- Entry lifecycle (create, compare, load, restore)

### Signature Format (Unified)
Single string format for fast comparison:
```
"ante:round:display_type:discards_used:hands_played:money"
```
Examples:
- `"2:3:F:0:0:150"` — Ante 2 Round 3, Entering shop, $150
- `"2:3:O:0:0:150"` — Ante 2 Round 3, Opening pack, $150
- `"5:15:P:0:1:250"` — Ante 5 Round 15, Play action, $250

**Key principle**: Display type is computed BEFORE signature creation, enabling simple string comparison.

### State Info vs Entry
- **state_info**: Temporary object from `StateSignature.get_state_info(run_data)` — raw state for display_type computation
- **entry**: 13-field array stored in cache — the canonical persistent structure

### Cache Ordering Model
- **Internal storage (`save_cache`)**: oldest-first (optimized for O(1) append in `create_save`)
- **Public view (`get_save_files`)**: newest-first cached view (UI and callbacks continue to use newest-first indices)
- **Index maps (`get_index_by_file`, `get_entry_by_id`)**: report newest-first indices to match UI pagination and step-back logic

### ordinal_state (O(1) Metadata)
In-memory state machine in `SaveManager.lua` for computing `display_type` and `ordinal` at save time without cache scanning.

**Structure:**
```lua
ordinal_state = {
   ante = nil,              -- Current ante
   blind_key = nil,         -- Current blind (e.g., "bl_small"), nil treated as "unknown"
   last_display_type = nil, -- For first_shop/after_pack detection
   last_discards_used = 0,  -- For play/discard detection
   last_hands_played = 0,   -- For play/discard detection
   last_round = nil,        -- For post-boss shop detection
   last_saved_round = nil,  -- Round when counters were last reset (for per-round ordinal)
   counters = { S=0, F=0, O=0, A=0, R=0, P=0, D=0, H=0, E=0, B=0, ["?"]=0 },
   defeated_boss_idx = nil, -- Boss blind index after defeat (nil = not in post-boss phase)
}
```

**Reset triggers:**
- Ante or round change during gameplay → resets all counters
- blind_key change alone does NOT reset counters (allows B to increment when skipping)
- Entering choose blind (B) → resets `defeated_boss_idx` and `last_round`
- Save restore → re-initialized from entry's stored values; scans cache to restore ALL counters at same ante/round (not just the loaded type)

**Boss tracking:**
- Set when E save on round 3 or boss blind (index > 2)
- Used by shop saves (F/S/O/A) to display defeated boss icon
- Reset when entering choose blind screen


### Timeline Pruning (Deferred)
When loading older save at index 5, saves 1-4 are marked via `pending_future_prune_boundary` but **not deleted immediately**. Deletion happens on next `create_save()` call. This allows "undo the undo" if user restarts before making new move.

### Retention Policy Boundary
- Retention orchestration lives in `SaveManager` (`_apply_retention_policy`), not in UI/callback code.
- `SaveManager` prepares entries for retention (`_prepare_entries_for_retention`), including lazy key-flag hydration.
- `Pruning.apply_retention_policy` receives a preservation callback (`should_preserve_entry`) and performs in-place compaction + file deletion.
- Current preserve rule is key saves (`ENTRY_IS_KEY == true`), but future preserve categories should be added through the SaveManager boundary.

### Duplicate Skip
After restore, first auto-save often matches restored state. `load_and_start_from_file()` stores individual loaded fields (`_loaded_ante`, `_loaded_round`, etc.); `consume_skip_on_save()` computes current state and compares fields directly (O(1), no signature string formatting).

### NaN Protection (v1.4.8+)
When score values overflow to extremely large numbers, they become NaN or infinity. Without protection, this causes crashes during save/load and arithmetic operations.

**The Problem:**
- Lua's `STR_PACK` serializes NaN as literal string `nan` and infinity as `inf`
- When `loadstring()` unpacks these, they're undefined globals → become `nil`
- Arithmetic operations on `nil` crash: `attempt to perform arithmetic on a nil value`

**Solution: NaNProtection Module (`Utils/NaNProtection.lua`)**

Centralized defense-in-depth sanitization with configurable infinity handling:

**NaN Handling (Always Active):**
- NaN values are **always converted to 0** to prevent crashes
- Applied at save, load, serialization, and display

**Infinity Handling (Configurable via `clamp_infinity_scores`):**

| Config | Display | Save/Load Behavior | Notes |
|--------|---------|-------------------|-------|
| `false` (default) | Shows as `inf` | Converts to `0` after save/load | Safe from crashes, but loses infinity value on reload |
| `true` | Shows as `1.8e308` | Preserved as `1.8e308` | Maintains playability, caps at max safe value |

**Context-Specific Infinity Handling:**
- **Continue panel (`round_scores`)**: Always converts inf/nan to 0 (safe display)
- **Stats screen (`high_scores`)**: Respects `clamp_infinity_scores` setting
- This allows Stats to show "inf" while Continue screen shows "0" for the same game

**Key Constants:**
```lua
M.MAX_SAFE_SCORE = 1.7976931348623157e308  -- IEEE 754 DBL_MAX
M.LARGE_NUMBER_THRESHOLD = 1e290           -- Above this, custom formatting
```

**Key Functions:**
| Function | Purpose |
|----------|---------|
| `sanitize(v, context)` | NaN→0 always; inf→MAX_SAFE_SCORE if clamping enabled, else preserved |
| `sanitize_round_scores(game)` | Post-load: fix nil values from corrupted saves (NaN→0) |
| `sanitize_round_scores_presave(game)` | Pre-save: NaN→0 always; inf→MAX_SAFE_SCORE if clamping enabled |
| `sanitize_number_format(num)` | Display: NaN→0; inf handling per config; custom format for very large numbers |
| `sanitize_serialize(v, k)` | Serialization: NaN→0 always; inf→MAX_SAFE_SCORE if clamping enabled |

**Defense-in-depth patches in `lovely.toml`:**

| Target | Purpose |
|--------|---------|
| `functions/misc_functions.lua` (after save_run) | Pre-save: `NaNProtection.sanitize_round_scores_presave(G.GAME)` |
| `game.lua` (after load) | Post-load: `NaNProtection.sanitize_round_scores(self.GAME)` |
| `engine/string_packer.lua` | Sanitize during serialization: `NaNProtection.sanitize_serialize(v, k)` |
| `functions/state_events.lua` | Sanitize `ease_to` calculation at the source |
| `engine/event.lua` (line 31, 62) | Sanitize ease event values |
| `functions/misc_functions.lua` (number_format) | Handle NaN/inf in display formatting |
| `functions/misc_functions.lua` (high scores) | Handle nil `.amt` in comparisons |
| `functions/UI_definitions.lua` | Handle nil best hand in continue screen UI |
| `state_events.lua`, `game.lua`, `blind.lua` | Handle nil chips in blind comparison expressions |

**Key Insights:**
- **NaN is always dangerous** → Always converted to 0
- **Infinity is configurable** → User chooses between "display as inf but lose on reload" vs "cap at 1.8e308 and keep"
- With clamping disabled, you won't crash on save/load, but infinity becomes 0 after reload
- Event.lua line 62 OVERWRITES `start_val` set at line 30, so patching line 62 is essential
- lovely.toml patches should call module functions, not inline logic (maintainability)

**Lua Number Handling Notes:**
```lua
-- NaN check (only NaN fails self-equality)
if v ~= v then -- v is NaN

-- Infinity check
if v == math.huge or v == -math.huge then -- v is ±infinity

-- Lua has NO DBL_MAX constant (math.huge is infinity, not max finite)
-- IEEE 754 DBL_MAX = (2 - 2^-52) * 2^1023
-- Computing at runtime is tricky (2^1024 overflows), so hardcode it:
local DBL_MAX = 1.7976931348623157e308

-- Very large numbers (>1e290) may overflow game's display code
-- Solution: format ourselves and return early
if num >= 1e290 then
    local exp = math.floor(math.log10(num))
    local mantissa = num / (10 ^ exp)
    return string.format("%.3fe%d", mantissa, exp)
end
```

### Scale Number Hook (`Utils/ScaleNumberHook.lua`)

The game's `scale_number()` function determines text size based on the numeric value. For extremely large numbers (e.g., 1.8e308), this causes massive text that breaks the UI (especially on the Continue screen).

**Solution:** For numbers > 1e290 (including `math.huge`), return the base `scale` parameter directly without any computation.

**How it works:**
1. Module loads early via `load_now = true, before = "globals.lua"` in lovely.toml
2. `button_callbacks.lua` loads and defines `scale_number` (line 1905)
3. `UI/ButtonCallbacks.lua` is appended to `button_callbacks.lua`
4. At the top of `UI/ButtonCallbacks.lua`, we call `ScaleNumberHook.install()`
5. The wrapper checks `if number > 1e290 then return scale end`, else passes to original

**Key Points:**
- Simple threshold check: `number > M.LARGE_NUMBER_THRESHOLD` (1e290)
- For very large numbers, just returns the base scale - no computation needed
- `math.huge > 1e290` is true, so infinity is handled automatically
- Installation is done from `UI/ButtonCallbacks.lua`, NOT via lovely.toml pattern patch
- Lovely modules are accessed via `require("ModuleName")`, NOT as globals

---

## 6. Core Flows

### Initialization
**See `INIT_FLOW.md`** for detailed diagram. Summary:
1. `Init.lua` loaded during game start, creates `REWINDER` namespace
2. Exports SaveManager API to `REWINDER.*`
3. Hooks `Game:set_render_settings` (runs during loading screen)
4. `preload_all_metadata()` — loads the save index and warms a bounded meta window
5. Matches `save.jkr` to cache via `_rewinder_id` (O(1)); fallback is newest save if no match

### Save Writing
1. Game calls `save_run()` → `G.culled_table` ready
2. `lovely.toml` patch → `REWINDER.defer_save_creation()`
3. Tag `G.culled_table` with `_rewinder_id` and call `SaveManager.create_save()` immediately (same frame, same table)
4. `SaveManager.create_save()`:
   - `StateSignature.get_state_info(run_data)` → extract raw state
   - Check ordinal_state reset (ante/round/blind change)
   - `_compute_display_type(state_info)` → single-char code using ordinal_state context
   - `_create_signature(state_info, display_type)` → unified signature string
   - Duplicate check via signature STRING comparison
   - Compute ordinal using O(1) counter approach
   - Boss tracking: set defeated_boss_idx on E saves for boss rounds
   - Compute blind_idx: B→0, shop after boss→defeated_boss_idx, else→actual
   - Write `.jkr` + `.meta` files (captures compressed bytes from write)
   - Write compressed bytes directly to `save.jkr` (avoids re-read from disk)
   - Append new entry in O(1) to internal oldest-first cache
   - Update `save_cache_by_file` immediately; lazily invalidate derived index maps (`save_index_by_file`, `save_cache_by_id`)
   - Apply retention policy only on ante change through SaveManager retention boundary (loads key flags, applies preserve policy callback, then rebuilds indices if needed)

### Save Loading
**See `CLICK_LOAD_FLOW.md`** for detailed diagram. Summary:
1. Click/hotkey → `load_and_start_from_file(file)`
2. Copy save to `save.jkr`, store loaded fields (`_loaded_ante`, `_loaded_round`, etc.)
3. Initialize `ordinal_state` from entry (includes ante, blind_key, round for per-round ordinals)
4. `G:delete_run()` → `G:start_run({savetext=...})` (fast path, no loading screen)
5. `consume_skip_on_save` uses direct field comparison (no signature string formatting)

### Step Back (S Key)
**See `PRESS_S_FLOW.md`** for detailed diagram. Summary:
1. Find `current_index` from `_last_loaded_file` or `ENTRY_IS_CURRENT`
2. Get previous entry at `current_index + 1`
3. Call `load_and_start_from_file()` with previous entry

### Save List Rendering
**See `SAVE_LIST_FLOW.md`** for detailed diagram. Summary:
1. Resolve active entry set (full or key-filtered) and target page containing current save.
2. Render visible rows only via `get_saves_page()` + `build_save_node()` (lazy meta loading, O(per_page)).
3. Apply mode behavior through callbacks: filter persists across reopen; mark mode commits on toggle-off and discards pending edits on close.
4. Keep layout/controller specifics in `SAVE_LIST_FLOW.md` to avoid duplication in this overview.

### Meta Cache (Bounded + Elastic UI, O(1) LRU)
- Base meta cache size: 32 entries
- Cache grows elastically while the Saves UI is open
- On close, cache recenters to current save and trims back to base size
- Current save meta is always pinned
- LRU uses counter-based timestamps (`meta_lru_ts` hash + `meta_lru_clock`): touch/remove are O(1), eviction scans only when cache overflows

### Continue from Main Menu
When user clicks "Continue" without using our UI:
1. `Init.lua` matches `save.jkr` to cached entries during loading screen
2. **Primary**: O(1) lookup by `_rewinder_id` field (injected into save data by `defer_save_creation`)
3. **Fallback**: Use newest save if no match (legacy saves without `_rewinder_id` are not supported)
5. `Game:start_run` clears stale `_loaded_*` markers (and resets `ordinal_state`) when no restore/step is pending, then calls `mark_loaded_state`
6. `mark_loaded_state` always updates `_last_loaded_file` (and `current_index` when known) from the file derived off `savetext._rewinder_id` — important for QuickLoad-style "load save.jkr" flows
7. `create_save()` writes compressed bytes directly to `save.jkr` (fallback: file copy) to keep base saves aligned for other mods

### Custom Save Field (`_rewinder_id`)
- Injected into `G.culled_table` in `defer_save_creation()` BEFORE game writes `save.jkr`
- Value is an epoch-based unique ID (milliseconds since Unix epoch + per-second sequence; same as `ENTRY_INDEX`)
- Enables O(1) exact matching via `save_cache_by_id` hash table
- Zero extra I/O — piggybacks on existing save.jkr write

---

## 7. Common Mistakes to Avoid

> [!CAUTION]
> **No loops in create_save** — Use `ordinal_state` for O(1) access, never scan `save_cache` for action detection or ordinal computation.

> [!IMPORTANT]
> **Ordinal is per-round, not per-blind** — All counters reset when `ante` or `round` changes. blind_key changes do NOT reset counters (this allows B1→B2→B3 when skipping blinds within same round).

> [!WARNING]
> **Restore resets ordinal_state** — Must re-initialize from entry's stored values (ante, blind_idx, discards_used, hands_played, display_type, ordinal for counter).
> For `P`/`D` loads, set last counters to **pre-action values** (`hands_played - 1` or `discards_used - 1`) so the identical post-load state still computes as `P`/`D` (not `H`).

> [!NOTE]
> **TOML regex escaping** — Double-escape backslashes in `lovely.toml` patterns (e.g., `\\(` not `\(`).

> [!NOTE]
> **match_indent not supported for regex patches** — `match_indent = true` only works for `[patches.pattern]`, not `[patches.regex]`. Remove it from regex patches to avoid Lovely Loader warnings.

> [!NOTE]
> **Signature comparison is string equality** — Display type is computed BEFORE signature creation, so `signatures_equal()` is just string comparison.

> [!NOTE]
> **No technical jargon in CHANGELOG** — CHANGELOG.md is for end users, not developers. Avoid terms like "O(1)", "hash table", "signature", "ordinal". Focus on user-visible behavior (e.g., "faster save list loading" not "O(1) lookup").

> [!CAUTION]
> **Never sanitize infinity to 0** — If scores overflow to infinity and you convert to 0, the player cannot beat any blind. Use `MAX_SAFE_SCORE` (DBL_MAX) instead.

> [!WARNING]
> **Lua has no DBL_MAX constant** — `math.huge` is infinity, not max finite double. Must hardcode `1.7976931348623157e308`. Computing at runtime is tricky because `2^1024` overflows to infinity.

> [!WARNING]
> **Very large numbers cause display overflow** — Numbers above ~1e290 may display incorrectly (e.g., "nane9223372036854775807"). Use custom formatting via `NaNProtection.sanitize_number_format()` to bypass the game's display code.

> [!NOTE]
> **Keep sanitization logic in NaNProtection module** — lovely.toml patches should call module functions (`NaNProtection.sanitize_round_scores_presave(G.GAME)`), not inline the logic. This keeps constants like `MAX_SAFE_SCORE` in one place.

> [!CAUTION]
> **Pattern patches fail silently** — `[patches.pattern]` in lovely.toml can fail to match without any error. Prefer `[patches.copy]` with `position = "append"` when possible. If a pattern patch must be used, add `pcall(print, ...)` diagnostics to verify it runs.

> [!CAUTION]
> **Verify fixes with basic diagnostics first** — Before assuming a fix works, add `pcall(print, "[Module] checkpoint X")` at key points. Don't rely on Logger (it depends on REWINDER.config). Pattern patches that "look correct" may not match due to subtle whitespace or encoding differences.

> [!WARNING]
> **Prefer appending to pattern injection** — For function wrapping, append the hook installation to a file that's already being appended (e.g., add hook install to `UI/ButtonCallbacks.lua` which is appended to `button_callbacks.lua`). This is more reliable than pattern-matching a specific line.

> [!NOTE]
> **Lovely modules are NOT globals** — Modules loaded via `[patches.module]` must be accessed via `require("ModuleName")`, not as globals. If you try to access them as globals, you'll get `nil`.

> [!NOTE]
> **Simplify large number handling** — For very large numbers (>1e290), consider just returning a default value instead of complex capping logic. Example: `if num > 1e290 then return base_scale end` is simpler than input/output capping.

> [!CAUTION]
> **Context-specific infinity handling** — Different UI contexts may need different infinity behavior. Continue panel should show 0 (safe), while Stats can show inf (user preference). Use separate patches for `round_scores` vs `high_scores`.

> [!CAUTION]
> **Lua forward declarations required for local functions** — In Lua, `local function foo()` is only visible AFTER its definition. If function A calls function B, but A is defined before B, you must forward-declare B with `local B` before A, then assign `B = function() ... end` at the actual definition site. This caused a crash when `_update_cache_current_flags` (line ~404) called `_rebuild_file_index` (line ~539).

> [!WARNING]
> **Restore resets ALL ordinal counters** — `_init_ordinal_state_from_entry` calls `_reset_ordinal_state` which zeros every counter, then must restore counters for ALL display types at the same ante/round by scanning the cache. Without this, loading an A save would reset the O counter, causing the next O save to get ordinal 1 again (duplicate).

---

## 8. Development

```bash
./scripts/sync_to_mods.sh           # One-time sync
./scripts/sync_to_mods.sh --watch   # Auto-sync on file changes
./scripts/create_release.sh         # Create release packages (auto-detects version)
./scripts/create_release.sh 1.4.7  # Create release with specific version
```

- **No build system**: Edit Lua files in-place, sync to game, restart Balatro
- **Logs**: Check `~/Library/Application Support/Balatro/Mods/lovely/log/` and repo-local `logs/` for crash traces and patch diagnostics
- **Testing**: Launch Balatro with Steamodded/Lovely Loader, verify mod in mods list

### Release Packages

The `create_release.sh` script generates two zip files in `release/[VERSION]/`:
- **General version** (`SaveRewinder-X.Y.Z.zip`): Files wrapped in `SaveRewinder/` folder (for GitHub releases, Nexus Mods)
- **Thunderstore version** (`SaveRewinder-X.Y.Z-Thunderstore.zip`): Files at root directory (includes `README.md`, `CHANGELOG.md`, `icon.png`, `manifest.json`)

**Base files** (both versions): Core mod files (main.lua, config.lua, Core/, UI/, Utils/, etc.)
**Thunderstore additions**: README.md, CHANGELOG.md, icon.png, manifest.json

### Version Management

When releasing a new version, update version in **4 places**:
1. `SaveRewinder.json` — `"version": "X.Y.Z"` (Steamodded reads this)
2. `manifest.json` — `"version_number": "X.Y.Z"` (Thunderstore/r2modman reads this)
3. `CHANGELOG.md` — Add new version section at top
4. `CHANGELOG_zh.md` — Same changes in Chinese

Then run `./scripts/create_release.sh` to generate release packages.

---

## 9. When to Ask Humans

- Changes to entry structure, metadata layout, or signature format
- Changing save timing or timeline-pruning logic
- Adding new `lovely.toml` patches that might conflict with other mods
- Changing `ordinal_state` reset/initialization behavior

---

## 10. Code Examples

```lua
-- Defer save (injected by lovely.toml after G.ARGS.save_run = G.culled_table)
REWINDER.defer_save_creation()

-- Load save
REWINDER.load_and_start_from_file("2-3-1609430.jkr")

-- Access cache entry (13-element array)
local file = entry[REWINDER.ENTRY_FILE]           -- index 1
local display_type = entry[REWINDER.ENTRY_DISPLAY_TYPE]  -- index 11
local blind_idx = entry[REWINDER.ENTRY_BLIND_IDX] -- index 10
local is_key = entry[REWINDER.ENTRY_IS_KEY]       -- index 13
local signature = entry[REWINDER.ENTRY_SIGNATURE] -- index 6 (unified format)

-- Convert blind_idx to key for sprite
local blind_key = REWINDER.index_to_blind_key(blind_idx)
local sprite = REWINDER.create_blind_sprite(blind_key)

-- Get state info from run_data (for display_type computation)
local state_info = StateSignature.get_state_info(run_data)

-- Create signature string (after computing display_type)
local signature = StateSignature.encode_signature(
   state_info.ante, state_info.round, display_type,
   state_info.discards_used, state_info.hands_played, state_info.money
)

-- Compare signatures (simple string equality)
if StateSignature.signatures_equal(sig_a, sig_b) then
   -- States match
end
```

---

## 11. Codebase Health & Refactoring Notes

### Current File Sizes

| File | Lines | Status | Notes |
|------|-------|--------|-------|
| `Core/SaveManager.lua` | 1292 | ⚠️ Over | Core orchestration remains cohesive but large; keep splits cautious. |
| `Utils/Keybinds.lua` | 841 | ⚠️ Slightly over | `navigate_focus` controller logic is the largest block. |
| `UI/RewinderUI.lua` | 710 | ⚠️ Near limit | Recent cleanup reduced duplication, still a candidate for future split. |
| `UI/ButtonCallbacks.lua` | 336 | ✅ OK | Second-pass refactor applied shared helpers for page/frame updates. |
| `Utils/NaNProtection.lua` | 233 | ✅ OK | Clamp logic now centralized via `should_clamp_infinity()`. |
| `Core/GamePatches.lua` | 175 | ✅ OK | Final-pass helper extraction reduced duplicate branches. |
| `Utils/Logger.lua` | 92 | ✅ OK | Shared `format_message(...)` and no undefined fallback vars. |

### Refactor Baseline (latest passes)

- Save creation hot path no longer pays O(N) front-insert costs; cache internals are oldest-first with cached newest-first public view.
- Pruning and retention are now single-pass/tail-trim oriented where possible.
- UI page-cycle configuration and localized fallback handling were deduplicated in `RewinderUI`.
- `Game:start_run` rewinder-specific logic is centralized in local helpers for maintainability.

### Quality Guidelines

1. Keep `create_save()` and per-frame UI paths allocation-light.
2. Prefer small shared helpers when repeated logic appears in 2+ places.
3. Keep localization fallbacks centralized (`loc(...)`) instead of repeating `(localize and localize(...))`.
4. Test edge cases: nil/NaN/inf scores, restore-then-save duplicate skip, and 50+ save pagination behavior.
5. Use `pcall(print, ...)` for early patch diagnostics, then move stable logs back to `Logger`.
