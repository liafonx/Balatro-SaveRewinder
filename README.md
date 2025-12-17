Fast Save Loader for Balatro
============================

Fast Save Loader is a Steamodded/Lovely mod that keeps rolling saves of your current run and lets you jump between recent states directly from inside Balatro.

Saves are stored per‑profile under `PROFILE/FastSaveLoader`.

## Features

- In‑run saves for key states:
  - Choosing blind
  - Selecting hand
  - End of round
  - In shop
- In‑game save browser with:
  - Ante / round / state labels
  - Color-coded round indicators (odd/even rounds)
  - Action type display (e.g., "Selecting Hand (Play)" or "Selecting Hand (Discard)")
  - Pagination with "Jump to current" button
  - Page-by-page metadata loading to keep the UI responsive
  - "Reload list" and "Delete all" actions
- Keyboard shortcuts:
  - `S` in a run: delete the latest save and load the most recent previous one (not the current state)
  - `Ctrl + S` in a run: open/close the saves window
  - Controller: click left stick (`L3`) in a run: same as `S` (step back one save)
  - Controller: click right stick (`R3`) in a run: same as `Ctrl + S` (open/close saves window)
- Configurable:
  - Toggles for which states create saves
  - Limit for how many recent antes’ saves are kept
- Localization:
  - English (`en-us`)
  - Simplified Chinese (`zh_CN`)

## Installation

1. Install Steamodded / Lovely for Balatro (follow their documentation).
2. Copy this folder into your Balatro `Mods` directory, for example:
   - macOS: `~/Library/Application Support/Balatro/Mods/FastSaveLoader`
3. Restart Balatro. You should see **Fast Save Loader** in the mods list.

## Usage

1. Start or continue a run with the mod enabled.
2. As you play, saves are created automatically at the enabled state transitions.
3. Press `Ctrl + S` during a run to open the **Saves** window:
   - Click a row to load that save (the game restarts the run from that state).
   - Use the page selector at the bottom to switch pages.
   - Click **Current save** to jump to the page containing your currently loaded save.
   - Use **Delete all** to clear all saves for the current profile.
   - Press `Ctrl + S` again to close the window.
   - Controller: `LB/RB` pages, `Y` jumps to **Current save**, and `B` goes back.
4. Press `S` during a run to quickly step back one save:
   - Loads the previous save in the timeline (one step older than the current state).
   - Future saves (newer than the loaded save) are marked for deletion but **not immediately removed**.
   - Future saves will be automatically deleted when you create a new save, keeping the timeline linear.
   - This deferred pruning allows you to step forward again if you reverted by mistake (by reloading the game before creating a new save).

## Configuration

In the Steamodded mod config UI for **Fast Save Loader** you can:

- Enable/disable saving when:
  - Choosing blind
  - Selecting hand
  - At end of round
  - In shop
- Choose **Max saved antes per run** (1, 2, 4, 6, 8, 16, or All).
- Click **Delete all saves** to purge every save for the current profile.

Changes take effect immediately for subsequent saves. Existing saves are pruned according to the ante limit. 

## Notes and limitations

- Fast Save Loader creates saves at a few safe points (choosing blind, in shop, end of round, etc.).
- If you trigger a load while Balatro is still saving during an animation/transition, the save you restore may be slightly behind the save point you expect to be.
- Because of Balatro's own saving behaviour and the time it takes to write and read `save.jkr`, the sequence of saves is not guaranteed to include every single intermediate state. During very fast transitions between states/pages, some points that "feel" like they should have been saved may be skipped in the save list.

### Key behaviours to preserve
- Branching: loading an older save (from list or `S` key) records a prune list; the next real save deletes "future" saves so timelines stay linear within a branch.
- Deferred pruning: future saves are not deleted immediately when loading an older save; they are deleted only when a new save is created. This makes revert operations non-destructive.
- Post-restore skip: duplicates of the just-restored state are skipped once; flags clear afterward so new actions are saved.
- Quick revert (`S`): always steps to the immediate previous save in the active branch; uses the same deferred pruning as loading from the list.
- Shop restores: ensure shop CardAreas exist or defer via `G.load_shop_*`; let the shop builder load saved shop areas to keep pack-open state without instantiation warnings.
