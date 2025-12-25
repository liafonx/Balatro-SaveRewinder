--- Save Rewinder - ActionDetector.lua
--
-- Detects action types (play/discard) by comparing saves in the same round.

local Logger = require("Logger")
local M = {}

M.debug_log = Logger.create("ActionDetector")

-- Detects action type (play/discard) for a SELECTING_HAND entry by comparing with previous save
-- Returns "play", "discard", or nil
function M.detect_action_type(entry, sig, save_cache, get_save_meta_func, entry_constants)
    if not entry or not sig or not save_cache then return nil end
    
    local ENTRY_ANTE = entry_constants.ENTRY_ANTE
    local ENTRY_ROUND = entry_constants.ENTRY_ROUND
    local ENTRY_SIGNATURE = entry_constants.ENTRY_SIGNATURE
    local ENTRY_DISCARDS_USED = entry_constants.ENTRY_DISCARDS_USED
    local ENTRY_HANDS_PLAYED = entry_constants.ENTRY_HANDS_PLAYED
    
    local st = G and G.STATES
    if not st or sig.state ~= st.SELECTING_HAND then
        return nil  -- Only for SELECTING_HAND states
    end
    
    -- Find the most recent save in the same round from cache
    local previous_entry = nil
    for _, e in ipairs(save_cache) do
        if e and e[ENTRY_ANTE] == sig.ante and e[ENTRY_ROUND] == sig.round then
            -- Found a save in the same round
            -- Load metadata if not already loaded (this will populate discards_used and hands_played)
            if not e[ENTRY_SIGNATURE] and get_save_meta_func then
                get_save_meta_func(e)
            end
            -- If we have the tracking values, use this entry
            if e[ENTRY_DISCARDS_USED] ~= nil and e[ENTRY_HANDS_PLAYED] ~= nil then
                previous_entry = e
                break
            end
        end
    end
    
    -- Compare with previous save to determine action type
    if previous_entry then
        if sig.discards_used > previous_entry[ENTRY_DISCARDS_USED] then
            return "discard"
        elseif sig.hands_played > previous_entry[ENTRY_HANDS_PLAYED] then
            return "play"
        end
    end
    
    return nil
end

-- Detects action type for all SELECTING_HAND entries in a list
-- Modifies entries in place
function M.detect_action_types_for_entries(entries, save_cache, get_save_meta_func, entry_constants)
    if not entries or not save_cache then return end
    
    local ENTRY_SIGNATURE = entry_constants.ENTRY_SIGNATURE
    local ENTRY_STATE = entry_constants.ENTRY_STATE
    local ENTRY_ACTION_TYPE = entry_constants.ENTRY_ACTION_TYPE
    local ENTRY_ANTE = entry_constants.ENTRY_ANTE
    local ENTRY_ROUND = entry_constants.ENTRY_ROUND
    local ENTRY_DISCARDS_USED = entry_constants.ENTRY_DISCARDS_USED
    local ENTRY_HANDS_PLAYED = entry_constants.ENTRY_HANDS_PLAYED
    local ENTRY_FILE = entry_constants.ENTRY_FILE
    
    local st = G and G.STATES
    for i, entry in ipairs(entries) do
        if entry[ENTRY_SIGNATURE] and entry[ENTRY_STATE] and st and entry[ENTRY_STATE] == st.SELECTING_HAND and not entry[ENTRY_ACTION_TYPE] then
            -- Find the chronologically previous save in the same round
            -- (entries are sorted newest first, so look forward in the list)
            local previous_entry = nil
            for j = i + 1, #entries do
                local e = entries[j]
                if e and e[ENTRY_ANTE] == entry[ENTRY_ANTE] and e[ENTRY_ROUND] == entry[ENTRY_ROUND] then
                    -- Ensure previous entry has metadata loaded
                    if not e[ENTRY_SIGNATURE] and get_save_meta_func then
                        get_save_meta_func(e)
                    end
                    if e[ENTRY_DISCARDS_USED] ~= nil and e[ENTRY_HANDS_PLAYED] ~= nil then
                        previous_entry = e
                        break  -- Found the chronologically previous one in same round
                    end
                end
            end
            
            -- Compare to determine action type
            if previous_entry then
                if entry[ENTRY_DISCARDS_USED] > previous_entry[ENTRY_DISCARDS_USED] then
                    entry[ENTRY_ACTION_TYPE] = "discard"
                    M.debug_log("action", string.format("Detected discard: %s (discards: %d -> %d)", entry[ENTRY_FILE], previous_entry[ENTRY_DISCARDS_USED], entry[ENTRY_DISCARDS_USED]))
                elseif entry[ENTRY_HANDS_PLAYED] > previous_entry[ENTRY_HANDS_PLAYED] then
                    entry[ENTRY_ACTION_TYPE] = "play"
                    M.debug_log("action", string.format("Detected play: %s (hands: %d -> %d)", entry[ENTRY_FILE], previous_entry[ENTRY_HANDS_PLAYED], entry[ENTRY_HANDS_PLAYED]))
                end
            end
        end
    end
end

return M

