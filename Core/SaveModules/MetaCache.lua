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
   local EntrySchema = require("SaveManagerEntrySchema")

   local api = {}

   -- Drives _apply_meta_to_entry, _build_meta_from_entry, and _clear_entry_meta.
   -- Each row: { entry_key, meta_key, apply_default?, read_as_bool? }
   local META_FIELD_MAP = {
      { entry_key = "ENTRY_MONEY",         meta_key = "money" },
      { entry_key = "ENTRY_SIGNATURE",     meta_key = "signature" },
      { entry_key = "ENTRY_DISCARDS_USED", meta_key = "discards_used" },
      { entry_key = "ENTRY_HANDS_PLAYED",  meta_key = "hands_played" },
      { entry_key = "ENTRY_BLIND_IDX",     meta_key = "blind_idx" },
      { entry_key = "ENTRY_DISPLAY_TYPE",  meta_key = "display_type" },
      { entry_key = "ENTRY_ORDINAL",       meta_key = "ordinal" },
      { entry_key = "ENTRY_IS_KEY",        meta_key = "is_key", apply_default = false, read_as_bool = true },
   }

   local function _apply_meta_to_entry(entry, meta)
      if not entry or not meta then return end
      for _, m in ipairs(META_FIELD_MAP) do
         local v = meta[m.meta_key]
         local val = v
         if val == nil and m.apply_default ~= nil then val = m.apply_default end
         entry[E[m.entry_key]] = val
      end
   end

   local function _clear_entry_meta(entry)
      if not entry then return end
      for _, m in ipairs(META_FIELD_MAP) do
         entry[E[m.entry_key]] = nil
      end
   end

   local function _drop_meta(file, force)
      if not file or not S.meta_cache[file] then return end
      if not force and index and index.is_async_pending and index.is_async_pending(file) then
         -- Keep metadata for pending async saves in memory until write completes.
         return
      end
      S.meta_cache[file] = nil
      S.meta_cache_size = math.max(0, S.meta_cache_size - 1)
      S.meta_lru_ts[file] = nil
      if S.save_cache_by_file then
         local entry = S.save_cache_by_file[file]
         if entry then _clear_entry_meta(entry) end
      end
   end

   local function _is_pinned(file)
      local current = M.get_current_file and M.get_current_file() or (M._last_loaded_file or (G and G.SAVED_GAME and G.SAVED_GAME._file) or nil)
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
            local is_pending = index and index.is_async_pending and index.is_async_pending(file)
            if not _is_pinned(file) and not is_pending and (not min_ts or ts < min_ts) then
               candidate, min_ts = file, ts
            end
         end
         if not candidate then break end
         local before = S.meta_cache_size
         _drop_meta(candidate)
         if S.meta_cache_size < before then
            evicted = evicted + 1
         else
            -- Defensive: avoid re-selecting the same non-droppable candidate.
            S.meta_lru_ts[candidate] = nil
         end
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
            _drop_meta(file, true)
         end
      end
   end

   local function _build_meta_from_entry(entry)
      if not entry then return nil end
      if not entry[E.ENTRY_DISPLAY_TYPE] then return nil end
      local meta = {}
      for _, m in ipairs(META_FIELD_MAP) do
         local v = entry[E[m.entry_key]]
         if m.read_as_bool then
            meta[m.meta_key] = (v == true)
         else
            meta[m.meta_key] = v
         end
      end
      return meta
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
      local is_pending = index.is_async_pending and index.is_async_pending(file)
      if is_pending and index.is_async_save_ready and index.is_async_save_ready(file) then
         index.clear_async_pending(file)
         is_pending = false
      end

      if is_pending then
         -- Queue mode: entry metadata is authoritative until file+meta land on disk.
         local pending_meta = _build_meta_from_entry(entry)
         if pending_meta then
            _cache_meta(file, pending_meta)
            _apply_meta_to_entry(entry, pending_meta)
            return true
         end
         return false
      end

      local save_path = dir .. "/" .. file
      local save_info = love.filesystem.getInfo(save_path)
      if not save_info or save_info.type ~= "file" then
         -- Stale cache entries can occur briefly around prune/refresh windows.
         if Logger.is_verbose() then
            M.debug_log("debug", "Skip meta read for missing save file: " .. tostring(file))
         end
         return false
      end

      local meta = S.meta_cache[file]
      if meta then
         _touch_lru(file)
         _apply_meta_to_entry(entry, meta)
         return true
      end

      local meta_path = dir .. "/" .. EntrySchema.meta_filename(file)
      meta = MetaFile.read_meta_file(meta_path)

      if meta and meta.display_type then
         _cache_meta(file, meta)
         _apply_meta_to_entry(entry, meta)
         return true
      end

      local rebuilt = _build_meta_from_entry(entry)
      if rebuilt and rebuilt.signature and MetaFile.write_meta_file(meta_path, rebuilt) then
         _cache_meta(file, rebuilt)
         _apply_meta_to_entry(entry, rebuilt)
         M.debug_log("warning", "Rebuilt missing .meta file for: " .. file)
         return true
      end

      M.debug_log("warning", "Missing .meta file for: " .. file)
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
      local meta_path = dir .. "/" .. EntrySchema.meta_filename(file)
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

   -- get_save_files, preload_all_metadata, and clear_all_saves
   -- now live in IndexStore where file discovery belongs.

   function api.cache_meta(file, meta)
      _cache_meta(file, meta)
   end

   function api.purge_meta_cache()
      _purge_meta_cache()
   end

   -- Expose private helpers for unit tests.
   api._apply_meta_to_entry  = _apply_meta_to_entry
   api._build_meta_from_entry = _build_meta_from_entry
   api._clear_entry_meta     = _clear_entry_meta

   return api
end
