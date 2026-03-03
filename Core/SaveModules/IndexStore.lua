local function _get_current_file(M)
   return M._last_loaded_file or (G and G.SAVED_GAME and G.SAVED_GAME._file) or nil
end

return function(ctx)
   local M = ctx.M
   local S = ctx.S
   local E = ctx.E
   local Logger = ctx.Logger

   local api = {}

   function api.get_save_cache()
      return S.save_cache
   end

   function api.set_save_cache(entries)
      S.save_cache = entries
   end

   function api.invalidate_save_cache_view()
      S.save_cache_view = nil
   end

   function api.prepend_save_view_entry()
      S.save_cache_view = nil
   end

   function api.get_save_cache_view()
      if not S.save_cache then return nil end
      if S.save_cache_view then return S.save_cache_view end
      local total = #S.save_cache
      local view = {}
      for i = 1, total do
         view[i] = S.save_cache[total - i + 1]
      end
      S.save_cache_view = view
      return S.save_cache_view
   end

   function api.rebuild_file_index()
      if not S.save_cache then
         S.save_cache_by_file, S.save_index_by_file, S.save_cache_by_id = nil, nil, nil
         return
      end
      local total = #S.save_cache
      S.save_cache_by_file, S.save_index_by_file, S.save_cache_by_id = {}, {}, {}
      for i, entry in ipairs(S.save_cache) do
         local file = entry and entry[E.ENTRY_FILE]
         local entry_id = entry and entry[E.ENTRY_INDEX]
         local display_index = total - i + 1
         if file then
            S.save_cache_by_file[file] = entry
            S.save_index_by_file[file] = display_index
         end
         if entry_id then
            S.save_cache_by_id[entry_id] = { entry = entry, index = display_index }
         end
      end
   end

   function api.invalidate_derived_indexes()
      S.save_index_by_file, S.save_cache_by_id = nil, nil
   end

   function api.remove_files_from_index(files)
      if not files then return end
      for _, file in ipairs(files) do
         if file and S.save_cache_by_file then
            S.save_cache_by_file[file] = nil
         end
         if file then
            api.clear_async_pending(file)
         end
      end
      S.save_cache_view = nil
      S.save_index_by_file = nil
      S.save_cache_by_id = nil
   end

   function M.get_current_file()
      return _get_current_file(M)
   end

   function api.update_cache_current_flags(force)
      if not S.save_cache then return end

      local current_file = _get_current_file(M)
      if not force and S.last_current_file ~= false and current_file == S.last_current_file then return end

      if not S.save_cache_by_file then api.rebuild_file_index() end

      if S.last_current_file and S.last_current_file ~= false and S.save_cache_by_file then
         local old_entry = S.save_cache_by_file[S.last_current_file]
         if old_entry then old_entry[E.ENTRY_IS_CURRENT] = false end
      end

      if current_file and S.save_cache_by_file then
         local new_entry = S.save_cache_by_file[current_file]
         if new_entry then new_entry[E.ENTRY_IS_CURRENT] = true end
      end

      S.last_current_file = current_file
   end

   function api.mark_async_pending(file)
      if not file or S.pending_async_files[file] then return end
      S.pending_async_files[file] = true
      S.pending_async_count = S.pending_async_count + 1
   end

   function api.clear_async_pending(file)
      if not file or not S.pending_async_files[file] then return end
      S.pending_async_files[file] = nil
      S.pending_async_count = math.max(0, S.pending_async_count - 1)
   end

   function api.is_async_pending(file)
      return file and S.pending_async_files[file] == true
   end

   function api.is_async_save_ready(file)
      if not file then return false end
      local dir = M.get_save_dir()
      local info = love.filesystem.getInfo(dir .. "/" .. file)
      return info and info.type == "file"
   end

   function api.process_async_save_results()
      if S.pending_async_count <= 0 then return end
      for file in pairs(S.pending_async_files) do
         if api.is_async_save_ready(file) then
            api.clear_async_pending(file)
         end
      end
   end

   function api.reset_async_state()
      S.pending_async_files = {}
      S.pending_async_count = 0
   end

   function api.reset_all_indices()
      S.last_current_file = false
      api.rebuild_file_index()
   end

   function api.get_entry_by_file(file)
      if not file then return nil end
      if not S.save_cache_by_file then api.rebuild_file_index() end
      return S.save_cache_by_file and S.save_cache_by_file[file]
   end

   function api.get_index_by_file(file)
      if not file then return nil end
      if not S.save_index_by_file then api.rebuild_file_index() end
      return S.save_index_by_file and S.save_index_by_file[file]
   end

   function api.get_entry_by_id(id)
      if not id then return nil end
      if not S.save_cache_by_id then api.rebuild_file_index() end
      local result = S.save_cache_by_id and S.save_cache_by_id[id]
      if not result and type(id) == "string" then
         local num = tonumber(id)
         if num then result = S.save_cache_by_id and S.save_cache_by_id[num] end
      end
      return result and result.entry, result and result.index
   end

   function api.find_current_index()
      if M._last_loaded_file then
         local idx = api.get_index_by_file(M._last_loaded_file)
         if idx then return idx end
      end
      if S.save_cache then
         local total = #S.save_cache
         for i, entry in ipairs(S.save_cache) do
            if entry and entry[E.ENTRY_IS_CURRENT] then
               return total - i + 1
            end
         end
      end
      return nil
   end

   function api.set_cache_current_file(file)
      M._last_loaded_file = file
      local entry = file and S.save_cache_by_file and S.save_cache_by_file[file]
      if entry and M.get_save_meta then
         M.get_save_meta(entry, { force = true })
      end
      api.update_cache_current_flags()
   end

   function M.invalidate_async_saves()
      api.reset_async_state()
   end

   function M.get_entry_by_file(file)
      return api.get_entry_by_file(file)
   end

   function M.get_index_by_file(file)
      return api.get_index_by_file(file)
   end

   function M.get_entry_by_id(id)
      return api.get_entry_by_id(id)
   end

   function M.find_current_index()
      return api.find_current_index()
   end

   function M._set_cache_current_file(file)
      return api.set_cache_current_file(file)
   end

   -- ── File Discovery (scan disk for .jkr files) ──────────────────────────

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

   function M.get_save_files(force_reload)
      api.process_async_save_results()
      if S.save_cache and not force_reload then
         api.update_cache_current_flags()
         if not S.save_cache_by_file then api.rebuild_file_index() end
         return api.get_save_cache_view()
      end

      S.save_cache = _list_and_sort_entries()
      S.bucket_counts = nil
      api.invalidate_save_cache_view()
      local newest = S.save_cache and S.save_cache[#S.save_cache]
      if newest and newest[E.ENTRY_INDEX] then
         M._last_generated_id = math.max(M._last_generated_id or 0, newest[E.ENTRY_INDEX])
      end
      api.rebuild_file_index()
      if ctx.meta and ctx.meta.purge_meta_cache then ctx.meta.purge_meta_cache() end
      api.update_cache_current_flags(true)
      return api.get_save_cache_view()
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
      if M.invalidate_queue_and_thread then M.invalidate_queue_and_thread() end
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
      S.bucket_counts = nil
      api.reset_async_state()
      api.reset_all_indices()
   end

   return api
end
