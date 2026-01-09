# Save Rewinder

English | [简体中文](https://github.com/Liafonx/Balatro-SaveRewinder/blob/main/README_zh.md)

**Undo mistakes. Experiment freely. Never lose progress.**

Save Rewinder automatically creates save points as you play Balatro, letting you rewind to any recent moment with a single keystroke.

## Why Use This Mod?

- 🎯 **Undo misplays** — Accidentally discarded the wrong card? Go back and try again
- 🧪 **Experiment freely** — Test risky strategies without committing
- 📸 **Automatic snapshots** — Creates a save whenever the game saves (blind selection, hand play/discard, shop, etc.)
- ⚡ **Instant restore** — Press `S` to step back, no menus needed
- 🔄 **Undo your undo** — Stepped back too far? rewinded saves stay in the list until you make a new move
- 🎮 **Full controller support** — Works great with gamepad

## Screenshots

| Saves Button | Save List (Blind Icons) |
|:---:|:---:|
| ![Saves button](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/Saves_button%20in_the_Options_menu.jpeg) | ![Blind icons](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/Save_list_with_blind_icon.jpeg) |
| **Save List (Round Numbers)** | **Mod Settings** |
| ![Round numbers](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/Save_list_with_round_number.jpeg) | ![Settings](https://raw.githubusercontent.com/Liafonx/Balatro-SaveRewinder/main/images/Mod_settings.jpeg) |

## Quick Start

### Installation

1. Install [Steamodded](https://github.com/Steamopollys/Steamodded) for Balatro
2. Download `SaveRewinder.zip` from the [Releases](../../releases) page
3. Extract to your game's `Mods` folder (creates `Mods/SaveRewinder/`)
4. Launch Balatro — you'll see **Save Rewinder** in the mods list

> ⚠️ Make sure `Mods/SaveRewinder/` contains mod files directly (like `main.lua`), not another `SaveRewinder` folder.

### Controls

| Action | Keyboard | Controller |
|--------|----------|------------|
| Step back one save | `S` | Click Left Stick |
| Open saves list | `Ctrl+S` | Click Right Stick |
| Navigate pages | — | `LB` / `RB` |
| Jump to current | — | `Y` |

### In-Game Menu

Open the Options menu and click the **orange "Saves" button**, or press `Ctrl+S` (or click Right Stick):
- Click any save to restore it
- Orange highlight shows your current position
- Use "Current save" button to find where you are

## Configuration

In the Steamodded config menu for Save Rewinder:

**Auto-Save Triggers:**
- **Toggle save points** — Choose which moments create saves:
  - Choosing blind
  - Selecting hand (after play/discard)
  - End of round
  - In shop

**Display Options:**
- **Show blind image** — Display blind icons (Small/Big/Boss) instead of round numbers in save list
- **Blind image effects** — Enable hover animation and sound on blind icons (on by default)

**Advanced:**
- **Limit saves** — Keep only recent antes (1, 2, 4, 6, 8, 16, or All; default: 4)
- **Debug: verbose logging** — Show detailed save operation logs
- **Delete all** — Clear all saves for current profile

## Save Data Location

Saves are stored in your Balatro profile folder:
```
[Balatro Save Path]/[Profile]/SaveRewinder/
```

- **`.jkr` files** — The actual save data, named `<ante>-<round>-<timestamp>.jkr`
- **`.meta` files** — Cached metadata for faster loading.

> ⚠️ **Note**: Saves are only kept for your **current run**. Saves persist even if you quit the game mid-run — when you reopen and continue your run, all saves will still be available. Starting a **new run** will delete all previous saves.

## Languages

- English
- 简体中文 (Simplified Chinese)

---

> 🤖 **Developers**: Working with LLM/AI? See [`docs/AGENT.md`](docs/AGENT.md) for architecture and design details.

