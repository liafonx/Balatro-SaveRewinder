# Key Saves Feature — Agent Execution Prompt

## Task

Implement the "Key Saves" feature for the Save Rewinder Balatro mod according to the plan in `docs/PLAN_KEY_SAVES.md` (v3b).

## Before Writing Any Code

1. Read `docs/AGENT.md` — project conventions, module structure, logging, common mistakes
2. Read `docs/PLAN_KEY_SAVES.md` — the full implementation plan (this is your spec)
3. Read `docs/CACHE_ENTRY_EXAMPLE.md` — current entry structure (you're adding field 13)
4. Read every source file you will modify before changing it:
   - `Core/SaveManager.lua` — entry constants, `_apply_meta_to_entry`, `_clear_entry_meta`, public API surface
   - `Utils/MetaFile.lua` — `NUMERIC_FIELDS`, `read_meta_file`, `write_meta_file`
   - `Utils/Pruning.lua` — `apply_retention_policy` compaction loop and its `entry_constants` parameter
   - `UI/RewinderUI.lua` — `build_save_node`, `get_saves_page`, `G.UIDEF.rewinder_saves`, bottom bar buttons
   - `UI/ButtonCallbacks.lua` — `rewinder_save_close`, wrapped `exit_overlay_menu`, `rewinder_save_restore`, `rewinder_save_jump_to_current`, `_navigate_page`, `rewinder_save_update_page`, `_snap_saves_focus_to_current`
   - `Utils/Keybinds.lua` — all `rewinder_btn_current` and `rewinder_btn_delete` references in `navigate_focus`, and `snap_to_current_save_entry`
   - `Core/Init.lua` — REWINDER namespace exports
   - `lovely.toml` — existing module patches (pattern for adding KeySaves)
   - `localization/en-us.lua` and `localization/zh_CN.lua`
   - `main.lua` — confirm "Delete all saves" button exists in config tab

## Implementation Order (follow exactly)

### Step 1: Data Layer — SaveManager Constants
- Add `"IS_KEY"` to `ENTRY_KEYS` array (field 13)
- Add `local ENTRY_IS_KEY = 13` constant
- Add to `_apply_meta_to_entry`: `entry[E.ENTRY_IS_KEY] = meta.is_key or false`
- Add to `_clear_entry_meta`: `entry[E.ENTRY_IS_KEY] = nil`

### Step 2: SaveManager Public API
- Add `M.get_entry_with_meta(file)` — returns entry from `save_cache_by_file[file]`, ensuring meta is loaded (call `get_save_meta` if `ENTRY_IS_KEY` is nil)
- Add `M.update_entry_is_key(file, is_key)` — updates `entry[ENTRY_IS_KEY]` in cache + updates `meta_cache` if present
- Export `ENTRY_IS_KEY` constant same way other `ENTRY_*` are exported

### Step 3: MetaFile
- In `read_meta_file`: do NOT add `is_key` to `NUMERIC_FIELDS`. After the parse loop, add: `meta.is_key = (tonumber(meta.is_key) == 1)`. This is the single normalization point.
- In `write_meta_file`: append `is_key=1` line only when `entry_meta.is_key == true`

### Step 4: Create `Core/KeySaves.lua`
- Copy the API code from `docs/PLAN_KEY_SAVES.md` section 2.1
- Add logger: `local Logger = require("Logger")` and `local debug_log = Logger.create("KeySaves")`
- Log failures in `commit_pending` at `"warning"` level

### Step 5: lovely.toml
- Add a `[patches.module]` entry for KeySaves, following the pattern of existing module patches

### Step 6: Init.lua
- Export KeySaves API to REWINDER namespace: `REWINDER.KeySaves = require("KeySaves")`
- Export individual functions if other modules use them directly

### Step 7: Pruning Guard
- In `Pruning.apply_retention_policy`: read `ENTRY_IS_KEY` from `entry_constants` parameter
- In the compaction loop, before deleting an entry, check `if ENTRY_IS_KEY and e[ENTRY_IS_KEY] == true then keep`
- Do NOT change future pruning — key saves are pruned with timeline forks

### Step 8: UI Styling — `build_save_node`
- Add teal color constant: `local KEY_SAVE_COLOR = {0.2, 0.7, 0.7, 1}`
- In browse mode (`_mark_active == false`): key saves get teal background + ★ prefix. Current+Key = teal + triangle + ★. Current-only = orange + triangle.
- In mark mode (`_mark_active == true`): use `KeySaves.effective_is_key(entry)` for preview state. Button = `"rewinder_save_toggle_key"` instead of `"rewinder_save_restore"`
- Entries with pending changes should show a subtle visual distinction

### Step 9: UI Buttons — Bottom Bar
- Remove `rewinder_btn_current` ("Current save") button
- Remove `rewinder_btn_delete` ("Delete all") button
- Add `rewinder_btn_mark_keys` ("Mark keys ★") button
- Add `rewinder_btn_filter_keys` ("Key saves only") button
- Add `REWINDER._filter_active = false` and `REWINDER._mark_active = false` state
- Add `_get_displayed_entries()` helper per plan section 4.2

### Step 10: UI Callbacks
- `G.FUNCS.rewinder_save_toggle_key` — calls `KeySaves.toggle_pending(file)`, then repaints current page via `rewinder_save_update_page` (NOT `_refresh_saves_view`)
- `G.FUNCS.rewinder_btn_mark_keys` — toggles `_mark_active`. Off→on: change label to "Done marking". On→off: call `KeySaves.commit_pending()`, rebuild via `_refresh_saves_view(nil)`
- `G.FUNCS.rewinder_btn_filter_keys` — toggles `_filter_active`. Rebuild via `_refresh_saves_view(nil)` (row count changes)
- `_refresh_saves_view(target_page)` — recompute entries, total pages, clamp page, rebuild cycle options, call `rewinder_save_update_page`
- Page label click (Option A): post-process `create_option_cycle` middle child. If structure doesn't match, fall back to a standard button.
- Make `rewinder_save_jump_to_current` filter-aware using `_key_save_reverse_map`
- Replace ALL `REWINDER.get_save_files()` calls in pagination/jump/update callbacks with `_get_displayed_entries()`

### Step 11: Close-Path Reset
- In `rewinder_save_close`: if `_mark_active`, call `KeySaves.discard_pending()`. Reset `_filter_active = false`, `_mark_active = false`
- In the wrapped `exit_overlay_menu` close path: same discard + reset

### Step 12: Controller Navigation
- Replace all 6 hardcoded button IDs in `Keybinds.lua` `navigate_focus` (see plan section 5.1 for exact lines)
- Make `snap_to_current_save_entry` filter-aware: use `_key_save_reverse_map` to translate full-list index to filtered index when `_filter_active`

### Step 13: Localization
- Add to `en-us.lua`: `rewinder_mark_keys`, `rewinder_mark_keys_active`, `rewinder_filter_keys`, `rewinder_filter_keys_active`, `rewinder_no_key_saves`
- Add to `zh_CN.lua`: same keys with Chinese translations from plan section 10

### Step 14: Documentation
- Update `docs/AGENT.md`: add KeySaves module to file structure table, update dependency graph, update entry structure description to 13 fields, add KeySaves to module dependency graph
- Update `docs/CACHE_ENTRY_EXAMPLE.md`: add field 13 (`IS_KEY`) to entry array, add `is_key=1` to .meta format example

## Critical Constraints

1. **Lua truthiness**: `0` is truthy in Lua. `is_key` normalization (`tonumber(v) == 1`) happens ONLY in `MetaFile.read_meta_file`. Everywhere else uses plain boolean checks.

2. **No loops in create_save**: Do not add any key-save logic to `create_save()`. Key saves are user-interaction only.

3. **Forward declarations**: If you add local functions in SaveManager that are called before their definition, forward-declare them.

4. **Module access**: `require("KeySaves")`, NOT as a global. Lovely modules are accessed via `require()`.

5. **Logger pattern**: Use `Logger.create("KeySaves")` for the new module. Use levels: `"warning"` for failures, `"info"` for commits, `"debug"` for pending state changes.

6. **Cache ordering**: `get_save_files()` returns newest-first. Internal `save_cache` is oldest-first. Index maps reference newest-first positions.

7. **Meta cache is lazy**: Entries may have `ENTRY_IS_KEY == nil` if meta was evicted. The `get_key_saves()` filter must call `get_save_meta` for nil entries to avoid false negatives.

8. **Batched marking**: Mark mode toggles are in-memory only (`_pending` table). Disk writes happen ONLY on "Done marking" via `commit_pending()`. Close without Done = `discard_pending()`.

9. **Two independent toggles**: `_filter_active` and `_mark_active` are independent booleans, not exclusive modes. Both can be true simultaneously.

10. **`_refresh_saves_view` vs `rewinder_save_update_page`**: Use `_refresh_saves_view` only when row count may change (filter toggle, Done commit). Use `rewinder_save_update_page` for styling-only changes (mark toggle on individual entry).

11. **UI node IDs in filter mode**: `build_save_node` uses position within the displayed list for node IDs. In filter mode, these are filtered positions (1..#filtered_page), not full-list positions.

12. **Both close paths**: The overlay has TWO close paths — `rewinder_save_close` AND the wrapped `exit_overlay_menu`. BOTH must discard pending + reset toggles.

## What NOT to Do

- Do not add features beyond the plan
- Do not refactor existing code unless the plan requires it
- Do not add comments to code you didn't change
- Do not add type annotations or docstrings beyond what exists in the codebase
- Do not change `create_save` hot path
- Do not change `revert_to_previous_save` logic (step-back works on full list naturally)
- Do not add a cached/memoized filter view — recompute on each call per plan
- Do not protect key saves from future pruning (timeline forks)
