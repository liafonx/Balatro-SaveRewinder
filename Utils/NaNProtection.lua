--- Save Rewinder - NaNProtection.lua
--
-- Handles NaN/nil/inf value sanitization to prevent crashes from score overflows.
--
-- Problem: When scores overflow to NaN or inf in Lua, saving produces "[chips]=nan" or
-- "[chips]=inf" which loadstring() interprets as undefined globals → nil, causing crashes.
--
-- Solution: Defense-in-depth sanitization at multiple points:
-- 1. Pre-save (misc_functions) - fix inf/NaN before save is written
-- 2. Load time (round_scores) - fix nil values after loading corrupted saves
-- 3. Runtime (ease events, chips comparisons) - guard against nil/NaN in calculations
-- 4. Display (number_format, DynaText) - prevent crashes in UI rendering

local Logger = require("Logger")
local debug_log = Logger.create("NaN")

local M = {}

-- Maximum valid score value (used instead of 0 for infinity)
-- IEEE 754 DBL_MAX = (2 - 2^-52) * 2^1023
-- Lua has no built-in constant (math.huge is infinity, not max finite)
-- Computing at runtime is tricky since 2^1024 overflows, so we hardcode it
M.MAX_SAFE_SCORE = 1.7976931348623157e308

-- Threshold above which we format numbers ourselves to avoid display overflow
M.LARGE_NUMBER_THRESHOLD = 1e290

--- Sanitize a value, replacing NaN/nil with 0 and inf with MAX_SAFE_SCORE (if enabled)
-- @param v any: The value to check
-- @param context string|nil: Optional context for debug logging
-- @return number: The sanitized value (0 if NaN/nil, MAX_SAFE_SCORE if inf and clamping enabled, original otherwise)
function M.sanitize(v, context)
    if v == nil then
        if context then
            debug_log("debug", context .. ": nil detected, returning 0")
        end
        return 0
    end
    if type(v) == "number" then
        if v ~= v then -- NaN check
            if context then
                debug_log("debug", context .. ": NaN detected, returning 0")
            end
            return 0
        end
        if v == math.huge or v == -math.huge then -- Infinity check
            -- Check config for clamping behavior (default: false)
            local should_clamp = false
            if REWINDER and REWINDER.config and REWINDER.config.clamp_infinity_scores ~= nil then
                should_clamp = REWINDER.config.clamp_infinity_scores
            end
            if should_clamp then
                if context then
                    debug_log("debug", context .. ": inf detected, returning MAX_SAFE_SCORE (" .. M.MAX_SAFE_SCORE .. ")")
                end
                return M.MAX_SAFE_SCORE
            else
                if context then
                    debug_log("debug", context .. ": inf detected, keeping as infinity (clamp disabled)")
                end
                return v
            end
        end
    end
    return v
end

--- Inline-safe sanitize wrapper for lovely.toml patches
-- Lightweight version without logging or infinity handling, includes built-in fallback
-- Safe to call even if module fails to load (patches can use: NaNProtection.sanitize_inline)
-- @param v any: Value to sanitize
-- @return number: Sanitized value (0 if NaN/nil, original otherwise)
function M.sanitize_inline(v)
    if v == nil then return 0 end
    if type(v) ~= "number" then return v end
   if v ~= v then return 0 end  -- NaN check
    return v
end

--- Check if a value is NaN
-- @param v any: The value to check
-- @return boolean: true if v is NaN
function M.isNaN(v)
    return type(v) == "number" and v ~= v
end

--- Check if a value is infinity
-- @param v any: The value to check
-- @return boolean: true if v is positive or negative infinity
function M.isInf(v)
    return type(v) == "number" and (v == math.huge or v == -math.huge)
end

--- Check if a value is invalid (NaN, inf, or nil)
-- @param v any: The value to check
-- @return boolean: true if v is invalid for serialization
function M.isInvalid(v)
    if v == nil then return true end
    if type(v) == "number" then
        return v ~= v or v == math.huge or v == -math.huge
    end
    return false
end

--- Sanitize all round_scores.amt fields in a GAME object (post-load)
-- Called after loading a save to fix nil values from corrupted NaN saves
-- @param game table: The G.GAME object
function M.sanitize_round_scores(game)
    if not game or not game.round_scores then return end

    local fixed = {}
    for k, v in pairs(game.round_scores) do
        if v and v.amt == nil then
            v.amt = 0
            table.insert(fixed, k)
        end
    end
    if #fixed > 0 then
        debug_log("info", "Fixed nil in " .. table.concat(fixed, ", "))
    end
end

--- Sanitize all round_scores.amt fields before saving (pre-save)
-- Called before save is written to fix NaN/inf values that would corrupt the save
-- @param game table: The G.GAME object
function M.sanitize_round_scores_presave(game)
    if not game or not game.round_scores then return end

    -- Check config for clamping behavior (default: false)
    local should_clamp = false
    if REWINDER and REWINDER.config and REWINDER.config.clamp_infinity_scores ~= nil then
        should_clamp = REWINDER.config.clamp_infinity_scores
    end

    local fixed_nan, fixed_inf = {}, {}
    for k, v in pairs(game.round_scores) do
        if v and type(v.amt) == "number" then
            local a = v.amt
            if a ~= a then -- NaN
                v.amt = 0
                table.insert(fixed_nan, k)
            elseif should_clamp and (a == math.huge or a == -math.huge) then -- Infinity (only clamp if enabled)
                v.amt = M.MAX_SAFE_SCORE
                table.insert(fixed_inf, k)
            end
        end
    end
    if #fixed_nan > 0 then
        debug_log("info", "NaN in " .. table.concat(fixed_nan, ", "))
    end
    if #fixed_inf > 0 then
        debug_log("info", "inf in " .. table.concat(fixed_inf, ", ") .. " (clamped to MAX_SAFE_SCORE)")
    end
end

--- Guard for DynaText methods - returns true if strings table is invalid
-- @param self table: The DynaText instance
-- @param method_name string: Name of the calling method (for logging)
-- @return boolean: true if guard should trigger (strings invalid)
function M.dynatext_guard(self, method_name)
    if not self.strings or not self.strings[self.focused_string] then
        debug_log("warning", method_name .. " guard triggered! strings=" ..
              tostring(self.strings) .. ", focused_string=" .. tostring(self.focused_string) ..
              ", count=" .. (self.strings and #self.strings or "nil"))
        return true
    end
    return false
end

--- Sanitize number for display in number_format
-- Note: No logging here since this runs every frame during display
-- @param num any: The input to number_format
-- @return any, boolean: Sanitized value and true if early return needed
function M.sanitize_number_format(num)
    if not num or type(num) ~= "number" then
        -- Return string if valid non-empty string, otherwise '0'
        if type(num) == "string" and num ~= "" then
            return num, true
        end
        return "0", true
    end

    -- NaN check
    if num ~= num then
        return 0, false
    end

    -- Infinity check - respect config for clamping behavior
    if num == math.huge or num == -math.huge then
        -- Check config for clamping behavior (default: false)
        local should_clamp = false
        if REWINDER and REWINDER.config and REWINDER.config.clamp_infinity_scores ~= nil then
            should_clamp = REWINDER.config.clamp_infinity_scores
        end
        if should_clamp then
            num = M.MAX_SAFE_SCORE
        else
            -- Let infinity pass through to game's number_format
            -- Game will handle it (may display as "inf" or cause issues)
            return num, false
        end
    end

    -- Very large numbers: format ourselves to avoid game's display overflow
    -- The game's number_format may overflow when converting huge numbers
    if num >= M.LARGE_NUMBER_THRESHOLD then
        local exp = math.floor(math.log10(num))
        local mantissa = num / (10 ^ exp)
        return string.format("%.1fe%d", mantissa, exp), true
    end

    return num, false
end

--- Sanitize value during serialization (string_packer)
-- @param v any: The value being serialized
-- @param k any: The key (for logging)
-- @return any: Sanitized value
function M.sanitize_serialize(v, k)
    if type(v) == "number" then
        if v ~= v then -- NaN check
            debug_log("debug", "NaN in key=" .. tostring(k) .. ", sanitizing to 0")
            return 0
        elseif v == math.huge or v == -math.huge then -- Infinity check
            -- Check config for clamping behavior (default: false)
            local should_clamp = false
            if REWINDER and REWINDER.config and REWINDER.config.clamp_infinity_scores ~= nil then
                should_clamp = REWINDER.config.clamp_infinity_scores
            end
            if should_clamp then
                debug_log("debug", "inf in key=" .. tostring(k) .. ", sanitizing to MAX_SAFE_SCORE")
                return M.MAX_SAFE_SCORE
            else
                debug_log("debug", "inf in key=" .. tostring(k) .. ", keeping as infinity (clamp disabled)")
                return v
            end
        end
    end
    return v
end

--- Format large score for continue screen display
-- Returns formatted text and scale to prevent huge text when score > threshold
-- Does NOT cap the actual display value, only caps for scale calculation
-- @param num any: The score value (usually round_scores.hand.amt)
-- @param base_scale number: Base scale value (usually 0.8*scale in continue screen)
-- @param max_scale_threshold number|nil: Maximum value for scale calculation (default 1e100)
-- @return string, number: Formatted text and scale value
function M.format_large_score(num, base_scale, max_scale_threshold)
    max_scale_threshold = max_scale_threshold or 1e100
    base_scale = base_scale or 0.32
    
    -- Sanitize input
    if not num or type(num) ~= "number" then
        debug_log("warning", "format_large_score: invalid input, num=" .. tostring(num))
        return "0", base_scale
    end
    if num ~= num then -- NaN check
        debug_log("warning", "format_large_score: NaN input")
        return "0", base_scale
    end
    
    debug_log("info", string.format("format_large_score: num=%.2e, base_scale=%.3f, threshold=%.2e", num, base_scale, max_scale_threshold))
    
    -- Format with FULL value (no capping)
    local text
    if number_format then
        text = number_format(num)
    else
        text = tostring(math.floor(num))
    end
    
    -- Cap ONLY for scale calculation to prevent huge text
    local capped_for_scale = math.min(num, max_scale_threshold)
    local scale
    if scale_number then
        scale = scale_number(capped_for_scale, base_scale)
    else
        -- Fallback scaling
        if capped_for_scale >= 1e12 then
            scale = base_scale * 0.6
        elseif capped_for_scale >= 1e9 then
            scale = base_scale * 0.7
        elseif capped_for_scale >= 1e6 then
            scale = base_scale * 0.8
        else
            scale = base_scale
        end
    end
    
    debug_log("info", string.format("format_large_score: returning text='%s', scale=%.3f", text, scale))
    
    return text, scale
end

debug_log("warning", "NaNProtection module fully loaded! format_large_score exists: " .. tostring(M.format_large_score ~= nil))
return M
