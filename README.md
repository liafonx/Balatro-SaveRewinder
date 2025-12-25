# Save Rewinder

**Undo mistakes. Experiment freely. Never lose progress.**

Save Rewinder automatically creates save points as you play Balatro, letting you rewind to any recent moment with a single keystroke.

## Why Use This Mod?

- 🎯 **Undo misplays** — Accidentally discarded the wrong card? Go back and try again
- 🧪 **Experiment freely** — Test risky strategies without committing
- 📸 **Automatic snapshots** — Creates a save whenever the game saves (blind selection, hand play/discard, shop, etc.)
- ⚡ **Instant restore** — Press `S` to step back, no menus needed
- 🎮 **Full controller support** — Works great with gamepad

## Quick Start

### Installation

1. Install [Steamodded](https://github.com/Steamopollys/Steamodded) for Balatro
2. Download the latest release (`SaveRewinder-[version].zip`) from the [Releases](../../releases) page
3. Extract and put the `SaveRewinder` folder (not the zip itself) into your game's `Mods` folder
4. Launch Balatro — you'll see **Save Rewinder** in the mods list

### Controls

| Action | Keyboard | Controller |
|--------|----------|------------|
| Step back one save | `S` | Click Left Stick |
| Open saves list | `Ctrl+S` | Click Right Stick |
| Navigate pages | — | `LB` / `RB` |
| Jump to current | — | `Y` |

### In-Game Menu

Press `Ctrl+S` (or click Right Stick) during a run to open the saves browser:
- Click any save to restore it
- Orange highlight shows your current position
- Use "Current save" button to find where you are

## Configuration

In the Steamodded config menu for Save Rewinder:

- **Toggle save points** — Choose which moments create saves:
  - Choosing blind
  - Selecting hand (after play/discard)
  - End of round
  - In shop
- **Limit saves** — Keep only recent antes (1, 2, 4, 6, 8, 16, or All; default: 4)
- **Delete all** — Clear all saves for current profile

## Save Data Location

Saves are stored in your Balatro profile folder:
```
[Balatro Save Path]/[Profile]/SaveRewinder/
```

Each save is a `.jkr` file named `<ante>-<round>-<timestamp>.jkr`.

## Languages

- English
- 简体中文 (Simplified Chinese)

---

> 🤖 **Developers**: Working with LLM/AI? See [`docs/AGENT.md`](docs/AGENT.md) for architecture and design details.

