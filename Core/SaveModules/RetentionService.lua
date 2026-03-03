return function(ctx)
   local M = ctx.M
   local S = ctx.S
   local E = ctx.E
   local Pruning = ctx.Pruning
   local Logger = ctx.Logger

   local api = {}

   local KEEP_ANTES_VALUES = Pruning.KEEP_ANTES_VALUES

   local function _compute_allowed_antes(entries)
      local keep_antes_config = (REWINDER and REWINDER.config and REWINDER.config.keep_antes) or 7
      local keep_antes = KEEP_ANTES_VALUES[keep_antes_config]
      if not keep_antes or keep_antes <= 0 then return nil end

      local ante_set = {}
      for _, e in ipairs(entries) do
         if e[E.ENTRY_ANTE] then ante_set[e[E.ENTRY_ANTE]] = true end
      end

      local antes = {}
      for a in pairs(ante_set) do
         antes[#antes + 1] = a
      end
      table.sort(antes, function(a, b) return a > b end)

      local allowed = {}
      local limit = math.min(keep_antes, #antes)
      for i = 1, limit do
         allowed[antes[i]] = true
      end
      return allowed
   end

   local function _ensure_key_flags_loaded(entries, allowed_antes)
      if not entries then return 0 end
      local loaded = 0
      for i = 1, #entries do
         local entry = entries[i]
         local hydrate = true
         if allowed_antes then
            hydrate = entry and entry[E.ENTRY_ANTE] and not allowed_antes[entry[E.ENTRY_ANTE]]
         end
         if hydrate and entry and entry[E.ENTRY_IS_KEY] == nil then
            if M.get_save_meta(entry) then
               loaded = loaded + 1
            end
         end
      end
      return loaded
   end

   local function _retention_should_preserve_entry(entry)
      return entry and entry[E.ENTRY_IS_KEY] == true
   end

   local function _apply_retention_policy(save_dir, entries)
      if not entries or #entries == 0 then return end
      local allowed = _compute_allowed_antes(entries)
      local loaded = _ensure_key_flags_loaded(entries, allowed)
      if loaded > 0 and Logger.is_verbose() then
         M.debug_log("debug", "Loaded key flags before retention prune: " .. tostring(loaded))
      end
      return Pruning.apply_retention_policy(save_dir, entries, E, {
         should_preserve_entry = _retention_should_preserve_entry,
      })
   end

   function M.ensure_key_flags_loaded(entries)
      local loaded = _ensure_key_flags_loaded(entries, nil)
      if loaded > 0 and Logger.is_verbose() then
         M.debug_log("debug", "Loaded missing key flags: " .. tostring(loaded))
      end
      return loaded
   end

   function M.apply_retention_policy_now()
      if not S.save_cache then M.get_save_files() end
      if not S.save_cache or #S.save_cache == 0 then return end
      local dir = M.get_save_dir()
      _apply_retention_policy(dir, S.save_cache)
      ctx.index.invalidate_save_cache_view()
      ctx.index.rebuild_file_index()
      ctx.index.update_cache_current_flags(true)
   end

   api.apply_retention_policy = _apply_retention_policy
   return api
end
