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
    G -->|Yes| H[Start SaveThread worker]
    H --> I[preload_all_metadata (index + warm meta window)]
    I --> J{save.jkr exists?}
    J -->|Yes| K[Read and unpack save.jkr]
    K --> L{Has _rewinder_id?}
    L -->|Yes| M[O(1) ID lookup]
    L -->|No| N[Use newest save]
    M --> O[Set _last_loaded_file]
    N --> O
    J -->|No| P[Skip matching]
    O --> Q[Game ready]
    P --> Q
```

---

## Step-by-Step

### Step 1: Module Loading

```lua
if not REWINDER then REWINDER = {} end
local StateSignature = require("StateSignature")
local SaveManager = require("SaveManager")
local SaveThread = require("SaveThread")
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

### Step 4: Save Thread + Cache Initialization

```lua
SaveThread.start()
local entries = SaveManager.preload_all_metadata(true)
```

**Actions:**
- Starts `rewinder_save_thread` while loading screen is visible
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
- `Utils/SaveThread.lua` — `start()`, thread lifecycle
- `Utils/MetaFile.lua` — `.meta` file parsing
- `lovely.toml` — Module loading order
