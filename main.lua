--- Save Rewinder - main.lua
--
-- Steamodded entry point (for config UI only).

REWINDER = REWINDER or {}

SMODS.Atlas {
   key = "modicon",
   path = "modicon.png",
   px = 32,
   py = 32,
}:register()

if SMODS and SMODS.current_mod then
   REWINDER.mod = SMODS.current_mod
   REWINDER.config = REWINDER.mod.config or {}

   local function _rewinder_keybind_label(name)
      if REWINDER and REWINDER.keybinds and REWINDER.keybinds.get_binding and REWINDER.keybinds.format_binding then
         return REWINDER.keybinds.format_binding(REWINDER.keybinds.get_binding(name))
      end
      return (localize and localize("rewinder_keybind_none")) or "[none]"
   end

   local function _rewinder_keybind_row(name, label_key)
      local ref_table = {
         name = name,
         label = { text = _rewinder_keybind_label(name) },
      }
      REWINDER._keybind_label_refs = REWINDER._keybind_label_refs or {}
      REWINDER._keybind_label_refs[#REWINDER._keybind_label_refs + 1] = ref_table
      return {
         n = G.UIT.R,
         config = { align = "cl", padding = 0.04 },
         nodes = {
            {
               n = G.UIT.C,
               config = { align = "cl", padding = 0 },
               nodes = {
                  {
                     n = G.UIT.T,
                     config = {
                        text = localize and localize(label_key) or label_key,
                        scale = 0.35,
                        colour = G.C.UI.TEXT_LIGHT,
                     },
                  },
               },
            },
            {
               n = G.UIT.C,
               config = { align = "cr", padding = 0.05 },
               nodes = {
                  UIBox_button({
                     ref_table = ref_table,
                     button = "rewinder_change_keybind",
                     label = {},
                     dynamic_label = ref_table.label,
                     minh = 0.32,
                     minw = 3,
                     col = true,
                     scale = 0.3,
                     colour = G.C.GREY,
                  }),
               },
            },
         },
      }
   end

   SMODS.current_mod.config_tab = function()
      return {
         n = G.UIT.ROOT,
         config = { r = 0.1, minw = 9, align = "tm", padding = 0.2, colour = G.C.BLACK },
         nodes = {
            -- Main row with two columns
            {
               n = G.UIT.R,
               config = { padding = 0.1 },
               nodes = {
                  -- Left column: Auto-Save Triggers
                  {
                     n = G.UIT.C,
                     config = { align = "tm", padding = 0.1 },
                     nodes = {
                        -- Section header
                        {
                           n = G.UIT.R,
                           config = { align = "cm", padding = 0.05 },
                           nodes = {
                              {
                                 n = G.UIT.T,
                                 config = {
                                    text = localize and localize("rewinder_section_auto_save") or "Auto-Save Triggers",
                                    colour = G.C.UI.TEXT_LIGHT,
                                    scale = 0.45,
                                 },
                              },
                           },
                        },
                        -- Toggles
                        {
                           n = G.UIT.R,
                           config = { align = "cl", padding = 0.02 },
                           nodes = {
                              create_toggle({
                                 label = localize and localize("rewinder_save_on_blind") or "Save when choosing blind",
                                 ref_table = REWINDER.config,
                                 ref_value = "save_on_blind",
                              }),
                           },
                        },
                        {
                           n = G.UIT.R,
                           config = { align = "cl", padding = 0.02 },
                           nodes = {
                              create_toggle({
                                 label = localize and localize("rewinder_save_on_selecting_hand") or "Save when selecting hand",
                                 ref_table = REWINDER.config,
                                 ref_value = "save_on_selecting_hand",
                              }),
                           },
                        },
                        {
                           n = G.UIT.R,
                           config = { align = "cl", padding = 0.02 },
                           nodes = {
                              create_toggle({
                                 label = localize and localize("rewinder_save_on_round_end") or "Save at end of round",
                                 ref_table = REWINDER.config,
                                 ref_value = "save_on_round_end",
                              }),
                           },
                        },
                        {
                           n = G.UIT.R,
                           config = { align = "cl", padding = 0.02 },
                           nodes = {
                              create_toggle({
                                 label = localize and localize("rewinder_save_on_shop") or "Save in shop",
                                 ref_table = REWINDER.config,
                                 ref_value = "save_on_shop",
                              }),
                           },
                        },
                     },
                  },
                  -- Right column: Display Options
                  {
                     n = G.UIT.C,
                     config = { align = "tm", padding = 0.1 },
                     nodes = {
                        -- Section header
                        {
                           n = G.UIT.R,
                           config = { align = "cm", padding = 0.05 },
                           nodes = {
                              {
                                 n = G.UIT.T,
                                 config = {
                                    text = localize and localize("rewinder_section_display") or "Display Options",
                                    colour = G.C.UI.TEXT_LIGHT,
                                    scale = 0.45,
                                 },
                              },
                           },
                        },
                        -- Toggles
                        {
                           n = G.UIT.R,
                           config = { align = "cl", padding = 0.02 },
                           nodes = {
                              create_toggle({
                                 label = localize and localize("rewinder_show_blind_image") or "Show blind image",
                                 ref_table = REWINDER.config,
                                 ref_value = "show_blind_image",
                              }),
                           },
                        },
                        {
                           n = G.UIT.R,
                           config = { align = "cl", padding = 0.02 },
                           nodes = {
                              create_toggle({
                                 label = localize and localize("rewinder_animate_blind_image") or "Blind image effects",
                                 ref_table = REWINDER.config,
                                 ref_value = "animate_blind_image",
                              }),
                           },
                        },
                     },
                  },
               },
            },
            -- Advanced section (full width)
            {
               n = G.UIT.R,
               config = { align = "cm", padding = 0.02 },
               nodes = {
                  {
                     n = G.UIT.T,
                     config = {
                        text = localize and localize("rewinder_section_advanced") or "Advanced",
                        colour = G.C.UI.TEXT_LIGHT,
                        scale = 0.45,
                     },
                  },
               },
            },
            {
               n = G.UIT.R,
               config = { align = "cm", padding = 0.03 },
               nodes = {
                  create_option_cycle({
                     label = localize and localize("rewinder_max_antes_per_run") or "Max saved antes per run",
                     options = {
                        "1",
                        "2",
                        "4",
                        "6",
                        "8",
                        "16",
                        (localize and localize("rewinder_all_label")) or "All",
                     },
                     current_option = REWINDER.config.keep_antes or 7,
                     colour = G.C.BOOSTER,
                     w = 4.5,
                     text_scale = 0.4,
                     scale = 0.8,
                     ref_table = REWINDER.config,
                     ref_value = "keep_antes",
                     opt_callback = "rewinder_config_change",
                  }),
               },
            },
            -- Debug toggle and Delete button on same row
            {
               n = G.UIT.R,
               config = { align = "cm", padding = 0.05 },
               nodes = {
                  {
                     n = G.UIT.C,
                     config = { align = "cm", padding = 0.1 },
                     nodes = {
                        create_toggle({
                           label = localize and localize("rewinder_debug_saves") or "Debug: verbose logging",
                           ref_table = REWINDER.config,
                           ref_value = "debug_saves",
                        }),
                     },
                  },
                  {
                     n = G.UIT.C,
                     config = { align = "cm", padding = 0.1 },
                     nodes = {
                        UIBox_button({
                           label = { (localize and localize("rewinder_delete_all_saves_button")) or "Delete all saves" },
                           button = "rewinder_save_delete_all",
                           minw = 3,
                           minh = 0.6,
                           scale = 0.4,
                           colour = G.C.RED,
                        }),
                     },
                  },
               },
            },
         },
      }
   end

   REWINDER.keybinds_tab = function()
      REWINDER._keybind_label_refs = {}
      return {
         n = G.UIT.ROOT,
         config = { r = 0.1, minw = 9, align = "tm", padding = 0.2, colour = G.C.BLACK },
         nodes = {
            {
               n = G.UIT.R,
               config = { align = "cm", padding = 0.05 },
               nodes = {
                  {
                     n = G.UIT.T,
                     config = {
                        text = localize and localize("rewinder_keybinds_title") or "Keybinds",
                        colour = G.C.UI.TEXT_LIGHT,
                        scale = 0.45,
                     },
                  },
               },
            },
            _rewinder_keybind_row("step_back", "rewinder_keybind_step_back"),
            _rewinder_keybind_row("toggle_saves", "rewinder_keybind_toggle_saves"),
            _rewinder_keybind_row("quick_saveload", "rewinder_keybind_quick_saveload"),
            {
               n = G.UIT.R,
               config = { align = "cm", padding = 0.06 },
               nodes = {
                  UIBox_button({
                     label = { localize and localize("rewinder_keybind_reset") or "Reset to defaults" },
                     button = "rewinder_reset_keybinds",
                     minw = 3.6,
                     minh = 0.6,
                     scale = 0.35,
                     colour = G.C.RED,
                  }),
               },
            },
            {
               n = G.UIT.R,
               config = { align = "cm", padding = 0.06 },
               nodes = {
                  {
                     n = G.UIT.T,
                     config = {
                        text = localize and localize("rewinder_keybind_hint") or "Click a keybind and press keys. Esc clears it.",
                        colour = G.C.UI.TEXT_LIGHT,
                        scale = 0.3,
                     },
                  },
               },
            },
         },
      }
   end

   G.FUNCS.rewinder_change_keybind = function(e)
      if not e or not e.config or not e.config.ref_table then return end
      local name = e.config.ref_table.name
      local dynamic_label = e.config.ref_table.label
      if dynamic_label then
         dynamic_label.text = localize and localize("rewinder_keybind_waiting") or "Waiting for input..."
      end

      if REWINDER and REWINDER.keybinds and REWINDER.keybinds.record then
         REWINDER.keybinds.record({
            name = name,
            callback = function(keys)
               if not keys then
                  if dynamic_label then dynamic_label.text = "error" end
                  return
               end
               if REWINDER.keybinds.update_binding then
                  -- update_binding merges the new keys into keyboard/controller sub-tables
                  REWINDER.keybinds.update_binding(name, keys)
               elseif REWINDER.keybinds.set_binding then
                  -- Fallback
                  REWINDER.keybinds.set_binding(name, keys)
               end
               if dynamic_label then
                  -- Get the full updated binding to format correctly
                  local new_binding = REWINDER.keybinds.get_binding(name)
                  dynamic_label.text = REWINDER.keybinds.format_binding(new_binding)
               end
            end,
            press_callback = function(keys)
               if dynamic_label then
                  dynamic_label.text = REWINDER.keybinds.format_binding(keys)
               end
            end,
         })
      end
   end

   G.FUNCS.rewinder_reset_keybinds = function()
      if REWINDER and REWINDER.keybinds and REWINDER.keybinds.reset_defaults then
         REWINDER.keybinds.reset_defaults()
      end
      if REWINDER and REWINDER._keybind_label_refs then
         for _, ref_table in ipairs(REWINDER._keybind_label_refs) do
            if ref_table and ref_table.label and ref_table.name then
               ref_table.label.text = _rewinder_keybind_label(ref_table.name)
            end
         end
      end
   end

   SMODS.current_mod.extra_tabs = function()
      return {
         {
            label = localize and localize("rewinder_tab_keybinds") or "Keybinds",
            tab_definition_function = REWINDER.keybinds_tab,
         },
      }
   end
end
