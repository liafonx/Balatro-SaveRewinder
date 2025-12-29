--- Save Rewinder - EntryConstants.lua
--
-- Constants for cache entry array indices.
-- Cache entries are stored as arrays to reduce memory usage.

local M = {}

-- Cache entry array indices (1-based in Lua)
-- Format: {file, ante, round, index, modtime, state, action_type, is_opening_pack, money, signature, discards_used, hands_played, is_current}
M.ENTRY_FILE = 1
M.ENTRY_ANTE = 2
M.ENTRY_ROUND = 3
M.ENTRY_INDEX = 4
M.ENTRY_MODTIME = 5
M.ENTRY_STATE = 6
M.ENTRY_ACTION_TYPE = 7  -- "play" or "discard" for SELECTING_HAND states, nil otherwise
M.ENTRY_IS_OPENING_PACK = 8  -- boolean: true if shop state has ACTION (opening pack)
M.ENTRY_MONEY = 9
M.ENTRY_SIGNATURE = 10
M.ENTRY_DISCARDS_USED = 11
M.ENTRY_HANDS_PLAYED = 12
M.ENTRY_IS_CURRENT = 13
M.ENTRY_BLIND_KEY = 14  -- Blind key (e.g., "bl_small", "bl_final_acorn") for displaying blind icon

return M

