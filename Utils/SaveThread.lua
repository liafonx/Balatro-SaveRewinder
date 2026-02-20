--- Save Rewinder - SaveThread.lua
--
-- Manages a background Love2D thread for save file I/O.
-- Moves expensive STR_PACK + compress + file writes off the main thread.
-- Main thread cost: ~5-10ms (channel:push C-level serialization)
-- Thread cost: ~51ms (STR_PACK + compress + write, invisible to user)

local Logger = require("Logger")
local M = {}
M.debug_log = Logger.create("SaveThread")

-- Thread code runs in an isolated Lua state with its own globals.
-- It requires game engine modules for STR_PACK and file I/O.
-- NaN/inf sanitization in string_packer is patched by lovely.toml.
-- This thread sets a lightweight REWINDER.config shim per request so
-- clamp_infinity_scores and big-backend mode match main-thread config.
local THREAD_CODE = [[
require("love.filesystem")
require("love.data")
require("love.thread")

-- Game engine dependencies for STR_PACK
require("engine.object")
require("engine.string_packer")

local SAVE_CH = love.thread.getChannel("rewinder_save")
local ERR_CH  = love.thread.getChannel("rewinder_errors")
local DONE_CH = love.thread.getChannel("rewinder_save_done")
local GEN_CH  = love.thread.getChannel("rewinder_save_generation")
local generation = 0

-- Thread-local REWINDER shim so patched string_packer can read clamp config.
local rewinder_config = { clamp_infinity_scores = false, big_backend_mode = false }
REWINDER = { config = rewinder_config }

local function refresh_generation()
    while GEN_CH:getCount() > 0 do
        local g = GEN_CH:pop()
        if type(g) == "number" then
            generation = g
        end
    end
end

while true do
    local req = SAVE_CH:demand()  -- Block until work arrives
    if not req or req.type == "kill" then break end

    refresh_generation()
    local req_generation = tonumber(req.generation) or 0
    if req_generation < generation then
        DONE_CH:push({
            status = "stale",
            file = req.file,
            generation = req_generation,
        })
    else
        local ok, err = pcall(function()
            rewinder_config.clamp_infinity_scores = (req.clamp_infinity_scores == true)
            rewinder_config.big_backend_mode = (req.big_backend_mode == true)

            -- STR_PACK + compress (the expensive work, now off main thread)
            local packed = STR_PACK(req.save_table)
            local compressed = love.data.compress("string", "deflate", packed, 1)

            -- A newer generation may be published while packing/compressing.
            refresh_generation()
            if req_generation < generation then
                DONE_CH:push({
                    status = "stale",
                    file = req.file,
                    generation = req_generation,
                })
                return
            end

            -- Write numbered save file
            local ok_write = love.filesystem.write(req.path, compressed)
            if not ok_write then
                error("write failed for " .. tostring(req.path))
            end

            -- Write save.jkr to keep _rewinder_id aligned
            if req.main_save_path then
                local ok_main = love.filesystem.write(req.main_save_path, compressed)
                if not ok_main then
                    error("write failed for " .. tostring(req.main_save_path))
                end
            end

            -- Optional metadata sidecar write
            if req.meta_path and req.meta_data then
                local ok_meta = love.filesystem.write(req.meta_path, req.meta_data)
                if not ok_meta then
                    error("write failed for " .. tostring(req.meta_path))
                end
            end

            DONE_CH:push({
                status = "ok",
                file = req.file,
                generation = req_generation,
            })
        end)

        if not ok then
            ERR_CH:push(tostring(err))
            DONE_CH:push({
                status = "error",
                file = req.file,
                generation = req_generation,
                error = tostring(err),
            })
        end
    end
end
]]

M._thread = nil
M._channel = nil
M._err_channel = nil
M._done_channel = nil
M._gen_channel = nil
M._generation = 0

local function _clear_channel(channel)
    if not channel then return end
    while channel:getCount() > 0 do
        channel:pop()
    end
end

local function _publish_generation()
    if not M._gen_channel then return end
    _clear_channel(M._gen_channel)
    M._gen_channel:push(M._generation or 0)
end

--- Start the save I/O thread.
-- Safe to call multiple times; restarts if thread died.
function M.start()
    if M._thread and M._thread:isRunning() then return true end

    -- Check if previous thread died with an error
    if M._thread then
        local thread_err = M._thread:getError()
        if thread_err then
            M.debug_log("error", "Previous save thread died: " .. tostring(thread_err))
        end
    end

    local ok, err = pcall(function()
        M._thread = love.thread.newThread(THREAD_CODE)
        M._channel = love.thread.getChannel("rewinder_save")
        M._err_channel = love.thread.getChannel("rewinder_errors")
        M._done_channel = love.thread.getChannel("rewinder_save_done")
        M._gen_channel = love.thread.getChannel("rewinder_save_generation")
        M._thread:start()
        _publish_generation()
    end)

    if not ok then
        M.debug_log("error", "Failed to start save thread: " .. tostring(err))
        M._thread = nil
        return false
    end

    M.debug_log("info", "Save I/O thread started")
    return true
end

--- Push a save request to the background thread.
-- Returns true if pushed successfully, false if thread unavailable
-- (caller should fall back to synchronous write).
function M.push_save(save_table, path, main_save_path, file, clamp_infinity_scores, big_backend_mode)
    -- Auto-restart if thread died
    if not M._thread or not M._thread:isRunning() then
        if not M.start() then return false end
    end

    local opts
    if type(save_table) == "table" and path == nil then
        opts = save_table
    else
        -- Backward-compatible positional signature.
        opts = {
            save_table = save_table,
            path = path,
            main_save_path = main_save_path,
            file = file,
            clamp_infinity_scores = clamp_infinity_scores,
            big_backend_mode = big_backend_mode,
        }
    end

    local ok, err = pcall(M._channel.push, M._channel, {
        save_table = opts.save_table,
        path = opts.path,
        main_save_path = opts.main_save_path,
        file = opts.file,
        clamp_infinity_scores = (opts.clamp_infinity_scores == true),
        big_backend_mode = (opts.big_backend_mode == true),
        meta_path = opts.meta_path,
        meta_data = opts.meta_data,
        generation = M._generation or 0,
    })

    if not ok then
        M.debug_log("error", "channel:push failed: " .. tostring(err))
        return false
    end

    return true
end

--- Invalidate queued/ongoing save requests.
-- Bumps generation so stale requests are ignored by the worker.
-- Also clears queued requests immediately from main-thread channel.
function M.invalidate_pending()
    M._generation = (M._generation or 0) + 1
    _publish_generation()

    if not M._channel then return end
    local dropped = 0
    while M._channel:getCount() > 0 do
        local req = M._channel:pop()
        if req and req.type ~= "kill" then
            dropped = dropped + 1
            if req.file and M._done_channel then
                M._done_channel:push({
                    status = "stale",
                    file = req.file,
                    generation = req.generation or 0,
                })
            end
        end
    end

    if dropped > 0 then
        M.debug_log("debug", "Invalidated queued saves: " .. tostring(dropped))
    end
end

--- Check and log any errors from the background thread.
-- Call periodically (e.g., at the start of create_save).
function M.check_errors()
    if not M._err_channel then return end
    while M._err_channel:getCount() > 0 do
        local err = M._err_channel:pop()
        if err then
            M.debug_log("error", "Save thread: " .. tostring(err))
        end
    end
end

--- Pop one completion result from save thread (or nil if none).
function M.pop_result()
    if not M._done_channel then return nil end
    return M._done_channel:pop()
end

function M.has_pending_results()
    return M._done_channel ~= nil and M._done_channel:getCount() > 0
end

--- Gracefully stop the save thread.
function M.stop()
    if M._channel and M._thread and M._thread:isRunning() then
        M._channel:push({ type = "kill" })
    end
    M._thread = nil
end

--- Check if the thread is currently running.
function M.is_running()
    return M._thread ~= nil and M._thread:isRunning()
end

return M
