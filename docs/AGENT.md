# Save Rewinder - Project Documentation

> Architecture and design documentation for AI/LLM-assisted development.

---

## 1. Project Goals & Overview

**Save Rewinder** is a save/rewind mod for *Balatro*. Core objectives:

- Automatically create multiple saves during gameplay (sorted by Ante/Round timeline)
- Allow players to restore runs from any save point ("undo / step back")
- Provide save list UI and hotkeys
- Run transparently, compatible with popular mods (`Steamodded`, `debugplus`, etc.)

---

## 2. Project Structure

### 2.1 Core Scripts

#### Core/ - Core Modules

- **`Core/Init.lua`** — Mod entry point. Sets up `REWINDER` namespace, preloads save metadata at startup.

- **`Core/StateSignature.lua`** — State signature module for comparing game states.
  - `get_signature(run_data)`: Generates fingerprint from Ante, Round, State, Money, etc.
  - `encode_signature(sig)`: Encodes to string `"ante:round:state:action_type:money"` for fast comparison.
  - `signatures_equal(a, b)`: Compares two signatures.

- **`Core/SaveManager.lua`** — Core save management (create, load, list, prune).
  - Key state: `save_cache` (in-memory array), `pending_future_prune`, `_last_loaded_file`
  - `create_save(run_data)`: Creates save with duplicate/config filtering.
  - `load_and_start_from_file(file)`: Loads save, copies to `save.jkr`, restarts run.
  - `revert_to_previous_save()`: Steps back one save.
  - Filename format: `<ante>-<round>-<timestamp>.jkr`

- **`Core/GamePatches.lua`** — Game function patches.
  - `Game:start_run` override: Marks loaded state, handles shop CardArea pre-loading.
  - `REWINDER.defer_save_creation()`: Deep-copies `G.culled_table`, defers save to next frame.

#### Utils/ - Utilities

- **`Utils/Logger.lua`** — Centralized logging. `Logger.create(module_name)` returns module-specific logger.
- **`Utils/EntryConstants.lua`** — Cache entry array index constants (`ENTRY_FILE`, `ENTRY_ANTE`, etc.)
- **`Utils/MetaFile.lua`** — `.meta` file read/write for fast metadata caching.
- **`Utils/FileIO.lua`** — File I/O: `copy_save_to_main`, `load_save_file`, `get_save_dir`.
- **`Utils/ActionDetector.lua`** — Detects play/discard action type by comparing `discards_used`/`hands_played`.
- **`Utils/CacheManager.lua`** — Updates cache entry `is_current` flags.
- **`Utils/Pruning.lua`** — `apply_retention_policy` and `prune_future_saves`.
- **`Utils/DuplicateDetector.lua`** — Skips duplicate saves within short time windows.

#### UI/ - User Interface

- **`UI/RewinderUI.lua`** — Save list overlay. `G.UIDEF.rewinder_saves()`, pagination, entry highlighting.
- **`UI/ButtonCallbacks.lua`** — Button handlers: `rewinder_save_restore`, `rewinder_save_jump_to_current`, etc.

#### Root Files

- **`Keybinds.lua`** — Hotkeys: `S` (step back), `Ctrl+S` (toggle UI). Controller: `L3`/`R3`.
- **`main.lua`** — Steamodded config UI integration.
- **`config.lua`** — Default config values.
- **`lovely.toml`** — Lovely Loader patches: injects `REWINDER.defer_save_creation()` after `save_run`.

### 2.2 Module Dependencies

```
GamePatches → SaveManager → StateSignature, FileIO, MetaFile, ActionDetector, CacheManager, Pruning, DuplicateDetector
UI (RewinderUI, ButtonCallbacks) → SaveManager
Keybinds → SaveManager
```

### 2.3 Documentation

- `CACHE_ENTRY_EXAMPLE.md`: Cache entry array structure details.
- `CLICK_LOAD_FLOW.md`: Complete save loading flow diagram.

### 2.4 Development Scripts

- **`scripts/sync_to_mods.sh`** (gitignored): Syncs mod files to game Mods directory via `rsync`.
  ```bash
  ./scripts/sync_to_mods.sh           # One-time sync
  ./scripts/sync_to_mods.sh --watch   # Auto-sync on changes
  ```

### 2.5 Reference Directories (Not Part of Mod)

- **`balatro_src/`** — Unpacked vanilla Balatro source files, used for:
  - Viewing original function implementations (`save_run`, `start_run`, etc.)
  - Text reference for writing `lovely.toml` regex patterns.

- **`lovely/`** — Local Lovely Loader files (including `lovely/log/`). Useful for debugging patches and viewing crash info.

- **`Steamodded/`** — Steamodded Loader scripts and config, for reference.

- **`Balatro-History/`** — Another save history mod, referenced for backup and timeline logic.

- **`Brainstorm-Rerolled/`** — Borrowed its fast restore path (`G:delete_run()` → `G:start_run()`) for instant rewind without loading screen.

- **`QuickLoad/`** — Borrowed its `get_compressed + STR_UNPACK` flow for fast `save.jkr` unpacking.

- **`BetterMouseandGamepad/`** — Referenced for controller navigation and focus management.

---

## 3. Core Flows

### 3.1 Save Writing Flow

1. Game executes `save_run()` → constructs `G.culled_table`
2. `lovely.toml` patch calls `REWINDER.defer_save_creation()`
3. `GamePatches.defer_save_creation()`:
   - Deep-copies `G.culled_table`
   - Defers to **next frame** via `G.E_MANAGER` (breaks recursive call stack)
4. `SaveManager.create_save()` on next frame:
   - Checks skip conditions (duplicate, config filters)
   - Prunes future saves if pending
   - Writes `.jkr` + `.meta` files
   - Updates `save_cache`, applies retention policy

### 3.2 Save Loading Flow

1. UI or hotkey calls `load_and_start_from_file(file)`
2. Copies save to `save.jkr`, unpacks via `get_compressed + STR_UNPACK`
3. Records `pending_future_prune` (saves newer than loaded)
4. Updates cache flags
5. Calls `G:delete_run()` → `G:start_run({savetext=...})` (fast path, no loading screen)
6. `Game:start_run` marks loaded state, pre-sets `G.load_shop_*` for shop saves

### 3.3 Timeline Pruning

- **Deferred pruning**: Future saves aren't deleted immediately when loading older save.
- Recorded to `pending_future_prune`, deleted on next `create_save`.
- Allows "undo the undo" if game is restarted before new save.

### 3.4 Duplicate Skip Logic

- After restore, first auto-save often matches restored state → skip it.
- `mark_loaded_state()` records signature, `consume_skip_on_save()` compares.
- Special handling for Shop + Pack Open states.

---

## 4. Architecture Design

### Why Static Patch + Deferred Execution?

**Problem**: Runtime hook of `save_run` caused stack overflow due to recursive mod hook chains.

**Solution** (current):
1. `lovely.toml` statically injects call after `G.ARGS.save_run = G.culled_table`
2. `defer_save_creation()` schedules save to next frame via event manager
3. Breaks synchronous call stack, avoids recursion with other mod hooks

**Benefits**:
- No hook order conflicts
- No stack overflow from recursive hooks
- Better mod compatibility
- Centralized logic in `SaveManager.lua`

---

## 5. Key Behaviors (Must Maintain)

1. **Deferred Timeline Pruning** — Future saves only deleted on next save creation, not immediately on load.

2. **Skip Duplicate After Restore** — First auto-save after restore is skipped if signature matches.

3. **Shop Area Handling** — Pre-write `shop_*` to `G.load_shop_*` to suppress "Card area not instantiated" warnings.

4. **Fast Step-Back** — `S` key uses `G:delete_run()` → `G:start_run()` path (no loading screen).

5. **Pack Open Detection** — `Card:open()` patch sets `skipping_pack_open` flag to skip save during pack opening.

---

## 6. Key Source Locations in balatro_src

- `functions/misc_functions.lua` — `save_run()`, where we inject `defer_save_creation()`
- `functions/button_callbacks.lua` — `G.FUNCS.start_run`, wipe flow
- `game.lua` — `Game:start_run`, `Game:delete_run`, `Game:update_shop`
- `engine/string_packer.lua` — `get_compressed`, `STR_UNPACK`
- `engine/controller.lua` — `Controller:navigate_focus`
