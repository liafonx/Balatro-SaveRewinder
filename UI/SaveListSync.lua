--- Save Rewinder - UI/SaveListSync.lua
--
-- Cooperative async queue drain engine for the saves overlay.
-- Drains queued rewinder saves one-per-tick while showing a loading state,
-- then triggers an overlay rebuild when complete.

if not REWINDER then REWINDER = {} end

local Logger = require("Logger")
local UIShared = require("UIShared")
local log = Logger.create("SaveListSync")

local M = {}

local function _handle_sync_result(sync_state, result)
   if not (result and sync_state and sync_state.waiting) then return end

   if sync_state.SM and sync_state.SM.mark_flush_healthy then
      sync_state.SM.mark_flush_healthy(result)
   elseif result.status == "ok" then
      REWINDER._rw_flush_verified = true
      REWINDER._rw_first_flush_time = nil
   end

   local bucket = result.file and sync_state.waiting[result.file] or nil
   if not bucket or #bucket == 0 then return end
   local item = table.remove(bucket, 1)
   if #bucket == 0 then
      sync_state.waiting[result.file] = nil
   end

   sync_state.inflight = math.max(0, (sync_state.inflight or 0) - 1)
   sync_state.completed = (sync_state.completed or 0) + 1
   if result.status ~= "ok" and sync_state.SM and sync_state.SM.sync_write_rewinder_item then
      sync_state.SM.sync_write_rewinder_item(item, "overlay async non-ok fallback")
   end
   item.save_table = nil
end

local function _finish(sync_state)
   if REWINDER._saves_open_sync ~= sync_state then return end
   REWINDER._saves_open_sync = nil
   if sync_state.on_complete then sync_state.on_complete() end
end

local function _tick(sync_state)
   if REWINDER._saves_open_sync ~= sync_state then return end

   local SM = sync_state.SM
   if not (SM and SM.rewinder_queue_depth and SM.dequeue_pending_rewinder) then
      REWINDER._saves_open_sync = nil
      return
   end
   if not UIShared.is_saves_overlay_open() then
      REWINDER._saves_open_sync = nil
      return
   end

   local SaveThread = REWINDER and REWINDER._SaveThread
   if not SaveThread or (SaveThread.start and not SaveThread.start()) then
      local item = SM.dequeue_pending_rewinder and SM.dequeue_pending_rewinder() or nil
      if item and SM.sync_write_rewinder_item then
         SM.sync_write_rewinder_item(item, "overlay async fallback")
         item.save_table = nil
      end
   else
      if SaveThread.check_errors then SaveThread.check_errors() end

      local push_budget = sync_state.push_budget or 1
      local pushed_this_tick = 0
      local config = REWINDER and REWINDER.config
      while pushed_this_tick < push_budget and SM.rewinder_queue_depth() > 0 do
         local item = SM.dequeue_pending_rewinder()
         if not item or not item.save_table or not item.rewinder_copy_path then
            break
         end

         local req = SM.build_rewinder_push_request and SM.build_rewinder_push_request(item, config)
         if not req or not req.path or not req.save_table then
            if SM.sync_write_rewinder_item then
               SM.sync_write_rewinder_item(item, "overlay async malformed request fallback")
            end
            item.save_table = nil
            pushed_this_tick = pushed_this_tick + 1
         else
            local ok = SaveThread.push_save and SaveThread.push_save(req)
            if ok then
               local file = req.file or item.file or "unknown"
               sync_state.waiting[file] = sync_state.waiting[file] or {}
               table.insert(sync_state.waiting[file], item)
               sync_state.inflight = (sync_state.inflight or 0) + 1
               sync_state.pushed = (sync_state.pushed or 0) + 1
            else
               if SM.sync_write_rewinder_item then
                  SM.sync_write_rewinder_item(item, "overlay async push fallback")
               end
               item.save_table = nil
            end
            pushed_this_tick = pushed_this_tick + 1
         end
      end

      local result_budget = sync_state.result_budget or 8
      local got_result = 0
      while got_result < result_budget do
         local result = SaveThread.pop_result and SaveThread.pop_result() or nil
         if not result then break end
         _handle_sync_result(sync_state, result)
         got_result = got_result + 1
      end
   end

   local remaining_queue = SM.rewinder_queue_depth()
   local remaining_inflight = sync_state.inflight or 0
   local now_t = (love and love.timer and love.timer.getTime) and love.timer.getTime() or nil
   if now_t and sync_state.started_at and (now_t - sync_state.started_at) > 6 and remaining_inflight > 0 then
      log("warning", string.format(
         "Saves UI async sync timeout: inflight=%d queue=%d; forcing blocking drain",
         remaining_inflight, remaining_queue
      ))
      if SM.flush_all_pending_rewinder then
         SM.flush_all_pending_rewinder("overlay_open_timeout")
      end
      sync_state.inflight = 0
      remaining_inflight = 0
      remaining_queue = SM.rewinder_queue_depth()
   end

   if remaining_queue <= 0 and remaining_inflight <= 0 then
      local t1 = (love and love.timer and love.timer.getTime) and love.timer.getTime() or nil
      local elapsed_ms = 0
      if sync_state.started_at and t1 then
         elapsed_ms = (t1 - sync_state.started_at) * 1000
      end
      log("debug", string.format(
         "Saves UI async sync complete: pushed=%d completed=%d elapsed=%.2fms",
         sync_state.pushed or 0, sync_state.completed or 0, elapsed_ms
      ))
      _finish(sync_state)
      return
   end

   UIShared.schedule_after_delay(0.01, function()
      _tick(sync_state)
   end)
end

function M.start(queue_depth, on_complete)
   local SM = REWINDER and REWINDER._SaveManager
   if not (SM and SM.flush_all_pending_rewinder) then return false end

   local sync_state = {
      SM = SM,
      waiting = {},
      inflight = 0,
      pushed = 0,
      completed = 0,
      push_budget = 1,
      result_budget = 8,
      started_at = (love and love.timer and love.timer.getTime) and love.timer.getTime() or nil,
      queued_initial = queue_depth or 0,
      on_complete = on_complete,
   }
   REWINDER._saves_open_sync = sync_state

   UIShared.schedule_after_delay(0.05, function()
      _tick(sync_state)
   end)
   return true
end

-- Expose private helper for unit tests.
M._handle_sync_result = _handle_sync_result

function M.cancel()
   local sync_state = REWINDER._saves_open_sync
   REWINDER._saves_open_sync = nil
   if not sync_state then return end

   -- Do not drain SaveThread DONE channel here.
   -- That channel is global and may contain results from non-overlay save paths.
   -- Force-sync only this overlay sync's waiting items to prevent in-flight loss.
   local forced = 0
   if sync_state.waiting and sync_state.SM and sync_state.SM.sync_write_rewinder_item then
      for _, bucket in pairs(sync_state.waiting) do
         for _, item in ipairs(bucket) do
            if item and item.save_table then
               sync_state.SM.sync_write_rewinder_item(item, "overlay cancel fallback")
               item.save_table = nil
               forced = forced + 1
            end
         end
      end
   end
   sync_state.waiting = {}
   sync_state.inflight = 0
   if forced > 0 then
      log("debug", string.format("Saves UI cancel fallback sync writes=%d", forced))
   end
end

return M
