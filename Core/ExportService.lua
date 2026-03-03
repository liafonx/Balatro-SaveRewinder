--- Save Rewinder - Core/ExportService.lua
--
-- Orchestrates export of selected saves to the OS filesystem as named files.
-- All OS-level I/O goes through Utils/FileIO.lua.

local ExportService = {}
local FileIO = require("FileIO")
local EntrySchema = require("SaveManagerEntrySchema")

local function _trim(s)
   if type(s) ~= "string" then return "" end
   return s:match("^%s*(.-)%s*$") or s
end

local function _escape_lua_pattern(s)
   return (tostring(s or "")):gsub("([^%w])", "%%%1")
end

local function _without_trailing_separators(path)
   local p = _trim(path)
   return p:gsub("[/\\]+$", "")
end

local function _ensure_profile_suffix(base_dir, profile)
   local base = _without_trailing_separators(base_dir)
   local prof = tostring(profile or "")
   if base == "" then return prof end
   if prof == "" then return base end
   if base:match("[/\\]" .. _escape_lua_pattern(prof) .. "$") then
      return base
   end
   return base .. "/" .. prof
end

local function _strip_profile_suffix(path, profile)
   local p = _without_trailing_separators(path)
   local prof = tostring(profile or "")
   if p == "" or prof == "" then return p end
   local suffix_pattern = "[/\\]" .. _escape_lua_pattern(prof) .. "$"
   if p:match(suffix_pattern) then
      return (p:gsub(suffix_pattern, ""))
   end
   return p
end

local function _sanitize_compact(str)
   if type(str) ~= "string" then return "" end
   local s = str:match("^%s*(.-)%s*$") or str
   s = s:gsub('[\\/:*?"<>|\r\n\t]', "_")
   s = s:gsub("%s+", "")
   return s
end

-- Returns the configured export directory, or the computed default.
function ExportService.get_export_dir()
   local configured_base = REWINDER and REWINDER.config and REWINDER.config.export_dir
   local base_dir = _trim(configured_base)
   if base_dir == "" then
      local profile = FileIO.get_profile()
      local save_dir = love.filesystem.getSaveDirectory()
      local root_dir = _strip_profile_suffix(save_dir, profile)
      if root_dir == "" then
         root_dir = save_dir
      end
      base_dir = _without_trailing_separators(root_dir) .. "/SW-Exports"
   end
   return _ensure_profile_suffix(base_dir, FileIO.get_profile())
end

-- Format a seed string for use in the run folder name.
-- Seeded runs always use the full seed; non-seeded runs abbreviate based on config.
function ExportService.format_seed(seed, is_seeded)
   local s = tostring(seed or "")
   if is_seeded then
      return s
   end
   local cfg = REWINDER and REWINDER.config or nil
   local show_full_non_seeded = false
   if cfg and type(cfg.export_full_seed_non_seeded) == "boolean" then
      show_full_non_seeded = cfg.export_full_seed_non_seeded
   else
      show_full_non_seeded = ((cfg and tonumber(cfg.export_seed_mode)) or 1) == 2
   end
   if not show_full_non_seeded then
      if #s < 3 then
         return s
      end
      local chars = {}
      for i = 1, #s do
         chars[i] = s:sub(i, i)
      end
      -- '*' is sanitized to '_' for path safety, so use a safe visible mask character.
      local mask_char = "X"
      for i = 3, math.min(6, #s) do
         chars[i] = mask_char
      end
      return table.concat(chars)
   end
   return s
end

-- Build the run-specific subfolder name from live G.GAME state.
-- Only valid during an active run (overlay only opens then).
function ExportService.build_run_folder_name()
   if not (G and G.GAME) then return "Unknown-Unknown-Unknown" end

   local deck = ""
   if G.GAME.selected_back and G.GAME.selected_back.loc_name then
      deck = tostring(G.GAME.selected_back.loc_name)
   end

   local stake = ""
   if G.GAME.stake and G.P_CENTER_POOLS and G.P_CENTER_POOLS.Stake then
      local stake_entry = G.P_CENTER_POOLS.Stake[G.GAME.stake]
      if stake_entry and stake_entry.key then
         if localize then
            local ok, name = pcall(localize, { type = "name_text", key = stake_entry.key, set = "Stake" })
            stake = (ok and type(name) == "string" and name ~= "") and name or stake_entry.key
         else
            stake = stake_entry.key
         end
      end
   end

   local seed_val = (G.GAME.pseudorandom and G.GAME.pseudorandom.seed) or ""
   local is_seeded = G.GAME.seeded == true
   local seed_str = ExportService.format_seed(seed_val, is_seeded)

   return _sanitize_compact(deck)
      .. "-" .. _sanitize_compact(stake)
      .. "-" .. FileIO.sanitize_path_component(seed_str)
end

-- Build the base filename (without extension) for a save entry.
-- Format: {ante_label}{N}-{round_or_blind}-{save_label}
function ExportService.build_file_name(entry)
   if not entry then return "unknown" end

   -- ante part
   local ante_label = (localize and localize("rewinder_ante_label")) or "Ante"
   local ante_num   = tostring(entry[EntrySchema.ENTRY_ANTE] or "")
   local ante_part  = FileIO.sanitize_path_component(ante_label .. ante_num)

   -- round or blind name
   local round_or_blind = ""
   local blind_idx = entry[EntrySchema.ENTRY_BLIND_IDX]
   local show_blind = REWINDER and REWINDER.config and REWINDER.config.show_blind_image
   if show_blind and blind_idx and blind_idx > 0 then
      local blind_key = EntrySchema.index_to_blind_key(blind_idx)
      if blind_key and localize then
         local ok, name = pcall(localize, { type = "name_text", key = blind_key, set = "Blind" })
         if ok and type(name) == "string" and name ~= "" then
            round_or_blind = name
         end
      end
   end
   if round_or_blind == "" then
      local round_label = (localize and localize("rewinder_round_label")) or "Round"
      round_or_blind = round_label .. tostring(entry[EntrySchema.ENTRY_ROUND] or "")
   end
   round_or_blind = FileIO.sanitize_path_component(round_or_blind)

   -- save label: custom name if set, else default state title
   local save_label = ""
   local file = entry[EntrySchema.ENTRY_FILE]
   local custom_name = (file and REWINDER.get_custom_state_name and REWINDER.get_custom_state_name(file)) or nil
   if type(custom_name) == "string" and custom_name ~= "" then
      save_label = custom_name
   elseif REWINDER.get_default_state_title then
      save_label = REWINDER.get_default_state_title(entry) or ""
   end
   save_label = FileIO.sanitize_path_component(save_label)
   if save_label == "" then
      save_label = "Save"
   end

   return ante_part .. "-" .. round_or_blind .. "-" .. save_label
end

-- Export selected saves to the OS filesystem.
-- selection_map: { [filename] = true, ... }
-- Returns (success_count, fail_count).
function ExportService.export_selected(selection_map)
   if type(selection_map) ~= "table" then return 0, 0 end

   local export_dir  = ExportService.get_export_dir()
   local run_folder  = ExportService.build_run_folder_name()
   local dest_dir    = export_dir .. "/" .. run_folder

   if not FileIO.create_dir_os(dest_dir) then
      local selected_count = 0
      for _, selected in pairs(selection_map) do
         if selected then selected_count = selected_count + 1 end
      end
      return 0, selected_count
   end

   local save_dir    = FileIO.get_save_dir()
   local success     = 0
   local fail        = 0
   local used_names  = {}

   local all_entries = (REWINDER.get_save_files and REWINDER.get_save_files()) or {}

   for _, entry in ipairs(all_entries) do
      local file = entry[EntrySchema.ENTRY_FILE]
      if file and selection_map[file] then
         -- Ensure metadata is loaded so build_file_name can use it
         if not entry[EntrySchema.ENTRY_SIGNATURE] and REWINDER.get_save_meta then
            REWINDER.get_save_meta(entry)
         end

         local base_name = ExportService.build_file_name(entry)
         if not base_name or base_name == "" then
            base_name = tostring(file):gsub("%.jkr$", "")
         end

         -- Deduplicate: append _2, _3, ... on collision
         local final_name = base_name
         local dup_n = 2
         while used_names[final_name] or FileIO.file_exists_os(dest_dir .. "/" .. final_name .. ".jkr") do
            final_name = base_name .. "_" .. tostring(dup_n)
            dup_n = dup_n + 1
         end
         used_names[final_name] = true

         local love_src  = save_dir .. "/" .. file
         local os_dest   = dest_dir .. "/" .. final_name .. ".jkr"

         if FileIO.copy_love_to_os(love_src, os_dest) then
            success = success + 1
            -- Optionally copy .meta sidecar
            if REWINDER and REWINDER.config and REWINDER.config.export_include_meta then
               local meta_file = EntrySchema.meta_filename(tostring(file))
               local meta_src  = save_dir .. "/" .. meta_file
               if love.filesystem.getInfo(meta_src) then
                  local meta_dest = dest_dir .. "/" .. final_name .. ".meta"
                  FileIO.copy_love_to_os(meta_src, meta_dest)
               end
            end
         else
            fail = fail + 1
         end
      end
   end

   return success, fail
end

return ExportService
