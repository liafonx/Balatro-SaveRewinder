--- Save Rewinder - main.lua
--
-- Steamodded entry point (for config UI only).

REWINDER = REWINDER or {}

if SMODS and SMODS.current_mod then
   REWINDER.mod = SMODS.current_mod
   REWINDER.config = REWINDER.mod.config or {}

   SMODS.current_mod.config_tab = function()
      return {
         n = G.UIT.ROOT,
         config = { r = 0.2, colour = G.C.BLACK },
         nodes = {
            {
               n = G.UIT.C,
               config = { padding = 0.25, align = "cm" },
               nodes = {
                  {
                     n = G.UIT.R,
                     config = { align = "cm", padding = 0.01 },
                     nodes = {
                        create_toggle({
                           label = localize and localize("rewinder_save_on_blind") or "Save when choosing blind",
                           ref_table = REWINDER.config,
                           ref_value = "save_on_blind",
                           label_scale = 0.35,
                           w = 3,
                           scale = 0.9,
                        }),
                     },
                  },
                  {
                     n = G.UIT.R,
                     config = { align = "cm", padding = 0.01 },
                     nodes = {
                        create_toggle({
                           label = localize and localize("rewinder_save_on_selecting_hand") or "Save when selecting hand",
                           ref_table = REWINDER.config,
                           ref_value = "save_on_selecting_hand",
                           label_scale = 0.35,
                           w = 3,
                           scale = 0.9,
                        }),
                     },
                  },
                  {
                     n = G.UIT.R,
                     config = { align = "cm", padding = 0.01 },
                     nodes = {
                        create_toggle({
                           label = localize and localize("rewinder_save_on_round_end") or "Save at end of round",
                           ref_table = REWINDER.config,
                           ref_value = "save_on_round_end",
                           label_scale = 0.35,
                           w = 3,
                           scale = 0.9,
                        }),
                     },
                  },
                  {
                     n = G.UIT.R,
                     config = { align = "cm", padding = 0.01 },
                     nodes = {
                        create_toggle({
                           label = localize and localize("rewinder_save_on_shop") or "Save in shop",
                           ref_table = REWINDER.config,
                           ref_value = "save_on_shop",
                           label_scale = 0.35,
                           w = 3,
                           scale = 0.9,
                        }),
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
                           w = 4,
                           text_scale = 0.42,
                           scale = 0.75,
                           ref_table = REWINDER.config,
                           ref_value = "keep_antes",
                           opt_callback = "rewinder_config_change",
                        }),
                     },
                  },
                  {
                     n = G.UIT.R,
                     config = { align = "cm", padding = 0.01 },
                     nodes = {
                        create_toggle({
                           label = localize and localize("rewinder_debug_saves") or "Debug: show save notifications",
                           ref_table = REWINDER.config,
                           ref_value = "debug_saves",
                           label_scale = 0.35,
                           w = 3,
                           scale = 0.9,
                        }),
                     },
                  },
                  {
                     n = G.UIT.R,
                     config = { align = "cm", padding = 0.01 },
                     nodes = {
                        UIBox_button({
                           label = { (localize and localize("rewinder_delete_all_saves_button")) or "Delete all saves" },
                           button = "rewinder_save_delete_all",
                           minw = 3,
                           minh = 0.7,
                           scale = 0.35,
                        }),
                    },
                  },
               },
            },
         },
      }
   end
end
