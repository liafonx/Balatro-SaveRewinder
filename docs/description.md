# Save Rewinder

Automatically creates save points as you play. Rewind to any moment instantly.

[简体中文](https://github.com/Liafonx/Balatro-SaveRewinder/blob/main/README_zh.md) | [Changelog](https://github.com/Liafonx/Balatro-SaveRewinder/blob/main/CHANGELOG.md) | [更新日志](https://github.com/Liafonx/Balatro-SaveRewinder/blob/main/CHANGELOG_zh.md)

## Key Features
- **Instant Undo** — Press `S` or `L3` to step back immediately.
- **Quick Saveload** — Press `L` or `R3` to instantly reload.
- **Key Saves** — Mark important saves and filter to key saves only.
- **Rename Saves** — Use the pencil mode to rename save entries inline.
- **Export Saves** — Export selected game save files to any directory.
- **Game Over Rewind** — Rewind to the last save directly from the game over panel.
- **Rewind Freely** — Stepped-back saves are preserved until you make a new save.
- **Save Browser** — Visual timeline with blind icons to easily find your spot.
- **Overflow Protection** — Rewind/save-load safely with extreme `naneinf` scores.

## Controls
| Action | Keyboard | Controller |
|--------|----------|------------|
| Step Back | `S` | `L3` |
| Quick Saveload | `L` | `R3` |
| Open List | `Ctrl+S` | `X` (Pause Menu) |

## Save List Icon Buttons
- **Check key saves** — Show only key saves.
- **★ Edit key saves** — Enter mark mode and toggle key marks.
- **✏️ Rename mode** — Enter rename mode and edit save titles.
- **⬇ Export mode** — Enter export mode, select saves, and export to a directory.
- **▶ Current save** — Jump to the currently loaded save.
- **Mark flow** — `★ Edit key saves` → click entries (pending shown as white dot badge) → `★ Save marking changes`.
- **Rename flow** — `✏️` → edit row title (pending shown as white dot badge) → click `✏️` again to commit drafts.
- **Export flow** — `⬇` → click rows to select → `⬇` again to export (exits mode if nothing selected).

## Enter Key (Overlay)
- Mark mode + Enter = commit mark edits.
- Rename mode + editing row + Enter = stage row draft and exit row edit.
- Rename mode + not editing row + Enter = commit rename drafts and exit rename mode.
- Export mode + Enter = same as ⬇ (exports selection if any selected, else exits mode).

## Configuration
Customize save triggers, save limits, keybinds, export directory, and more in the Steamodded mod menu.

> ℹ️ Saves are stored in `[Profile]/SaveRewinder/`. They persist if you quit mid-run, but are cleared when starting a **new run**. 
> ℹ️ Exported saves go to `[Balatro folder]/SW-Exports/[Profile]/` by default.
