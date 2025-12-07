--- Fast Save Loader - DuplicateDetector.lua
--
-- Detects and prevents duplicate saves.

local M = {}

-- Debug logging helper (injected by Init.lua)
M.debug_log = function(tag, msg)
    if LOADER and LOADER.debug_log then
        LOADER.debug_log(tag, msg)
    else
        print("[FastSL][DuplicateDetector][" .. tostring(tag) .. "] " .. tostring(msg))
    end
end

-- Checks if a save should be skipped due to being a duplicate
-- Returns true if save should be skipped
function M.should_skip_duplicate(sig, last_save_sig, last_save_time, current_time, StateSignature)
    if not sig then return false end
    
    -- Prevent duplicate saves only if same signature AND created very recently (< 0.5s)
    -- This prevents double-saves at game start while allowing legitimate same-state saves later
    if last_save_sig and last_save_time and 
       StateSignature.signatures_equal(last_save_sig, sig) and
       (current_time - last_save_time) < 0.5 then
        return true  -- Silently skip immediate duplicate
    end
    
    -- Special handling for end of round states: prevent saving twice if we just saved at end of round
    -- ROUND_EVAL and HAND_PLAYED are both "end of round" states, but have different state values
    local st = G and G.STATES
    if st and (sig.state == st.ROUND_EVAL or sig.state == st.HAND_PLAYED) then
        if last_save_sig and last_save_time and
           (current_time - last_save_time) < 1.0 then  -- 1 second window for end of round
            -- Check if previous save was also an end of round state
            if last_save_sig.state == st.ROUND_EVAL or last_save_sig.state == st.HAND_PLAYED then
                -- Check if it's the same ante/round (same round end)
                if last_save_sig.ante == sig.ante and last_save_sig.round == sig.round then
                    M.debug_log("filter", "Skipping duplicate end of round save (previous was " .. 
                        (last_save_sig.state == st.ROUND_EVAL and "ROUND_EVAL" or "HAND_PLAYED") .. 
                        ", current is " .. (sig.state == st.ROUND_EVAL and "ROUND_EVAL" or "HAND_PLAYED") .. ")")
                    return true
                end
            end
        end
    end
    
    return false
end

return M

