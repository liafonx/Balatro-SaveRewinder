# Save Rewinder - AI Development Guide

Detailed guidance for AI agents working on this repo. More comprehensive than `.github/copilot-instructions.md`.

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

- **Dual Keybinding System (v1.4.7)**: Separate `keyboard` and `controller` tables for each action. Allows `S` for keyboard step-back while keeping `L3` for controller.
- **Controller Navigation**: Hardcoded hooks for `LB`/`RB` (page flip) and `Y` (jump to current) in the saves overlay. Custom focus navigation logic prevents vanilla crashes.
- **Controller Shortcuts**: `X` button (Pause Menu only) opens saves list.
- **Keybinds.lua Refactor**: Centralized controller hooks, context-aware `format_binding`, and safe `update_binding` logic.
- **Save ordering guard**: new saves re-sort if out-of-order to prevention timeline misordering.

## 1.2 Unfinished / Open Requirements

- **Docs/UI**: Refine UI labels to clearly show both active bindings (currently context-sensitive based on last input).

---

## 2. File Structure & Relations

### Core/ — Core Modules

| File | Purpose | Key Exports | Dependencies |
|------|---------|-------------|--------------|
| `Init.lua` | Entry point. Sets up `REWINDER` namespace, hooks `Game:set_render_settings` for cache init at boot | `REWINDER` global | SaveManager |
| `SaveManager.lua` | Save management: create, load, list, prune. Contains `ordinal_state` for O(1) metadata. Single source of truth for entry constants | `ENTRY_*` constants, `get_save_files`, `create_save`, `load_and_start_from_file`, `blind_key_to_index`, `index_to_blind_key` | StateSignature, FileIO, MetaFile, Pruning |
| `GamePatches.lua` | Game function overrides. Hooks `Game:start_run` for loaded state marking, shop CardArea pre-loading | `defer_save_creation` | SaveManager |

**Module Dependency Graph:**
```
lovely.toml patches → GamePatches.defer_save_creation()
                              ↓
Init.lua → SaveManager.preload_all_metadata() (at boot; warms bounded meta window)
                              ↓
SaveManager → StateSignature (state info extraction)
            → FileIO (file read/write)
            → MetaFile (fast .meta read/write)
            → Pruning (retention policy, future prune)
                              ↓
UI (RewinderUI, ButtonCallbacks) → SaveManager (entry data, load functions)
Keybinds → SaveManager (step back, UI toggle)
```

### Documentation Files

**IMPORTANT: CHANGELOG is user-facing**
- `CHANGELOG.md` / `CHANGELOG_zh.md` are for **end users**, not developers
- Focus on **what users will notice**, not implementation details
- ✅ Good: "Shop saves now show previous boss blind icon"
- ❌ Bad: "Refactored blind icon logic from display-time to save-time determination"
- Skip technical details unless they directly impact user experience

**Other docs:**
- `README.md` / `README_zh.md`: User-facing project overview
- `docs/AGENT.md`: This file - AI agent development guide
- `docs/*.md`: Technical documentation for developers

### Utils/ — Utilities

| File | Purpose | Key Functions | Used By |
|------|---------|---------------|---------|
| `StateSignature.lua` | Game state extraction and signature encoding | `get_state_info`, `encode_signature`, `signatures_equal`, `describe_save` | SaveManager, Init |
| `MetaFile.lua` | Fast `.meta` file read/write (7 fields). Uses `NUMERIC_FIELDS` set for O(1) field type lookup | `read_meta_file`, `write_meta_file` | SaveManager |
| `FileIO.lua` | File operations for `.jkr` files | `copy_save_to_main`, `load_save_file`, `write_save_file`, `get_save_dir` | SaveManager |
| `Pruning.lua` | Retention policy (max antes), future save cleanup on restore | `apply_retention_policy`, `prune_future_saves` | SaveManager |
| `Logger.lua` | Centralized logging with module-specific tags | `Logger.create(module_name)` → returns logger with `step`, `list`, `error`, `prune`, `restore`, `info`, `detail` methods | All modules |
| `G.STATES.lua` | Reference file for `G.STATES` enum and `G.P_BLINDS` table | **Not loaded at runtime** — IDE autocomplete only | None |

### UI/ — User Interface

| File | Purpose | Key Functions | Dependencies |
|------|---------|---------------|--------------|
| `RewinderUI.lua` | Save list overlay with pagination, blind sprites, entry highlighting | `G.UIDEF.rewinder_saves`, `build_save_node`, `create_blind_sprite`, `get_saves_page` | SaveManager (`ENTRY_*` constants) |
| `ButtonCallbacks.lua` | UI button handlers for restore, navigation, deletion | `rewinder_save_restore`, `rewinder_save_jump_to_current`, `rewinder_next_page`, `rewinder_prev_page` | SaveManager |

### Root Files

| File | Purpose |
|------|---------|
| `Keybinds.lua` | Keybinds manager (Dual Binding system). Handles input hooks, restricted execution (Run stage), and UI formatting. Contains specific hooks for Controller navigation (`navigate_focus`) and shortcuts. |
| `main.lua` | Steamodded config tab integration (auto-save toggles, display options) |
| `config.lua` | Default config values |
| `lovely.toml` | Lovely Loader patches: injects `REWINDER.defer_save_creation()` after `save_run` |

### Localization/

| File | Purpose |
|------|---------|
| `localization/en-us.lua` | English strings for UI labels, state names, config options |
| `localization/zh_CN.lua` | Chinese (Simplified) strings |

---

## 3. Documentation Files

| Doc | Content |
|-----|---------|
| `CACHE_ENTRY_EXAMPLE.md` | **12-field entry structure**, unified signature format, display type codes, meta file format, entry lifecycle |
| `INIT_FLOW.md` | Mod initialization: namespace setup, cache preload during loading screen, save.jkr matching |
| `CLICK_LOAD_FLOW.md` | Complete save loading flow from UI click to game restart |
| `PRESS_S_FLOW.md` | Step-back hotkey (`S`) flow: find previous save, load, and start |
| `SAVE_LIST_FLOW.md` | Save list UI rendering: pagination, lazy loading, entry node building |

---

## 4. References Directory (Not Part of Mod)

All materials in `References/` are for development reference only, not distributed with mod.

**Note:** Most mod folders in `References/` are symlinks pointing to `/Users/liafo/Library/Application Support/Balatro/Mods/`. This allows References to use live versions of mods for code inspection and pattern reference. Actual mod files are in the Mods folder (used by the game).

| Folder | Content | Use For |
|--------|---------|---------|
| `balatro_src/` | Unpacked vanilla Balatro source (`game.lua`, `functions/misc_functions.lua`, `functions/button_callbacks.lua`, etc.) | Understanding original implementations (`save_run`, `start_run`), writing `lovely.toml` regex patterns |
| `lovely/` | Lovely Loader files including `log/` directory | Debugging patches, crash logs, patch diagnostics |
| `Steamodded/` | Steamodded loader scripts and config | Understanding mod loading, config tab patterns |
| `Balatro-History/` | Another save history mod | Timeline and backup logic reference |
| `Brainstorm-Rerolled/` | Fast restart mod | Borrowed `G:delete_run()` → `G:start_run({savetext=...})` pattern for instant restore |
| `QuickLoad/` | Fast save loading mod | Borrowed `get_compressed()` + `STR_UNPACK()` flow for `.jkr` unpacking |
| `BetterMouseandGamepad/` | Controller navigation mod | Focus management, L3/R3 mapping patterns |
| `UnBlind/` | Boss blind preview mod | Blind sprite creation with `AnimatedSprite`, dissolve shader, shadow effects |
| `JokerDisplay/` | Joker info display mod | Config UI organization (two-column layout) |

---

## 5. Key Concepts

### Entry Structure (Unified)
12-field arrays for memory efficiency. Access via `REWINDER.ENTRY_*` constants.

**See `CACHE_ENTRY_EXAMPLE.md`** for:
- All 12 field indices and types
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
- **entry**: 12-field array stored in cache — the canonical persistent structure

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
- Save restore → re-initialized from entry's stored values

**Boss tracking:**
- Set when E save on round 3 or boss blind (index > 2)
- Used by shop saves (F/S/O/A) to display defeated boss icon
- Reset when entering choose blind screen


### Timeline Pruning (Deferred)
When loading older save at index 5, saves 1-4 are marked in `pending_future_prune` but **not deleted immediately**. Deletion happens on next `create_save()` call. This allows "undo the undo" if user restarts before making new move.

### Duplicate Skip
After restore, first auto-save often matches restored state. `load_and_start_from_file()` stores individual loaded fields (`_loaded_ante`, `_loaded_round`, etc.); `consume_skip_on_save()` computes current state and compares fields directly (O(1), no signature string formatting).

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
   - Write `.jkr` + `.meta` files
   - Update cache, apply retention policy

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
1. `G.UIDEF.rewinder_saves()` calls `get_save_files()` (updates current flags)
2. Calculate pagination, find page containing current save
3. `get_saves_page()` renders only visible entries (O(per_page))
4. `build_save_node()` uses pre-computed `ENTRY_DISPLAY_TYPE` and `ENTRY_ORDINAL`
5. Lazy-load metadata on-demand when entry is first rendered

### Meta Cache (Bounded + Elastic UI)
- Base meta cache size: 32 entries
- Cache grows elastically while the Saves UI is open
- On close, cache recenters to current save and trims back to base size
- Current save meta is always pinned

### Continue from Main Menu
When user clicks "Continue" without using our UI:
1. `Init.lua` matches `save.jkr` to cached entries during loading screen
2. **Primary**: O(1) lookup by `_rewinder_id` field (injected into save data by `defer_save_creation`)
3. **Fallback**: Use newest save if no match (legacy saves without `_rewinder_id` are not supported)
5. `Game:start_run` clears stale `_loaded_*` markers (and resets `ordinal_state`) when no restore/step is pending, then calls `mark_loaded_state`
6. `mark_loaded_state` always updates `_last_loaded_file` (and `current_index` when known) from the file derived off `savetext._rewinder_id` — important for QuickLoad-style "load save.jkr" flows
7. `create_save()` copies the freshly written rewinder `.jkr` to `save.jkr` (fast path), keeping base saves aligned for other mods

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

---

## 8. Development

```bash
./scripts/sync_to_mods.sh           # One-time sync
./scripts/sync_to_mods.sh --watch   # Auto-sync on file changes
./scripts/create_release.sh         # Create release packages (auto-detects version)
./scripts/create_release.sh 1.4.7  # Create release with specific version
```

- **No build system**: Edit Lua files in-place, sync to game, restart Balatro
- **Logs**: Check `References/lovely/log/` for crash traces and patch diagnostics
- **Testing**: Launch Balatro with Steamodded/Lovely Loader, verify mod in mods list

### Development Setup

**References Folder Structure:**
- `References/` contains symlinks pointing to actual mods in `/Users/liafo/Library/Application Support/Balatro/Mods/`
- This allows References to use live versions of mods for development reference
- Actual mod files are in Mods folder (used by the game)
- References folder is for code inspection and pattern reference only

**lovely.toml Configuration:**
- `match_indent` is **not supported** for `[patches.regex]` patches (only for `[patches.pattern]`)
- If you see warnings about `match_indent` in regex patches, remove that key
- Pattern patches can use `match_indent = true` to match indentation
- Regex patches match exact text regardless of indentation

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

-- Access cache entry (12-element array)
local file = entry[REWINDER.ENTRY_FILE]           -- index 1
local display_type = entry[REWINDER.ENTRY_DISPLAY_TYPE]  -- index 11
local blind_idx = entry[REWINDER.ENTRY_BLIND_IDX] -- index 10
local signature = entry[REWINDER.ENTRY_SIGNATURE] -- index 6 (unified format)

-- Convert blind_idx to key for sprite
local blind_key = REWINDER.SaveManager.index_to_blind_key(blind_idx)
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
