# Cache Entry Structure

This document shows the structure of cache entries used in Save Rewinder.

## Entry Array Format

Cache entries are stored as **arrays** (not key-value tables) to reduce memory. Access fields using index constants from `REWINDER.ENTRY_*`:

```lua
-- Array format: {file, ante, round, index, modtime, state, action_type, is_opening_pack, money, signature, discards_used, hands_played, is_current, blind_key}
local entry = {
    "2-3-1609430.jkr",  -- [1] ENTRY_FILE - Filename: <ante>-<round>-<unique_id>.jkr
    2,                   -- [2] ENTRY_ANTE - Ante number
    3,                   -- [3] ENTRY_ROUND - Round number
    1609430,             -- [4] ENTRY_INDEX - Unique timestamp-based ID
    1703123456,          -- [5] ENTRY_MODTIME - File modification time (Unix timestamp)
    5,                   -- [6] ENTRY_STATE - Game state constant (e.g., G.STATES.SHOP)
    nil,                 -- [7] ENTRY_ACTION_TYPE - "play" or "discard" for SELECTING_HAND only, nil otherwise
    true,                -- [8] ENTRY_IS_OPENING_PACK - Boolean: true if shop state has ACTION (opening pack)
    150,                 -- [9] ENTRY_MONEY - Current money/dollars
    "2:3:5::150",        -- [10] ENTRY_SIGNATURE - Encoded signature for fast comparison
                         --     Format: "ante:round:state:action_type:money"
                         --     action_type: "" (nil), "play", or "discard"
    0,                   -- [11] ENTRY_DISCARDS_USED - Discards used in current round
    0,                   -- [12] ENTRY_HANDS_PLAYED - Hands played in current round
    false,               -- [13] ENTRY_IS_CURRENT - Whether this is the currently loaded save
    "bl_final_acorn",    -- [14] ENTRY_BLIND_KEY - Blind key for displaying blind icon (e.g., "bl_small", "bl_big", "bl_final_acorn")
}

-- Access example:
-- entry[REWINDER.ENTRY_FILE] = "2-3-1609430.jkr"
-- entry[REWINDER.ENTRY_STATE] = 5
-- entry[REWINDER.ENTRY_IS_OPENING_PACK] = true
-- entry[REWINDER.ENTRY_BLIND_KEY] = "bl_final_acorn"
```

## Index Constants

```lua
ENTRY_FILE = 1
ENTRY_ANTE = 2
ENTRY_ROUND = 3
ENTRY_INDEX = 4
ENTRY_MODTIME = 5
ENTRY_STATE = 6
ENTRY_ACTION_TYPE = 7      -- "play" or "discard" for SELECTING_HAND states only
ENTRY_IS_OPENING_PACK = 8  -- boolean for shop states with ACTION
ENTRY_MONEY = 9
ENTRY_SIGNATURE = 10
ENTRY_DISCARDS_USED = 11
ENTRY_HANDS_PLAYED = 12
ENTRY_IS_CURRENT = 13
ENTRY_BLIND_KEY = 14       -- Blind key string (e.g., "bl_small", "bl_final_acorn")
```

## Field Descriptions

### action_type vs is_opening_pack

These are **separate fields** with different purposes:

| Field | Type | Used For | Values |
|-------|------|----------|--------|
| `action_type` | string/nil | SELECTING_HAND states | `"play"`, `"discard"`, or `nil` |
| `is_opening_pack` | boolean | Shop states | `true` if has ACTION (pack open), `false` otherwise |

**UI Labels derived from these:**
- `action_type = "play"` → "selecting hand (play)"
- `action_type = "discard"` → "selecting hand (discard)"
- `action_type = nil` + SELECTING_HAND → "start of round"
- `is_opening_pack = true` → "opening pack"
- `is_opening_pack = false` + SHOP → "shop"

### Signature Encoding

Signature is a string for O(1) comparison: `"ante:round:state:action_type:money"`

- `action_type` encoded as empty string `""` when nil
- Example: `"2:3:5::150"` (shop state, no action_type)
- Example: `"2:3:1:play:150"` (selecting hand after play)

## Entry Lifecycle

### Created During Save (`create_save`)

1. `StateSignature.get_signature(run_data)` computes signature:
   - Reads `run_data.ACTION` to set `is_opening_pack`
   - `action_type` detected by comparing with previous save's `discards_used`/`hands_played`
2. Entry created as 13-element array
3. `.meta` file written with metadata (fast loading on next boot)
4. Entry inserted at index 1 in `save_cache`

### Loaded from Filesystem (`get_save_files`)

1. Basic fields parsed from filename: `{file, ante, round, index, modtime, nil, nil, false, nil, nil, nil, nil, false}`
2. Metadata loaded via `get_save_meta()`:
   - **Fast path**: Read from `.meta` file (key=value format)
   - **Slow path**: Decode full `.jkr`, then write `.meta` for future
3. `action_type` for SELECTING_HAND detected in second pass
4. `is_current` set by `_update_cache_current_flags()`

## Performance Notes

- **Array structure**: No key names = less memory than tables
- **Signature string**: O(1) comparison vs O(n) field-by-field
- **`.meta` caching**: Avoids decompressing `.jkr` files on every boot
- **Direct file copy**: `copy_save_to_main` copies without decode when loading
- **On-demand description**: Labels computed only when needed (UI/logging)
