# Copilot instructions for Save Rewinder

Quick, targeted guidance for AI coding agents working on this repo.

## 1. Big Picture
This is a Balatro mod that snapshots game state and supports instant rewind/restore via a cached `.jkr` + `.meta` timeline. It uses **static patching** (via `lovely.toml`) and **deferred execution** (next-frame events) to avoid recursive hook conflicts with other mods.

## 2. Major Components
- **Core logic**: `Core/Init.lua` (entry point), `Core/SaveManager.lua` (save CRUD), `Core/GamePatches.lua` (game hooks), `Core/StateSignature.lua` (state fingerprinting)
- **Utilities**: `Utils/FileIO.lua`, `Utils/MetaFile.lua`, `Utils/Pruning.lua`, `Utils/DuplicateDetector.lua`, `Utils/ActionDetector.lua`, `Utils/CacheManager.lua`, `Utils/Logger.lua`
- **UI**: `UI/RewinderUI.lua` (save list overlay), `UI/ButtonCallbacks.lua` (restore/navigation handlers)
- **Config & entry**: `Keybinds.lua`, `config.lua` (default settings), `lovely.toml` (static patches), `main.lua` (Steamodded config UI)
- **Localization**: `localization/en-us.lua`, `localization/zh_CN.lua` (i18n strings for UI labels, state names, config options)
- **Reference code**: `balatro_src/` (vanilla game source for matching patched function names)

## 3. Critical Flows (Preserve These)
### Save Creation
`save_run()` → `lovely.toml` injects `REWINDER.defer_save_creation()` → deep-copy `G.culled_table` → defer to next frame → `SaveManager.create_save()` → write `.jkr` + `.meta` → update cache → apply retention policy

### Save Loading
Click/hotkey → `load_and_start_from_file(file)` → copy to `save.jkr` → record `pending_future_prune` → `G:delete_run()` → `G:start_run({savetext=...})` (fast path, no loading screen) → `Game:start_run` marks loaded state

### Timeline Pruning (Deferred)
When loading older save at index 5, saves 1-4 are marked in `pending_future_prune` but **not deleted immediately**. Deletion happens on next `create_save()` call. This allows "undo the undo" if user restarts before making new move.

### Duplicate Skip
After restore, first auto-save often matches restored state. `mark_loaded_state()` records signature; `consume_skip_on_save()` compares and skips if identical. Special handling for Shop + Pack Open states.

## 4. Project-Specific Patterns
- **Filename format**: `<ante>-<round>-<timestamp>.jkr`
- **Cache entries**: 14-element arrays (not tables) indexed by `REWINDER.ENTRY_*` constants. See `CACHE_ENTRY_EXAMPLE.md`
- **Metadata**: `.meta` files cache `ante`, `round`, `state`, `money`, etc. for fast UI loading without unpacking full `.jkr`. Format: simple key=value pairs (e.g., `ante=2`, `round=3`)
- **Logging**: Use `Logger.create(module)` for module-specific logs (e.g., `local log = Logger.create("SaveManager")`). Tags: `step`, `list`, `error`, `prune`, `restore` always log; others require `debug_saves` config
- **Deferred execution**: Never hook `save_run` synchronously. Static patch injects deferred call to avoid recursion with other mods
- **State signature**: Format `"ante:round:state:action_type:money"` for O(1) equality checks
- **Localization**: Use `localize("rewinder_key")` for all user-facing text. Add new keys to both `localization/en-us.lua` and `localization/zh_CN.lua`
- **Controller support**: Full gamepad navigation (L3/R3, LB/RB, Y button). Test UI with both keyboard and controller

## 5. Developer Workflows
```bash
./scripts/sync_to_mods.sh           # One-time sync to Mods folder
./scripts/sync_to_mods.sh --watch   # Auto-sync on file changes
```
- **No build system**: Edit Lua files in-place, sync to game, restart Balatro
- **Logs**: Check `lovely/log/` (in workspace root) for crash traces and patch diagnostics
- **Testing**: Launch Balatro with Steamodded/Lovely Loader, verify mod in mods list

## 6. Integration & Dependencies
- **Lovely Loader**: `lovely.toml` patches inject code into vanilla functions. Patterns must match `balatro_src/` filenames exactly
- **Mod compatibility**: Static patching avoids hook-order issues. Keep function signatures stable when refactoring
- **Borrowed patterns**: Fast restore from `Brainstorm-Rerolled` (`G:delete_run` → `G:start_run`), unpack flow from `QuickLoad`, blind sprites from `UnBlind`, controller focus from `BetterMouseandGamepad`
- **balatro_src/ reference**: Unpacked vanilla game source for viewing original implementations (`save_run`, `start_run`, etc.) and writing `lovely.toml` regex patterns. NOT part of distributed mod

## 7. Safe-Edit Checklist
Before changing save logic:
1. Read `Core/SaveManager.lua` and `Core/StateSignature.lua`
2. Preserve deferred pruning and duplicate-skip unless intentionally changing UX
3. Update `CACHE_ENTRY_EXAMPLE.md` + `CLICK_LOAD_FLOW.md` if altering data formats
4. Run `./scripts/sync_to_mods.sh` and test in-game
5. Check `lovely/log/` for errors
6. **Important**: Development script improvements (like `sync_to_mods.sh` changes) should **not** be added to `CHANGELOG.md` — only user-facing changes

## 8. Code Examples
```lua
-- Defer save (injected by lovely.toml after G.ARGS.save_run = G.culled_table)
REWINDER.defer_save_creation()

-- Create save manually
SaveManager.create_save(g_copied_table)

-- Load save
REWINDER.load_and_start_from_file("2-3-1609430.jkr")

-- Access cache entry (14-element array)
local file = entry[REWINDER.ENTRY_FILE]
local state = entry[REWINDER.ENTRY_STATE]
local blind_key = entry[REWINDER.ENTRY_BLIND_KEY]

-- Create blind sprite (from UnBlind pattern)
local sprite = AnimatedSprite(0, 0, 0.45, 0.45,
    G.ANIMATION_ATLAS['blind_chips'],
    G.P_BLINDS[blind_key].pos)
sprite:define_draw_steps({
    {shader = 'dissolve', shadow_height = 0.02},
    {shader = 'dissolve'}
})
```

## 9. When to Ask Humans
- Changes to signature format, metadata layout, or retention semantics
- Altering deferred-execution or timeline-pruning logic
- Adding new `lovely.toml` patches that might conflict with other mods

## 10. Further Reading
- **Architecture**: `docs/AGENT.md` (detailed flows, design rationale)
- **Cache structure**: `docs/CACHE_ENTRY_EXAMPLE.md` (13-field array format)
- **Load flow**: `docs/CLICK_LOAD_FLOW.md` (step-by-step restore process)
- **User guide**: `README.md` and `README_zh.md`
