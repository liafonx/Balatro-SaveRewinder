# Cache Entry Structure

This document shows what a cache entry looks like after all recent changes.

## Example Cache Entry

Cache entries are stored as **arrays** (not key-value tables) to reduce memory size. Access fields using index constants:

```lua
-- Array format: {file, ante, round, index, modtime, state, action_type, money, signature, discards_used, hands_played, is_current}
local entry = {
    "2-3-1609430.jkr",      -- [ENTRY_FILE] - Filename format: <ante>-<round>-<unique_id>.jkr
    2,                       -- [ENTRY_ANTE] - Ante number (parsed from filename or from signature)
    3,                       -- [ENTRY_ROUND] - Round number (parsed from filename or from signature)
    1609430,                 -- [ENTRY_INDEX] - Unique timestamp-based ID (parsed from filename or generated)
    1703123456,              -- [ENTRY_MODTIME] - File modification time (Unix timestamp)
    5,                       -- [ENTRY_STATE] - Game state constant (e.g., G.STATES.SHOP)
    "opening_pack",          -- [ENTRY_ACTION_TYPE] - Action type: nil (no action), "opening_pack" (shop with action),
                            --                      "play" or "discard" (selecting hand actions)
    150,                     -- [ENTRY_MONEY] - Current money/dollars
    "2:3:5:opening_pack:150", -- [ENTRY_SIGNATURE] - Encoded signature string for fast comparison
                            --                    Format: "ante:round:state:action_type:money"
                            --                    action_type: "" (nil), "opening_pack", "play", or "discard"
    0,                       -- [ENTRY_DISCARDS_USED] - Number of discards used (for action type detection)
    0,                       -- [ENTRY_HANDS_PLAYED] - Number of hands played (for action type detection)
    false,                   -- [ENTRY_IS_CURRENT] - Whether this is the currently loaded save
                            --                    (set by _update_cache_current_flags)
                            -- Note: description is computed on-demand, not stored
}

-- Access using constants exported from SaveManager:
-- entry[LOADER.ENTRY_FILE] = "2-3-1609430.jkr"
-- entry[LOADER.ENTRY_ANTE] = 2
-- entry[LOADER.ENTRY_STATE] = 5
-- etc.
```

## Key Changes from Previous Version

1. **Array Structure**: Entries are stored as arrays (not key-value tables) to reduce memory size:
   - All fields accessed by index constants (e.g., `entry[LOADER.ENTRY_FILE]`, `entry[LOADER.ENTRY_STATE]`)
   - Constants exported from `SaveManager` and available via `LOADER.ENTRY_*`
   - Format: `{file, ante, round, index, modtime, state, action_type, money, signature, discards_used, hands_played, is_current}`
   - Label is computed on-demand from `state` + `action_type` using `StateSignature.get_label_from_state()`

2. **Merged Action Fields**: `has_action` has been merged into `action_type`:
   - `nil` = no action
   - `"opening_pack"` = shop with action (replaces `has_action = true` for shop state)
   - `"play"` or `"discard"` = selecting hand actions
   - This simplifies the structure and eliminates redundancy

3. **Encoded Signature**: `signature` is a string like `"2:3:5:opening_pack:150"` for fast comparison:
   - Format: `"ante:round:state:action_type:money"`
   - `action_type` encoded as `""` (nil), `"opening_pack"`, `"play"`, or `"discard"`
   - Enables O(1) string comparison instead of field-by-field comparison

4. **Fast File Copy**: When loading save, file is copied directly to `save.jkr` without decoding:
   - Only decodes file once (for `start_run` hook)
   - Saves time on large save files

5. **On-Demand Description**: `description` field removed - computed on-demand when needed:
   - Reduces memory usage (no string storage per entry)
   - Minimal performance cost (just string formatting from cached fields)
   - Used only for logging/debugging, not in hot paths

6. **`is_current`**: Flag indicating if this save is the currently active one (for UI highlighting).

## When Entry is Created

### During Save Creation (`create_save`)
- Signature is computed from `StateSignature.get_signature(run_data)` which:
  - Reads `run_data.ACTION` to determine if shop state has action
  - Sets `action_type = "opening_pack"` for shop states with action
  - Sets `action_type = "play"` or `"discard"` for selecting_hand states (by comparing with previous save)
- Entry is created as an array with all fields in order: `{file, ante, round, index, modtime, state, action_type, money, signature, discards_used, hands_played, is_current}`
- **`.meta` file is written** with metadata fields (key=value format for readability, not array)
  - Format: key=value pairs for metadata fields only
  - Enables fast metadata loading without unpacking full save files
- Entry is immediately added to `save_cache` at index 1

### When Loading from Filesystem (`get_save_files`)
- Basic fields are parsed from filename and file info, entry created as array: `{file, ante, round, index, modtime, nil, nil, nil, nil, nil, nil, false}`
- Metadata is loaded via `get_save_meta()` which:
  - Returns early if `entry[ENTRY_SIGNATURE]` already exists (cached in memory)
  - **Fast path**: Tries to read from `.meta` file first (key=value format for readability)
    - `.meta` file stores: `state`, `action_type`, `money`, `signature`, `discards_used`, `hands_played`
    - These fields are populated into the array at their respective indices
  - **Slow path**: If `.meta` doesn't exist, decodes the full `.jkr` file and calls `StateSignature.get_signature()` on decoded data
    - After decoding, automatically writes `.meta` file for future fast reads
  - Stores fields directly in array at their index positions
- `action_type` for `SELECTING_HAND` states (play/discard) is detected in a second pass by comparing with previous saves
- `is_current` is set by `_update_cache_current_flags()`

## Cache Benefits

- **Performance**: 
  - When `signature` is cached in memory, no file I/O needed
  - **`.meta` file caching**: Metadata stored in `.meta` files (same structure as cache entry)
    - Reading `.meta` is much faster than unpacking full `.jkr` files
    - `.meta` files are automatically created when saves are created or when metadata is first loaded
  - Fast signature comparison using encoded string (O(1) vs O(n) field comparison)
  - File copy optimization: save files copied directly to `save.jkr` without decode
- **Accuracy**: `action_type` is captured from live game state (`run_data.ACTION`) before saving, not inferred
- **UI**: Color coding and labels computed from cached `state` + `action_type` on-demand
- **Memory**: 
  - Array structure (no key names) significantly reduces memory overhead compared to key-value tables
  - No nested tables - all fields in a flat array
  - `description` field removed - computed on-demand when needed (only for logging)
- **Unified Structure**: `.meta` files store the same metadata fields as cache entries (though in key=value format for readability), ensuring consistency

