# Cache Entry Structure

Cache entries use **12-field arrays** for memory efficiency. Access via `REWINDER.ENTRY_*` constants.

## Entry Array Format

```lua
-- 12-field entry: {file, ante, round, index, money, signature,
--                  discards_used, hands_played, is_current, blind_idx, display_type, ordinal}
local entry = {
    "2-3-1609430.jkr",  -- [1] ENTRY_FILE
    2,                   -- [2] ENTRY_ANTE
    3,                   -- [3] ENTRY_ROUND
    1609430,             -- [4] ENTRY_INDEX (unique millisecond timestamp for sorting)
    150,                 -- [5] ENTRY_MONEY
    "2:3:5::150",        -- [6] ENTRY_SIGNATURE
    0,                   -- [7] ENTRY_DISCARDS_USED
    0,                   -- [8] ENTRY_HANDS_PLAYED
    false,               -- [9] ENTRY_IS_CURRENT
    15,                  -- [10] ENTRY_BLIND_IDX (number, use index_to_blind_key for string)
    "S",                 -- [11] ENTRY_DISPLAY_TYPE
    2,                   -- [12] ENTRY_ORDINAL
}
```

## Index Constants

```lua
ENTRY_KEYS = {
   "FILE", "ANTE", "ROUND", "INDEX",
   "MONEY", "SIGNATURE", "DISCARDS_USED", "HANDS_PLAYED",
   "IS_CURRENT", "BLIND_IDX", "DISPLAY_TYPE", "ORDINAL",
}
```

## Display Type Codes

| Code | Description | Show Ordinal |
|------|-------------|--------------|
| S | Shop | Yes |
| F | First shop (entering) | No |
| O | Opening pack | Yes |
| R | Start of round | No (has prefix) |
| P | Play action | Yes |
| D | Discard action | Yes |
| H | Selecting hand | Yes |
| E | End of round | No |
| B | Choose blind | Yes |
| ? | Unknown | Yes |

## .meta File Format

```
money=150
signature=2:3:5::150
discards_used=0
hands_played=0
blind_idx=15
display_type=S
ordinal=2
```

## Entry Lifecycle

### Created (`create_save`)
1. O(1) action detection via `ordinal_state`
2. O(1) first_shop detection via `last_display_type`
3. `compute_display_type()` → single-char code
4. `counters[display_type]++` → ordinal
5. 12-element array constructed with blind_idx (number)
6. `.meta` file written

### Loaded (`get_save_meta`)
1. Parse filename → file, ante, round, index
2. Read `.meta` → remaining 8 fields
3. Fallback: decode `.jkr` if no valid meta
