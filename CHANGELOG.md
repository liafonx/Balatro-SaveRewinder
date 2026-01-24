# Changelog

English | [简体中文](https://github.com/Liafonx/Balatro-SaveRewinder/blob/main/CHANGELOG_zh.md)

All notable changes to Save Rewinder will be documented in this file.

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

