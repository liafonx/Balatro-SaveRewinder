--- Save Rewinder - Logger.lua
--
-- Centralized logging utility. Provides a factory to create module-specific loggers.
--
-- Log Levels:
--   - "info": Verbose logs, only shown when rewinder_debug_saves is ENABLED
--   - Always-log tags (step, list, error, prune, restore, monitor): Always shown
--   - Other tags: Only shown when rewinder_debug_saves is ENABLED

local M = {}

M._prefix = "[Rewinder]"

-- Tags that always log (regardless of debug_saves config)
-- These are critical operational logs that should always be visible
M._always_log_tags = {
    step = true,
    list = true,
    error = true,
    prune = true,
    restore = true,
    monitor = true,
}

--- Check if a tag should be logged based on current config
-- @param tag string: The log tag
-- @return boolean: true if this tag should be logged
local function should_log(tag)
    -- Always-log tags bypass config check
    if M._always_log_tags[tag] then
        return true
    end
    -- All other tags (including "info") require debug_saves to be enabled
    if REWINDER and REWINDER.config and REWINDER.config.debug_saves then
        return true
    end
    return false
end

--- Create a logger for a specific module
-- @param module_name string: Name of the module (e.g., "SaveManager", "FileIO")
-- @return function: A debug_log(tag, msg) function for that module
function M.create(module_name)
    return function(tag, msg)
        -- Check if we should log this tag
        if not should_log(tag) then
            return
        end

        -- Format message
        local full_msg
        if module_name and module_name ~= "" then
            if tag and tag ~= "" then
                full_msg = M._prefix .. "[" .. module_name .. "][" .. tostring(tag) .. "] " .. tostring(msg)
            else
                full_msg = M._prefix .. "[" .. module_name .. "] " .. tostring(msg)
            end
        else
            if tag and tag ~= "" then
                full_msg = M._prefix .. "[" .. tostring(tag) .. "] " .. tostring(msg)
            else
                full_msg = M._prefix .. " " .. tostring(msg)
            end
        end

        -- Protected print (prevents crash if another mod has buggy print hook)
        pcall(print, full_msg)
    end
end

--- Simple log function (no module name, used by Init.lua)
-- @param tag string: Log category tag
-- @param msg string: Log message
function M.log(tag, msg)
    if not should_log(tag) then
        return
    end

    local full_msg
    if tag and tag ~= "" then
        full_msg = M._prefix .. "[" .. tostring(tag) .. "] " .. tostring(msg)
    else
        full_msg = M._prefix .. " " .. tostring(msg)
    end

    pcall(print, full_msg)
end

return M

