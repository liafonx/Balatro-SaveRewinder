# Init Flow Documentation

Describes the mod initialization during game loading.

---

## Entry Point

**`Core/Init.lua`** — Loaded by `lovely.toml` before game starts.

---

## Flow Diagram

```mermaid
flowchart TD
    A[Game Launch] --> B[lovely.toml loads Init.lua]
    B --> C[Create REWINDER namespace]
    C --> D[Load SaveManager module]
    D --> E[Export API to REWINDER]
    E --> F[Hook Game:set_render_settings]
    F --> G{Loading screen visible?}
    G -->|Yes| H[preload_all_metadata (index + warm meta window)]
    H --> I{save.jkr exists?}
    I -->|Yes| J[Read and unpack save.jkr]
    J --> K{Has _rewinder_id?}
    K -->|Yes| L[O(1) ID lookup]
    K -->|No| M[Use newest save]
    L --> N[Set _last_loaded_file]
    M --> N
    I -->|No| O[Skip matching]
    N --> P[Game ready]
    O --> P
```

---

## Step-by-Step

### Step 1: Module Loading

```lua
if not REWINDER then REWINDER = {} end
local StateSignature = require("StateSignature")
local SaveManager = require("SaveManager")
```

Creates global namespace and loads core modules.

---

### Step 2: API Export

```lua
REWINDER.get_save_files = SaveManager.get_save_files
REWINDER.load_and_start_from_file = SaveManager.load_and_start_from_file
-- ... all ENTRY_* constants auto-copied
```

Exposes SaveManager functions and entry constants for UI/callbacks.

---

### Step 3: Hook Loading Screen

**Hook**: `Game:set_render_settings()` — runs during loading screen

This timing is ideal because:
- `G.SETTINGS.profile` is already set
- Loading screen hides any brief blocking
- Happens before main menu (pre-caches for instant UI)

---

### Step 4: Cache Initialization

```lua
local entries = SaveManager.preload_all_metadata(true)
```

**Actions:**
- Scans save directory for `.jkr` files
- Builds `save_cache`, `save_cache_by_file`, `save_cache_by_id`
- Warms a bounded meta window (default 32 entries)

---

### Step 5: Match save.jkr (Continue Support)

When user has an existing run, match it to our cache:

**Primary — O(1) ID lookup:**
```lua
local rewinder_id = run_data._rewinder_id
local entry, idx = SaveManager.get_entry_by_id(rewinder_id)
```

**Fallback:** Use newest save if no match (legacy saves without `_rewinder_id` are not supported).

**Result:** Sets `_last_loaded_file`, `current_index`, `ENTRY_IS_CURRENT` flag.

---

## Key State Variables

| Variable | Set By | Purpose |
|----------|--------|---------|
| `REWINDER._cache_initialized` | `set_render_settings` | Ensures init runs once |
| `REWINDER._main_save_matched` | `set_render_settings` | Prevents redundant matching |
| `SaveManager._last_loaded_file` | Init matching | Current save file for UI |
| `SaveManager.current_index` | Init matching | Index in save list |

---

## Performance Notes

| Aspect | Optimization |
|--------|-------------|
| Timing | During loading screen (hidden from user) |
| Metadata loading | Bounded meta window warmed at boot |
| ID matching | O(1) hash table lookup |
| Field matching | Not used (legacy saves not supported) |

---

## Related Files

- `Core/SaveManager.lua` — `preload_all_metadata()`, `get_entry_by_id()`
- `Utils/MetaFile.lua` — `.meta` file parsing
- `lovely.toml` — Module loading order
