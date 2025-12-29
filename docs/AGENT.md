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
  
> **Note for CHANGELOG**: Development script improvements (like `sync_to_mods.sh` changes) are **not** user-facing features and should **not** be included in CHANGELOG.md. Only include changes that affect mod functionality, UI, or user experience.

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

---

## 7. Blind Information & Sprite Access (for UI Enhancement)

### Accessing Blind Data

**Key Globals:**
- `G.GAME.round_resets.blind_choices[type]` — Blind key for each type ('Small', 'Big', 'Boss')
- `G.P_BLINDS[blind_key]` — Full blind configuration from globals
- `G.GAME.round_resets.blind_states[type]` — State: 'Select', 'Defeated', 'Skipped', 'Hide', 'Upcoming'

**Example from UnBlind mod:**
```lua
-- Get blind config for current ante
local blind_choice = {
    config = G.P_BLINDS[G.GAME.round_resets.blind_choices['Small']]
}

-- blind_choice.config contains:
--   .key     - "bl_small", "bl_big", "bl_final_acorn", etc.
--   .name    - Display name
--   .pos     - Position in sprite atlas
--   .atlas   - Atlas name (usually 'blind_chips')
--   .mult    - Score multiplier
--   .dollars - Reward amount
```

### Creating Blind Sprites

**AnimatedSprite creation:**
```lua
-- Full-size blind sprite (from UnBlind mod)
local blind_sprite = AnimatedSprite(
    0, 0,                                    -- x, y position
    0.75, 0.75,                              -- width, height
    G.ANIMATION_ATLAS['blind_chips'],        -- Atlas (or blind_choice.config.atlas)
    blind_choice.config.pos                  -- Position in atlas
)

-- Apply shaders for visual effects
blind_sprite:define_draw_steps({
    {shader = 'dissolve', shadow_height = 0.05},
    {shader = 'dissolve'}
})

-- Smaller sprites (for save list entries)
local small_blind = AnimatedSprite(
    0, 0, 
    0.5, 0.5,                                -- Smaller size for list
    G.ANIMATION_ATLAS['blind_chips'],
    blind_pos
)
```

### Determining Round Type from Save Data

**Round-to-Blind Mapping:**
- Round 1 (Small Blind) → `G.GAME.round_resets.blind_choices['Small']`
- Round 2 (Big Blind) → `G.GAME.round_resets.blind_choices['Big']`  
- Round 3 (Boss Blind) → `G.GAME.round_resets.blind_choices['Boss']`

**From run_data in save file:**
```lua
-- run_data structure (from .jkr file):
--   .round              - 1, 2, or 3
--   .round_resets.blind_choices
--       .Small  = 'bl_small'
--       .Big    = 'bl_big'
--       .Boss   = 'bl_final_acorn'

-- Map round number to blind type
local blind_type = (round == 1 and 'Small') or (round == 2 and 'Big') or 'Boss'
local blind_key = run_data.round_resets.blind_choices[blind_type]
local blind_config = G.P_BLINDS[blind_key]

-- Create sprite for that blind
local blind_sprite = AnimatedSprite(0, 0, 0.4, 0.4, 
    G.ANIMATION_ATLAS[blind_config.atlas or 'blind_chips'],
    blind_config.pos
)
```

### Integration with Save Rewinder

**Blind Image Feature - IMPLEMENTED ✅**

The mod now displays blind icons instead of/alongside round numbers in save list entries.

**Implementation Details:**

1. **State Signature (`Core/StateSignature.lua`)**:
   - Extracts `blind_key` from `game.blind_on_deck` (primary) or round number mapping (fallback)
   - Special case: Round 0 (blind selection) forced to Small blind
   - Returns signature with `blind_key` field (e.g., `"bl_small"`, `"bl_final_acorn"`)

2. **Save Creation (`Core/SaveManager.lua`)**:
   - Stores `blind_key` in cache entry at `ENTRY_BLIND_KEY` (index 14)
   - Writes `blind_key` to `.meta` file for fast loading
   - Exports `ENTRY_BLIND_KEY` constant

3. **UI Rendering (`UI/RewinderUI.lua`)**:
   - `create_blind_sprite(blind_key, width, height)`:
     - Creates `AnimatedSprite` with `'blind_chips'` atlas
     - Applies dissolve shader with shadow (`shadow_height=0.05`, `shadow_parrallax={x=1.5, y=-1.5}`)
     - Animation control via `config.animate_blind_image`:
       - When enabled: Full animation frames + hover sound effect (using `focus_with_object`)
       - When disabled: Static single frame (`sprite.animation.frames = 1`)
     - Size: 0.45x0.45 for compact display
   - `build_save_node()`:
     - Checks `config.show_blind_image` to show blind sprite or round number
     - For round number mode: displays neutral text color, only separator is colored
     - Sets `chosen='vert'` on current save entry (triggers animated red triangle indicator)

4. **Configuration (`config.lua` + `main.lua`)**:
   - `show_blind_image = true` — Toggle blind icons vs round numbers
   - `animate_blind_image = false` — Control sprite animation and hover effects (default: static)
   - Steamodded UI toggles with bilingual localization (EN/ZH)
   - Config UI organized into columns: "Auto-Save Triggers" (left), "Display Options" (right), "Advanced" (bottom)

**Reference:**
- Blind sprite creation borrowed from `UnBlind/UI_Def append.lua`
- Shadow positioning: `shadow_parrallax = {x = 1.5, y = -1.5}` creates lower-right shadow like UnBlind
- Hover sound effect pattern from `UnBlind` using `focus_with_object` for collision detection
- Animation control: `sprite.animation.frames = 1` stops frame cycling

---

## 8. Reference Mods (balatro_src/ Neighbors)

### UnBlind/
Boss blind preview mod. Key patterns borrowed:
- **Blind sprite creation**: `AnimatedSprite` with `G.ANIMATION_ATLAS['blind_chips']`
- **Shader setup**: `define_draw_steps` with `dissolve` shader for shadow effects
- **Shadow positioning**: `shadow_parrallax = {x, y}` for dynamic shadow offset
- **Hover effects**: `focus_with_object = true` enables collision detection for hover callbacks
- **Key files**: `UI_Def append.lua`, `unBlindShopGUI.lua`

### BetterMouseandGamepad/
Controller and mouse navigation improvements. Key patterns:
- **Focus management**: Controller navigation through UI elements
- **L3/R3 mapping**: Gamepad stick clicks for quick actions
- **Key file**: `BetterMouseAndGamepad.lua`

### Brainstorm-Rerolled/
Joker reroll mod with fast game restart. Key patterns:
- **Fast restore path**: `G:delete_run()` → `G:start_run({savetext=...})` without loading screen
- **Key files**: `Core/*.lua`

### QuickLoad/
Fast save loading mod. Key patterns:
- **Save unpacking**: `get_compressed()` + `STR_UNPACK()` for `.jkr` file reading
- **Key file**: `QuickLoad.lua`

### JokerDisplay/
Joker info display mod with well-organized config UI. Key patterns:
- **Config tab layout**: Two-column organization with section headers
- **UI structure**: `G.UIT.C` for columns, `G.UIT.T` for headers, padding for separation
- **Key file**: `src/config_tab.lua`

---

## 9. Logger System

### Architecture

The logging system uses a module-based approach for organized output:

```lua
-- Create module-specific logger
local log = Logger.create("SaveManager")

-- Log with different tags
log.step("Creating save...")      -- Always shows (important operations)
log.list("Files: " .. count)      -- Always shows (list operations)
log.error("Failed: " .. msg)      -- Always shows (errors)
log.prune("Pruned " .. n)         -- Always shows (pruning)
log.restore("Restored: " .. f)    -- Always shows (restore operations)
log.info("Details...")            -- Only when debug_saves enabled
log.detail("Verbose...")          -- Only when debug_saves enabled
```

### Log Tags

| Tag | Visibility | Purpose |
|-----|------------|---------|
| `step` | Always | Major operation milestones |
| `list` | Always | File listing operations |
| `error` | Always | Error conditions |
| `prune` | Always | Save pruning operations |
| `restore` | Always | Save restore operations |
| `info` | Debug only | Verbose operational details |
| `detail` | Debug only | Extra verbose details |

### Debug Mode

Controlled by `config.debug_saves` toggle in mod settings (labeled "Debug: verbose logging"):
- **OFF (default)**: Only critical tags shown (`step`, `list`, `error`, `prune`, `restore`)
- **ON**: All tags shown including `info` and `detail`

---

## 10. Initialization Flow

### Blueprint Pattern (Immediate Init)

The mod uses immediate initialization at require-time (similar to Blueprint mod):

```lua
-- Core/Init.lua
if not REWINDER._initialized then
    REWINDER._initialized = true
    
    -- Load modules immediately (runs when file is required)
    REWINDER.SaveManager = require("SaveManager")
    -- etc.
    
    -- Cache initialization runs during game load, before Continue button
    SaveManager.initialize_cache()
end
```

**Benefits:**
- No lag spike when player clicks Continue
- Smoother UX as saves are pre-loaded during initial game loading
- Avoids lazy initialization patterns that cause visible delays

### Cache Initialization

`SaveManager.initialize_cache()`:
1. Lists all `.jkr` files in save directory
2. For each file, reads `.meta` or unpacks `.jkr` for metadata
3. Builds sorted cache array (newest first)
4. Runs once at mod load time

---

## 11. Config UI Layout

### Organization (JokerDisplay Pattern)

The Steamodded config tab uses a two-column layout:

```
┌─────────────────────────────────────────────────┐
│  Auto-Save Triggers       │  Display Options    │
├─────────────────────────────────────────────────┤
│  ☑ Save when choosing     │  ☑ Show blind image │
│     blind                 │  ☑ Blind image      │
│  ☑ Save when selecting    │     effects         │
│     hand                  │                     │
│  ☑ Save at end of round   │                     │
│  ☑ Save in shop           │                     │
├─────────────────────────────────────────────────┤
│                   Advanced                      │
├─────────────────────────────────────────────────┤
│       Max saved antes per run: [< 4 >]          │
│  ☐ Debug: verbose logging    [Delete all saves] │
└─────────────────────────────────────────────────┘
```

### UI Elements Used
- `G.UIT.ROOT` — Root container
- `G.UIT.R` — Row (horizontal grouping)
- `G.UIT.C` — Column (vertical grouping)
- `G.UIT.T` — Text (section headers)
- `create_toggle()` — Toggle switches
- `create_option_cycle()` — Dropdown/cycle selector
- `UIBox_button()` — Action buttons

---

## 12. Known Issues & Workarounds

### ✅ Fixed: Arrow Indicator Position
The vertical triangle arrow (`chosen='vert'`) positioning was resolved by adding left spacer padding to entry content:
```lua
-- Add spacer before content for arrow clearance
{ n = G.UIT.C, config = { minw = 0.15 } },
```

### ✅ Fixed: Shadow Position
Blind sprite shadows now appear at lower-right (matching UnBlind) using:
```lua
shadow_parrallax = { x = 1.5, y = -1.5 },
shadow_height = 0.05
```

### Note: Duplicate Logging
When extracting `blind_key` from save data, use `log.detail()` instead of `log.info()` to avoid verbose output during normal operation.
