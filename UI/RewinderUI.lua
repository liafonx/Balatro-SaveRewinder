--- Save Rewinder - UI/RewinderUI.lua
--
-- Bootstrap for UI definition patches.
-- Concrete implementations are split into focused modules:
--   - UI/IconFactory.lua
--   - UI/SaveRows.lua
--   - UI/OverlayBuilder.lua

if not REWINDER then REWINDER = {} end

require("UIShared")
require("UILayout")
require("UIIconFactory")
require("UISaveRows")
require("UIOverlayBuilder")
