# Changelog

All notable changes to Save Rewinder will be documented in this file.

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

