--- Save Rewinder - Logger.lua
--
-- Centralized logging utility. Provides a factory to create module-specific loggers.

local M = {}

M._prefix = "[Rewinder]"

-- Tags that always log (regardless of debug_saves config)
M._always_log_tags = {
    step = true,
    list = true,
    error = true,
    prune = true,
    restore = true,
    monitor = true,
}

--- Create a logger for a specific module
-- @param module_name string: Name of the module (e.g., "SaveManager", "FileIO")
-- @return function: A debug_log(tag, msg) function for that module
function M.create(module_name)
    return function(tag, msg)
        -- Check if we should log
        local always_log = M._always_log_tags[tag]
        if not always_log then
            if not REWINDER or not REWINDER.config or not REWINDER.config.debug_saves then
                return
            end
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
    local always_log = M._always_log_tags[tag]
    if not always_log then
        if not REWINDER or not REWINDER.config or not REWINDER.config.debug_saves then
            return
        end
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

