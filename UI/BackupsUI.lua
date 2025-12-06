--- Fast Save Loader - UI/BackupsUI.lua
--
-- In-game UI for listing and restoring backups, plus an Options button.

if not LOADER then LOADER = {} end

function LOADER.get_backup_meta(entry)
   local dir = LOADER.get_backup_dir()
   local full_path = dir .. "/" .. entry.file

   local ok, packed = pcall(get_compressed, full_path)
   if not ok or not packed then
      return { ante = 0, round = 0, label = entry.file }
   end

   local ok2, save = pcall(STR_UNPACK, packed)
   if not ok2 or not save or type(save) ~= "table" then
      return { ante = 0, round = 0, label = entry.file }
   end

   local game = save.GAME or {}
   local ante = (game.round_resets and game.round_resets.ante) or game.ante or 0
   local round = game.round or 0

   local state_label = nil
   local state_debug = nil
   local state = save.STATE
   if G and G.STATES and state then
      if state == G.STATES.SHOP then
         state_label = (localize and localize("fastsl_state_shop")) or "In shop"
      elseif state == G.STATES.DRAW_TO_HAND then
         state_label = (localize and localize("fastsl_state_start_round")) or "Start of round"
      elseif state == G.STATES.SELECTING_HAND then
         state_label = (localize and localize("fastsl_state_selecting_hand")) or "Selecting hand"
      elseif state == G.STATES.ROUND_EVAL or state == G.STATES.HAND_PLAYED then
         state_label = (localize and localize("fastsl_state_end_of_round")) or "End of round"
      elseif state == G.STATES.BLIND_SELECT then
         state_label = (localize and localize("fastsl_state_choose_blind")) or "Choosing next blind"
      end
      if LOADER and LOADER.describe_state_label then
         state_debug = LOADER.describe_state_label(state)
      end
   end

   local label_parts = {}
   if state_label then table.insert(label_parts, state_label) end
   if #label_parts == 0 then
      local ts = entry.modtime or 0
      table.insert(label_parts, os.date("%Y-%m-%d %H:%M", ts))
   end

   local label = table.concat(label_parts, " • ")
   if label == "" then
      label = (localize and localize("fastsl_state_in_run")) or "In run"
   end

   local meta = {
      ante = ante or 0,
      round = round or 0,
      label = label,
      state = state,
      debug_label = state_debug,
   }

   -- Cache for debug logging elsewhere.
   LOADER._last_metas = LOADER._last_metas or {}
   LOADER._last_metas[entry.file] = meta

   return meta
end

function LOADER.get_backup_files()
   local dir = LOADER.get_backup_dir()
   local entries = {}

   if not love.filesystem.getInfo(dir) then
      return entries
   end

   for _, file in ipairs(love.filesystem.getDirectoryItems(dir)) do
      local full = dir .. "/" .. file
      local info = love.filesystem.getInfo(full)
      if info and info.type == "file" then
         local ante_str, round_str, index_str = string.match(file, "^(%d+)%-(%d+)%-(%d+)%.jkr$")
         local index = tonumber(index_str or "")
         table.insert(entries, {
            file = file,
            modtime = info.modtime,
            index = index or 0,
         })
      end
   end

   table.sort(entries, function(a, b)
      local ma, mb = a.modtime or 0, b.modtime or 0
      if ma ~= mb then
         return ma > mb
      end
      local ia, ib = a.index or 0, b.index or 0
      if ia ~= ib then
         return ia > ib
      end
      return (a.file or "") < (b.file or "")
   end)

   return entries
end

function LOADER.build_backup_node(entry, meta, ordinal_suffix)
   meta = meta or LOADER.get_backup_meta(entry)
   local parts = {}

   if meta.ante and (meta.rel_round or meta.round) then
      local ante_label = (localize and localize("fastsl_ante_label")) or "Ante"
      local round_label = (localize and localize("fastsl_round_label")) or "Round"
      -- Display the actual game round (which starts at 0) rather than
      -- the per-ante relative index used internally for grouping.
      local round_value = meta.round or meta.rel_round
      table.insert(
         parts,
         ante_label .. " " .. tostring(meta.ante) .. "  " .. round_label .. " " .. tostring(round_value)
      )
   end
   if meta.label then
      table.insert(parts, meta.label)
   end

   local label = table.concat(parts, "  •  ")

   if ordinal_suffix and ordinal_suffix ~= "" then
      label = label .. " " .. ordinal_suffix
   end

   return {
      n = G.UIT.R,
      config = { align = "cm", padding = 0.05 },
      nodes = {
         {
            n = G.UIT.R,
            config = {
               button = "loader_backup_restore",
               align = "cl",
               colour = G.C.BLUE,
               minw = 9.6,
               maxw = 9.6,
               padding = 0.1,
               r = 0.1,
               hover = true,
               shadow = true,
               ref_table = { file = entry.file },
            },
            nodes = {
               {
                  n = G.UIT.T,
                  config = {
                     text = label,
                     colour = G.C.UI.TEXT_LIGHT,
                     scale = 0.45,
                  },
               },
            },
         },
      },
   }
end

function LOADER.get_backups_page(args)
   local entries = args.entries or {}
   local per_page = args.per_page or 8
   local page_num = args.page_num or 1

   local content
   if #entries == 0 then
      content = {
         n = G.UIT.T,
         config = {
            text = (localize and localize("fastsl_no_backups")) or "No backups yet",
            colour = G.C.UI.TEXT_LIGHT,
            scale = 0.5,
         },
      }
   else
      local nodes = {}
      local offset = (page_num - 1) * per_page
      local max_index = math.min(#entries - offset, per_page)

      -- First pass over all entries: collect metadata and find the
      -- minimum round per ante so that we can later compute a
      -- per-ante "relative round" index (rounds reset to 1 when
      -- starting a new ante).
      local metas_all = {}
      local ante_min_round = {}
      for idx, entry in ipairs(entries) do
         local meta = LOADER.get_backup_meta(entry)
         metas_all[idx] = meta

         local ante = meta.ante or 0
         local round = meta.round or 0
         if ante_min_round[ante] == nil or round < ante_min_round[ante] then
            ante_min_round[ante] = round
         end
      end

      -- Second pass: assign a per-ante relative round number starting
      -- at 1 for the first saved state in each ante, and count how
      -- many saves share each (ante, rel_round, label) key so we can
      -- give them stable ordinals.
      local label_totals = {}
      for _, meta in ipairs(metas_all) do
         local ante = meta.ante or 0
         local round = meta.round or 0
         local base = ante_min_round[ante] or 0
         meta.rel_round = (round - base) + 1

         local key = tostring(ante) .. ":" .. tostring(meta.rel_round or 0) .. ":" .. (meta.label or "")
         label_totals[key] = (label_totals[key] or 0) + 1
      end

      -- Third pass over all entries (from newest to oldest) to assign
      -- ordinals where the oldest save for a given label gets "1" and
      -- newer ones get higher numbers.
      local label_seen_from_newest = {}
      local ordinals = {}
      for idx, entry in ipairs(entries) do
         local meta = metas_all[idx]
         local ante = meta.ante or 0
         local rel_round = meta.rel_round or meta.round or 0
         local key = tostring(ante) .. ":" .. tostring(rel_round) .. ":" .. (meta.label or "")
         label_seen_from_newest[key] = (label_seen_from_newest[key] or 0) + 1
         local total = label_totals[key] or label_seen_from_newest[key]
         -- Newest gets highest number; oldest (last) gets 1.
         ordinals[idx] = total - label_seen_from_newest[key] + 1
      end

      -- Finally, build only the nodes that belong to this page.
      for i = 1, max_index do
         local entry = entries[offset + i]
         local global_index = offset + i
         local meta = metas_all[global_index]
         local ordinal_suffix = tostring(ordinals[global_index] or 1)

         table.insert(nodes, LOADER.build_backup_node(entry, meta, ordinal_suffix))
      end

      content = {
         n = G.UIT.R,
         config = { align = "tm", padding = 0.05, r = 0.1 },
         nodes = nodes,
      }
   end

   return {
      n = G.UIT.ROOT,
      config = {
         align = (#entries == 0 and "cm" or "tm"),
         minw = 10,
         minh = 6,
         r = 0.1,
         colour = G.C.CLEAR,
      },
      nodes = { content },
   }
end

function G.UIDEF.fast_loader_backups()
   local entries = LOADER.get_backup_files()
   local per_page = 8

   local total_pages = math.max(1, math.ceil(#entries / per_page))
   local page_numbers = {}
   for i = 1, total_pages do
      local pattern = (localize and localize("fastsl_page_label")) or "Page %d/%d"
      page_numbers[i] = string.format(pattern, i, total_pages)
   end

   local backups_box = UIBox({
      definition = LOADER.get_backups_page({ entries = entries, per_page = per_page, page_num = 1 }),
      config = { type = "cm" },
   })

   return create_UIBox_generic_options({
      back_func = "options",
      contents = {
         {
            n = G.UIT.R,
            config = { align = "cm" },
            nodes = {
               { n = G.UIT.O, config = { id = "loader_backups", object = backups_box } },
            },
         },
         {
            n = G.UIT.R,
            config = { align = "cm", colour = G.C.CLEAR },
            nodes = {
               create_option_cycle({
                  options = page_numbers,
                  current_option = 1,
                  opt_callback = "loader_backup_update_page",
                  opt_args = { ui = backups_box, per_page = per_page, entries = entries },
                  w = 4.5,
                  colour = G.C.RED,
                  cycle_shoulders = false,
                  no_pips = true,
               }),
            },
         },
         {
            n = G.UIT.R,
            config = { align = "cm", colour = G.C.CLEAR },
            nodes = {
               {
                  n = G.UIT.C,
                  config = { align = "cm", padding = 0.1 },
                  nodes = {
                     UIBox_button({
                        button = "loader_backup_reload",
                        label = { (localize and localize("fastsl_reload_list")) or "Reload list" },
                        minw = 4,
                     }),
                  },
               },
               {
                  n = G.UIT.C,
                  config = { align = "cm", padding = 0.1 },
                  nodes = {
                     UIBox_button({
                        button = "loader_backup_delete_all",
                        label = { (localize and localize("fastsl_delete_all")) or "Delete all" },
                        minw = 4,
                     }),
                  },
               },
            },
         },
      },
   })
end

-- Inject a "Backups" button into the in-run Options menu.
LOADER._create_UIBox_options = create_UIBox_options

function create_UIBox_options()
   local ui = LOADER._create_UIBox_options()

   if G.STAGE == G.STAGES.RUN then
      local n1 = ui.nodes and ui.nodes[1]
      local n2 = n1 and n1.nodes and n1.nodes[1]
      local n3 = n2 and n2.nodes and n2.nodes[1]

      if n3 and n3.nodes then
         local button = UIBox_button({
            button = "loader_backup_open",
            label = { (localize and localize("fastsl_backups_button")) or "Backups" },
            minw = 5,
         })
         table.insert(n3.nodes, button)
      end
   end

   return ui
end
