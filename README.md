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
  - `S` in a run: open/close the backups window
  - `Ctrl + S` in a run: delete the latest backup and load the previous one
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
3. Press `S` during a run to open the **Backups** window:
   - Click a row to load that backup (the game restarts the run from that state).
   - Use the page selector at the bottom to switch pages.
   - Use **Delete all** to clear all backups for the current profile.
4. Press `Ctrl + S` during a run to quickly step back one backup:
   - The most recent backup is deleted.
   - The previous backup is loaded and the run is restarted from that point.

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

## Credits

Fast Save Loader is derived from and heavily inspired by the original Antihypertensive save manager project:

- https://github.com/miku1958/Balatro.antihypertensive.git
