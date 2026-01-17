# Press S (Step Back) Flow Documentation

This document describes the flow when a user presses `S` to step back to the previous save.

## Overview

```
User presses S
    ↓
Keybinds.lua (debounce check)
    ↓
revert_to_previous_save() — find previous entry, call load_and_start_from_file
    ↓
(Same flow as CLICK_LOAD_FLOW.md from Step 2 onwards)
```

## Detailed Flow

### Step 1: Keypress Handler (`Keybinds.lua`)

**Function**: `love.keypressed(key, scancode, isrepeat)`

```lua
if key == "s" and not ctrl_down and not isrepeat then
   if can_trigger_quick_revert() then
      revert_to_previous_save()
   end
end
```

**Guards**:
1. Must be in a run (`G.STAGE == G.STAGES.RUN`)
2. Not Ctrl+S (that toggles save window)
3. Not a repeat keypress
4. Debounce: 0.25s cooldown between presses

### Step 2: Find Previous Save (`SaveManager.lua`)

**Function**: `M.revert_to_previous_save()`

**Logic** (optimized):
```lua
-- 1. Use existing cache if available (skip full reload)
local entries = save_cache or M.get_save_files()

-- 2. Use current_index as primary source (always updated by load/save)
local current_idx = M.current_index or 0
if current_idx == 0 or current_idx > #entries then
   -- Fallback: try to find by file reference (rare case)
   local current_file = G.SAVED_GAME._file or M._last_loaded_file
   current_idx = M.get_index_by_file(current_file) or 0
end

-- 3. Target is index + 1 (older save), or index 1 if unknown
local target_idx = (current_idx == 0) and 1 or (current_idx + 1)
if target_idx > #entries then return end  -- Already at oldest

-- 4. Direct entry access (no lookup needed)
local target_entry = entries[target_idx]

-- 5. Load the target
M.load_and_start_from_file(target_entry[E.ENTRY_FILE], { 
   skip_restore_identical = true,  -- Don't skip first save after restore
   no_wipe = true                  -- Use fast path (G:delete_run → G:start_run)
})
```

### Step 3: Load and Start

**Same as CLICK_LOAD_FLOW.md Step 2** with these options:
- `skip_restore_identical = true` → Sets `reason = "step"` instead of `"restore"`
- `no_wipe = true` → Uses fast path: `G:delete_run()` → `G:start_run()`

## Key Differences from Click-to-Load

| Aspect | Press S | Click Restore |
|--------|---------|---------------|
| Target selection | Next older entry (index + 1) | Specific clicked entry |
| Skip reason | `"step"` | `"restore"` |
| Wipe behavior | `no_wipe = true` (fast) | `no_wipe` not set (normal) |
| `pending_index` | Not set | Set from UI |
| Debounce | 0.25s cooldown | None |

## Entry Index Navigation

```
Entries array (sorted newest-first):
┌─────┬─────┬─────┬─────┬─────┐
│  1  │  2  │  3  │  4  │  5  │  ← Index
│ New │     │     │     │ Old │  ← Age
└─────┴─────┴─────┴─────┴─────┘
         ←── Press S moves this way (to older saves)
         
Current at index 2 → Press S → Load index 3
Current at index 5 → Press S → No action (already oldest)
Current unknown    → Press S → Load index 1 (newest)
```

## Controller Support

**L3 (Left Stick Press)**: Same as pressing S
```lua
if button == "leftstick" and G.STAGE == G.STAGES.RUN and not G.SETTINGS.paused then
   if can_trigger_quick_revert() then
      revert_to_previous_save()
   end
end
```

## State Variables

| Variable | Purpose |
|----------|---------|
| `_last_quick_revert_time` | Debounce timestamp (0.25s cooldown) |
| `M.current_index` | **Primary** source for current position (always updated) |
| `M._last_loaded_file` | Fallback for current position |
| `G.SAVED_GAME._file` | Fallback for current position |
| `save_cache` | Cached entries array (avoids full reload) |

## Edge Cases

1. **No saves**: `entries` is empty → return early
2. **At oldest save**: `target_idx > #entries` → return early
3. **Unknown current position**: `current_idx == 0` → load index 1 (newest)
4. **Rapid presses**: Debounced to 0.25s minimum interval

## Sequence Diagram

```
User presses S
    ↓
love.keypressed (Keybinds.lua)
    ↓ check: is 's', not ctrl, not repeat, in RUN stage
    ↓ check: debounce (0.25s since last)
revert_to_previous_save (local wrapper)
    ↓
REWINDER.revert_to_previous_save (SaveManager.lua)
    ↓ use save_cache if exists (skip reload)
    ↓ use M.current_index directly (O(1), no lookup)
    ↓ target = current_index + 1
    ↓ bounds check
    ↓ direct entry access: entries[target_idx]
load_and_start_from_file(file, { skip_restore_identical=true, no_wipe=true })
    ↓
(Same as CLICK_LOAD_FLOW from Step 2)
    ↓
Game restarted at previous save
```

## Performance Notes

1. **Fast path enabled**: `no_wipe = true` uses `G:delete_run()` directly
2. **No UI overhead**: Skips save window open/close
3. **Debounced**: Prevents accidental rapid-fire reverts
4. **Cache reuse**: Uses existing `save_cache` if available (skips full reload)
5. **Direct index access**: Uses `M.current_index` directly (O(1), no hash lookup in common case)
6. **Fallback only when needed**: Index lookup via hash table only if `current_index` is invalid

