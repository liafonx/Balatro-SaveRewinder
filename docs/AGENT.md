# Save Rewinder - AI Development Guide

Detailed guidance for AI agents working on this repo. More comprehensive than `.github/copilot-instructions.md`.

---

## 1. Big Picture

This is a Balatro mod that snapshots game state and supports instant rewind/restore via a cached `.jkr` + `.meta` timeline. It uses **static patching** (via `lovely.toml`) and **deferred execution** (next-frame events) to avoid recursive hook conflicts with other mods.

**Core objectives:**
- Automatically create multiple saves during gameplay (sorted chronologically)
- Allow players to restore runs from any save point ("undo / step back")
- Provide save list UI with blind icons, hotkeys, and controller support
- Run transparently, compatible with popular mods (`Steamodded`, `debugplus`, etc.)

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
Init.lua → SaveManager.preload_all_metadata() (at boot)
                              ↓
SaveManager → StateSignature (fingerprinting)
            → FileIO (file read/write)
            → MetaFile (fast .meta read/write)
            → Pruning (retention policy, future prune)
                              ↓
UI (RewinderUI, ButtonCallbacks) → SaveManager (entry data, load functions)
Keybinds → SaveManager (step back, UI toggle)
```

### Utils/ — Utilities

| File | Purpose | Key Functions | Used By |
|------|---------|---------------|---------|
| `StateSignature.lua` | Game state fingerprinting for duplicate detection | `get_signature`, `encode_signature`, `describe_signature`, `get_label_from_state` | SaveManager, GamePatches |
| `MetaFile.lua` | Fast `.meta` file read/write (7 fields: money, signature, discards_used, hands_played, blind_idx, display_type, ordinal) | `read_meta_file`, `write_meta_file` | SaveManager |
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
| `Keybinds.lua` | `S` (step back), `Ctrl+S` (toggle UI), Controller: `L3`/`R3`, LB/RB for page nav |
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
| `CACHE_ENTRY_EXAMPLE.md` | **12-field entry structure**, display type codes (S/F/O/R/P/D/H/E/B/?), meta file format, entry lifecycle |
| `CLICK_LOAD_FLOW.md` | Complete save loading flow diagram with all steps from click to game restart |

---

## 4. References Directory (Not Part of Mod)

All materials in `References/` are for development reference only, not distributed with mod:

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

### Entry Structure
12-field arrays for memory efficiency. Access via `REWINDER.ENTRY_*` constants.

**See `CACHE_ENTRY_EXAMPLE.md`** for:
- All 12 field indices and types
- Display type codes and their meanings
- Meta file format
- Entry lifecycle (create, load, restore)

### ordinal_state (O(1) Metadata)
In-memory state machine in `SaveManager.lua` for computing `display_type` and `ordinal` at save time without cache scanning.

**Structure:**
```lua
ordinal_state = {
   ante = nil,              -- Current ante
   blind_key = nil,         -- Current blind (e.g., "bl_small")
   last_display_type = nil, -- For first_shop detection
   last_discards_used = 0,  -- For play/discard detection
   last_hands_played = 0,   -- For play/discard detection
   counters = { S=0, O=0, P=0, D=0, H=0, B=0, ["?"]=0 }  -- Per-type ordinals
}
```

**Reset triggers:**
- Ante or blind_key change during gameplay
- Save restore → re-initialized from entry's stored values

### Timeline Pruning (Deferred)
When loading older save at index 5, saves 1-4 are marked in `pending_future_prune` but **not deleted immediately**. Deletion happens on next `create_save()` call. This allows "undo the undo" if user restarts before making new move.

### Duplicate Skip
After restore, first auto-save often matches restored state. `mark_loaded_state()` records signature; `consume_skip_on_save()` compares and skips if identical.

---

## 6. Core Flows

### Save Writing
1. Game calls `save_run()` → `G.culled_table` ready
2. `lovely.toml` patch → `REWINDER.defer_save_creation()`
3. Deep-copy `G.culled_table`, defer to next frame via `G.E_MANAGER`
4. `SaveManager.create_save()`:
   - Check ordinal_state reset (ante/blind change)
   - O(1) action detection (compare discards_used/hands_played)
   - O(1) first_shop detection (check last_display_type)
   - Compute display_type and ordinal
   - Write `.jkr` + `.meta` files
   - Update cache, apply retention policy

### Save Loading
**See `CLICK_LOAD_FLOW.md`** for detailed diagram. Summary:
1. Click/hotkey → `load_and_start_from_file(file)`
2. Copy save to `save.jkr`, record `pending_future_prune`
3. Initialize `ordinal_state` from entry
4. `G:delete_run()` → `G:start_run({savetext=...})` (fast path, no loading screen)
5. `Game:start_run` marks loaded state, pre-sets shop CardAreas

---

## 7. Common Mistakes to Avoid

> [!CAUTION]
> **No loops in create_save** — Use `ordinal_state` for O(1) access, never scan `save_cache` for action detection or ordinal computation.

> [!IMPORTANT]
> **Ordinal is per-blind, not per-ante** — Counters reset when `blind_key` changes. Each blind (Small/Big/Boss) has separate ordinal sequences.

> [!WARNING]
> **Restore resets ordinal_state** — Must re-initialize from entry's stored values (ante, blind_idx, discards_used, hands_played, display_type, ordinal for counter).

> [!NOTE]
> **TOML regex escaping** — Double-escape backslashes in `lovely.toml` patterns (e.g., `\\(` not `\(`).

---

## 8. Development

```bash
./scripts/sync_to_mods.sh           # One-time sync
./scripts/sync_to_mods.sh --watch   # Auto-sync on file changes
```

- **No build system**: Edit Lua files in-place, sync to game, restart Balatro
- **Logs**: Check `References/lovely/log/` for crash traces and patch diagnostics
- **Testing**: Launch Balatro with Steamodded/Lovely Loader, verify mod in mods list

---

## 9. When to Ask Humans

- Changes to entry structure, metadata layout, or signature format
- Altering deferred-execution or timeline-pruning logic
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

-- Convert blind_idx to key for sprite
local blind_key = REWINDER.SaveManager.index_to_blind_key(blind_idx)
local sprite = REWINDER.create_blind_sprite(blind_key)
```
