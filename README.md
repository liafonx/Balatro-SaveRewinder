# Save Rewinder

English | [简体中文](https://github.com/Liafonx/Balatro-SaveRewinder/blob/main/README_zh.md)

**Undo mistakes. Experiment freely. Never lose progress.**

Save Rewinder automatically creates save points as you play Balatro, letting you rewind to any recent moment with a single keystroke.

- 📸 **Automatic snapshots** — Creates save points for every action (blind selection, hands, shop).
- ⚡ **Instant Undo** — Press `S` (keyboard) or `L3` (controller) to rewind immediately.
- 🔁 **Quick Saveload** — Press `L` (keyboard) or `R3` (controller) to instantly reload.
- ⭐ **Key Saves** — Mark important saves and filter the list to key saves only.
- ✏️ **Rename Saves** — Rename save entries in the save list.
- 💀 **Game Over Rewind** — Rewind to your last save directly from the game over panel.
- 🧪 **Experiment Freely** — Test strategies without fear; stepped-back saves stay available until you make a new action.
- 🛡️ **Score Overflow Protection** — Rewind/save-load safely with extreme `naneinf/inf` scores (optional clamp to `1.8e308`).

## Screenshots

| Saves Button | Save List (Blind Icons) |
|:---:|:---:|
| ![Saves button](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/Saves_button%20in_the_Options_menu.jpeg) | ![Blind icons](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/Save_list_with_blind_icon.jpeg) |
| **Save List (Round Numbers)** | **Mod Settings** |
| ![Round numbers](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/Save_list_with_round_number.jpeg) | ![Settings](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/Mod_settings.jpeg) |

## Installation

1. Install [Steamodded](https://github.com/Steamopollys/Steamodded) for Balatro
2. Download and extract the [latest release](https://github.com/Liafonx/Balatro-SaveRewinder/releases) — it contains a `SaveRewinder` folder
3. Copy the `SaveRewinder` folder into your game's `Mods` folder
4. Launch Balatro — you'll see **Save Rewinder** in the mods list

> ⚠️ **Important**: Ensure `Mods/SaveRewinder/` contains mod files directly (like `main.lua`), not another nested `SaveRewinder` folder.

> 📦 **Thunderstore Users**: Files are at the zip root. Create `Mods/SaveRewinder/` and extract all files into it. Final structure: `Mods/SaveRewinder/main.lua`.

## Quick Start

### Controls

| Action | Keyboard (default) | Controller (default) |
|--------|----------|------------|
| Step back one save (configurable) | `S` | Click Left Stick (L3) |
| Quick saveload (configurable) | `L` | Click Right Stick (R3) |
| Open saves list (configurable) | `Ctrl+S` | `X` (in Pause Menu Only) |

> **Tip:** Open the **Pause Menu → Options** and click the **orange "Saves" button** (or press `Ctrl+S` / `X`) to browse and restore any save.

### Save List Icon Buttons

- **Check key saves** — Text button. Shows only key saves.
- **★ Edit key saves** — Star icon button. Enters mark mode so you can add/remove key marks.
- **✏️ Rename mode** — Pencil icon button. Enter rename mode to edit save titles inline.
- **▶ Current save** — Triangle icon button. Jumps to your currently loaded save.

How to use:
1. Press **★ Edit key saves**.
2. Click save rows to toggle key marks (pending changes show a white dot badge).
3. Press **★ Save marking changes** to apply. Close the panel to discard pending edits.
4. Use **Check key saves** to filter, and **▶ Current save** to jump back to your current position.

Rename flow:
1. Press the **✏️** button to enter rename mode.
2. Click a save row and edit its title.
3. Click the row again (or switch rows) to stage the draft (pending rename show a white dot badge).
4. Press **✏️** again to commit staged rename drafts.

### Enter Key Behavior (Saves Overlay)

When the saves overlay is open:
- **Mark mode + Enter** — Same as clicking **★ Save marking changes** (commits mark edits / exits mark mode).
- **Rename mode + editing a row + Enter** — Same as clicking that row again (stages current row draft and exits row editing).
- **Rename mode + not editing a row + Enter** — Same as clicking **✏️** (commits staged rename drafts and exits rename mode).

## Game Over Rewind

When you lose a run, the game over panel includes a button so you can jump straight back into the timeline.

## Configuration

In the Steamodded config menu for Save Rewinder:

- Choose when to save (Blind, Hand, Round, Shop).
- Toggle blind icons and animations.
- Set max antes to keep (Default: 4).
- Configure overflow score handling (cap at 1.8e308 or keep as naneinf).
- Customize keyboard and controller keybinds.

## Save Data Location

Saves are stored in `[Profile]/SaveRewinder/`.

> ⚠️ **Note**: Saves are for the **current run only** and are cleared when starting a new run. Quitting and continuing later preserves your full history.

## Languages

- English
- 简体中文 (Simplified Chinese)
