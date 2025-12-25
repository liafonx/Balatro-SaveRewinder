# Click-to-Load Flow Documentation

This document describes the complete flow when a user clicks on a save entry in the UI to load it.

## Overview

1. **UI Button Click** → Button callback triggered
2. **Cache Update** → Update current file flags immediately
3. **File Copy** → Copy save file directly to `save.jkr`
4. **State Setup** → Prepare restore state and skip flags
5. **Timeline Management** → Calculate which "future" saves to prune
6. **Game Restart** → Start game run from loaded save
7. **State Marking** → Mark loaded state for skip logic

## Detailed Flow

### Step 1: UI Button Click (`UI/ButtonCallbacks.lua`)

**Function**: `G.FUNCS.loader_save_restore(e)`

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
5. Call `LOADER.load_and_start_from_file(file)`

---

### Step 2: Load and Start (`SaveManager.lua`)

**Function**: `M.load_and_start_from_file(file, opts)`

**Actions**:
1. **Reset restore state flags**:
   ```lua
   M._loaded_mark_applied = nil
   M._loaded_meta = nil
   M._pending_skip_reason = "restore"  -- or "step" if skip_restore_identical
   M._restore_active = true
   M._last_loaded_file = file
   M.skip_next_save = true
   ```
2. **Update cache flags**: `_set_cache_current_file(file)`
3. Log: `"Loading <description>"`
4. Call `start_from_file(file, opts)` (local function)

---

### Step 3: Start From File (`SaveManager.lua`)

**Function**: `start_from_file(file, opts)` (local function)

**Actions**:
1. **Calculate timeline index**:
   - Find entry index in save list by matching `file`
   - Store as `idx_from_list`
2. **Calculate future saves to prune**:
   ```lua
   M.pending_future_prune = {}
   -- If loading save at index 5, saves 1-4 are "future" and will be pruned
   -- on next real save (deferred pruning strategy)
   for i = 1, idx_from_list - 1 do
      table.insert(M.pending_future_prune, entries[i][ENTRY_FILE])
   end
   ```
3. **Set current index**: `M.current_index = pending_index or idx_from_list or 1`
4. **Close saves UI**: `LOADER.saves_open = false`
5. **Copy save file directly** (fast path):
   ```lua
   M.copy_save_to_main(file)  -- Copies file directly to save.jkr, no decode
   ```
6. **Load run data from save.jkr**:
   ```lua
   run_data = get_compressed(profile .. "/save.jkr")  -- Read what was just copied
   run_data._file = file  -- Link to source save file
   ```
7. **Set up game state**:
   ```lua
   G.SAVED_GAME = run_data
   G.SETTINGS.current_setup = "Continue"
   G.SAVED_GAME._file = file  -- Preserve file reference
   ```
8. **Start the run** (two paths):
   - **Fast path** (`no_wipe = true`): `G:delete_run()` → `G:start_run({ savetext = ... })`
   - **Normal path**: `G.FUNCS.start_run(nil, { savetext = ... })`

---

### Step 4: Game Start Run Hook (`GamePatches.lua`)

**Function**: `Game:start_run(args)` (patched version)

**Actions**:
1. **Match save file** (if `_file` not set):
   - Try to find matching save by signature comparison
   - Load metadata on-demand if not cached
   - Set `args.savetext._file` if match found
   - Fallback: use newest save if no signature match
2. **Mark loaded state** (if not already marked):
   ```lua
   LOADER.mark_loaded_state(args.savetext, {
      reason = "restore",  -- or "continue" or "step"
      last_loaded_file = args.savetext._file,
      set_skip = true,
   })
   ```
3. **Handle shop card areas** (deferred loading):
   - Extract `shop_jokers`, `shop_booster`, `shop_vouchers`, `pack_cards` from `cardAreas`
   - Store in `self.load_*` temporary variables
   - Remove from `cardAreas` to prevent conflicts during restore
4. **Call original `start_run`**: `LOADER._start_run(self, args)`
5. **Rebuild pack cards** (if `load_pack_cards` exists):
   - Create `CardArea` and load cards
   - Handles "opening pack" state restoration

---

### Step 5: Mark Loaded State (`SaveManager.lua`)

**Function**: `M.mark_loaded_state(run_data, opts)`

**Actions**:
1. **Store skip reason**: `M._pending_skip_reason = "restore"`
2. **Get signature**: `M._loaded_meta = StateSignature.get_signature(run_data)`
   - Includes: ante, round, state, action_type, money, is_opening_pack
3. **Set skip flag** (with shop exception):
   ```lua
   local is_shop = (loaded_sig.state == G.STATES.SHOP)
   local is_opening_pack = loaded_sig.is_opening_pack
   if is_shop and not is_opening_pack then
      M.skip_next_save = false  -- Don't skip! User action will trigger save
   else
      M.skip_next_save = true   -- Skip duplicate save
   end
   ```
4. **Mark as applied**: `M._loaded_mark_applied = true`

---

### Step 6: Next Save (Skip Logic)

**Function**: `M.consume_skip_on_save(save_table)` (called during next `create_save`)

**Actions**:
1. **Compare signatures**: 
   - `incoming_sig` (from `_loaded_meta`) vs `current_sig` (from current save)
   - If equal → skip save (duplicate)
2. **Shop pack open special case**:
   - If shop with `is_opening_pack` and `pack_cards` exists → skip
3. **Set skip flag**: `save_table.LOADER_SKIP_SAVE = true` if should skip
4. **Reset flags** (but preserve `_last_loaded_file` for UI)

---

## Key State Variables

### During Load Flow

| Variable | Set In | Purpose |
|----------|--------|---------|
| `_last_loaded_file` | `load_and_start_from_file` | Tracks current save file for UI highlighting |
| `pending_index` | `loader_save_restore` | Save index for timeline consistency |
| `pending_future_prune` | `start_from_file` | List of "future" saves to delete on next save |
| `skip_next_save` | `load_and_start_from_file` | Flag to skip duplicate save |
| `_loaded_meta` | `mark_loaded_state` | Signature of loaded state for comparison |
| `_loaded_mark_applied` | `mark_loaded_state` | Prevents double-marking |

### Cache Updates

- `entry[ENTRY_IS_CURRENT] = true` for loaded save
- `entry[ENTRY_IS_CURRENT] = false` for all other saves
- Updated immediately on click (before loading) for instant UI feedback

---

## Timeline Pruning Strategy

**Deferred Pruning**: Future saves are not deleted immediately when loading an older save.

**Why?**
- Allows user to "undo" a revert by stepping forward again
- Non-destructive operation
- Pruning happens on next real save (when timeline diverges)

**How it works**:
1. When loading save at index `N`, saves at indices `1` to `N-1` are "future"
2. These are added to `pending_future_prune` list
3. On next `create_save()`, `prune_future_saves()` is called
4. Future saves are deleted from disk and removed from cache

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

---

## Sequence Diagram

```
User Click
    ↓
loader_save_restore (ButtonCallbacks)
    ↓ update cache flags, set pending_index
load_and_start_from_file (SaveManager)
    ↓ reset state, log
start_from_file (local)
    ↓ calculate prune list
    ↓ copy_save_to_main (direct file copy)
    ↓ load run_data from save.jkr
Game:start_run (patched)
    ↓ match save file if needed
    ↓ mark_loaded_state
    ↓ handle shop card areas
Game:start_run (original)
    ↓
Game Running (from save state)
    ↓
Next save triggered
    ↓
consume_skip_on_save
    ↓ compare signatures, skip if duplicate
prune_future_saves (if needed)
    ↓
Timeline cleaned up
```
