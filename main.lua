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
end
