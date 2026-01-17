# Entry Structure (Unified)

Entry is the **single canonical structure** used for both storage and comparison.

---

## Entry Array Format

Cache entries use **12-field arrays** for memory efficiency. Access via `REWINDER.ENTRY_*` constants.

```lua
-- 12-field entry: {file, ante, round, index, money, signature,
--                  discards_used, hands_played, is_current, blind_idx, display_type, ordinal}
local entry = {
    "2-3-1609430.jkr",  -- [1] ENTRY_FILE
    2,                   -- [2] ENTRY_ANTE
    3,                   -- [3] ENTRY_ROUND
    1609430,             -- [4] ENTRY_INDEX (unique millisecond timestamp for sorting)
    150,                 -- [5] ENTRY_MONEY
    "2:3:F:0:0:150",     -- [6] ENTRY_SIGNATURE (unified format with display_type)
    0,                   -- [7] ENTRY_DISCARDS_USED
    0,                   -- [8] ENTRY_HANDS_PLAYED
    false,               -- [9] ENTRY_IS_CURRENT
    15,                  -- [10] ENTRY_BLIND_IDX (number, use index_to_blind_key for string)
    "F",                 -- [11] ENTRY_DISPLAY_TYPE
    1,                   -- [12] ENTRY_ORDINAL
}
```

## Entry Index Constants

```lua
ENTRY_KEYS = {
   "FILE", "ANTE", "ROUND", "INDEX",
   "MONEY", "SIGNATURE", "DISCARDS_USED", "HANDS_PLAYED",
   "IS_CURRENT", "BLIND_IDX", "DISPLAY_TYPE", "ORDINAL",
}
```

---

## Signature String Format (Unified)

The signature string encodes key entry fields for **fast comparison**:

```
"ante:round:display_type:discards_used:hands_played:money"
```

Examples:
```lua
"2:3:F:0:0:150"  -- Ante 2 Round 3, Entering shop, $150
"2:3:O:0:0:150"  -- Ante 2 Round 3, Opening pack, $150
"2:3:S:0:0:145"  -- Ante 2 Round 3, Reroll shop, $145
"2:3:A:0:0:142"  -- Ante 2 Round 3, After pack (in shop), $142
"5:15:P:0:1:250" -- Ante 5 Round 15, Play (hands_played=1), $250
"5:15:D:1:1:250" -- Ante 5 Round 15, Discard (discards_used=1), $250
```

**Key insight**: Display type is computed BEFORE signature creation, enabling simple string comparison.

---

## State Info Structure

`StateSignature.get_state_info(run_data)` extracts raw state info for display_type computation:

```lua
local state_info = {
    ante = 2,                    -- Current ante number
    round = 3,                   -- Current round number
    state = 5,                   -- G.STATES value (e.g., SHOP=5, SELECTING_HAND=13)
    money = 150,                 -- Current money
    is_opening_pack = false,     -- true if SHOP state with ACTION
    discards_used = 0,           -- Discards used this round
    hands_played = 0,            -- Hands played this round
    blind_key = "bl_small",      -- Current blind key
}
```

**Note**: `state_info` is NOT the same as entry. It's a temporary structure used to compute `display_type`.

---

## Display Type Codes

| Code | Description | Show Ordinal |
|------|-------------|--------------|
| S | Shop (reroll) | Yes |
| A | After pack (in shop) | Yes |
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
signature=2:3:F:0:0:150
discards_used=0
hands_played=0
blind_idx=15
display_type=F
ordinal=1
```

## Entry Lifecycle

### Created (`create_save`)
1. `StateSignature.get_state_info(run_data)` → extract raw state
2. `_compute_display_type(state_info)` → single-char code using ordinal_state context
3. `_create_signature(state_info, display_type)` → unified signature string
4. Duplicate check via signature STRING comparison
5. `counters[display_type]++` → ordinal
6. Boss tracking for shop blind icons
7. 12-element entry array constructed
8. `.meta` file written

### Compared (`consume_skip_on_save`)
1. Get state_info from run_data
2. Compute display_type using ordinal_state context
3. Create current signature string
4. Compare with loaded signature STRING (simple equality)

### Loaded (`get_save_meta`)
1. Parse filename → file, ante, round, index
2. Read `.meta` → remaining 8 fields
3. Fallback: decode `.jkr` if no valid meta

## ordinal_state Structure

```lua
ordinal_state = {
   ante = nil,              -- Current ante
   blind_key = nil,         -- Current blind (e.g., "bl_small"), nil treated as "unknown"
   last_display_type = nil, -- For first_shop, after_pack, and action type detection
   last_discards_used = 0,  -- For play/discard detection
   last_hands_played = 0,   -- For play/discard detection
   last_round = nil,        -- For post-boss shop detection
   last_saved_round = nil,  -- Round when counters were last reset (for per-round ordinal)
   counters = { S=0, F=0, O=0, A=0, R=0, P=0, D=0, H=0, E=0, B=0, ["?"]=0 },
   defeated_boss_idx = nil, -- Boss blind index after defeat (nil = not in post-boss phase)
}
```

**Counter behavior:**
- All counters reset when `ante` or `round` changes
- Counters do NOT reset on blind_key change (allows B1→B2→B3 when skipping blinds)
- Within a round, counters increment normally

### Boss Tracking Logic
- **Set**: On E save when `round == 3` or `actual_blind_idx > 2`
- **Reset**: On B save (entering choose blind)
- **Used by**: Shop saves (F/S/O/A) to show defeated boss icon instead of next blind

