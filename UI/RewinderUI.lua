--- Save Rewinder - UI/RewinderUI.lua
--
-- In-game UI for listing and restoring saves, plus an Options button.

if not REWINDER then REWINDER = {} end

local SAVE_ENTRY_W = 8.8

-- Get dot color based on round number (odd/even)
-- Colors chosen for good contrast against blue background (G.C.BLUE)
function REWINDER.get_round_color(round)
   if round == nil then return G.C.UI.TEXT_LIGHT end
   
   -- Use different bright colors for odd and even rounds
   if round % 2 == 0 then
      -- Even rounds: bright orange
      return G.C.ORANGE or {1, 0.7, 0.2, 1}
   else
      -- Odd rounds: bright green (good contrast on blue)
      return G.C.YELLOW
   end
end

function REWINDER.build_save_node(entry, meta, ordinal_suffix, is_first_entry, opts)
   -- Use entry as array (no keys, accessed by index)
   if not entry then return nil end
   opts = opts or {}

   -- Build ante/round text
   local ante_text = ""
   if entry[REWINDER.ENTRY_ANTE] then
      local ante_label = (localize and localize("rewinder_ante_label")) or "Ante"
      local round_label = (localize and localize("rewinder_round_label")) or "Round"
      ante_text = ante_label .. " " .. tostring(entry[REWINDER.ENTRY_ANTE])
      -- Add round number if available
      if entry[REWINDER.ENTRY_ROUND] ~= nil then
         local ante_round_spacing = (localize and localize("rewinder_ante_round_spacing")) or " "
         ante_text = ante_text .. ante_round_spacing .. round_label .. " " .. tostring(entry[REWINDER.ENTRY_ROUND])
      end
   end
   
   -- Build state label text
   local state_text = ""
   if entry[REWINDER.ENTRY_STATE] ~= nil then
      -- Use action_type (play/discard) and is_opening_pack (boolean) for label generation
      local label = (REWINDER.StateSignature and REWINDER.StateSignature.get_label_from_state(entry[REWINDER.ENTRY_STATE], entry[REWINDER.ENTRY_ACTION_TYPE], entry[REWINDER.ENTRY_IS_OPENING_PACK])) or "state"
      if label and label ~= "state" then
         local label_key = label:gsub(" ", "_"):gsub("%(", ""):gsub("%)", "")
         local localized = nil
         if label_key == "opening_pack" then
            localized = localize and localize("rewinder_state_opening_pack")
         elseif label_key == "start_of_round" then
            localized = localize and localize("rewinder_state_start_round")
         elseif label_key:match("selecting_hand") then
            -- Handle selecting_hand with action type
            if entry[REWINDER.ENTRY_ACTION_TYPE] == "play" then
               localized = localize and localize("rewinder_state_selecting_hand_play")
            elseif entry[REWINDER.ENTRY_ACTION_TYPE] == "discard" then
               localized = localize and localize("rewinder_state_selecting_hand_discard")
            else
               localized = localize and localize("rewinder_state_start_round")
            end
         elseif label_key == "end_of_round" then
            localized = localize and localize("rewinder_state_end_of_round")
         elseif label_key == "choose_blind" then
            localized = localize and localize("rewinder_state_choose_blind")
         elseif label_key == "shop" then
            localized = localize and localize("rewinder_state_shop")
         else
            localized = localize and localize("rewinder_state_"..label_key)
         end
         -- Use localized text if available, otherwise use the raw label
         state_text = (localized and localized ~= "") and localized or label
      end
   end

   -- Build tailing number text (at the end)
   -- For selecting_hand with action_type, use label_value (discards_used or hands_played)
   -- For start/end of round, don't show ordinal (they appear once per round)
   -- For others, use ordinal_suffix
   local tailing_number_text = ""
   local st = G and G.STATES
   local is_selecting_hand_with_action = st and entry[REWINDER.ENTRY_STATE] == st.SELECTING_HAND and entry[REWINDER.ENTRY_ACTION_TYPE]
   
   -- Check if this is start of round or end of round (don't show ordinal for these)
   local label = (REWINDER.StateSignature and REWINDER.StateSignature.get_label_from_state(entry[REWINDER.ENTRY_STATE], entry[REWINDER.ENTRY_ACTION_TYPE], entry[REWINDER.ENTRY_IS_OPENING_PACK])) or ""
   local is_start_or_end_round = (label == "start of round" or label == "end of round")
   
   if is_selecting_hand_with_action and meta and meta.label_value then
      -- Use label_value (discards_used or hands_played) as tailing number
      tailing_number_text = tostring(meta.label_value)
   elseif not is_start_or_end_round and ordinal_suffix and ordinal_suffix ~= "" then
      -- Use ordinal_suffix for other states (but not start/end of round)
      tailing_number_text = ordinal_suffix
   end

   -- Use cached is_current flag (always set by _update_cache_current_flags before UI build)
   local is_current = (entry[REWINDER.ENTRY_IS_CURRENT] == true)
   
   -- Background color
   local button_colour = G.C.BLUE
   local default_text_colour = G.C.UI.TEXT_LIGHT
   
   -- Get dot color for round number (odd/even)
   local dot_colour = default_text_colour
   if not is_current and entry[REWINDER.ENTRY_ROUND] ~= nil then
      dot_colour = REWINDER.get_round_color(entry[REWINDER.ENTRY_ROUND])
   end
   
   if is_current then
      -- Use orange color for highlight
      button_colour = G.C.ORANGE or {1, 0.6, 0.2, 1}  -- Fallback orange
      dot_colour = G.C.WHITE  -- White dot for better contrast on orange
      default_text_colour = G.C.WHITE
      -- Add visual indicator prefix to ante text
      ante_text = "▶ " .. ante_text
   end
   
   -- Build text nodes - separate nodes for text and colored dot
   local text_nodes = {}
   
   if ante_text ~= "" then
      table.insert(text_nodes, {
         n = G.UIT.T,
         config = {
            text = ante_text,
            colour = default_text_colour,
            scale = 0.45,
         },
      })
   end
   
   -- Add colored separator (always show if we have ante text)
   local separator = (localize and localize("rewinder_separator")) or " | "
   if ante_text ~= "" then
      table.insert(text_nodes, {
         n = G.UIT.T,
         config = {
            text = separator,
            colour = dot_colour,
            scale = 0.45,
         },
      })
   end
   
   -- Build state and tailing number text
   local state_tailing_text = ""
   if state_text ~= "" then
      state_tailing_text = state_text
      if tailing_number_text ~= "" then
         -- Use different spacing for selecting_hand with action vs other states
         local spacing
         if is_selecting_hand_with_action then
            spacing = localize and localize("rewinder_card_number_spacing")
            if spacing == nil then spacing = " " end
         else
            spacing = localize and localize("rewinder_tailing_number_spacing")
            if spacing == nil then spacing = " " end
         end
         state_tailing_text = state_tailing_text .. spacing .. tailing_number_text
      end
   elseif tailing_number_text ~= "" then
      local spacing = localize and localize("rewinder_tailing_number_spacing")
      if spacing == nil then spacing = " " end
      state_tailing_text = spacing .. tailing_number_text
   end
   
   if state_tailing_text ~= "" then
      table.insert(text_nodes, {
         n = G.UIT.T,
         config = {
            text = state_tailing_text,
            colour = default_text_colour,
            scale = 0.45,
         },
      })
   end
   
   return {
      n = G.UIT.R,
      config = { align = "cm", padding = 0.05 },
      nodes = {
         {
            n = G.UIT.R,
            config = {
               id = opts.id,
               button = "rewinder_save_restore",
               align = "cl",
               colour = button_colour,
               minw = SAVE_ENTRY_W,
               maxw = SAVE_ENTRY_W,
               padding = 0.1,
               r = 0.1,
               hover = true,
               can_collide = true,
               shadow = true,
               focus_args = { snap_to = opts.snap_to == true },
               ref_table = { file = entry[REWINDER.ENTRY_FILE] },
            },
            nodes = text_nodes,
         },
      },
   }
end

function REWINDER.get_saves_page(args)
   local entries = args.entries or {}
   local per_page = args.per_page or 8
   local page_num = args.page_num or 1
   

   local content
   if #entries == 0 then
      content = {
         n = G.UIT.T,
         config = {
            text = (localize and localize("rewinder_no_saves")) or "No saves yet",
            colour = G.C.UI.TEXT_LIGHT,
            scale = 0.5,
         },
      }
   else
      local nodes = {}
      local offset = (page_num - 1) * per_page
      local max_index = math.min(#entries - offset, per_page)

      -- Collect the entries for the current page and ensure their metadata is loaded.
      local page_entries = {}
      for i = 1, max_index do
         local entry = entries[offset + i]
         page_entries[i] = entry
         if entry and not entry[REWINDER.ENTRY_SIGNATURE] and REWINDER.get_save_meta then
            REWINDER.get_save_meta(entry)
         end
      end

      -- First pass: compute labels for entries that already have metadata and
      -- track minimum round per state label. This avoids force-loading
      -- off-page entries.
      local label_min_round = {}
      local meta_cache = {}
      local st = G and G.STATES
      
      for _, entry in ipairs(entries) do
         if entry and entry[REWINDER.ENTRY_SIGNATURE] then
         local label = (REWINDER.StateSignature and REWINDER.StateSignature.get_label_from_state(entry[REWINDER.ENTRY_STATE], entry[REWINDER.ENTRY_ACTION_TYPE], entry[REWINDER.ENTRY_IS_OPENING_PACK])) or ""
         local round = entry[REWINDER.ENTRY_ROUND] or 0
         
         if not meta_cache[entry] then meta_cache[entry] = {} end
         meta_cache[entry].label = label
            meta_cache[entry].action_type = entry[REWINDER.ENTRY_ACTION_TYPE]
         
         if label ~= "" and not (label:match("selecting hand") and entry[REWINDER.ENTRY_ACTION_TYPE]) then
            if label_min_round[label] == nil or round < label_min_round[label] then
               label_min_round[label] = round
               end
            end
         end
      end

      -- Second pass: assign label_value for entries with metadata.
      local label_totals = {}
      for _, entry in ipairs(entries) do
         if entry and entry[REWINDER.ENTRY_SIGNATURE] then
         local meta = meta_cache[entry] or {}
         local label = meta.label or ""
         local round = entry[REWINDER.ENTRY_ROUND] or 0
         local ante = entry[REWINDER.ENTRY_ANTE] or 0
         
         local label_value = 0
         local is_selecting_hand_with_action = st and entry[REWINDER.ENTRY_STATE] == st.SELECTING_HAND and entry[REWINDER.ENTRY_ACTION_TYPE]
         
         if is_selecting_hand_with_action then
            if entry[REWINDER.ENTRY_ACTION_TYPE] == "discard" and entry[REWINDER.ENTRY_DISCARDS_USED] ~= nil then
               label_value = entry[REWINDER.ENTRY_DISCARDS_USED]
            elseif entry[REWINDER.ENTRY_ACTION_TYPE] == "play" and entry[REWINDER.ENTRY_HANDS_PLAYED] ~= nil then
               label_value = entry[REWINDER.ENTRY_HANDS_PLAYED]
            else
               local base = (label ~= "" and label_min_round[label]) or round
               label_value = (round - base) + 1
            end
         else
            local base = (label ~= "" and label_min_round[label]) or round
            label_value = (round - base) + 1
         end
         
         meta.label_value = label_value

         local key = tostring(ante) .. ":" .. tostring(label_value) .. ":" .. label
         label_totals[key] = (label_totals[key] or 0) + 1
         end
      end

      -- Third pass: assign ordinals for entries with metadata (newest -> oldest).
      local label_seen_from_newest = {}
      local ordinals = {}
      for idx, entry in ipairs(entries) do
         if entry and entry[REWINDER.ENTRY_SIGNATURE] then
         local meta = meta_cache[entry] or {}
         local ante = entry[REWINDER.ENTRY_ANTE] or 0
         local label_value = meta.label_value or 0
         local label = meta.label or ""
         local key = tostring(ante) .. ":" .. tostring(label_value) .. ":" .. label
         label_seen_from_newest[key] = (label_seen_from_newest[key] or 0) + 1
         local total = label_totals[key] or label_seen_from_newest[key]
         ordinals[idx] = total - label_seen_from_newest[key] + 1
         end
      end

      -- Finally, build only the nodes that belong to this page.
      for i = 1, max_index do
         local entry = entries[offset + i]
         local global_index = offset + i
         local meta = meta_cache[entry] or {}
         local ordinal_suffix = tostring(ordinals[global_index] or 1)
      local is_first_entry = (global_index == 1)

         table.insert(nodes, REWINDER.build_save_node(entry, meta, ordinal_suffix, is_first_entry, {
            id = "rewinder_save_entry_" .. tostring(global_index),
            snap_to = (entry and entry[REWINDER.ENTRY_IS_CURRENT] == true),
         }))
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
         minw = SAVE_ENTRY_W,
         minh = 6,
         r = 0.1,
         colour = G.C.CLEAR,
      },
      nodes = { content },
   }
end

function G.UIDEF.rewinder_saves()
   -- get_save_files() updates cache flags automatically
   local entries = REWINDER.get_save_files()
   local per_page = 8

   local total_pages = math.max(1, math.ceil(#entries / per_page))
   local page_numbers = {}
   for i = 1, total_pages do
      local pattern = (localize and localize("rewinder_page_label")) or "Page %d/%d"
      page_numbers[i] = string.format(pattern, i, total_pages)
   end

   -- Find which page contains the current (highlighted) save
   local initial_page = 1
   for i, entry in ipairs(entries) do
      if entry and entry[REWINDER.ENTRY_IS_CURRENT] == true then
         initial_page = math.ceil(i / per_page)
         break
      end
   end

   local saves_box = UIBox({
      definition = REWINDER.get_saves_page({ entries = entries, per_page = per_page, page_num = initial_page }),
      config = { type = "cm" },
   })

   -- Store references for jump_to_current functionality
   if not REWINDER._saves_ui_refs then REWINDER._saves_ui_refs = {} end
   REWINDER._saves_ui_refs.saves_box = saves_box
   REWINDER._saves_ui_refs.per_page = per_page
   REWINDER._saves_ui_refs.entries = entries
   REWINDER._saves_ui_refs.page_numbers = page_numbers
   
   -- Create cycle config and store it for jump_to_current
   local cycle_config = {
      options = page_numbers,
      current_option = initial_page,
      opt_callback = "rewinder_save_update_page",
      opt_args = { ui = saves_box, per_page = per_page, entries = entries },
   }
   REWINDER._saves_ui_refs.cycle_config = cycle_config

   return create_UIBox_generic_options({
      back_func = "options",
      minw = SAVE_ENTRY_W,
      back_id = "rewinder_back",
      contents = {
         {
            n = G.UIT.R,
            config = { align = "cm" },
            nodes = {
               { n = G.UIT.O, config = { id = "rewinder_saves", object = saves_box } },
            },
         },
         {
            n = G.UIT.R,
            config = { align = "cm", colour = G.C.CLEAR },
            nodes = {
               create_option_cycle({
                  id = "rewinder_page_cycle",
                  options = page_numbers,
                  current_option = initial_page,
                  opt_callback = "rewinder_save_update_page",
                  opt_args = { ui = saves_box, per_page = per_page, entries = entries },
                  w = 4.5,
                  colour = G.C.BLUE,
                  cycle_shoulders = true,
                  no_pips = true,
                  focus_args = { nav = "wide" },
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
                        id = "rewinder_btn_current",
                        button = "rewinder_save_jump_to_current",
                        label = { (localize and localize("rewinder_jump_to_current")) or "Current save" },
                        minw = 3.6,
                        scale = 0.42,
                        colour = G.C.BLUE,
                        focus_args = { nav = "wide", button = "y", set_button_pip = true },
                      }),
                  },
               },
               {
                  n = G.UIT.C,
                  config = { align = "cm", padding = 0.1 },
                  nodes = {
                     UIBox_button({
                        id = "rewinder_btn_delete",
                        button = "rewinder_save_delete_all",
                        label = { (localize and localize("rewinder_delete_all")) or "Delete all" },
                        minw = 3.6,
                        scale = 0.42,
                        focus_args = { nav = "wide" },
                      }),
                  },
               },
            },
         },
      },
   })
end

-- Inject a "Saves" button into the in-run Options menu.
REWINDER._create_UIBox_options = create_UIBox_options

function create_UIBox_options()
   local ui = REWINDER._create_UIBox_options()

   if G.STAGE == G.STAGES.RUN then
      local n1 = ui.nodes and ui.nodes[1]
      local n2 = n1 and n1.nodes and n1.nodes[1]
      local n3 = n2 and n2.nodes and n2.nodes[1]

      if n3 and n3.nodes then
         local button = UIBox_button({
            button = "rewinder_save_open",
            label = { (localize and localize("rewinder_saves_button")) or "Saves" },
            minw = 5,
            colour = G.C.ORANGE or {1, 0.6, 0.2, 1},  -- Orange button to stand out
         })
         table.insert(n3.nodes, button)
      end
   end

   return ui
end
