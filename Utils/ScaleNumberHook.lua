--- Scale Number Hook
-- Wraps scale_number() to return base scale for very large numbers
-- Must be INSTALLED after game's button_callbacks.lua defines scale_number
-- The module itself can load early, but install() must be called after scale_number exists
--
-- NOTE: This is a lovely module, accessed via require("ScaleNumberHook"), NOT a global!

local M = {}

-- Flag to track if hook is installed
M.installed = false

-- Threshold above which we bypass scale_number and return the base scale directly
M.LARGE_NUMBER_THRESHOLD = 1e290

local function should_use_base_scale(v)
    if type(v) ~= "number" then
        return false
    end
    if v ~= v then
        return true -- NaN
    end
    if v == math.huge or v == -math.huge then
        return true -- inf
    end
    return math.abs(v) > M.LARGE_NUMBER_THRESHOLD
end

function M.install()
    -- Already installed?
    if M.installed then
        return true
    end

    -- Wait for scale_number to be defined
    if not scale_number then
        return false
    end

    -- Save original (might be Talisman's wrapper or the original)
    local _original_scale_number = scale_number

    -- Replace with wrapper that returns base scale for very large numbers
    scale_number = function(number, scale, max)
        -- Keep base scale for non-finite and very large values.
        -- This keeps overflow text (e.g., naneinf) readable on Continue screen.
        if should_use_base_scale(number) then
            return scale
        end

        return _original_scale_number(number, scale, max)
    end

    M.installed = true
    return true
end

return M
