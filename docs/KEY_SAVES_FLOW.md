# Key Saves Implementation Summary (As-Built)

This document reflects the **current shipped implementation** in the repository (including post-plan UI refinements), not the earlier plan draft.

---

## Scope Delivered

Implemented end-to-end:

1. `ENTRY_IS_KEY` added as entry field 13 in SaveManager cache model
2. `.meta` support for `is_key=1` (read/write normalization)
3. `Core/KeySaves.lua` pending/commit/discard workflow
4. SaveManager helper APIs for key-save cache/meta updates
5. Retention pruning boundary in SaveManager preserves key saves via policy callback (future-prune behavior unchanged)
6. UI mark/filter modes with filter-aware page + current-save targeting
7. Controller navigation updates for new bottom-row controls
8. Localization for key-save mode labels and empty state
9. Post-implementation UI polish shipped (color-driven key marker, `[?]` pending indicator, split bottom action bar, persistent filter mode); see `SAVE_LIST_FLOW.md` for detailed render/layout behavior.

---

## Files Involved

### Core/Data

- `Core/SaveManager.lua`
- `Core/KeySaves.lua`
- `Utils/MetaFile.lua`
- `Utils/Pruning.lua`
- `Core/Init.lua`
- `lovely.toml`

### UI/Input

- `UI/RewinderUI.lua`
- `UI/ButtonCallbacks.lua`
- `Utils/Keybinds.lua`

### Localization/Docs

- `localization/en-us.lua`
- `localization/zh_CN.lua`
- `docs/AGENT.md`
- `docs/CACHE_ENTRY_EXAMPLE.md`
- `docs/SAVE_LIST_FLOW.md`

---

## Current Behavior Snapshot

### Entry/Data Model

- Entry format is 13 fields:
  - `{file, ante, round, index, money, signature, discards_used, hands_played, is_current, blind_idx, display_type, ordinal, is_key}`
- `ENTRY_IS_KEY = 13`
- `get_entry_with_meta(file)` ensures key flag can be resolved lazily
- `update_entry_is_key(file, is_key)` updates cache + meta cache

### Meta Format

- `is_key` is optional in `.meta`
- On read: normalized to boolean (`true` only when persisted as `1`)
- On write: `is_key=1` written only when true

### Pruning Semantics

- SaveManager retention boundary prepares entries (including lazy key-flag hydration) before pruning
- Retention policy keeps key saves outside normal ante window via `should_preserve_entry` callback
- Timeline future-prune after restore still applies normally

### KeySaves Facade

- `effective_is_key(entry)` supports mark-mode preview
- `toggle_pending(file)` changes in-memory intent only
- `commit_pending()` writes all pending changes and updates cache
- `discard_pending()` clears pending edits
- `get_key_saves(entries)` returns filtered array + index map

### UI Modes

- `mark` mode:
  - entry click toggles key state preview (no restore)
  - exiting mark mode commits pending changes
  - closing overlay discards pending edits
- `filter` mode:
  - toggles key-only list view
  - persists between overlay close/open
  - always repositions to page containing current save (or page 1 fallback)

### Shared UI Surface (Reference)

Key-save mode behavior is surfaced on the saves overlay through:
- mark button (`rewinder_btn_mark_keys`)
- filter button (`rewinder_btn_filter_keys`)
- jump button (`rewinder_btn_jump_to_current`)
- row-level key-state preview in mark mode

Detailed row styling and bottom-bar layout are documented in `SAVE_LIST_FLOW.md`.

---

## Controller Navigation (Current IDs)

Bottom-row focus order stays:
1. `rewinder_btn_filter_keys`
2. `rewinder_btn_mark_keys`
3. `rewinder_btn_jump_to_current`

Controller paging/jump behavior is shared with the saves-list surface and detailed in `SAVE_LIST_FLOW.md`.

---

## Notes

- This file intentionally describes **current behavior** and supersedes the earlier transitional summary that referenced removed IDs such as `rewinder_btn_current` / `rewinder_btn_delete`.
