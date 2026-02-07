# Save Rewinder Key Saves Plan Review (V2)

## Scope
Plan reviewed:
- `docs/PLAN_KEY_SAVES.md` (v2, post-review)

Code context reviewed:
- `docs/AGENT.md`
- `Core/SaveManager.lua`
- `Utils/Pruning.lua`
- `Utils/MetaFile.lua`
- `UI/RewinderUI.lua`
- `UI/ButtonCallbacks.lua`
- `Utils/Keybinds.lua`

---

## Findings (Severity Ordered)

### 1) [High] Filter-mode index mapping is still underspecified and likely to break jump/focus behavior
V2 introduces `_get_displayed_entries()` and stores `REWINDER._key_save_index_map` as `filtered_idx -> original_idx` (`docs/PLAN_KEY_SAVES.md:203-214`), which is good progress.

However, current jump/focus/controller flows operate on **full-list index space**:
- Jump-to-current computes page from `REWINDER.find_current_index()` (`UI/ButtonCallbacks.lua:156-159`).
- Focus snap uses `"rewinder_save_entry_" .. full_index` (`UI/ButtonCallbacks.lua:87-90`, `Utils/Keybinds.lua:520-525`).

In filter mode, list IDs are filtered-position IDs (`UI/RewinderUI.lua:520`), so full indices will not match UI node IDs.  
V2 states expected behavior for filter jump (`docs/PLAN_KEY_SAVES.md:358-360`) but does not define a reverse map (`original_idx -> filtered_idx`) and where it is used.

### 2) [Medium] `is_key` normalization is directionally right but specified inconsistently across modules
V2 correctly calls out the Lua truthiness trap and wants strict normalization (`docs/PLAN_KEY_SAVES.md:54-55`, `:397`).

But section wording mixes concerns:
- It says add `is_key` to `NUMERIC_FIELDS` in `MetaFile` (`docs/PLAN_KEY_SAVES.md:53`),
- then references normalization in SaveManager `_apply_meta_to_entry` with `tonumber(value)` (`docs/PLAN_KEY_SAVES.md:54`), where `value` does not exist in that function shape.

Recommendation: normalize in `MetaFile.read_meta_file` once (`meta.is_key = tonumber(v) == 1`) and keep SaveManager as plain assignment (`entry[...] = meta.is_key == true`).

### 3) [Medium] Option A page-label click remains brittle; fallback trigger criteria are not defined
V2 keeps Option A with fallback (`docs/PLAN_KEY_SAVES.md:236-239`), which is pragmatic.

Risk remains because this UI path is structure-sensitive:
- Existing code already needs deep cycle/DynaText traversal (`UI/ButtonCallbacks.lua:287-311`).
- Controller paging assumes specific cycle child positions (`Utils/Keybinds.lua:721-724`).

The plan should explicitly define when to abandon Option A (e.g., failed label-node discovery, click not firing in test matrix) and immediately switch to the explicit fallback button.

### 4) [Medium] Performance section still relies on a weak assumption about key-save growth
V2 says O(N) recompute is acceptable because users “won’t mark hundreds” (`docs/PLAN_KEY_SAVES.md:344-345`, `:395`).

This is plausible, but not a guarantee. Since retention pruning exempts key saves (`docs/PLAN_KEY_SAVES.md:166-173`), N is not strictly bounded by retention anymore.

At minimum, this should be documented as an assumption, not a hard bound.

### 5) [Low] Mark/filter mode refresh behavior after toggle is not fully specified
V2 defines callback direction (`docs/PLAN_KEY_SAVES.md:265-267`) and write-failure handling (`docs/PLAN_KEY_SAVES.md:149-153`, `:362`), but it does not precisely state:
- whether toggle in mark mode repaints only one row or rebuilds current page,
- what happens in filter mode when the current item is unmarked (page decrement vs page reset).

Edge case is listed (`docs/PLAN_KEY_SAVES.md:359`), but the exact callback flow is still open.

---

## What V2 Fixed Well (Compared to Previous Review)

1. **Module boundary improved**: `Core/KeySaves.lua` now delegates through SaveManager public primitives (`docs/PLAN_KEY_SAVES.md:76-86`, `:91-92`), avoiding direct private-local access.
2. **Truthiness risk explicitly acknowledged**: strict `tonumber(value) == 1` intent is present (`docs/PLAN_KEY_SAVES.md:54-55`, `:397`).
3. **Displayed-entry abstraction added**: central helper for all/filter source (`docs/PLAN_KEY_SAVES.md:199-218`).
4. **Controller migration checklist expanded**: all known hardcoded IDs are enumerated (`docs/PLAN_KEY_SAVES.md:282-294`).
5. **Failure semantics added**: no in-memory mutation on meta write failure (`docs/PLAN_KEY_SAVES.md:149-153`).
6. **Accessibility improved**: color + star indicator instead of color-only (`docs/PLAN_KEY_SAVES.md:13`, `:262-263`, `:394`).
7. **Close-path reset clarified**: mode reset in both close paths (`docs/PLAN_KEY_SAVES.md:195`, `:357`).

---

## Direct Answers to Requested Review Areas

### 1. Architectural fit
V2 is now mostly sound. A thin `Core/KeySaves.lua` facade is acceptable because it no longer requires direct access to SaveManager internals.

### 2. Data model
13th entry field is still the right approach. Backward compatibility strategy (missing field = falsy) is correct. Tighten where boolean normalization happens.

### 3. Performance
No immediate hot-path threat. Hidden cost remains in repeated O(N) filter scans and possible long-run growth of key saves. Acceptable for expected sizes, but should be framed as assumption-based.

### 4. UI/UX concerns
- **Page-label click**: viable but fragile; fallback is necessary.
- **Three modes**: now clearer and more coherent than v1.
- **Color/accessibility**: improved (teal + ★), though current-save prominence tradeoff should be user-tested.

### 5. Edge cases missed
Major missing detail is index-space mapping for filter mode jump/focus/controller behavior (full index vs filtered index).

### 6. Pruning guard
Decision remains correct: key saves survive retention pruning but not timeline-fork future pruning.

### 7. Step-back behavior
Correct as specified: full-list chronological step-back is consistent with timeline semantics and existing `revert_to_previous_save`.

### 8. Module dependencies
Circular risk is low if dependency direction stays one-way (`KeySaves -> SaveManager` only).

### 9. Simplification opportunities
If Option A clickability is unstable, switch early to fallback button and avoid cycle-tree surgery.

### 10. Missing details
Need explicit reverse-index mapping usage in filter mode and a precise page-refresh policy after key toggles.

---

## Recommendation Before Implementation

Resolve these two items before coding:
1. Define and implement full-to-filtered index mapping contract for jump/focus/controller in filter mode.
2. Lock exact `is_key` parse pipeline (where normalization occurs) to avoid dual-source ambiguity.

With those addressed, V2 is implementation-ready.
