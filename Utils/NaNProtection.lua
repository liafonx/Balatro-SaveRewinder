--- Save Rewinder - NaNProtection.lua
--
-- Centralized NaN/inf protections for save/load/runtime display.

local Logger = require("Logger")
local debug_log = Logger.create("NaN")

local M = {}

M.MAX_SAFE_SCORE = 1.7976931348623157e308
M.LARGE_NUMBER_THRESHOLD = 1e290

local function is_nan(v)
    return type(v) == "number" and v ~= v
end
M.is_nan = is_nan

local function is_inf(v)
    return type(v) == "number" and (v == math.huge or v == -math.huge)
end
M.is_inf = is_inf

local function _format_scientific(num)
    local abs_num = math.abs(num)
    local exp = math.floor(math.log10(abs_num))
    local mantissa = num / (10 ^ exp)
    return string.format("%.1fe%d", mantissa, exp)
end

local function should_clamp_infinity()
    if REWINDER and REWINDER.config and REWINDER.config.clamp_infinity_scores ~= nil then
        return REWINDER.config.clamp_infinity_scores
    end
    return false
end
M.should_clamp_infinity = should_clamp_infinity

local function is_known_big_mod_loaded()
    local mods = SMODS and SMODS.Mods
    if type(mods) ~= "table" then return false end

    local ids = { "Talisman", "Amulet", "talisman", "amulet" }
    for _, id in ipairs(ids) do
        local m = mods[id]
        if type(m) == "table" and m.can_load ~= false and m.disabled ~= true then
            return true
        end
    end
    return false
end

local function to_big_returns_big_type()
    if type(to_big) ~= "function" then return false end
    local ok, v = pcall(to_big, 1)
    if not ok then return false end
    return type(v) ~= "number"
end

-- Session-local cache: nil = not yet checked, true/false = cached result.
-- Mods don't load/unload mid-session so this is safe to cache permanently.
local _big_backend_cached = nil

function M.has_big_backend()
    if _big_backend_cached ~= nil then return _big_backend_cached end
    if type(Big) == "table" and type(Big.is) == "function" then
        _big_backend_cached = true
        return true
    end
    if to_big_returns_big_type() then
        _big_backend_cached = true
        return true
    end
    if is_known_big_mod_loaded() then
        _big_backend_cached = true
        return true
    end
    _big_backend_cached = false
    return false
end

-- Lightweight sanitizer for hot paths (event easing values).
function M.sanitize_inline(v)
    -- Only recover nil. Preserve NaN/inf so overflow displays are not coerced to 0 mid-animation.
    if v == nil then return 0 end
    return v
end

-- Comparison helper that stays compatible with to_big environments.
function M.score_gt(amt, current)
    if amt == nil then return false end

    -- Fast path: regular finite numbers (common case).
    if type(amt) == "number" and type(current) == "number" and
       amt == amt and current == current and
       amt ~= math.huge and amt ~= -math.huge then
        return math.floor(amt) > current
    end

    if type(amt) ~= "number" then
        -- Big-number backend compatibility: compare via to_big if available.
        if M.has_big_backend() and type(to_big) == "function" then
            local ok_l, l = pcall(to_big, amt)
            local ok_r, r = pcall(to_big, current or 0)
            if ok_l and ok_r then
                return l > r
            end
        end

        if type(amt) == "table" and type(amt.to_number) == "function" then
            local ok, v = pcall(function() return amt:to_number() end)
            if ok and type(v) == "number" then
                amt = v
            else
                return false
            end
        else
            return false
        end
    end

    if is_nan(amt) then
        return not (type(current) == "number" and is_nan(current))
    end

    if amt == math.huge then
        return current ~= math.huge
    end
    if amt == -math.huge then
        return false
    end

    local lhs = math.floor(amt)
    local rhs = current
    if type(rhs) ~= "number" then
        rhs = tonumber(rhs) or 0
    end
    if is_nan(rhs) then
        return false
    end

    if type(to_big) == "function" and M.has_big_backend() then
        local ok_l, l = pcall(to_big, lhs)
        local ok_r, r = pcall(to_big, rhs)
        if ok_l and ok_r then
            return l > r
        end
    end
    return lhs > rhs
end

local function normalize_score_value(amt)
    if type(amt) ~= "number" then
        -- Preserve big-number objects in big backend mode.
        if M.has_big_backend() then
            return amt
        end
        if type(amt) == "table" and type(amt.to_number) == "function" then
            local ok, v = pcall(function() return amt:to_number() end)
            if ok and type(v) == "number" then
                amt = v
            else
                return 0
            end
        else
            return 0
        end
    end
    if is_nan(amt) then
        return 0/0
    end
    if is_inf(amt) then
        if should_clamp_infinity() then
            return amt < 0 and -M.MAX_SAFE_SCORE or M.MAX_SAFE_SCORE
        end
        return amt
    end
    return math.floor(amt)
end

-- Continue panel score assignment.
function M.sanitize_round_score_assignment(amt)
    return normalize_score_value(amt)
end

-- Profile high score assignment.
function M.sanitize_high_score_assignment(amt)
    return normalize_score_value(amt)
end

-- number_format hook helper.
function M.sanitize_number_format(num)
    -- Fast path: standard finite numbers in normal range.
    if type(num) == "number" and num == num and num ~= math.huge and num ~= -math.huge then
        local abs_num = math.abs(num)
        if abs_num < M.LARGE_NUMBER_THRESHOLD then
            return num, false
        end
        return _format_scientific(num), true
    end

    if num == nil then
        return "0", true
    end

    if type(num) == "string" then
        if num ~= "" then
            return num, true
        end
        return "0", true
    end

    if type(num) ~= "number" then
        -- Big-number mods may pass objects with :to_number(); convert when possible.
        if type(num) == "table" and type(num.to_number) == "function" then
            local ok, v = pcall(function() return num:to_number() end)
            if ok and type(v) == "number" then
                num = v
            else
                return tostring(num), true
            end
        else
            return tostring(num), true
        end
    end

    -- Preserve runtime-specific NaN string behavior (nan/-nan) by letting game format it.
    if is_nan(num) then
        return num, false
    end

    if is_inf(num) then
        if should_clamp_infinity() then
            num = num < 0 and -M.MAX_SAFE_SCORE or M.MAX_SAFE_SCORE
        else
            return num, false
        end
    end

    local abs_num = math.abs(num)
    if abs_num >= M.LARGE_NUMBER_THRESHOLD then
        return _format_scientific(num), true
    end

    return num, false
end

return M
