--- Fast Save Loader - SaveManager.lua
--
-- Runs in the save manager thread and creates timestamped backups
-- whenever the main save file is written.

if not ANTIHYP then ANTIHYP = {} end

if not ANTIHYP.PATHS then
   ANTIHYP.PATHS = {
      BACKUPS = "FastSaveLoader",
   }
end

function ANTIHYP.execute_save_manager(request)
   local profile = tostring(request.profile_num or 1)
   if not love.filesystem.getInfo(profile) then
      love.filesystem.createDirectory(profile)
   end

   local backup_dir = profile .. "/" .. ANTIHYP.PATHS.BACKUPS
   if not love.filesystem.getInfo(backup_dir) then
      love.filesystem.createDirectory(backup_dir)
   end

   local save_table = request.save_table or {}

   if save_table.ANTIHYP_SKIP_BACKUP then
      save_table.ANTIHYP_SKIP_BACKUP = nil
      return
   end

   -- Read and clear the optional per-ante retention hint that the
   -- main game thread attached to this save. A value of 0 or nil
   -- means no ante limit ("All").
   local keep_antes = tonumber(save_table.ANTIHYP_KEEP_ANTES or 0) or 0
   save_table.ANTIHYP_KEEP_ANTES = nil

   -- String-pack the incoming save so we can cheaply compare against
   -- the most recent backup. This lets us avoid creating duplicate
   -- backups when reloading the same state (either from this mod or
   -- from the vanilla continue menu).
   local packed_new
   if STR_PACK then
      local ok, result = pcall(STR_PACK, save_table)
      if ok and type(result) == "string" then
         packed_new = result
      end
   end

   if packed_new then
      local latest_file
      local latest_mtime = -math.huge
      if love.filesystem.getInfo(backup_dir) then
         for _, file in ipairs(love.filesystem.getDirectoryItems(backup_dir)) do
            local full = backup_dir .. "/" .. file
            local info = love.filesystem.getInfo(full)
            if info and info.type == "file" and (info.modtime or 0) > latest_mtime then
               latest_mtime = info.modtime or 0
               latest_file = full
            end
         end
      end

      if latest_file then
         local ok, packed_old = pcall(get_compressed, latest_file)
         if ok and type(packed_old) == "string" and packed_old == packed_new then
            -- New save is byte-identical to the last backup: skip.
            return
         end
      end
   end

   local game = save_table.GAME or {}

   local seed = "seed"
   if game.pseudorandom and game.pseudorandom.seed then
      seed = tostring(game.pseudorandom.seed)
   end

   local ante = 0
   if game.round_resets and game.round_resets.ante then
      ante = tonumber(game.round_resets.ante) or 0
   end

   local round = tonumber(game.round or 0) or 0
   local timestamp = os.time()

   local file_name = string.format("%s-%d-%d-%d", seed, ante, round, timestamp)
   local save_path = backup_dir .. "/" .. file_name .. ".jkr"

   -- If we successfully packed the table, reuse that string so that
   -- comparisons stay consistent. Otherwise fall back to the table.
   if packed_new then
      compress_and_save(save_path, packed_new)
   else
      compress_and_save(save_path, save_table)
   end

   -- If configured, keep only the most recent N antes worth of saves
   -- in this run (all saves from the latest antes, none from older
   -- antes). A keep_antes of 0 means "unlimited".
   if keep_antes and keep_antes > 0 then
      local entries = {}
      if love.filesystem.getInfo(backup_dir) then
         for _, file in ipairs(love.filesystem.getDirectoryItems(backup_dir)) do
            local full = backup_dir .. "/" .. file
            local info = love.filesystem.getInfo(full)
            if info and info.type == "file" then
               local seed_str, ante_str, round_str = string.match(file, "^(.-)%-(%d+)%-(%d+)%-%d+%.jkr$")
               local a = tonumber(ante_str or "")
               local r = tonumber(round_str or "")
               if a then
                  table.insert(entries, {
                     file = file,
                     ante = a,
                     round = r,
                     modtime = info.modtime or 0,
                  })
               end
            end
         end
      end

      -- Work out which antes we are allowed to keep: take the highest
      -- N ante numbers present and delete saves from older antes.
      local ante_set = {}
      for _, e in ipairs(entries) do
         ante_set[e.ante] = true
      end
      local antes = {}
      for a, _ in pairs(ante_set) do
         table.insert(antes, a)
      end
      table.sort(antes, function(a, b) return a > b end)

      local allowed = {}
      for i = 1, math.min(keep_antes, #antes) do
         allowed[antes[i]] = true
      end

      for _, e in ipairs(entries) do
         if not allowed[e.ante] then
            pcall(love.filesystem.remove, backup_dir .. "/" .. e.file)
         end
      end
   end
end

return ANTIHYP
