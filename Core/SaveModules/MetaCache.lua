local function _normalize_custom_state_name(name)
   if type(name) ~= "string" then return nil end
   local trimmed = name:match("^%s*(.-)%s*$")
   if trimmed == "" then return nil end
   return trimmed
end

return function(ctx)
   local M = ctx.M
   local S = ctx.S
   local E = ctx.E
   local MetaFile = ctx.MetaFile
   local Logger = ctx.Logger
   local index = ctx.index

   local api = {}

   local function _apply_meta_to_entry(entry, meta)
      if not entry or not meta then return end
      entry[E.ENTRY_MONEY] = meta.money
      entry[E.ENTRY_SIGNATURE] = meta.signature
      entry[E.ENTRY_DISCARDS_USED] = meta.discards_used
      entry[E.ENTRY_HANDS_PLAYED] = meta.hands_played
      entry[E.ENTRY_BLIND_IDX] = meta.blind_idx
      entry[E.ENTRY_DISPLAY_TYPE] = meta.display_type
      entry[E.ENTRY_ORDINAL] = meta.ordinal
      entry[E.ENTRY_IS_KEY] = meta.is_key or false
   end

   local function _clear_entry_meta(entry)
      if not entry then return end
      entry[E.ENTRY_MONEY] = nil
      entry[E.ENTRY_SIGNATURE] = nil
      entry[E.ENTRY_DISCARDS_USED] = nil
      entry[E.ENTRY_HANDS_PLAYED] = nil
      entry[E.ENTRY_BLIND_IDX] = nil
      entry[E.ENTRY_DISPLAY_TYPE] = nil
      entry[E.ENTRY_ORDINAL] = nil
      entry[E.ENTRY_IS_KEY] = nil
   end

   local function _drop_meta(file)
      if not file or not S.meta_cache[file] then return end
      S.meta_cache[file] = nil
      S.meta_cache_size = math.max(0, S.meta_cache_size - 1)
      S.meta_lru_ts[file] = nil
      if S.save_cache_by_file then
         local entry = S.save_cache_by_file[file]
         if entry then _clear_entry_meta(entry) end
      end
   end

   local function _is_pinned(file)
      local current = M._last_loaded_file or (G and G.SAVED_GAME and G.SAVED_GAME._file) or nil
      return file and file == current
   end

   local function _evict_meta_if_needed()
      local evicted = 0
      if M._overlay_open then
         if S.meta_cache_size > S.meta_cache_limit then
            S.meta_cache_limit = S.meta_cache_size
         end
         return
      end

      while S.meta_cache_size > S.meta_cache_limit do
         local candidate, min_ts = nil, nil
         for file, ts in pairs(S.meta_lru_ts) do
            if not _is_pinned(file) and (not min_ts or ts < min_ts) then
               candidate, min_ts = file, ts
            end
         end
         if not candidate then break end
         _drop_meta(candidate)
         evicted = evicted + 1
      end

      if evicted > 0 and Logger.is_verbose() then
         local now = love and love.timer and love.timer.getTime() or 0
         if (now - S.last_eviction_log_time) > 0.5 or evicted >= 4 then
            M.debug_log("debug", "Meta cache evicted=" .. tostring(evicted))
            S.last_eviction_log_time = now
         end
      end
   end

   local function _touch_lru(file)
      if not file then return end
      S.meta_lru_clock = S.meta_lru_clock + 1
      S.meta_lru_ts[file] = S.meta_lru_clock
   end

   local function _cache_meta(file, meta)
      if not file or not meta then return end
      if not S.meta_cache[file] then
         S.meta_cache_size = S.meta_cache_size + 1
      end
      S.meta_cache[file] = meta
      _touch_lru(file)
      _evict_meta_if_needed()
   end

   local function _purge_meta_cache()
      if not S.save_cache_by_file then return end
      for file in pairs(S.meta_cache) do
         if not S.save_cache_by_file[file] then
            _drop_meta(file)
         end
      end
   end

   local function _list_and_sort_entries()
      local dir = M.get_save_dir()
      local files = love.filesystem.getDirectoryItems(dir)
      local entries = {}
      for _, file in ipairs(files) do
         if file:match("%.jkr$") then
            local full = dir .. "/" .. file
            local info = love.filesystem.getInfo(full)
            if info and info.type == "file" then
               local ante_str, round_str, index_str = file:match("^(%d+)%-(%d+)%-(%d+)%.jkr$")
               local ante = tonumber(ante_str) or 0
               local round = tonumber(round_str) or 0
               local index_id = tonumber(index_str) or 0
               entries[#entries + 1] = {
                  file, ante, round, index_id,
                  nil, nil, nil, nil, false, nil, nil, nil, nil,
               }
            end
         end
      end

      table.sort(entries, function(a, b)
         return a[E.ENTRY_INDEX] < b[E.ENTRY_INDEX]
      end)
      return entries
   end

   function M.set_overlay_open(is_open)
      M._overlay_open = is_open and true or false
      if REWINDER then REWINDER.saves_open = M._overlay_open end
      if not M._overlay_open then
         S.meta_cache_limit = M.META_CACHE_BASE_LIMIT
         _evict_meta_if_needed()
      end
   end

   function M.is_overlay_open()
      return M._overlay_open
   end

   function M.ensure_meta_window(center_idx, window_size, force_log, suppress_log)
      local entries = M.get_save_files()
      if not entries or #entries == 0 then return end
      local total = #entries
      local size = window_size or M.META_CACHE_BASE_LIMIT
      local half = math.floor(size / 2)
      local start = math.max(1, (center_idx or 1) - half)
      local finish = math.min(total, start + size - 1)
      start = math.max(1, finish - size + 1)
      if not suppress_log and (force_log or start ~= S.last_meta_window_start or finish ~= S.last_meta_window_finish) then
         M.debug_log("debug", string.format("Meta window %d-%d (%d)", start, finish, size))
         S.last_meta_window_start, S.last_meta_window_finish = start, finish
      end
      for i = start, finish do
         M.get_save_meta(entries[i], { force = true })
      end
   end

   function M.ensure_meta_window_for_page(page_num, per_page, window_pages, force_log, suppress_log)
      local per = per_page or 8
      local pages = window_pages or 4
      local center_page = page_num or 1
      local center_idx = (center_page - 1) * per + math.ceil(per / 2)
      M.ensure_meta_window(center_idx, per * pages, force_log, suppress_log)
   end

   function M.calc_meta_window_bounds(center_idx, window_size)
      local entries = M.get_save_files()
      if not entries or #entries == 0 then return nil, nil, window_size or M.META_CACHE_BASE_LIMIT end
      local total = #entries
      local size = window_size or M.META_CACHE_BASE_LIMIT
      local half = math.floor(size / 2)
      local start = math.max(1, (center_idx or 1) - half)
      local finish = math.min(total, start + size - 1)
      start = math.max(1, finish - size + 1)
      return start, finish, size
   end

   function M.calc_meta_window_bounds_for_page(page_num, per_page, window_pages)
      local per = per_page or 8
      local pages = window_pages or 4
      local center_page = page_num or 1
      local center_idx = (center_page - 1) * per + math.ceil(per / 2)
      return M.calc_meta_window_bounds(center_idx, per * pages)
   end

   function M.get_save_meta(entry, opts)
      if not entry or not entry[E.ENTRY_FILE] then return nil end
      opts = opts or {}
      local file = entry[E.ENTRY_FILE]
      if entry[E.ENTRY_SIGNATURE] and not opts.force then
         if S.meta_cache[file] then _touch_lru(file) end
         return true
      end

      local dir = M.get_save_dir()
      local meta = S.meta_cache[file]
      if meta then
         _touch_lru(file)
         _apply_meta_to_entry(entry, meta)
         return true
      end

      local meta_path = dir .. "/" .. file:gsub("%.jkr$", ".meta")
      meta = MetaFile.read_meta_file(meta_path)

      if meta and meta.display_type then
         _cache_meta(file, meta)
         _apply_meta_to_entry(entry, meta)
         return true
      end

      M.debug_log("error", "Missing .meta file for: " .. file)
      _clear_entry_meta(entry)
      return false
   end

   M.normalize_custom_state_name = _normalize_custom_state_name

   function M.get_custom_state_name(file)
      if not file then return nil end
      local entry = M.get_entry_by_file(file)
      if not entry then return nil end
      if not M.get_save_meta(entry) then return nil end
      local meta = S.meta_cache[file]
      if not meta then return nil end
      return _normalize_custom_state_name(meta.custom_state_name)
   end

   function M.set_custom_state_name(file, name)
      if not file then return false end

      local entry = M.get_entry_by_file(file)
      if not entry then
         M.debug_log("warning", "set_custom_state_name: entry not found for " .. tostring(file))
         return false
      end

      name = _normalize_custom_state_name(name)
      if not M.get_save_meta(entry, { force = true }) then
         M.debug_log("error", "set_custom_state_name: metadata unavailable for " .. tostring(file))
         return false
      end

      local dir = M.get_save_dir()
      local meta_path = dir .. "/" .. file:gsub("%.jkr$", ".meta")
      local meta = S.meta_cache[file]
      if not meta then
         M.debug_log("error", "set_custom_state_name: meta cache miss for " .. file)
         return false
      end

      meta.custom_state_name = name
      local success = MetaFile.write_meta_file(meta_path, meta)
      if not success then
         M.debug_log("error", "set_custom_state_name: write failed for " .. file)
         return false
      end

      _cache_meta(file, meta)
      _apply_meta_to_entry(entry, meta)
      M.debug_log("info", string.format("Set custom name for %s: %s", file, name or "[cleared]"))
      return true
   end

   function M.get_save_files(force_reload)
      index.process_async_save_results()
      if S.save_cache and not force_reload then
         index.update_cache_current_flags()
         if not S.save_cache_by_file then index.rebuild_file_index() end
         return index.get_save_cache_view()
      end

      S.save_cache = _list_and_sort_entries()
      index.invalidate_save_cache_view()
      local newest = S.save_cache and S.save_cache[#S.save_cache]
      if newest and newest[E.ENTRY_INDEX] then
         M._last_generated_id = math.max(M._last_generated_id or 0, newest[E.ENTRY_INDEX])
      end
      index.rebuild_file_index()
      _purge_meta_cache()
      index.update_cache_current_flags(true)
      return index.get_save_cache_view()
   end

   function M.preload_all_metadata(force_reload)
      local entries = M.get_save_files(force_reload)
      if entries and #entries > 0 then
         M.ensure_meta_window(1, M.META_CACHE_BASE_LIMIT)
      end
      return entries
   end

   function M.clear_all_saves()
      M.invalidate_async_saves()
      local dir = M.get_save_dir()
      if love.filesystem.getInfo(dir) then
         for _, file in ipairs(love.filesystem.getDirectoryItems(dir)) do
            love.filesystem.remove(dir .. "/" .. file)
         end
      end

      M.debug_log("info", "Cleared all saves")
      S.save_cache = {}
      S.save_cache_view = nil
      S.meta_cache = {}
      S.meta_cache_size = 0
      S.meta_lru_ts = {}
      S.meta_lru_clock = 0
      S.meta_cache_limit = M.META_CACHE_BASE_LIMIT
      index.reset_async_state()
      index.reset_all_indices()
   end

   function api.cache_meta(file, meta)
      _cache_meta(file, meta)
   end

   function api.purge_meta_cache()
      _purge_meta_cache()
   end

   return api
end
