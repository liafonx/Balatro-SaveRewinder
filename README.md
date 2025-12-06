Fast Save Loader for Balatro
============================

Fast Save Loader is a Steamodded/Lovely mod that keeps rolling backups of your current run and lets you jump between recent states directly from inside Balatro.

Backups are stored per‑profile under `PROFILE/FastSaveLoader`.

## Features

- In‑run backups for key states:
  - Choosing blind
  - Selecting hand
  - End of round
  - In shop
- In‑game backup browser with:
  - Ante / round / state labels
  - Pagination
  - “Reload list” and “Delete all” actions
- Keyboard shortcuts:
  - `S` in a run: delete the latest backup and load the most recent previous one (not the current state)
  - `Ctrl + S` in a run: open/close the backups window
- Configurable:
  - Toggles for which states create backups
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
2. As you play, backups are created automatically at the enabled state transitions.
3. Press `Ctrl + S` during a run to open the **Backups** window:
   - Click a row to load that backup (the game restarts the run from that state).
   - Use the page selector at the bottom to switch pages.
   - Use **Delete all** to clear all backups for the current profile.
   - Press `Ctrl + S` again to close the window.
4. Press `S` during a run to quickly step back one backup:
   - If you haven’t loaded from the list, the most recent backup is deleted and the previous one is loaded.
   - If you just restored a backup from the list (and haven’t created a new save yet), pressing `S` deletes every newer-or-equal backup so the restored point becomes the branch root, then loads the next older backup after it. This keeps the timeline consistent even before a new save exists.

## Configuration

In the Steamodded mod config UI for **Fast Save Loader** you can:

- Enable/disable saving when:
  - Choosing blind
  - Selecting hand
  - At end of round
  - In shop
- Choose **Max saved antes per run** (1, 2, 4, 6, 8, 16, or All).
- Click **Delete all saves** to purge every backup for the current profile.

Changes take effect immediately for subsequent saves. Existing backups are pruned according to the ante limit. 

## Notes and limitations

- Fast Save Loader creates backups at a few safe points (choosing blind, in shop, end of round, etc.).
- If you trigger a load while Balatro is still saving during an animation/transition, the backup you restore may be slightly behind the save point you expect to be.
- Because of Balatro’s own saving behaviour and the time it takes to write and read `save.jkr`, the sequence of backups is not guaranteed to include every single intermediate state. During very fast transitions between states/pages, some points that “feel” like they should have been saved may be skipped in the backup list.

### Key behaviours to preserve
- Branching: loading an older backup records a prune list; the next real save deletes “future” saves so timelines stay linear within a branch.
- Post-restore skip: duplicates of the just-restored state are skipped once; flags clear afterward so new actions are saved.
- Quick revert (`S`): always steps to the immediate previous backup in the active branch; `current_index` resets on new saves.
- Shop restores: ensure shop CardAreas exist or defer via `G.load_shop_*`; let the shop builder load saved shop areas to keep pack-open state without instantiation warnings.
