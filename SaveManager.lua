--- Fast Save Loader - SaveManager.lua
--
-- Runs in the save manager thread and creates timestamped backups
-- whenever the main save file is written.

local debug_log = function(tag, msg)
    if LOADER and LOADER.debug_log then
        LOADER.debug_log(tag, msg)
    else
        print("[FastSL][SaveManager][" .. tostring(tag) .. "] " .. tostring(msg))
    end
end

if not LOADER then LOADER = {} end

if not LOADER.PATHS then
   LOADER.PATHS = { BACKUPS = "FastSaveLoader" }
end

local function ensure_dir(path)
   if not love.filesystem.getInfo(path) then
      love.filesystem.createDirectory(path)
   end
end

-- Helper to save meta data (simple string serialization for now)
local function compress_and_save_meta(_file, _meta_table)
    local meta_string = ""
    if _meta_table then
        for k, v in pairs(_meta_table) do
            if type(v) == "string" or type(v) == "number" then
                meta_string = meta_string .. tostring(k) .. ":" .. tostring(v) .. ","
            end
        end
        meta_string = meta_string:sub(1, #meta_string - 1) -- Remove trailing comma
    end
    
    local f = love.filesystem.newFile(_file, "w")
    if f then
        f:write(meta_string)
        f:close()
        debug_log("meta", "Saved meta to: " .. _file)
    else
        debug_log("error", "Failed to open meta file for writing: " .. _file)
    end
end

local function collect_backups(backup_dir)
   local newest_file, newest_mtime = nil, -math.huge
   local entries = {}
   local ante_set = {}

   local items = love.filesystem.getDirectoryItems(backup_dir)
   for _, file in ipairs(items) do
      if file:match("%.jkr$") then -- Only consider .jkr files
         local full = backup_dir .. "/" .. file
         local info = love.filesystem.getInfo(full)
         if info and info.type == "file" then
            local mtime = info.modtime or 0
            if mtime > newest_mtime then
               newest_mtime, newest_file = mtime, full
            end

            -- Filename format: "<ante>-<round>-<index>.jkr"
            local ante_str, round_str, index_str = string.match(file, "^(%d+)%-(%d+)%-(%d+)%.jkr$")
            local ante = tonumber(ante_str or "")
            local round = tonumber(round_str or "")
            local index = tonumber(index_str or "")
            if ante then
               table.insert(entries, {
                  file = file,
                  ante = ante,
                  round = round,
                  index = index or 0,
                  modtime = mtime,
               })
               ante_set[ante] = true
            end
         end
      end
   end

   return newest_file, entries, ante_set
end

function LOADER.execute_save_manager(request)
   local profile = tostring(request.profile_num or 1)
   ensure_dir(profile)

   local backup_dir = profile .. "/" .. LOADER.PATHS.BACKUPS
   ensure_dir(backup_dir)

   local save_table = request.save_table or {}
   local prune_list = save_table.LOADER_PRUNE_LIST
   local StateSignatureAPI = save_table.LOADER_STATE_SIGNATURE_API -- Retrieve StateSignature API
   save_table.LOADER_PRUNE_LIST = nil
   save_table.LOADER_STATE_SIGNATURE_API = nil -- Clear API from save_table

   if save_table.LOADER_SKIP_BACKUP then
      save_table.LOADER_SKIP_BACKUP = nil
      -- Hold only the most recent prune list so the last loaded save
      -- decides which branch gets trimmed.
      if prune_list and next(prune_list) then
         LOADER._deferred_prune = prune_list
         debug_log("prune", "Deferring prune list with " .. tostring(#prune_list) .. " items (backup skipped)")
      else
         LOADER._deferred_prune = nil
      end
      return
   end

   -- Apply a deferred prune list if no new list was provided.
   if (not prune_list or not next(prune_list)) and LOADER and LOADER._deferred_prune then
      prune_list = LOADER._deferred_prune
      debug_log("prune", "Using deferred prune list with " .. tostring(#(prune_list or {})) .. " items")
   end
   LOADER._deferred_prune = nil

   -- If a prune list was passed and we are keeping this backup, delete
   -- those files now to complete the timeline branch.
   if prune_list and next(prune_list) then
      for _, file_to_delete in ipairs(prune_list) do
         pcall(love.filesystem.remove, backup_dir .. "/" .. file_to_delete)
         pcall(love.filesystem.remove, backup_dir .. "/" .. file_to_delete:gsub("%.jkr$", ".meta")) -- Delete companion .meta file
      end
      debug_log("prune", "Applied prune list size " .. tostring(#prune_list))
   end

   -- Read and clear the optional per-ante retention hint that the
   -- main game thread attached to this save. A value of 0 or nil
   -- means no ante limit ("All").
   local keep_antes = tonumber(save_table.LOADER_KEEP_ANTES or 0) or 0
   save_table.LOADER_KEEP_ANTES = nil

   local game = save_table.GAME or {}
   local ante = (game.round_resets and tonumber(game.round_resets.ante)) or 0
   local round = tonumber(game.round or 0) or 0
   LOADER._save_counter = (LOADER._save_counter or 0) + 1

   -- File names encode ante, round, and a monotonic index for this run.
   -- Example: "2-3-42.jkr"
   local file_name = string.format("%d-%d-%d", ante, round, LOADER._save_counter)

       local save_path = backup_dir .. "/" .. file_name .. ".jkr"
   
       compress_and_save(save_path, save_table)
   
       -- Generate and save companion .meta file
       if StateSignatureAPI and StateSignatureAPI.get_signature then
           local meta_table = StateSignatureAPI.get_signature(save_table)
           compress_and_save_meta(backup_dir .. "/" .. file_name .. ".meta", meta_table)
       else
           debug_log("error", "StateSignatureAPI not available for meta file generation.")
       end
   
       apply_retention_policy(backup_dir, keep_antes)
   end
   
   local function apply_retention_policy(backup_dir, keep_antes)
       -- If configured, keep only the most recent N antes worth of saves
       -- in this run (all saves from the latest antes, none from older
       -- antes). A keep_antes of 0 means "unlimited".
       if keep_antes and keep_antes > 0 then
          local _, entries, ante_set = collect_backups(backup_dir)
          if entries and next(entries) ~= nil then
          local antes = {}
          for a in pairs(ante_set or {}) do
             table.insert(antes, a)
          end
          table.sort(antes, function(a, b) return a > b end)
    
          local allowed = {}
          local limit = math.min(keep_antes, #antes)
          for i = 1, limit do
             allowed[antes[i]] = true
          end
    
             for _, e in ipairs(entries) do
                if not allowed[e.ante] then
                   pcall(love.filesystem.remove, backup_dir .. "/" .. e.file)
                   pcall(love.filesystem.remove, backup_dir .. "/" .. e.file:gsub("%.jkr$", ".meta")) -- Delete companion .meta file
                end
             end
          end
       end
   end
    
   return LOADER
