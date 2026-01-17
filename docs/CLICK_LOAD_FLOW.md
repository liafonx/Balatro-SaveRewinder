# Click-to-Load Flow Documentation

This document describes the complete flow when a user clicks on a save entry in the UI to load it.

## Overview (Optimized)

1. **UI Button Click** → Button callback triggered
2. **Load and Start** → Single function handles: state setup, signature pre-compute, prune boundary, file copy, game restart
3. **Game Start Run Hook** → Handle shop card areas (signature marking skipped - already done)
4. **Next Save** → Skip logic compares pre-computed signatures

## Detailed Flow

### Step 1: UI Button Click (`UI/ButtonCallbacks.lua`)

**Function**: `G.FUNCS.rewinder_save_restore(e)`

```lua
-- User clicks on a save entry
-- Button has ref_table = { file = "2-3-1609430.jkr" }
```

**Actions**:
1. Extract `file` from `e.config.ref_table.file`
2. **Immediately update cache flags** via `_set_cache_current_file(file)` 
   - Ensures UI highlighting works if user reopens saves menu
   - Sets `entry[ENTRY_IS_CURRENT] = true` for clicked file in cache
3. Find entry index in save list and set `pending_index`
   - Used for timeline stepping consistency
4. Log: `"restore -> loading <description>"`
5. Call `REWINDER.load_and_start_from_file(file)`

---

### Step 2: Load and Start (`SaveManager.lua`)

**Function**: `M.load_and_start_from_file(file, opts)`

This is now a **single unified function** that handles all load logic (previously split across multiple functions).

**Actions**:
1. **Get entry and cache**: `M.get_save_files()`, lookup entry by file
2. **Store loaded fields** (O(1) - for direct comparison in skip logic):
   ```lua
   M._loaded_mark_applied = true  -- Pre-marked here
   M._loaded_ante = entry[E.ENTRY_ANTE]
   M._loaded_round = entry[E.ENTRY_ROUND]
   M._loaded_money = entry[E.ENTRY_MONEY]
   -- ... other fields for direct comparison
   M._loaded_display_type = entry[E.ENTRY_DISPLAY_TYPE]
   ```
3. **Set prune boundary** (O(1) instead of O(N) list building):
   ```lua
   -- Instead of building a list of files, store just the timestamp boundary
   M.pending_future_prune_boundary = entry[E.ENTRY_INDEX]
   -- During prune: delete all entries where INDEX > boundary
   ```
4. **Initialize ordinal_state** from loaded entry (includes ante, blind_key, round for per-round ordinals)
5. **Copy save file**: `M.copy_save_to_main(file)` — copies raw bytes to `save.jkr`
6. **Let game read save.jkr** (uses same code path as normal "Continue"):
   ```lua
   G.SAVED_GAME = nil  -- Clear stale cache
   local data = get_compressed(profile .. "/save.jkr")  -- Game's built-in
   local run_data = STR_UNPACK(data)                    -- Game's built-in
   ```
7. **Start the run**:
   - **Fast path** (`no_wipe = true`): `G:delete_run()` → `G:start_run({ savetext = ... })`
   - **Normal path**: `G.FUNCS.start_run(nil, { savetext = ... })`

---

### Step 3: Game Start Run Hook (`GamePatches.lua`)

**Function**: `Game:start_run(args)` (patched version)

**Actions**:
1. **Match save file** (if `_file` not set, for "Continue" from main menu):
   - **Primary**: O(1) lookup by `_rewinder_id` field in save.jkr (exact match)
   - **Fallback**: Field comparison (ante, round, money, discards, hands, display_type) for legacy saves
   - **Final fallback**: Use newest save if no match
2. **Mark loaded state** (SKIPPED if `_loaded_mark_applied == true`):
   - When loading via `load_and_start_from_file`, signature is pre-computed
   - Only called for "Continue" from main menu (not through our UI)
3. **Handle shop card areas** (deferred loading):
   - Extract `shop_jokers`, `shop_booster`, `shop_vouchers`, `pack_cards` from `cardAreas`
   - Store in `self.load_*` temporary variables
   - Remove from `cardAreas` to prevent conflicts during restore
4. **Call original `start_run`**: `REWINDER._start_run(self, args)`
5. **Rebuild pack cards** (if `load_pack_cards` exists)

---

### Step 4: Next Save (Skip Logic)

**Function**: `M.consume_skip_on_save(save_table)` (called during next `create_save`)

**Actions**:
1. **Compute current state**:
   - `state_info = StateSignature.get_state_info(save_table)`
   - `display_type = _compute_display_type(state_info)` using ordinal_state
2. **Direct field comparison** (O(1) - no signature string formatting):
   - Compare: ante, round, money, discards_used, hands_played, display_type
   - If all match → skip save (duplicate)
3. **Shop pack open special case**:
   - If `_loaded_display_type == "O"` and `pack_cards` exists → skip
4. **Set skip flag**: `save_table.REWINDER_SKIP_SAVE = true` if should skip
5. **Reset flags** (but preserve `_last_loaded_file` for UI)

---

## Key State Variables

### During Load Flow

| Variable | Set In | Purpose |
|----------|--------|---------|
| `_last_loaded_file` | `load_and_start_from_file` | Tracks current save file for UI highlighting |
| `pending_index` | `rewinder_save_restore` | Save index for timeline consistency |
| `pending_future_prune_boundary` | `load_and_start_from_file` | Timestamp boundary for future prune (O(1) storage) |
| `skip_next_save` | `load_and_start_from_file` | Flag to skip duplicate save |
| `_loaded_ante/round/money/...` | `load_and_start_from_file` | Individual fields for O(1) comparison (no signature string) |
| `_loaded_display_type` | `load_and_start_from_file` | Display type of loaded state |
| `_loaded_mark_applied` | `load_and_start_from_file` | Pre-set to true (skips redundant marking) |

### Cache Updates

- **O(1) via change detection**: Only updates when `_last_loaded_file` changes
- `old_entry[ENTRY_IS_CURRENT] = false` (via hash lookup)
- `new_entry[ENTRY_IS_CURRENT] = true` (via hash lookup)

---

## Timeline Pruning Strategy

**Deferred Pruning**: Future saves are not deleted immediately when loading an older save.

**Why?**
- Allows user to "undo" a revert by stepping forward again
- Non-destructive operation
- Pruning happens on next real save (when timeline diverges)

**How it works** (optimized with timestamp boundary):
1. When loading save, store its `ENTRY_INDEX` (timestamp) as `pending_future_prune_boundary`
2. This is **O(1)** instead of building a list of file names
3. On next `create_save()`, `prune_future_saves()` deletes all entries where `INDEX > boundary`
4. Since entries are sorted newest-first, this is a single-pass from the start of the list

---

## Error Handling

- **File not found**: `load_save_file` returns `nil`, error logged, function returns early
- **Copy failure**: `copy_save_to_main` returns `false`, error logged
- **start_run failure**: `pcall` protects, error logged but game may be in inconsistent state
- **Cache updates**: Always use `pcall` for filesystem operations to prevent crashes

---

## Performance Considerations

1. **Immediate cache update**: UI highlighting works instantly, even before file loads
2. **Direct file copy**: `copy_save_to_main` copies binary file without decode/encode cycle
3. **Fast restart path**: `no_wipe` option uses `G:delete_run()` → `G:start_run()` for faster restore
4. **Deferred pruning**: Timeline cleanup happens on next save, not during load
5. **O(1) prune setup**: Timestamp boundary instead of O(N) file list building
6. **Pre-computed signature**: Eliminates redundant `mark_loaded_state` call in game hook
7. **Unified load function**: Reduced function call overhead by inlining `start_from_file`
8. **Game-native load**: Uses `get_compressed` + `STR_UNPACK` directly from `save.jkr` (same as "Continue")

---

## Sequence Diagram

```
User Click
    ↓
rewinder_save_restore (ButtonCallbacks)
    ↓ update cache flags, set pending_index
load_and_start_from_file (SaveManager) — unified function
    ↓ store loaded fields (O(1))
    ↓ set prune boundary (O(1), no list building)
    ↓ initialize ordinal_state
    ↓ copy_save_to_main (direct file copy)
    ↓ load run_data
Game:start_run (patched)
    ↓ mark_loaded_state SKIPPED (already pre-computed)
    ↓ handle shop card areas
Game:start_run (original)
    ↓
Game Running (from save state)
    ↓
Next save triggered
    ↓
consume_skip_on_save
    ↓ direct field comparison (no string formatting)
prune_future_saves (if boundary set)
    ↓ single-pass delete using timestamp boundary
Timeline cleaned up
```
