# Click-to-Load Flow Documentation

This document describes the complete flow when a user clicks on a save entry in the UI to load it.

## Overview

When a user clicks on a save entry in the saves UI, the following sequence occurs:

1. **UI Button Click** → Button callback triggered
2. **Cache Update** → Update current file flags immediately
3. **File Loading** → Load save file from disk
4. **State Setup** → Prepare restore state and skip flags
5. **Timeline Management** → Calculate which "future" saves to prune
6. **Game Restart** → Sync to main save and restart game run
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
   - This ensures UI highlighting works if user reopens saves menu
   - Sets `entry.is_current = true` for clicked file in cache
3. Find entry index in save list and set `pending_index = i`
   - Used for timeline stepping consistency
4. Log: `"restore -> loading <description>"`
5. Call `LOADER.load_and_start_from_file(file)`

---

### Step 2: Load Save File (`SaveManager.lua`)

**Function**: `M.load_and_start_from_file(file, opts)`

**Actions**:
1. **Load file from disk**: `M.load_save_file(file)`
   - Decompress and unpack `.jkr` file
   - Returns `run_data` table
2. **Set file reference**: `run_data._file = file`
   - Critical: This links the loaded data to the save file
3. **Reset restore state flags**:
   ```lua
   M._pending_skip_reason = "restore"  -- or "step" if skip_restore_identical
   M._restore_active = true
   M._last_loaded_file = file
   M.skip_next_save = true  -- Will be checked on next save
   ```
4. **Update cache flags again** (redundant but safe): `_set_cache_current_file(file)`
5. Log: `"Loading <description>"`
6. Call `start_from_run_data(run_data)`

---

### Step 3: Prepare Run Data (`SaveManager.lua`)

**Function**: `start_from_run_data(run_data)` (local function)

**Actions**:
1. **Calculate timeline index**:
   - Find entry index in save list by matching `run_data._file`
   - Store as `idx_from_list`
2. **Calculate future saves to prune**:
   ```lua
   M.pending_future_prune = {}
   -- If loading save at index 5, saves 1-4 are "future" and will be pruned
   -- on next real save (deferred pruning strategy)
   ```
3. **Set current index**: `M.current_index = pending_index or idx_from_list or 1`
4. **Close saves UI**: `LOADER.saves_open = false`
5. **Set up game state**:
   ```lua
   G.SAVED_GAME = run_data
   G.SETTINGS.current_setup = "Continue"
   G.SAVED_GAME._file = run_data._file  -- Preserve file reference
   ```
6. **Sync to main save**: `M.sync_to_main_save(run_data)`
   - Serialize, compress, and write to `PROFILE/save.jkr`
   - This ensures game's "Continue" button works
7. **Clear screen wipes**: Remove any existing `G.screenwipe` or `G.screenwipecard`
8. **Start the run**: `G.FUNCS.start_run(nil, { savetext = G.SAVED_GAME })`

---

### Step 4: Game Start Run Hook (`GamePatches.lua`)

**Function**: `Game:start_run(args)` (patched version)

**Actions**:
1. **Match save file** (if `_file` not set):
   - Try to find matching save by signature comparison
   - Set `args.savetext._file` if match found
   - Update cache flags
2. **Mark loaded state** (if not already marked):
   ```lua
   LOADER.mark_loaded_state(args.savetext, {
      reason = "restore",  -- or "continue" or "step"
      last_loaded_file = args.savetext._file,
      set_skip = true,
   })
   ```
   - This records the signature and ACTION state for skip logic
3. **Handle shop card areas** (deferred loading):
   - Extract `shop_jokers`, `shop_booster`, `shop_vouchers`, `pack_cards` from `cardAreas`
   - Store in `self.load_*` temporary variables
   - Remove from `cardAreas` to prevent conflicts during restore
4. **Preserve `_last_loaded_file`**:
   - Ensures UI highlighting continues to work
   - Only reset on brand new run (no `savetext`)
5. **Call original `start_run`**: `LOADER._start_run(self, args)`
   - Game's original function handles actual run initialization
6. **Rebuild pack cards** (if `load_pack_cards` exists):
   - Create `CardArea` and load cards
   - This handles the "opening pack" state restoration

---

### Step 5: Mark Loaded State (`SaveManager.lua`)

**Function**: `M.mark_loaded_state(run_data, opts)`

**Actions**:
1. **Store skip reason**: `M._pending_skip_reason = "restore"`
2. **Get signature**: `M._loaded_meta = StateSignature.get_signature(run_data)`
   - Includes: ante, round, state, label, money, has_action
3. **Check ACTION**: `M._loaded_had_action = StateSignature.has_action(run_data)`
4. **Set skip flag** (with shop exception):
   ```lua
   if is_shop and not _loaded_had_action then
      M.skip_next_save = false  -- Don't skip! User action will trigger save
   else
      M.skip_next_save = true   -- Skip duplicate save
   end
   ```
5. **Mark as applied**: `M._loaded_mark_applied = true`

---

### Step 6: Next Save (Skip Logic)

**Function**: `M.consume_skip_on_save(save_table)` (called during next `create_save`)

**Actions**:
1. **Compare signatures**: 
   - `incoming_sig` (from loaded state) vs `current_sig` (from current save)
   - If equal → skip save (duplicate)
2. **Shop pack open special case**:
   - If shop with ACTION and `pack_cards` exists → skip (pack opening save)
3. **Set skip flag**: `save_table.LOADER_SKIP_SAVE = true` if should skip
4. **Reset flags** (but preserve `_last_loaded_file` for UI)

---

## Key State Variables

### During Load Flow

| Variable | Set In | Purpose |
|----------|--------|---------|
| `_last_loaded_file` | `load_and_start_from_file` | Tracks current save file for UI highlighting |
| `pending_index` | `loader_save_restore` | Save index for timeline consistency |
| `pending_future_prune` | `start_from_run_data` | List of "future" saves to delete on next save |
| `skip_next_save` | `load_and_start_from_file` | Flag to skip duplicate save |
| `_loaded_meta` | `mark_loaded_state` | Signature of loaded state for comparison |
| `_loaded_had_action` | `mark_loaded_state` | Whether loaded state had ACTION |
| `_loaded_mark_applied` | `mark_loaded_state` | Prevents double-marking |

### Cache Updates

- `entry.is_current = true` for loaded save
- `entry.is_current = false` for all other saves
- Updated immediately on click (before loading) for instant UI feedback

---

## Timeline Pruning Strategy

**Deferred Pruning**: Future saves are not deleted immediately when loading an older save.

**Why?**
- Allows user to "undo" a revert by reloading the game
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
- **Unpack failure**: `pcall` protects, error logged
- **start_run failure**: `pcall` protects, error logged but game may be in inconsistent state
- **Cache updates**: Always use `pcall` for filesystem operations to prevent crashes

---

## Performance Considerations

1. **Immediate cache update**: UI highlighting works instantly, even before file loads
2. **Deferred file operations**: File loading happens synchronously but is fast (already in memory cache)
3. **Deferred pruning**: Timeline cleanup happens on next save, not during load (faster restore)

---

## Sequence Diagram (Simplified)

```
User Click
    ↓
loader_save_restore
    ↓ (update cache flags)
load_and_start_from_file
    ↓ (load file, set state)
start_from_run_data
    ↓ (calculate prune list, sync save)
Game:start_run (patched)
    ↓ (mark state, handle shop areas)
Game:start_run (original)
    ↓
Game Running (from save state)
    ↓
Next save triggered
    ↓
consume_skip_on_save
    ↓ (compare signatures, skip if duplicate)
prune_future_saves (if needed)
    ↓
Timeline cleaned up
```

