# Changelog

English | [简体中文](https://github.com/Liafonx/Balatro-SaveRewinder/blob/main/CHANGELOG_zh.md)

All notable changes to Save Rewinder will be documented in this file.

## [1.6.1] - 2026-02-24
### Added
- **Export saves**: Select saves from the overlay and export `.jkr` (and optionally `.meta`) files to an OS directory. Configurable export path, profile-aware default directory, paste/reset controls, and full seed display toggle for non-seeded runs.
- **Max saves per type per round**: New config option to limit saves of the same type within a round (choices: 8, 16, 64, 128, All; default: 16).
- **Save list loading state**: When opening the save list while saves are still being written, the panel shows a syncing indicator with a queued-saves count instead of rendering an incomplete list.

### Improved
- **Performance during long runs (Endless mode)**: Save creation is now handled through an async queue with state-aware write budgets, preventing hitches during rapid actions in deep Endless runs.
- **Blind icon for choose-blind saves**: Choose-blind saves now show the actual next blind icon when you are choosing between remaining blinds (round > 0). The initial choose-blind save at the start of each ante still shows the ? icon.


## [1.5.5] - 2026-02-14
### Added
- **Game Over rewind action**: Added a rewind button on the game over panel.
- **Rename saves mode**: Added inline save-title editing in the saves list, with staged rename drafts and batch commit on rename-mode exit (pending drafts use the row-edge white dot badge).

### Changed
- **Pending indicator UI**: Replaced inline `[?]` text marker with a row-edge white dot badge for staged mark/rename changes.

### Fixed
- **DVPreview compatibility**: Added restore-time guard to avoid compatibility issues.

## [1.5.0] - 2026-02-07
### Added
- **Key saves (bookmarks)**: Mark important saves, filter to key saves only, and use mark mode to preview/apply in batch (pending changes show as `[?]`).

### Changed
- **Saves panel controls**: Bottom bar now uses **Check key saves**, **★ Edit key saves**, and **▶ Current save** (triangle icon); the in-list **Delete all** action was removed.
- **Retention policy**: Key saves are preserved when cleanup runs after hitting save limits.

### Fixed
- **Talisman/Amulet compatibility**: The mod is now compatible with Talisman/Amulet (e.g. Big Ante mode).

### Improved
- **Performance during long runs**: Save creation and save list handling are smoother when many saves exist or after extended play.

## [1.4.8] - 2026-01-29
### Fixed
- **Score overflow crash**: Fixed crashes when sl/rewind after score becomes overflowed (naneinf). The game now handles overflow scenarios instead of crashing.

### Added
- **Overflow score config**: New option to control how infinity scores are handled - cap at 1.8e308 (preserve through reload) or keep as naneinf (becomes 0 after reload). Default: keep as naneinf.

## [1.4.7] - 2026-01-29
### Added
- **Keybinds tab**: Customize shortcuts in mod settings (supports keyboard combos and controller buttons).
- **OS-aware labels**: Key names display as Cmd/Option/Win where appropriate.
- **Controller shortcut**: `X` (Pause Menu) opens the save list.

### Changed
- **Controller defaults**: `R3` = Quick saveload.
- **Memory optimization**: Reduced memory usage for save entries.

### Fixed
- **Save list order**: Prevented saves from appearing out of order after quit/continue flows.
- **Crash fix**: Resolved a crash when navigating the save list with controller D-Pad.

## [1.4.6.1] - 2026-01-17

### Changed
- **Release package structure** — Changed zip file structure: mod files are now wrapped in a `SaveRewinder` folder instead of being at the root

> ℹ️ **Note**: This version contains **no new features or bug fixes**. It only changes the release zip structure for easier installation. If you had any trouble installing or updating to version 1.4.6, please use this version. Otherwise, **no update is needed** if you're already running 1.4.6 successfully.

> 📦 **Thunderstore Users**: The Thunderstore package structure remains unchanged — files are still at the root directory (not wrapped in a folder).

## [1.4.6] - 2026-01-17

### Added
- **Smart Continue matching** — When you continue a run, the mod automatically highlights your exact position in the save list (even if it's not the latest save)
- **Custom save identifier** — Saves now include a unique `_rewinder_id` field for exact matching

### Fixed
- **First opening pack save blocked** — Opening pack saves now work correctly after restoring to "entering shop"
- **Shop save after pack labeled as reroll** — Shop saves after closing a pack now labeled as "In shop" instead of "Reroll shop"
- **Choose blind ordinal reset** — Sequential choose blind saves now increment correctly (B1, B2, B3)
- **Duplicate saves after restore** — Fixed duplicate detection state not resetting on restore
- **Page number display not updating** — Page number now correctly updates when clicking "Current save" button
- **Inconsistent window height** — Save list window now maintains consistent height regardless of number of saves displayed

### Improved
- Faster save list loading and highlighting
- Better detection of duplicate saves

> ⚠️ **Note**: This version adds a `_rewinder_id` field to your save data. This does not affect normal gameplay but means **your save.jkr file will be slightly different with this mod installed**.

## [1.4.5] - 2026-01-09

### ⚠️ BREAKING CHANGES

**Old saves are incompatible with this version. Please delete your save folder before updating.**

### Added
- **"Reroll shop" label** — Shop saves now labeled more clearly as "Reroll shop" instead of "In shop"
- **Undiscovered blind icon** — Choose blind saves now shows "?" icon instead of last blind icon
- **Previous boss blind icon** — After beating a boss, shop saves show the boss you just defeated
- **Shop indicator** — First shop in each ante shows "$" indicator

### Fixed
- **Choose blind ordinal** — First "choose blind" save now correctly shows ordinal 1

### Optimized
- **Faster save list loading** — Save metadata now pre-computed when creating saves

### Changed
- **Simplified release zip** — Now extracts directly to `Mods/SaveRewinder/` without nested folder

### Improved
- Cleaner save list display (removed "+>" prefix from some states)

## [1.4.0] - 2025-12-29


### Added
- **Blind icons in save list** — Shows the blind image (Small/Big/Boss) instead of round number (enabled by default)
- **Hover effects on blind icons** — Animation and sound when hovering (enabled by default)
- Reorganized config UI with two-column layout and section headers
- Screenshots added to README

### Changed
- Config setting "Debug: show save notifications" renamed to "Debug: verbose logging"
- "Return" button in save list now returns directly to game instead of options menu
- Improved shadow rendering on blind sprites (matches UnBlind mod style)
- Deferred cache initialization to run after Steamodded is ready

### Fixed
- Fixed arrow indicator positioning on current save entry
- Reduced verbose logging during normal operation

## [1.3.1] - 2025-12-28

### Added
- Orange "Saves" button in the pause menu for better visibility
- In-game mod icon (visible in Steamodded mod list)

### Changed
- Updated installation instructions to mention the orange Saves button

## [1.3.0] - 2025-12-25

### Added
- Chinese language support (简体中文)
- Localized UI separators and spacing for better language-specific formatting
- Developer documentation (`docs/AGENT.md`) for LLM/AI-assisted development

### Changed
- Default "Max saved antes per run" changed from "All" to 4
- Improved save entry display with language-specific formatting

### Fixed
- Fixed spacing between UI elements in different languages
- Fixed separator character compatibility across different fonts

## [1.2.0] - 2025-12-20

### Added
- "Undo your undo" feature - rewinded saves stay in the list until you make a new move
- Controller support: L3 to step back, R3 to open saves list
- Page navigation with LB/RB buttons
- Jump to current save with Y button

### Changed
- Improved save list UI with colored separators based on round number
- Better state labels (e.g., "Selecting hands (Play)" vs "Selecting hands (Discard)")

## [1.1.0] - 2025-12-15

### Added
- Configuration options in Steamodded menu
- Toggle save points for different game states
- Configurable save retention (1, 2, 4, 6, 8, 16 antes or All)
- Delete all saves button

### Changed
- Saves now stored in profile-specific folder
- Improved metadata caching with `.meta` files

## [1.0.0] - 2025-12-10

### Added
- Initial release
- Automatic save creation at key game moments
- Press `S` to step back one save
- Press `Ctrl+S` to open saves browser
- Save list UI with pagination
- Current save highlighting
