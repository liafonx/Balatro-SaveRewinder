if not REWINDER then REWINDER = {} end

local UIShared = require("UIShared")
local Layout = require("UILayout")
local UIIconFactory = require("UIIconFactory")

local loc = UIShared.loc

local function build_page_cycle_config(page_numbers, initial_page, saves_box, per_page, entries)
   return {
      options = page_numbers,
      current_option = initial_page,
      opt_callback = "rewinder_save_update_page",
      opt_args = { ui = saves_box, per_page = per_page, entries = entries },
   }
end

local function dim_colour(colour, factor)
   if type(colour) ~= "table" then return colour end
   factor = factor or 0.45
   return {
      (colour[1] or 1) * factor,
      (colour[2] or 1) * factor,
      (colour[3] or 1) * factor,
      colour[4] or 1,
   }
end

function G.UIDEF.rewinder_saves(opts)
   opts = opts or {}
   local loading_state = opts.loading_state
   local loading_mode = loading_state ~= nil

   local entries = {}
   if not loading_mode then
      local get_entries = REWINDER._get_displayed_entries or REWINDER.get_save_files
      entries = get_entries()
   end
   local per_page = 8

   local total_pages = math.max(1, math.ceil(#entries / per_page))
   local page_numbers = UIShared.build_page_numbers(total_pages)

   local initial_page = 1
   if not loading_mode then
      local SM = REWINDER._SaveManager
      local current_idx = SM and (SM.current_index or SM.find_current_index and SM.find_current_index())
      local display_idx = current_idx
      if REWINDER._filter_active and current_idx then
         display_idx = REWINDER._key_save_reverse_map and REWINDER._key_save_reverse_map[current_idx] or nil
      end
      if display_idx and display_idx >= 1 then
         initial_page = math.ceil(display_idx / per_page)
      end
   end
   if REWINDER.ensure_meta_window_for_page and not REWINDER._filter_active and not loading_mode then
      REWINDER.ensure_meta_window_for_page(initial_page, per_page, 4)
   end

   local saves_box = UIBox({
      definition = REWINDER.get_saves_page({
         entries = entries,
         per_page = per_page,
         page_num = initial_page,
         loading_state = loading_state,
      }),
      config = { type = "cm" },
   })

   if not REWINDER._saves_ui_refs then REWINDER._saves_ui_refs = {} end
   REWINDER._saves_ui_refs.saves_box = saves_box
   REWINDER._saves_ui_refs.per_page = per_page
   REWINDER._saves_ui_refs.entries = entries
   REWINDER._saves_ui_refs.page_numbers = page_numbers
   REWINDER._saves_ui_refs.loading_state = loading_state

   local mark_label = REWINDER._mark_active and loc("rewinder_mark_keys_active", "Save marking changes")
      or loc("rewinder_mark_keys", "Edit key saves")
   local filter_label = REWINDER._filter_active and loc("rewinder_filter_keys_active", "Return to all saves")
      or loc("rewinder_filter_keys", "Check key saves")
   local rename_inactive_colour = UIShared.get_pillar_namebox_colour()
   local save_window_outline_colour = UIShared.get_saves_outline_colour()
   local mark_button_colour = REWINDER._mark_active and (G.C.RED or {0.9, 0.2, 0.2, 1}) or (REWINDER.KEY_SAVE_COLOR or Layout.KEY_SAVE_COLOR)
   local rename_button_colour = REWINDER._rename_active and (G.C.RED or {0.9, 0.2, 0.2, 1}) or rename_inactive_colour
   local jump_button_colour = G.C.ORANGE or {1, 0.6, 0.2, 1}
   local filter_button_colour = G.C.BLUE
   local icon_button_border_colour = UIShared.get_icon_button_border_colour()
   local disabled_icon_button_border_colour = UIShared.get_icon_button_disabled_border_colour()
   local mark_enabled = (not REWINDER._rename_active) and (not loading_mode)
   local rename_enabled = (not REWINDER._mark_active) and (not loading_mode)
   local jump_enabled = (not (REWINDER._rename_active or REWINDER._mark_active)) and (not loading_mode)
   local filter_enabled = not loading_mode
   local mark_button_ref = { label = { text = mark_label } }
   local filter_button_ref = { label = { text = filter_label } }
   REWINDER._saves_ui_refs.mark_button_ref = mark_button_ref
   REWINDER._saves_ui_refs.filter_button_ref = filter_button_ref

   local cycle_config = build_page_cycle_config(page_numbers, initial_page, saves_box, per_page, entries)
   REWINDER._saves_ui_refs.cycle_config = cycle_config

   local page_cycle = create_option_cycle({
      id = "rewinder_page_cycle",
      options = cycle_config.options,
      current_option = cycle_config.current_option,
      opt_callback = cycle_config.opt_callback,
      opt_args = cycle_config.opt_args,
      w = 4.5,
      colour = G.C.BLUE,
      cycle_shoulders = true,
      no_pips = true,
      focus_args = { nav = "wide" },
   })

   return create_UIBox_generic_options({
      back_func = "rewinder_save_close",
      minw = Layout.SAVE_ENTRY_W,
      back_id = "rewinder_back",
      outline_colour = save_window_outline_colour,
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
            nodes = { page_cycle },
         },
         {
            n = G.UIT.R,
            config = { align = "cm", colour = G.C.CLEAR },
            nodes = {
               {
                  n = G.UIT.C,
                  config = { align = "cm", minw = Layout.MODE_ROW_HALF_W, padding = 0.05 },
                  nodes = {
                     UIBox_button({
                        id = "rewinder_btn_filter_keys",
                        button = filter_enabled and "rewinder_btn_filter_keys" or nil,
                        label = {},
                        dynamic_label = filter_button_ref.label,
                        minw = Layout.FILTER_BUTTON_W,
                        scale = 0.42,
                        colour = filter_enabled and filter_button_colour or dim_colour(filter_button_colour),
                        focus_args = { nav = "wide" },
                     }),
                  },
               },
               {
                  n = G.UIT.C,
                  config = { align = "cm", minw = Layout.MODE_ROW_HALF_W, padding = 0.05 },
                  nodes = {
                     {
                        n = G.UIT.R,
                        config = { align = "cm", colour = G.C.CLEAR },
                        nodes = {
                           UIIconFactory.build_icon_button({
                              id = "rewinder_btn_mark_keys",
                              button = "rewinder_btn_mark_keys",
                              fill_id = "rewinder_btn_mark_keys_fill",
                              fill_colour = mark_enabled and mark_button_colour or dim_colour(mark_button_colour),
                              icon = REWINDER.create_star_icon(G.C.WHITE, Layout.ICON_BUTTON_ICON_SIZE, Layout.ICON_BUTTON_ICON_SIZE),
                              border_colour = icon_button_border_colour,
                              disabled_border_colour = disabled_icon_button_border_colour,
                              enabled = mark_enabled,
                              focus_args = { nav = "wide" },
                           }),
                           UIIconFactory.build_icon_button({
                              id = "rewinder_btn_toggle_rename",
                              button = "rewinder_btn_toggle_rename",
                              fill_id = "rewinder_btn_toggle_rename_fill",
                              fill_colour = rename_enabled and rename_button_colour or dim_colour(rename_button_colour),
                              icon = REWINDER.create_pencil_icon(G.C.WHITE, Layout.ICON_BUTTON_ICON_SIZE, Layout.ICON_BUTTON_ICON_SIZE),
                              border_colour = icon_button_border_colour,
                              disabled_border_colour = disabled_icon_button_border_colour,
                              enabled = rename_enabled,
                              ref_table = { mode = "rename" },
                              focus_args = { nav = "wide" },
                           }),
                           UIIconFactory.build_icon_button({
                              id = "rewinder_btn_jump_to_current",
                              button = "rewinder_save_jump_to_current",
                              fill_id = "rewinder_btn_jump_to_current_fill",
                              fill_colour = jump_enabled and jump_button_colour or dim_colour(jump_button_colour),
                              icon = REWINDER.create_triangle_icon(G.C.WHITE, Layout.ICON_BUTTON_ICON_SIZE, Layout.ICON_BUTTON_ICON_SIZE),
                              border_colour = icon_button_border_colour,
                              disabled_border_colour = disabled_icon_button_border_colour,
                              enabled = jump_enabled,
                              focus_args = { nav = "wide", button = "y", set_button_pip = true },
                           }),
                        },
                     },
                  },
               },
            },
         },
      },
   })
end

-- Build "Rewind to Last Save" button for the Game Over panel.
function REWINDER.create_game_over_rewind_button()
   if not REWINDER.load_and_start_from_file then return nil end
   local label_text = loc("rewinder_game_over_button", "Rewind")
   local label_obj = DynaText({
      string = label_text,
      colours = { G.C.UI.TEXT_DARK },
      scale = 0.3,
      shadow = false,
   })
   return {
      n = G.UIT.R,
      config = { align = "cm" },
      nodes = {{
         n = G.UIT.C,
         config = {
            align = "cm",
            padding = 0,
            r = 0.1,
            hover = true,
            colour = G.C.EDITION,
            button = "rewinder_game_over_rewind",
            minh = 0.4,
            shadow = true,
            outline = 0.7,
            outline_colour = G.C.UI.TEXT_DARK,
            focus_args = { nav = "wide" },
         },
         nodes = {{
            n = G.UIT.R,
            config = { align = "cm", padding = 0, minw = 2.3, maxw = 2.1 },
            nodes = {{
               n = G.UIT.O,
               config = { object = label_obj },
            }},
         }},
      }},
   }
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
         local focus_args = { nav = "wide" }
         if REWINDER.keybinds and REWINDER.keybinds.get_binding then
            local binding = REWINDER.keybinds.get_binding("toggle_saves")
            if binding and binding.controller and not binding.controller["[none]"] then
               for k in pairs(binding.controller) do
                  if k:sub(1, 3) == "gp_" then
                     local btn = k:sub(4)
                     focus_args = { button = btn, set_button_pip = true, nav = "wide" }
                     break
                  end
               end
            end
         end

         local button = UIBox_button({
            button = "rewinder_save_open",
            label = { loc("rewinder_saves_button", "Saves") },
            minw = 5,
            colour = G.C.ORANGE or {1, 0.6, 0.2, 1},
            focus_args = focus_args,
         })
         table.insert(n3.nodes, button)
      end
   end

   return ui
end

return {}
