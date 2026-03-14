--- Save Rewinder - QueueService.lua
--
-- Ring buffer queue, flush orchestration, and sync fallback for rewinder saves.
-- Consolidates queue infrastructure that was previously split across
-- SaveManager.lua, GamePatches.lua, and ButtonCallbacks.lua.

return function(ctx)
   local M = ctx.M
   local Logger = ctx.Logger
   local FileIO = ctx.FileIO

   local api = {}

   -- ── Utilities ──────────────────────────────────────────────────────────

   local function _queue_depth()
      return math.max(0, (M._rw_queue_tail or 0) - (M._rw_queue_head or 1) + 1)
   end

   local function _basename(path)
      if not path then return nil end
      return tostring(path):match("[^/]+$") or tostring(path)
   end

   -- ── Freeze / Deep Copy (queue payload preparation) ─────────────────────

   local function _deep_copy(tbl, seen)
      if type(tbl) ~= "table" then return tbl end
      if seen and seen[tbl] then return seen[tbl] end
      seen = seen or {}
      -- Metatables intentionally skipped: save data contains only plain data tables.
      local copy = {}
      seen[tbl] = copy
      for key, value in pairs(tbl) do
         copy[key] = _deep_copy(value, seen)
      end
      return copy
   end

   local function _freeze_save_table(save_table)
      if type(save_table) ~= "table" then return save_table end
      -- Preserve any unknown top-level fields from other mods.
      local frozen = {}
      for key, value in pairs(save_table) do
         frozen[key] = value
      end
      -- Freeze sections that contain live refs from :save() outputs.
      frozen.cardAreas = _deep_copy(save_table.cardAreas)
      frozen.tags = _deep_copy(save_table.tags)
      frozen.BLIND = _deep_copy(save_table.BLIND)
      frozen.BACK = _deep_copy(save_table.BACK)
      return frozen
   end

   -- Expose on M so CreateService can call M.freeze_save_table(run_data)
   M.freeze_save_table = _freeze_save_table

   -- ── Health Tracking ────────────────────────────────────────────────────

   function M.mark_flush_healthy(result)
      if not REWINDER or type(result) ~= "table" then return end
      if result.status == "ok" then
         REWINDER._rw_flush_verified = true
         REWINDER._rw_first_flush_time = nil
      end
   end

   -- ── Request Building ───────────────────────────────────────────────────

   function M.build_rewinder_push_request(item, config)
      if not item then return nil end
      local path = item.rewinder_copy_path or item.path
      if not path then return nil end
      return {
         save_table = item.save_table,
         path = path,
         file = item.file or _basename(path),
         clamp_infinity_scores = config and config.clamp_infinity_scores,
         big_backend_mode = (config and config.big_backend_mode)
            or (NaNProtection and NaNProtection.has_big_backend and NaNProtection.has_big_backend()),
         meta_path = item.rewinder_meta_path or item.meta_path,
         meta_data = item.rewinder_meta_data or item.meta_data,
      }
   end

   -- ── Sync Fallback ──────────────────────────────────────────────────────

   function M.sync_write_rewinder_item(item, log_prefix)
      if not item or not item.save_table or not item.rewinder_copy_path then return false end
      local prefix = tostring(log_prefix or "rewinder sync fallback")
      local write_ok, write_err = FileIO.write_save_file(item.save_table, item.rewinder_copy_path)
      if not write_ok then
         M.debug_log("error", prefix .. " save failed: " .. tostring(write_err))
         return false
      end
      if item.rewinder_meta_path and item.rewinder_meta_data then
         local ok_meta, err_meta = pcall(love.filesystem.write, item.rewinder_meta_path, item.rewinder_meta_data)
         if not ok_meta then
            M.debug_log("warning", prefix .. " meta failed: " .. tostring(err_meta))
         end
      end
      return true
   end

   local function _sync_write_rewinder_item(item)
      return M.sync_write_rewinder_item(item, "flush_all sync fallback")
   end

   -- ── Ring Buffer Queue ──────────────────────────────────────────────────

   function M.enqueue_pending_rewinder(item)
      if not item then return false end

      if _queue_depth() >= 16 then
         return false
      end
      local now = (love and love.timer and love.timer.getTime) and love.timer.getTime() or nil
      item.created_at = item.created_at or now or os.clock()
      M._rw_queue_tail = (M._rw_queue_tail or 0) + 1
      M._rw_queue[M._rw_queue_tail] = item
      return true
   end

   function M.rewinder_queue_depth()
      return _queue_depth()
   end

   function M.dequeue_pending_rewinder()
      while (M._rw_queue_head or 1) <= (M._rw_queue_tail or 0) do
         local item = M._rw_queue[M._rw_queue_head]
         M._rw_queue[M._rw_queue_head] = nil
         M._rw_queue_head = M._rw_queue_head + 1
         if item and item.file and M._rw_cancelled_files[item.file] then
            M._rw_cancelled_files[item.file] = nil
            item.save_table = nil
         else
            return item
         end
      end
      return nil
   end

   function M.discard_pending_rewinder()
      M._rw_queue = {}
      M._rw_queue_head = 1
      M._rw_queue_tail = 0
      M._rw_cancelled_files = {}
   end

   function M.cancel_pending_rewinder_by_files(files)
      if not files then return end
      for _, file in ipairs(files) do
         if file then
            M._rw_cancelled_files[file] = true
         end
      end
   end

   function M.invalidate_queue_and_thread()
      if M.discard_pending_rewinder then
         M.discard_pending_rewinder()
      end
      if REWINDER and REWINDER._SaveThread and REWINDER._SaveThread.invalidate_pending then
         REWINDER._SaveThread.invalidate_pending()
      end
   end

   -- ── Blocking Flush (used pre-load, pre-overlay) ────────────────────────

   local function _drain_rewinder_queue_sync(reason)
      local drained = 0
      while M.rewinder_queue_depth and M.rewinder_queue_depth() > 0 do
         local item = M.dequeue_pending_rewinder and M.dequeue_pending_rewinder() or nil
         if item then
            _sync_write_rewinder_item(item)
            item.save_table = nil
            drained = drained + 1
         end
      end
      if drained > 0 then
         M.debug_log("warning", string.format("flush_all: sync-drained=%d (%s)", drained, tostring(reason)))
      end
   end

   function M.flush_all_pending_rewinder(reason)
      local SaveThread = REWINDER and REWINDER._SaveThread
      if not SaveThread then
         _drain_rewinder_queue_sync(reason or "save_thread_missing")
         return
      end
      if SaveThread.start and not SaveThread.start() then
         _drain_rewinder_queue_sync(reason or "save_thread_unavailable")
         return
      end
      if SaveThread.check_errors then SaveThread.check_errors() end

      local waiting = {}
      local pushed = 0
      local completed = 0
      local config = REWINDER and REWINDER.config

      while M.rewinder_queue_depth() > 0 do
         local item = M.dequeue_pending_rewinder()
         if item and item.save_table and item.rewinder_copy_path then
            local req = M.build_rewinder_push_request(item, config)
            local file = req and req.file or item.file or _basename(item.rewinder_copy_path)
            local ok = req and SaveThread.push_save(req)

            if ok then
               waiting[file] = waiting[file] or {}
               table.insert(waiting[file], item)
               pushed = pushed + 1
            else
               _sync_write_rewinder_item(item)
               item.save_table = nil
            end
         end
      end

      if pushed <= 0 then return end

      local timeout = love.timer.getTime() + 3
      while completed < pushed and love.timer.getTime() < timeout do
         local result = SaveThread.pop_result and SaveThread.pop_result() or nil
         if result then
            M.mark_flush_healthy(result)
            local bucket = result.file and waiting[result.file] or nil
            local item = bucket and table.remove(bucket, 1) or nil
            if bucket and #bucket == 0 then
               waiting[result.file] = nil
            end
            if item then
               if result.status ~= "ok" then
                  M.debug_log("warning", string.format("flush_all: non-ok result file=%s status=%s", tostring(result.file), tostring(result.status)))
                  _sync_write_rewinder_item(item)
               end
               item.save_table = nil
               completed = completed + 1
            end
         else
            love.timer.sleep(0.01)
         end
      end

      for _, bucket in pairs(waiting) do
         for i = 1, #bucket do
            local item = bucket[i]
            _sync_write_rewinder_item(item)
            item.save_table = nil
            completed = completed + 1
         end
      end

      if Logger.is_verbose() then
         M.debug_log("debug", string.format("flush_all_rewinder(%s): pushed=%d completed=%d", tostring(reason), pushed, completed))
      end
   end

   -- ── Trickle Flush (per-frame, called from lovely.toml patch) ───────────

   local function _activate_fallback(reason)
      if REWINDER._rw_flush_fallback then return end
      REWINDER._rw_flush_fallback = true
      M.debug_log("warning", "SaveThread fallback activated: " .. tostring(reason))
      while M.rewinder_queue_depth() > 0 do
         local item = M.dequeue_pending_rewinder()
         M.sync_write_rewinder_item(item, "fallback sync")
         if item then item.save_table = nil end
      end
   end

   local function _tiered_trickle_policy(queue_depth, now, last_flush_time, prefix, tiers)
      if queue_depth <= 0 then
         return 0, prefix .. "_empty"
      end

      local selected = tiers[#tiers]
      for i = 1, #tiers do
         local tier = tiers[i]
         if queue_depth <= tier.max_depth then
            selected = tier
            break
         end
      end

      if (now - (last_flush_time or 0)) < (selected.cooldown or 0) then
         return 0, prefix .. "_cooldown"
      end
      return selected.budget or 1, prefix .. "_" .. tostring(selected.mode or "trickle")
   end

   local function _compute_flush_policy(queue_depth)
      local STATES = G and G.STATES
      local state = G and G.STATE
      local now = love.timer.getTime()

      if STATES and state == STATES.SHOP then
         return _tiered_trickle_policy(queue_depth, now, REWINDER._rw_last_shop_flush_t, "shop", {
            { max_depth = 5, cooldown = 0.90, mode = "trickle", budget = 1 },
            { max_depth = 9, cooldown = 0.55, mode = "soft", budget = 1 },
            { max_depth = math.huge, cooldown = 0.35, mode = "controlled", budget = 1 },
         })
      end

      local is_play_hot = false
      if STATES then
         if state == STATES.SELECTING_HAND then
            local action = G and G.action
            if type(action) == "table" and action.type == "play" then
               is_play_hot = true
            end
         elseif state == STATES.ROUND_EVAL or state == STATES.HAND_PLAYED then
            is_play_hot = true
         end
      end
      if is_play_hot then
         return _tiered_trickle_policy(queue_depth, now, REWINDER._rw_last_play_flush_t, "play", {
            { max_depth = 3, cooldown = 0.90, mode = "trickle", budget = 1 },
            { max_depth = 7, cooldown = 0.55, mode = "soft", budget = 1 },
            { max_depth = math.huge, cooldown = 0.30, mode = "controlled", budget = 1 },
         })
      end

      return 2, "default"
   end

   function M.flush_trickle_pending()
      if not M.rewinder_queue_depth or M.rewinder_queue_depth() <= 0 then return end
      local SaveThread = REWINDER and REWINDER._SaveThread
      if not SaveThread then
         _activate_fallback("save_thread_missing")
         return
      end

      if SaveThread.check_errors then SaveThread.check_errors() end
      if SaveThread.is_running and not SaveThread.is_running() then
         M.debug_log("warning", "SaveThread not running, attempting restart")
         if not (SaveThread.start and SaveThread.start()) then
            _activate_fallback("thread_dead")
            return
         end
      end

      if SaveThread.has_pending_results and SaveThread.pop_result then
         while SaveThread.has_pending_results() do
            local result = SaveThread.pop_result()
            if result and result.status == "error" then
               _activate_fallback("thread_error")
               return
            end
            if result
               and not REWINDER._rw_flush_verified
               and REWINDER._rw_first_flush_file
               and result.file == REWINDER._rw_first_flush_file
               and result.status == "ok" then
               if M.mark_flush_healthy then
                  M.mark_flush_healthy(result)
               else
                  REWINDER._rw_flush_verified = true
               end
            end
         end
      end

      if not REWINDER._rw_flush_verified
         and REWINDER._rw_first_flush_time
         and (love.timer.getTime() - REWINDER._rw_first_flush_time) > 5 then
         _activate_fallback("no_done_response")
         return
      end

      local queue_depth = M.rewinder_queue_depth()
      local flush_budget, flush_mode = _compute_flush_policy(queue_depth)
      if flush_budget <= 0 then return end

      local config = REWINDER and REWINDER.config
      for _ = 1, flush_budget do
         if M.rewinder_queue_depth() <= 0 then break end
         local item = M.dequeue_pending_rewinder()
         if not item or not item.save_table or not item.rewinder_copy_path then break end
         local req = M.build_rewinder_push_request(item, config)
         if not req or not req.path or not req.save_table then
            M.sync_write_rewinder_item(item, "fallback sync")
            item.save_table = nil
            return
         end
         local file = (req and req.file) or item.file or (item.rewinder_copy_path and item.rewinder_copy_path:match("[^/]+$"))
         local push_t0 = (config and config.debug_saves) and love.timer.getTime() or nil
         local ok = (SaveThread.push_save and req and req.path and req.save_table) and SaveThread.push_save(req)
         if ok and not REWINDER._rw_first_flush_file then
            REWINDER._rw_first_flush_file = file
            REWINDER._rw_first_flush_time = love.timer.getTime()
         end
         local mode = tostring(flush_mode or "")
         if ok and string.sub(mode, 1, 5) == "shop_" then
            REWINDER._rw_last_shop_flush_t = love.timer.getTime()
         elseif ok and string.sub(mode, 1, 5) == "play_" then
            REWINDER._rw_last_play_flush_t = love.timer.getTime()
         end
         if not ok then
            _activate_fallback("push_failed")
            M.sync_write_rewinder_item(item, "fallback sync")
            item.save_table = nil
            return
         end
         item.save_table = nil
         if push_t0 then
            M.debug_log("debug", string.format("rewinder_flush[%s]: %.2fms q:%d",
               tostring(flush_mode), (love.timer.getTime() - push_t0) * 1000, M.rewinder_queue_depth()))
         end
      end
   end

   return api
end
