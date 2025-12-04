--- Antihypertensive Save Manager - UI/BackupsUI.lua
--
-- In-game UI for listing and restoring backups, plus an Options button.

if not ANTIHYP then ANTIHYP = {} end

local function get_backup_meta(entry)
   local dir = ANTIHYP.get_backup_dir()
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
   local state = save.STATE
   if G and G.STATES and state then
      if state == G.STATES.SHOP then
         state_label = (localize and localize("fastsl_state_shop")) or "In shop"
      elseif state == G.STATES.DRAW_TO_HAND then
         state_label = (localize and localize("fastsl_state_start_round")) or "Start of round"
      elseif state == G.STATES.SELECTING_HAND then
         state_label = (localize and localize("fastsl_state_selecting_hand")) or "Selecting hand"
      elseif state == G.STATES.ROUND_EVAL or state == G.STATES.HAND_PLAYED then
         state_label = (localize and localize("fastsl_state_end_of_hand")) or "End of hand"
      elseif state == G.STATES.BLIND_SELECT then
         state_label = (localize and localize("fastsl_state_choose_blind")) or "Choosing next blind"
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

   return {
      ante = ante or 0,
      round = round or 0,
      label = label,
   }
end

function ANTIHYP.get_backup_files()
   local dir = ANTIHYP.get_backup_dir()
   local entries = {}

   if not love.filesystem.getInfo(dir) then
      return entries
   end

   for _, file in ipairs(love.filesystem.getDirectoryItems(dir)) do
      local full = dir .. "/" .. file
      local info = love.filesystem.getInfo(full)
      if info and info.type == "file" then
         table.insert(entries, { file = file, modtime = info.modtime })
      end
   end

   table.sort(entries, function(a, b)
      return (a.modtime or 0) > (b.modtime or 0)
   end)

   return entries
end

function ANTIHYP.build_backup_node(entry, meta, ordinal_suffix)
   meta = meta or get_backup_meta(entry)
   local parts = {}

   if meta.ante and meta.round then
      local ante_label = (localize and localize("fastsl_ante_label")) or "Ante"
      local round_label = (localize and localize("fastsl_round_label")) or "Round"
      table.insert(parts, ante_label .. " " .. tostring(meta.ante) .. "  " .. round_label .. " " .. tostring(meta.round))
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
               button = "anti_backup_restore",
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

function ANTIHYP.get_backups_page(args)
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

      -- First pass over all entries: collect metadata and total counts
      -- per label so that we can give older saves lower numbers (1 is
      -- the oldest occurrence of that label, even if it is not on the
      -- first page).
      local metas_all = {}
      local label_totals = {}
      for idx, entry in ipairs(entries) do
         local meta = get_backup_meta(entry)
         metas_all[idx] = meta
         -- Group counts by (ante, round, label) so that
         -- numbering restarts for each round.
         local key = tostring(meta.ante or 0) .. ":" .. tostring(meta.round or 0) .. ":" .. (meta.label or "")
         label_totals[key] = (label_totals[key] or 0) + 1
      end

      -- Second pass over all entries (from newest to oldest) to assign
      -- ordinals where the oldest save for a given label gets "1" and
      -- newer ones get higher numbers.
      local label_seen_from_newest = {}
      local ordinals = {}
      for idx, entry in ipairs(entries) do
         local meta = metas_all[idx]
         local key = tostring(meta.ante or 0) .. ":" .. tostring(meta.round or 0) .. ":" .. (meta.label or "")
         label_seen_from_newest[key] = (label_seen_from_newest[key] or 0) + 1
         local total = label_totals[key] or 1
         -- Newest gets highest number; oldest (last) gets 1.
         ordinals[idx] = total - label_seen_from_newest[key] + 1
      end

      -- Finally, build only the nodes that belong to this page.
      for i = 1, max_index do
         local entry = entries[offset + i]
         local global_index = offset + i
         local meta = metas_all[global_index]
         local ordinal_suffix = tostring(ordinals[global_index] or 1)

         table.insert(nodes, ANTIHYP.build_backup_node(entry, meta, ordinal_suffix))
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

function G.UIDEF.antihypertensive_backups()
   local entries = ANTIHYP.get_backup_files()
   local per_page = 8

   local total_pages = math.max(1, math.ceil(#entries / per_page))
   local page_numbers = {}
   for i = 1, total_pages do
      local pattern = (localize and localize("fastsl_page_label")) or "Page %d/%d"
      page_numbers[i] = string.format(pattern, i, total_pages)
   end

   local backups_box = UIBox({
      definition = ANTIHYP.get_backups_page({ entries = entries, per_page = per_page, page_num = 1 }),
      config = { type = "cm" },
   })

   return create_UIBox_generic_options({
      back_func = "options",
      contents = {
         {
            n = G.UIT.R,
            config = { align = "cm" },
            nodes = {
               { n = G.UIT.O, config = { id = "antihyp_backups", object = backups_box } },
            },
         },
         {
            n = G.UIT.R,
            config = { align = "cm", colour = G.C.CLEAR },
            nodes = {
               create_option_cycle({
                  options = page_numbers,
                  current_option = 1,
                  opt_callback = "anti_backup_update_page",
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
                        button = "anti_backup_reload",
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
                        button = "anti_backup_delete_all",
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
ANTIHYP._create_UIBox_options = create_UIBox_options

function create_UIBox_options()
   local ui = ANTIHYP._create_UIBox_options()

   if G.STAGE == G.STAGES.RUN then
      local n1 = ui.nodes and ui.nodes[1]
      local n2 = n1 and n1.nodes and n1.nodes[1]
      local n3 = n2 and n2.nodes and n2.nodes[1]

      if n3 and n3.nodes then
         local button = UIBox_button({
            button = "anti_backup_open",
            label = { (localize and localize("fastsl_backups_button")) or "Backups" },
            minw = 5,
         })
         table.insert(n3.nodes, button)
      end
   end

   return ui
end
