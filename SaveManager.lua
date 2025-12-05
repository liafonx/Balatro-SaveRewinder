--- Fast Save Loader - SaveManager.lua
--
-- Runs in the save manager thread and creates timestamped backups
-- whenever the main save file is written.

if not ANTIHYP then ANTIHYP = {} end

if not ANTIHYP.PATHS then
   ANTIHYP.PATHS = { BACKUPS = "FastSaveLoader" }
end

local function ensure_dir(path)
   if not love.filesystem.getInfo(path) then
      love.filesystem.createDirectory(path)
   end
end

local function collect_backups(backup_dir)
   local newest_file, newest_mtime = nil, -math.huge
   local entries = {}
   local ante_set = {}

   local items = love.filesystem.getDirectoryItems(backup_dir)
   for _, file in ipairs(items) do
      local full = backup_dir .. "/" .. file
      local info = love.filesystem.getInfo(full)
      if info and info.type == "file" then
         local mtime = info.modtime or 0
         if mtime > newest_mtime then
            newest_mtime, newest_file = mtime, full
         end

         -- New filename format: "<ante>-<round>-<timestamp>.jkr"
         local ante_str, round_str = string.match(file, "^(%d+)%-(%d+)%-%d+%.jkr$")
         local ante = tonumber(ante_str or "")
         local round = tonumber(round_str or "")
         if ante then
            table.insert(entries, {
               file = file,
               ante = ante,
               round = round,
               modtime = mtime,
            })
            ante_set[ante] = true
         end
      end
   end

   return newest_file, entries, ante_set
end

function ANTIHYP.execute_save_manager(request)
   local profile = tostring(request.profile_num or 1)
   ensure_dir(profile)

   local backup_dir = profile .. "/" .. ANTIHYP.PATHS.BACKUPS
   ensure_dir(backup_dir)

   local save_table = request.save_table or {}
   if save_table.ANTIHYP_SKIP_BACKUP then
      save_table.ANTIHYP_SKIP_BACKUP = nil
      return
   end
   save_table.ANTIHYP_TRIGGER = nil

   -- Read and clear the optional per-ante retention hint that the
   -- main game thread attached to this save. A value of 0 or nil
   -- means no ante limit ("All").
   local keep_antes = tonumber(save_table.ANTIHYP_KEEP_ANTES or 0) or 0
   save_table.ANTIHYP_KEEP_ANTES = nil

   -- String-pack the incoming save for consistent on-disk format.
   local packed_new
   if STR_PACK then
      local ok, result = pcall(STR_PACK, save_table)
      if ok and type(result) == "string" then
         packed_new = result
      end
   end

   local newest_file, entries, ante_set = nil, nil, nil
   if keep_antes > 0 then
      newest_file, entries, ante_set = collect_backups(backup_dir)
   end

   local game = save_table.GAME or {}
   local ante = (game.round_resets and tonumber(game.round_resets.ante)) or 0
   local round = tonumber(game.round or 0) or 0
   ANTIHYP._save_counter = (ANTIHYP._save_counter or 0) + 1

   -- File names encode ante, round, and a monotonic counter for the run.
   -- Example: "2-3-42.jkr"
   local file_name = string.format("%d-%d-%d", ante, round, ANTIHYP._save_counter)

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
   if keep_antes and keep_antes > 0 and entries and next(entries) ~= nil then
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
         end
      end
   end
end

return ANTIHYP
