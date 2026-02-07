# Key Saves Feature — Implementation Plan (v3b, batched marking)

## Overview

Add a "key saves" (bookmark/star) system to the Save Rewinder. Players can mark important saves, which get a distinct visual style (teal/cyan + ★ indicator), survive retention pruning, and can be filtered to show only key saves.

### Decisions (locked)

- **Key save color**: Teal/Cyan `{0.2, 0.7, 0.7, 1}`
- **Current + Key priority**: Key color wins (teal + triangle arrow). Orange suppressed.
- **Future prune**: Key saves do NOT survive future pruning (timeline fork). Only retention.
- **Module location**: Thin `Core/KeySaves.lua` facade delegating to SaveManager-exported primitives.
- **Key indicator**: Color + ★ prefix (not color-only, for accessibility).

---

## 1. Data Model Changes

### 1.1 Entry Array Extension (13th field)

Add field 13: `ENTRY_IS_KEY` (boolean).

```lua
ENTRY_KEYS = {
   "FILE", "ANTE", "ROUND", "INDEX",
   "MONEY", "SIGNATURE", "DISCARDS_USED", "HANDS_PLAYED",
   "IS_CURRENT", "BLIND_IDX", "DISPLAY_TYPE", "ORDINAL",
   "IS_KEY",  -- NEW: boolean true if user marked as key save
}
-- ENTRY_IS_KEY = 13
```

Backward compatible: missing field defaults to `nil` (falsy).

### 1.2 `.meta` File Extension

Add optional line: `is_key=1` (only written when true; absent = not key).

```
money=150
signature=2:3:F:0:0:150
discards_used=0
hands_played=0
blind_idx=15
display_type=F
ordinal=1
is_key=1
```

### 1.3 MetaFile Changes

**Reading** (`MetaFile.read_meta_file`):
- Do NOT add `is_key` to `NUMERIC_FIELDS` (it's boolean, not numeric).
- Add dedicated normalization after the parse loop: `meta.is_key = (tonumber(meta.is_key) == 1)`.
- This is the **single normalization point** — all downstream code receives a true Lua boolean.

**Writing** (`MetaFile.write_meta_file`):
- Append `is_key=1` line only when `entry_meta.is_key == true`. Omit line otherwise (backward compatible).

### 1.4 SaveManager Changes

Add to `ENTRY_KEYS` and local constants:
```lua
local ENTRY_IS_KEY = 13
```

Add to `_apply_meta_to_entry` (plain assignment — MetaFile already normalized):
```lua
entry[E.ENTRY_IS_KEY] = meta.is_key or false
```

Add to `_clear_entry_meta`:
```lua
entry[E.ENTRY_IS_KEY] = nil
```

Export new public primitives for KeySaves facade:
```lua
-- Get entry + meta by file (public, for KeySaves)
function M.get_entry_with_meta(file) end

-- Update is_key on entry + meta cache (public, for KeySaves)
function M.update_entry_is_key(file, is_key) end
```

These avoid exposing `save_cache_by_file` and `meta_cache` directly.

---

## 2. New Module: `Core/KeySaves.lua`

Thin facade. Loaded as Lovely module `require("KeySaves")`. One-directional dependency: KeySaves → SaveManager.

### 2.1 API

```lua
local KeySaves = {}
local SaveManager = require("SaveManager")
local MetaFile = require("MetaFile")

-- Pending state for batched marking
local _pending = {}  -- file → new_is_key (boolean), only entries that changed

-- Check if an entry is a key save (committed state)
function KeySaves.is_key(entry)
   return entry and entry[SaveManager.ENTRY_IS_KEY] == true
end

-- Check effective is_key considering pending changes (for preview)
-- Returns: effective_is_key, is_pending
function KeySaves.effective_is_key(entry)
   if not entry then return false, false end
   local file = entry[SaveManager.ENTRY_FILE]
   if _pending[file] ~= nil then
      return _pending[file], true  -- pending change exists
   end
   return entry[SaveManager.ENTRY_IS_KEY] == true, false
end

-- Toggle pending key status for a file (does NOT write to disk)
-- Returns: new effective is_key
function KeySaves.toggle_pending(file)
   local entry = SaveManager.get_entry_with_meta(file)
   if not entry then return nil end
   local committed = entry[SaveManager.ENTRY_IS_KEY] == true
   if _pending[file] ~= nil then
      -- Already pending: check if toggling back to committed state
      local new_val = not _pending[file]
      if new_val == committed then
         _pending[file] = nil  -- Cancel pending change (back to original)
      else
         _pending[file] = new_val
      end
      return _pending[file] ~= nil and _pending[file] or committed
   else
      -- First toggle: set pending to opposite of committed
      _pending[file] = not committed
      return _pending[file]
   end
end

-- Commit all pending changes to disk + memory
-- Returns: number of successful commits, number of failures
function KeySaves.commit_pending()
   local success, fail = 0, 0
   local dir = SaveManager.get_save_dir()
   for file, new_is_key in pairs(_pending) do
      local meta_path = dir .. "/" .. file:gsub("%.jkr$", ".meta")
      local meta = MetaFile.read_meta_file(meta_path)
      if meta then
         meta.is_key = new_is_key
         local ok = MetaFile.write_meta_file(meta_path, meta)
         if ok then
            SaveManager.update_entry_is_key(file, new_is_key)
            success = success + 1
         else
            fail = fail + 1
         end
      else
         fail = fail + 1
      end
   end
   _pending = {}
   return success, fail
end

-- Discard all pending changes (no disk writes)
function KeySaves.discard_pending()
   _pending = {}
end

-- Check if there are any pending changes
function KeySaves.has_pending()
   return next(_pending) ~= nil
end

-- Get filtered view (key saves only) as flat entry array
-- Also returns index_map: filtered_position → original_position
-- Uses committed state (not pending) — filter view is for browse, not mark
function KeySaves.get_key_saves(entries)
   if not entries then return {}, {} end
   local filtered = {}
   local index_map = {}  -- filtered_idx → original_idx
   for i, entry in ipairs(entries) do
      -- CRITICAL: SaveManager metadata is lazy-loaded and may be evicted.
      -- Never treat nil ENTRY_IS_KEY as "definitely not key" without loading .meta.
      if entry[SaveManager.ENTRY_IS_KEY] == nil and SaveManager.get_save_meta then
         SaveManager.get_save_meta(entry)
      end
      if entry[SaveManager.ENTRY_IS_KEY] == true then
         filtered[#filtered + 1] = entry
         index_map[#filtered] = i
      end
   end
   return filtered, index_map
end

return KeySaves
```

### 2.2 Batched Marking Lifecycle

1. User enters mark mode → `_pending` is empty
2. User clicks entries → `toggle_pending(file)` adds/removes from `_pending` (no disk I/O)
3. User clicks "Done marking" → `commit_pending()` writes all changes to disk + memory
4. User closes overlay without Done → `discard_pending()` clears `_pending`, no changes persisted

### 2.3 Failure Handling

If any `.meta` write fails during `commit_pending()`:
- Successfully committed entries are kept (partial commit is acceptable — each entry is independent)
- Failed entries are logged but not retried
- `_pending` is cleared regardless (avoid stale pending state)
- Return counts let caller decide whether to show a warning

---

## 3. Pruning Guard

### 3.1 Retention Policy Guard

In `Pruning.apply_retention_policy` compaction loop — add `ENTRY_IS_KEY` to entry_constants parameter:

```lua
local ENTRY_IS_KEY = entry_constants.ENTRY_IS_KEY

-- In the compaction loop:
if e[ENTRY_ANTE] and not allowed[e[ENTRY_ANTE]] then
   if ENTRY_IS_KEY and e[ENTRY_IS_KEY] == true then
      -- Key save: keep it regardless of ante retention
      if write ~= read then all_entries[write] = e end
      write = write + 1
   else
      _remove_save_file_pair(save_dir, e[ENTRY_FILE])
      removed_count = removed_count + 1
   end
```

### 3.2 Future Prune

NO changes. Key saves are pruned with the rest during timeline forks.

---

## 4. UI Changes

### 4.1 Save List State (Two Independent Toggles)

State tracked by two independent booleans on `REWINDER`:

| Toggle | Variable | Default | Effect |
|--------|----------|---------|--------|
| Filter | `_filter_active` | `false` | `true` = show only key saves; `false` = show all |
| Mark | `_mark_active` | `false` | `true` = click toggles pending key status; `false` = click restores |

**Combined states:**

| Filter | Mark | Display | Click Behavior | Entries Source |
|--------|------|---------|----------------|---------------|
| off | off | All saves | Restore | `REWINDER.get_save_files()` |
| off | on | All saves, keys styled (with pending preview) | Toggle pending key | `REWINDER.get_save_files()` |
| on | off | Key saves only | Restore | `KeySaves.get_key_saves(entries)` |
| on | on | Key saves only, pending unmarks previewed | Toggle pending key (demark) | `KeySaves.get_key_saves(entries)` |

**Reset on overlay close** (BOTH close paths: `rewinder_save_close` and wrapped `exit_overlay_menu`):
- If `_mark_active`: call `KeySaves.discard_pending()` (uncommitted changes lost)
- Set `_filter_active = false`, `_mark_active = false`

### 4.2 Displayed Entries Abstraction

**Review fix (finding #1)**: All pagination/jump/update callbacks must use a unified entry source.

Add helper in ButtonCallbacks:
```lua
local function _get_displayed_entries()
   local all = REWINDER.get_save_files()
   if REWINDER._filter_active then
      local KeySaves = require("KeySaves")
      local filtered, idx_map = KeySaves.get_key_saves(all)
      REWINDER._key_save_index_map = idx_map  -- filtered → original
      -- Build reverse map: original → filtered
      local reverse = {}
      for fi, oi in pairs(idx_map) do
         reverse[oi] = fi
      end
      REWINDER._key_save_reverse_map = reverse
      return filtered
   end
   REWINDER._key_save_index_map = nil
   REWINDER._key_save_reverse_map = nil
   return all
end
```

Replace ALL `REWINDER.get_save_files()` calls in pagination/jump/update callbacks with `_get_displayed_entries()`.

**Do not bypass this helper** in:
- `G.UIDEF.rewinder_saves` (initial entries and total pages)
- `rewinder_save_update_page`
- `rewinder_save_jump_to_current`
- `_navigate_page` helper

Otherwise page labels, node IDs, and displayed rows will diverge.

### 4.2b Filter-Mode Index Mapping Contract

**Review fix (finding #1, v2 review)**: In filter mode, UI node IDs use filtered-position indices, but jump/focus/controller code uses full-list indices. This mismatch must be resolved.

**Two maps stored on `REWINDER` when `_filter_active`** (nil otherwise):

| Map | Direction | Source | Purpose |
|-----|-----------|--------|---------|
| `_key_save_index_map` | filtered_idx → original_idx | `KeySaves.get_key_saves()` | Restore: get real entry position for `load_and_start_from_file` |
| `_key_save_reverse_map` | original_idx → filtered_idx | Built from `_key_save_index_map` | Jump-to-current: find filtered page for a full-list index |

**Where each map is used:**

1. **`_key_save_index_map`** (filtered → original):
   - `rewinder_save_restore` callback: when user clicks entry in filter mode, the entry itself already has the correct file, so this map is used only if positional lookup is needed (e.g., `load_and_start_from_file` that takes an index).
   - Step-back after filter-mode restore: `revert_to_previous_save` works on full list (no map needed — it uses `save_cache_by_file`).

2. **`_key_save_reverse_map`** (original → filtered):
   - `rewinder_save_jump_to_current` (page label click): find `REWINDER.find_current_index()` in full list → look up `_key_save_reverse_map[full_idx]` to get filtered position → compute page from filtered position. If not in map, jump to page 1.
   - Controller focus snap after mode transition: uses filtered position to build node ID `"rewinder_save_entry_" .. filtered_idx`.

3. **UI node IDs**: In filter mode, `build_save_node` receives the position within the filtered list (1..#filtered for that page). Node IDs use this filtered position, matching controller focus expectations.

### 4.2c Cycle Config Rebuild Contract (Critical)

Actions that can change displayed row count MUST rebuild cycle options, not only page contents:
- filter toggle on/off
- initial overlay open
- Done marking commit (because key count can change)
- force reload / delete-all / external cache reload

Reason: reusing old `cycle_config.options` after row-count changes can desync page label text from actual pages and produce out-of-range `to_key`.

Add helper `_refresh_saves_view(target_page)` in `ButtonCallbacks.lua`:
1. Call `_get_displayed_entries()` to get current entry list
2. Recompute `total_pages` from entry count
3. Clamp `target_page` (or current page if nil) to `[1, total_pages]`
4. Rebuild `page_numbers` options array and update `cycle_config.options`
5. Call `rewinder_save_update_page` with the clamped page

Use `_refresh_saves_view(...)` for all transitions that change row count (filter toggle, Done commit, reload).

### 4.2d Filter-Aware Focus and Snap Contract

Current helper paths use full-list indices:
- `_snap_saves_focus_to_current` in `ButtonCallbacks.lua`
- `snap_to_current_save_entry` in `Keybinds.lua`

In filter mode this breaks because UI node IDs are filtered-position IDs.

Required mapping logic:
```lua
local full_idx = REWINDER.find_current_index and REWINDER.find_current_index()
local display_idx = full_idx
if REWINDER._filter_active then
   display_idx = REWINDER._key_save_reverse_map and REWINDER._key_save_reverse_map[full_idx] or nil
end
-- if display_idx exists: snap to rewinder_save_entry_<display_idx>
-- else: snap to first entry on page (or page cycle if empty)
```

This prevents silent snap failures and controller dead-focus when current save is not in filtered view.

### 4.3 Button Layout Redesign

**Current bottom bar**: `[Current save]  [Delete all]`
**New bottom bar**: `[Mark keys ★]  [Key saves only]`

Button behavior (independent toggles):

- **"Mark keys ★"** (`rewinder_btn_mark_keys`):
  - Off → on: `_mark_active = true`, label changes to "Done marking", button highlighted, page rebuilds with pending-preview styling
  - On → off ("Done marking" clicked): `KeySaves.commit_pending()`, `_mark_active = false`, label reverts, page rebuilds with committed state (via `_refresh_saves_view`, with page clamp)
  - Filter state is **unchanged** — mark mode overlays on current view

- **"Key saves only"** (`rewinder_btn_filter_keys`):
  - Off → on: `_filter_active = true`, label changes to "Show all", page rebuilds with filtered entries (via `_refresh_saves_view`, with page clamp)
  - On → off: `_filter_active = false`, label reverts, page rebuilds with all entries (via `_refresh_saves_view`, with page clamp)
  - Mark state is **unchanged** — toggling filter while marking keeps pending changes
  - **Edge case**: if mark is active when filter toggles, the displayed list changes but `_pending` set is preserved. Mark mode now operates on the new displayed list.

**Interaction examples:**
1. All view → Mark → toggle some entries → Done → commits all
2. All view → Mark → toggle entries → Filter on → demark some → Done → commits all pending
3. Filter on → Mark → demark entries → Done → commits

### 4.4 Page Label Click → Jump to Current

Attempt Option A (post-process `create_option_cycle` middle child to attach click callback).

**Fallback trigger criteria** (abandon Option A if ANY of these occur):
1. `cycle_node.nodes` has fewer than 3 children or structure differs from expected
2. Attaching `config.button` to middle child does not fire on click (test: no callback invocation)
3. Controller paging breaks (cycle child positions shift, `Keybinds.lua:721-724` logic fails)

If any trigger fires, immediately switch to **fallback**: a small clickable text button in the bottom bar or below the cycle widget, using standard `UIBox_button`.

Implementation sketch (Option A):
```lua
-- After create_option_cycle returns the node tree:
local cycle_node = <the returned row>
if cycle_node and cycle_node.nodes and #cycle_node.nodes >= 3 then
   -- Middle child is the label area
   local label_node = cycle_node.nodes[2]
   if label_node and label_node.config then
      label_node.config.button = "rewinder_save_jump_to_current"
      label_node.config.hover = true
   end
end
```

### 4.5 Key Save Entry Styling

In `build_save_node`, styling depends on committed state AND pending preview:

**Browse mode** (`_mark_active == false`):

| State | Background Color | Text Color | Indicator |
|-------|-----------------|------------|-----------|
| Normal | `G.C.BLUE` | `TEXT_LIGHT` | — |
| Current (not key) | `G.C.ORANGE` | `WHITE` | Triangle arrow |
| Key save (not current) | `{0.2, 0.7, 0.7, 1}` (teal) | `WHITE` | ★ prefix |
| Current + Key | `{0.2, 0.7, 0.7, 1}` (teal) | `WHITE` | Triangle arrow + ★ prefix |

**Mark mode** (`_mark_active == true`):
- All entries show `button = "rewinder_save_toggle_key"` instead of `"rewinder_save_restore"`
- Use `KeySaves.effective_is_key(entry)` for visual state (includes pending preview):
  - **Effective key** (committed key OR pending-mark): teal background + ★ prefix
  - **Effective non-key** (committed non-key OR pending-unmark): blue background, no ★
  - **Pending indicator**: entries with pending changes get a subtle visual cue (e.g., slightly different outline or ★ with different shade) so user can see what will change on "Done"

### 4.5b Toggle Refresh Behavior

**Mark mode toggle** (`rewinder_save_toggle_key`):
1. Call `KeySaves.toggle_pending(file)` → returns new effective `is_key` (no disk I/O)
2. **Repaint current page** via `rewinder_save_update_page` (same page, no row-count change — only styling changes). Do NOT use `_refresh_saves_view` here.

**"Done marking" commit**:
1. Call `KeySaves.commit_pending()` → writes all pending changes to disk + memory
2. `_mark_active = false`
3. Rebuild via `_refresh_saves_view(nil)` — row count may have changed (key saves added/removed affects filter view)

**Filter toggle while marking**:
- `_pending` set is preserved, page rebuilds via `_refresh_saves_view` with new entry source
- In filter+mark: pending-unmark entries still show (committed until Done). Pending-mark entries from all-view remain in `_pending` but aren't visible in filter (not committed yet).

### 4.6 Step-Back Behavior

Step-back (`S` key / `revert_to_previous_save`) always operates on the **full save list**. No changes needed to `revert_to_previous_save`.

When restoring from filter mode, `load_and_start_from_file` receives the actual file from the entry (which has the correct original index). Step-back then naturally finds the chronological predecessor in the full list.

If predecessor was pruned: existing logic handles this (`target_idx > #entries` returns early).

---

## 5. Controller Navigation Updates

### 5.1 Full Button ID Migration Checklist

All hardcoded references in `Keybinds.lua` `navigate_focus`:

| Line(s) | Old ID | New ID |
|---------|--------|--------|
| ~712 | `rewinder_btn_current` | `rewinder_btn_mark_keys` |
| ~768 | `rewinder_btn_current` | `rewinder_btn_mark_keys` |
| ~795 | `rewinder_btn_current` | `rewinder_btn_mark_keys` |
| ~806 | `rewinder_btn_delete` | `rewinder_btn_filter_keys` |
| ~809 | `rewinder_btn_current` | `rewinder_btn_mark_keys` |
| ~818 | `rewinder_btn_current` | `rewinder_btn_mark_keys` |

### 5.2 Mark Mode Controller Interaction

In mark mode, pressing A/Enter on a save entry triggers `rewinder_save_toggle_key` instead of `rewinder_save_restore`. This is handled by the button callback change in `build_save_node`, not by controller-specific logic.

---

## 6. File Changes Summary

| File | Changes |
|------|---------|
| **`Core/KeySaves.lua`** | **NEW** — Thin facade: pending state, commit/discard, query, filter |
| `Core/SaveManager.lua` | Add `ENTRY_IS_KEY` (field 13), `get_entry_with_meta()`, `update_entry_is_key()` |
| `Utils/MetaFile.lua` | Read/write `is_key` field; boolean normalization `(tonumber(v) == 1)` |
| `Utils/Pruning.lua` | Guard key saves from retention policy deletion |
| `UI/RewinderUI.lua` | Key save styling (teal + ★), mode-dependent button callback, button layout redesign, page label click |
| `UI/ButtonCallbacks.lua` | `_get_displayed_entries()` + `_refresh_saves_view()` helpers, new callbacks: `toggle_pending`, `mark_toggle`, `filter_toggle`, `done_marking` (commit); discard+reset in both close paths; filter-aware jump/snap |
| `Utils/Keybinds.lua` | Update all 6 hardcoded button ID references in `navigate_focus`; make current-entry snap filter-aware |
| `Core/Init.lua` | Export KeySaves API to REWINDER namespace |
| `lovely.toml` | Add `KeySaves` module patch |
| `localization/en-us.lua` | New strings |
| `localization/zh_CN.lua` | Chinese translations |
| `main.lua` | "Delete all saves" button stays in config tab (already there) |
| `docs/AGENT.md` | Document new module, entry field 13, key saves system |
| `docs/CACHE_ENTRY_EXAMPLE.md` | Add field 13 |

---

## 7. Implementation Order

1. **Data layer**: Add `ENTRY_IS_KEY` to SaveManager constants + `_apply_meta_to_entry` + `_clear_entry_meta`
2. **SaveManager public API**: Add `get_entry_with_meta()`, `update_entry_is_key()`
3. **MetaFile**: Read/write `is_key` with boolean normalization
4. **Core/KeySaves.lua**: Create module with pending state, commit/discard, query, filter
5. **lovely.toml**: Register KeySaves module
6. **Init.lua**: Export KeySaves to REWINDER namespace
7. **Pruning guard**: Add key save guard to `apply_retention_policy`
8. **UI styling**: Update `build_save_node` for teal color + ★ + pending preview via `effective_is_key()`
9. **UI buttons**: Replace bottom bar buttons, add `_filter_active`/`_mark_active` toggles + `_get_displayed_entries()`
10. **UI callbacks**: Implement mark toggle (pending), filter toggle, "Done marking" (commit), page label click, `_refresh_saves_view()` rebuild helper
11. **Close-path reset**: Add `discard_pending()` + toggle reset in both overlay close paths
12. **Controller nav**: Update all 6 button IDs in navigate_focus + make current-entry snap filter-aware
13. **Localization**: Add all new strings (en-us + zh_CN)
14. **Documentation**: Update AGENT.md, CACHE_ENTRY_EXAMPLE.md

---

## 8. Performance Considerations

- **Toggle pending**: O(1) table insert/remove on `_pending`. No disk I/O. No rebuild.
- **Commit pending**: One `.meta` rewrite per changed entry + O(1) cache update each. Batch write on "Done" only.
- **Filter view**: O(N) scan on each page/jump call. Runs only when UI is open and user navigates pages — not per-frame, not on hot path. For N=200 entries, this is sub-millisecond.
- **Filter activation cost**: First filter pass may trigger lazy `.meta` loads for entries with unknown `ENTRY_IS_KEY`. This is O(N) metadata reads once per overlay session; acceptable because overlay-open mode already permits cache growth and reads are tiny.
- **Pruning guard**: One extra boolean check per entry — negligible.
- **No hot path impact**: `create_save` unchanged. Key logic runs only on user interaction.
- **No cached filter view**: Filter is recomputed on each page change. This avoids cache invalidation complexity and is fast enough for expected N.

### 8.1 Key Save Growth Assumption

**Assumption**: Key saves exempt from retention pruning, so their count is not bounded by `max_antes_per_run`. However, practical growth is limited by user behavior — marking hundreds of saves requires deliberate effort.

**If assumption is violated (50+ key saves):**
- Filter scan remains O(N) where N is total saves, not key saves. The existing save list already handles 50+ total saves without issues (same iteration pattern).
- The filter scan runs on UI interaction only (page change, mode toggle), not per-frame. Even at N=500, a single `ipairs` loop with one boolean check per entry is negligible.
- No cached filter is needed. Cache invalidation complexity would outweigh any performance gain at these scales.
- **Documented as assumption, not guarantee**: if profiling shows issues at extreme scale, a cached filtered view with dirty-flag invalidation can be added as a future optimization.

---

## 9. Edge Cases

1. **Filter on with no key saves**: Show "No key saves marked" message (empty state).
2. **Key save pruned by future prune**: Key status lost with the save (intentional).
3. **Legacy saves without is_key**: Default to `nil` (falsy). No migration needed.
4. **Current save not in filtered set**: Jump-to-current in filter mode → page 1.
5. **Double-toggle in mark mode**: Toggling same entry twice cancels the pending change.
6. **Partial commit failure**: `commit_pending()` returns success/fail counts. Failed entries logged.
7. **Lazy meta false-negative**: Filter scan must call `get_save_meta` when `ENTRY_IS_KEY` is nil to avoid missing key saves outside warmed cache window.

---

## 10. New Localization Keys

```lua
-- English (en-us.lua)
rewinder_mark_keys = 'Mark key saves',
rewinder_mark_keys_active = 'Done marking',
rewinder_filter_keys = 'Key saves only',
rewinder_filter_keys_active = 'Show all',
rewinder_no_key_saves = 'No key saves marked',

-- Chinese (zh_CN.lua)
rewinder_mark_keys = '标记关键存档',
rewinder_mark_keys_active = '完成标记',
rewinder_filter_keys = '仅显示关键存档',
rewinder_filter_keys_active = '显示全部',
rewinder_no_key_saves = '未标记关键存档',
```

---

## 11. Resolved Questions

| Question | Decision | Rationale |
|----------|----------|-----------|
| Future prune | Key saves NOT protected | Timeline consistency; no ghost entries |
| Key color | Teal `{0.2, 0.7, 0.7, 1}` | Distinct from blue (normal) and orange (current) |
| Current + Key priority | Key color (teal) wins | Teal + arrow + ★ provides clear identification |
| Module location | Thin `Core/KeySaves.lua` facade | Keeps SaveManager from growing; clean public API boundary |
| Key indicator | ★ prefix + teal color | Accessibility: not color-only |
| Max key saves | No limit | Practical constraint: users won't mark hundreds |
| Filtered list format | Flat entry arrays + separate index_map | Avoids breaking existing UI entry contract |
| `is_key` parsing | `tonumber(value) == 1` in MetaFile only | Single normalization point; avoids dual-source ambiguity |
| Page label click | Try Option A, fallback to button | Worth attempting for UX; bail if fragile |
| Mark mode commit | Batched (commit on "Done") | Avoids partial disk state during marking session |
| Close without Done | Discard all pending | Clean abort; no accidental changes |
| Mark mode preview | Show would-be state (teal/blue swap) | User sees what will change before committing |
| Filter + Mark | Independent toggles | Filter changes view, mark changes click behavior; both can be active |
