# Save Rewinder

English | [简体中文](https://github.com/Liafonx/Balatro-SaveRewinder/blob/main/README_zh.md)

**Undo mistakes. Experiment freely. Never lose progress.**

Save Rewinder automatically creates save points as you play Balatro, letting you rewind to any recent moment with a single keystroke.

- 📸 **Automatic snapshots** — Creates save points for every action (blind selection, hands, shop).
- ⚡ **Instant Undo** — Press `S` (keyboard) or `L3` (controller) to rewind immediately.
- 🔁 **Quick Saveload** — Press `L` (keyboard) or `R3` (controller) to instantly reload.
- 🧪 **Experiment Freely** — Test strategies without fear; stepped-back saves are preserved safely.
- 🎮 **Full Controller Support** — Dedicated navigation and separate keybindings.

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

> **Tip:** Open the **Options** menu and click the **orange "Saves" button** (or press `Ctrl+S` / `X`) to browse and restore any save.

## Configuration

In the Steamodded config menu for Save Rewinder:

- Choose when to save (Blind, Hand, Round, Shop).
- Toggle blind icons and animations.
- Set max antes to keep (Default: 4).
- Customize keyboard and controller inputs separately.

## Save Data Location

Saves are stored in `[Profile]/SaveRewinder/`.

> ⚠️ **Note**: Saves are for the **current run only** and are cleared when starting a new run. Quitting and continuing later preserves your full history.

## Languages

- English
- 简体中文 (Simplified Chinese)

---

> 🤖 **Developers**: Working with LLM/AI? See [`docs/AGENT.md`](docs/AGENT.md) for architecture and design details.
