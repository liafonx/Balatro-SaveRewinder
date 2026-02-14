if not REWINDER then REWINDER = {} end

local KeySaves = require("KeySaves")
local UIShared = require("UIShared")
local Layout = require("UILayout")

REWINDER._filter_active = REWINDER._filter_active or false
REWINDER._mark_active = REWINDER._mark_active or false

local loc = UIShared.loc

-- Cache for blind sprite configurations (not the sprites themselves, since UI objects
-- get destroyed when removed). We cache the config lookup to avoid repeated G.P_BLINDS access.
local blind_config_cache = {}

local function get_blind_config_cached(blind_key)
   if not blind_key then return nil end
   if blind_config_cache[blind_key] then
      return blind_config_cache[blind_key]
   end

   if not G or not G.P_BLINDS then return nil end
   local blind_config = G.P_BLINDS[blind_key]
   if not blind_config then return nil end

   local atlas_key = blind_config.atlas or "blind_chips"
   if not G.ANIMATION_ATLAS or not G.ANIMATION_ATLAS[atlas_key] then return nil end

   blind_config_cache[blind_key] = {
      atlas_key = atlas_key,
      pos = blind_config.pos,
   }

   return blind_config_cache[blind_key]
end

local function setup_blind_sprite(sprite)
   if sprite.parent then sprite:remove() end

   sprite.shadow_parrallax = {x = 1.5, y = -0.5}
   sprite:define_draw_steps({
      {shader = "dissolve", shadow_height = 0.05},
      {shader = "dissolve"},
   })
   sprite.states.drag.can = false

   local effects_enabled = REWINDER.config and REWINDER.config.animate_blind_image
   if effects_enabled then
      sprite.float = true
      sprite.states.hover.can = true
      sprite.states.collide.can = true
      sprite.hover = function()
         if (not G.CONTROLLER.dragging.target or G.CONTROLLER.using_touch) and
            not sprite.hovering and sprite.states.visible then
            sprite.hovering = true
            sprite.hover_tilt = 3
            sprite:juice_up(0.05, 0.02)
            play_sound("chips1", math.random() * 0.1 + 0.55, 0.12)
            Node.hover(sprite)
         end
      end
      sprite.stop_hover = function()
         sprite.hovering = false
         sprite.hover_tilt = 0
         Node.stop_hover(sprite)
      end
   else
      sprite.animation.frames = 1
      sprite.current_animation.frames = 1
      sprite.states.hover.can = false
      sprite.states.collide.can = false
   end
   return sprite
end

function REWINDER.create_blind_sprite(blind_key, width, height)
   local w, h = width or 0.45, height or 0.45

   if blind_key == "bl_undiscovered" then
      if not G or not G.b_undiscovered or not G.ANIMATION_ATLAS or not G.ANIMATION_ATLAS["blind_chips"] then
         return nil
      end
      return setup_blind_sprite(AnimatedSprite(0, 0, w, h, G.ANIMATION_ATLAS["blind_chips"], G.b_undiscovered.pos))
   end

   local config = get_blind_config_cached(blind_key)
   if not config then return nil end
   local atlas = G.ANIMATION_ATLAS[config.atlas_key]
   if not atlas then return nil end

   return setup_blind_sprite(AnimatedSprite(0, 0, w, h, atlas, config.pos))
end

function REWINDER.get_round_color(round)
   if round == nil then return G.C.UI.TEXT_LIGHT end
   if round % 2 == 0 then
      return G.C.ORANGE or {1, 0.7, 0.2, 1}
   end
   return G.C.YELLOW
end

-- Format: { loc_key, has_prefix, show_ordinal }
local DISPLAY_TYPE_LABELS = {
   S = { "rewinder_state_shop", false, true },
   A = { "rewinder_state_after_pack", false, true },
   F = { "rewinder_state_entering_shop", false, false },
   O = { "rewinder_state_opening_pack", false, true },
   R = { "rewinder_state_start_round", false, false },
   P = { "rewinder_state_selecting_hand_play", false, true },
   D = { "rewinder_state_selecting_hand_discard", false, true },
   H = { "rewinder_state_selecting_hand", false, true },
   E = { "rewinder_state_end_of_round", false, false },
   B = { "rewinder_state_choose_blind", false, true },
   ["?"] = { "rewinder_state_in_run", false, true },
}

local function get_label_from_display_type(display_type)
   local info = DISPLAY_TYPE_LABELS[display_type or "?"] or DISPLAY_TYPE_LABELS["?"]
   local loc_key, has_prefix, show_ordinal = info[1], info[2], info[3]
   local text = loc(loc_key, loc_key)
   if has_prefix then
      text = "+> " .. text
   end
   return text, show_ordinal
end

local function _build_default_state_title(entry)
   if not entry then return "" end
   local display_type = entry[REWINDER.ENTRY_DISPLAY_TYPE]
   if not display_type and REWINDER.get_save_meta then
      REWINDER.get_save_meta(entry)
      display_type = entry[REWINDER.ENTRY_DISPLAY_TYPE]
   end

   local state_text = ""
   local show_ordinal = true
   if display_type then
      state_text, show_ordinal = get_label_from_display_type(display_type)
   else
      state_text = loc("rewinder_state_in_run", "in run")
   end

   local tailing_number_text = ""
   local ordinal = entry[REWINDER.ENTRY_ORDINAL]
   if show_ordinal and ordinal and ordinal > 0 then
      tailing_number_text = tostring(ordinal)
   end

   local state_tailing_text = ""
   if state_text ~= "" then
      state_tailing_text = state_text
      if tailing_number_text ~= "" then
         local is_selecting_hand = (display_type == "P" or display_type == "D" or display_type == "H")
         local spacing = is_selecting_hand and loc("rewinder_card_number_spacing", " ") or loc("rewinder_tailing_number_spacing", " ")
         if spacing == nil then spacing = " " end
         state_tailing_text = state_tailing_text .. spacing .. tailing_number_text
      end
   elseif tailing_number_text ~= "" then
      local spacing = loc("rewinder_tailing_number_spacing", " ")
      if spacing == nil then spacing = " " end
      state_tailing_text = spacing .. tailing_number_text
   end
   return state_tailing_text
end

function REWINDER.get_default_state_title(file_or_entry)
   local entry = file_or_entry
   if type(file_or_entry) == "string" and REWINDER._SaveManager and REWINDER._SaveManager.get_entry_by_file then
      entry = REWINDER._SaveManager.get_entry_by_file(file_or_entry)
   end
   return _build_default_state_title(entry)
end

function REWINDER.build_save_node(entry, opts)
   if not entry then return nil end
   opts = opts or {}
   local file = entry[REWINDER.ENTRY_FILE]

   local show_blind_image = REWINDER.config and REWINDER.config.show_blind_image
   local is_mark_mode = REWINDER._mark_active == true

   local ante_text = ""
   if entry[REWINDER.ENTRY_ANTE] then
      local ante_label = loc("rewinder_ante_label", "Ante")
      ante_text = ante_label .. " " .. tostring(entry[REWINDER.ENTRY_ANTE])
   end

   local state_text = ""
   local show_ordinal = true
   local display_type = entry[REWINDER.ENTRY_DISPLAY_TYPE]

   if display_type then
      state_text, show_ordinal = get_label_from_display_type(display_type)
   else
      state_text = loc("rewinder_state_in_run", "in run")
   end

   local tailing_number_text = ""
   local ordinal = entry[REWINDER.ENTRY_ORDINAL]
   local default_state_title = _build_default_state_title(entry)
   if show_ordinal and ordinal and ordinal > 0 then
      tailing_number_text = tostring(ordinal)
   end

   local is_current = (entry[REWINDER.ENTRY_IS_CURRENT] == true)
   if not is_current then
      local current_file = REWINDER._SaveManager and REWINDER._SaveManager._last_loaded_file
      if current_file and file and current_file == file then
         is_current = true
      end
   end
   local is_key = (entry[REWINDER.ENTRY_IS_KEY] == true)
   local is_pending = false
   if is_mark_mode then
      is_key, is_pending = KeySaves.effective_is_key(entry)
   end

   local key_save_colour = copy_table(Layout.KEY_SAVE_COLOR or {0.2, 0.7, 0.7, 1})
   local button_colour = copy_table(G.C.BLUE)
   local default_text_colour = G.C.UI.TEXT_LIGHT

   if is_key then
      button_colour = copy_table(key_save_colour)
      default_text_colour = G.C.WHITE
   end
   -- Current-save orange highlight applies only to non-key saves.
   if is_current and not is_key then
      button_colour = copy_table(G.C.ORANGE or {1, 0.6, 0.2, 1})
      default_text_colour = G.C.WHITE
   end

   if is_pending then
      button_colour = {
         math.min(1, button_colour[1] + 0.05),
         math.min(1, button_colour[2] + 0.05),
         math.min(1, button_colour[3] + 0.05),
         button_colour[4] or 1,
      }
   end

   local dot_colour = G.C.UI.TEXT_LIGHT
   if entry[REWINDER.ENTRY_ROUND] ~= nil then
      dot_colour = REWINDER.get_round_color(entry[REWINDER.ENTRY_ROUND])
   end
   if is_current then dot_colour = copy_table(default_text_colour) end

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

   if ante_text ~= "" then
      if show_blind_image and entry[REWINDER.ENTRY_BLIND_IDX] then
         local blind_key = REWINDER._SaveManager and REWINDER._SaveManager.index_to_blind_key(entry[REWINDER.ENTRY_BLIND_IDX])
         local blind_sprite = blind_key and REWINDER.create_blind_sprite(blind_key)

         if blind_sprite then
            local effects_enabled = REWINDER.config and REWINDER.config.animate_blind_image
            local h_spacing = 0.06
            table.insert(text_nodes, { n = G.UIT.C, config = { minw = h_spacing } })
            table.insert(text_nodes, {
               n = G.UIT.C,
               config = { align = "cm", padding = 0 },
               nodes = {
                  {
                     n = G.UIT.O,
                     config = {
                        object = blind_sprite,
                        focus_with_object = effects_enabled,
                     },
                  },
               },
            })
            table.insert(text_nodes, { n = G.UIT.C, config = { minw = h_spacing } })
         else
            local separator = loc("rewinder_separator", " | ")
            table.insert(text_nodes, {
               n = G.UIT.T,
               config = { text = separator, colour = dot_colour, scale = 0.45 },
            })
         end
      else
         local round_text = ""
         if entry[REWINDER.ENTRY_ROUND] ~= nil then
            local round_label = loc("rewinder_round_label", "Round")
            local spacing = loc("rewinder_ante_round_spacing", " ")
            round_text = spacing .. round_label .. " " .. tostring(entry[REWINDER.ENTRY_ROUND])
         end

         if round_text ~= "" then
            table.insert(text_nodes, {
               n = G.UIT.T,
               config = { text = round_text, colour = default_text_colour, scale = 0.45 },
            })
         end

         local separator = loc("rewinder_separator", " | ")
         table.insert(text_nodes, {
            n = G.UIT.T,
            config = { text = separator, colour = dot_colour, scale = 0.45 },
         })
      end
   end

   if display_type == "F" then
      local dollar_colour = is_current and copy_table(default_text_colour) or (G.C.GOLD or {0.9, 0.7, 0.2, 1})
      table.insert(text_nodes, {
         n = G.UIT.T,
         config = { text = "$", colour = dollar_colour, scale = 0.5 },
      })
   end

   local custom_state_name = REWINDER.get_custom_state_name and REWINDER.get_custom_state_name(file)
   local rename_pending_text = REWINDER._rename_active and REWINDER._rename_pending and REWINDER._rename_pending[file] or nil
   local rename_pending_clear = REWINDER._rename_active and REWINDER._rename_pending_clear and REWINDER._rename_pending_clear[file] or false

   if custom_state_name then
      state_text = custom_state_name
      tailing_number_text = ""
   end
   if rename_pending_text ~= nil then
      state_text = tostring(rename_pending_text)
      tailing_number_text = ""
   elseif rename_pending_clear then
      state_text = default_state_title
      tailing_number_text = ""
   end

   local state_tailing_text = ""
   if state_text ~= "" then
      state_tailing_text = state_text
      if tailing_number_text ~= "" then
         local is_selecting_hand = (display_type == "P" or display_type == "D" or display_type == "H")
         local spacing
         if is_selecting_hand then
            spacing = loc("rewinder_card_number_spacing", " ")
         else
            spacing = loc("rewinder_tailing_number_spacing", " ")
         end
         if spacing == nil then spacing = " " end
         state_tailing_text = state_tailing_text .. spacing .. tailing_number_text
      end
   elseif tailing_number_text ~= "" then
      local spacing = loc("rewinder_tailing_number_spacing", " ")
      if spacing == nil then spacing = " " end
      state_tailing_text = spacing .. tailing_number_text
   end

   local is_rename_editing = (REWINDER._rename_active and REWINDER._rename_editing_file == file)
   if is_rename_editing then
      if not REWINDER._rename_input_ref then
         REWINDER._rename_input_ref = { text = custom_state_name or "" }
      end

      local rename_input = create_text_input({
         max_length = 20,
         extended_corpus = true,
         all_caps = false,
         rewinder_rename_input = true,
         ref_table = REWINDER._rename_input_ref,
         ref_value = "text",
         prompt_text = loc("rewinder_rename_prompt", "Enter custom name"),
         w = 4.2,
         h = 0.58,
         text_scale = 0.45,
         colour = G.C.CLEAR,
         hooked_colour = G.C.CLEAR,
      })
      if rename_input and rename_input.nodes and rename_input.nodes[1] and rename_input.nodes[1].config then
         rename_input.nodes[1].config.shadow = false
         rename_input.nodes[1].config.colour = G.C.CLEAR
      end

      table.insert(text_nodes, {
         n = G.UIT.C,
         config = { align = "cm", padding = 0 },
         nodes = { rename_input },
      })
   elseif state_tailing_text ~= "" then
      table.insert(text_nodes, {
         n = G.UIT.T,
         config = {
            text = state_tailing_text,
            colour = custom_state_name and lighten(default_text_colour, 0.1) or default_text_colour,
            scale = 0.45,
         },
      })
   end

   local padded_text_nodes = {}
   local left_padding = 0.06
   table.insert(padded_text_nodes, { n = G.UIT.C, config = { minw = left_padding } })
   if is_current then
      local arrow = REWINDER.create_triangle_arrow(G.C.WHITE)
      table.insert(padded_text_nodes, {
         n = G.UIT.O,
         config = { object = arrow, can_collide = false },
      })
      table.insert(padded_text_nodes, { n = G.UIT.C, config = { minw = 0.08 } })
   end

   for _, node in ipairs(text_nodes) do
      table.insert(padded_text_nodes, node)
   end

   local is_row_editing = is_rename_editing
   local row_button = is_mark_mode and "rewinder_save_toggle_key" or "rewinder_save_restore"
   local row_colour = button_colour
   if is_row_editing and type(button_colour) == "table" then
      row_colour = darken(copy_table(button_colour), 0.3)
   end
   return {
      n = G.UIT.R,
      config = { align = "cm", padding = 0.06 },
      nodes = {
         {
            n = G.UIT.R,
            config = {
               id = opts.id,
               button = row_button,
               align = "cl",
               colour = row_colour,
               minw = Layout.SAVE_ENTRY_W,
               maxw = Layout.SAVE_ENTRY_W,
               padding = 0.08,
               r = 0.1,
               hover = not is_row_editing,
               can_collide = true,
               shadow = not is_row_editing,
               focus_args = { snap_to = opts.snap_to == true },
               ref_table = { file = file },
            },
            nodes = padded_text_nodes,
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
      local empty_key = REWINDER._filter_active and "rewinder_no_key_saves" or "rewinder_no_saves"
      local empty_text = REWINDER._filter_active and "No key saves marked" or "No saves yet"
      content = {
         n = G.UIT.T,
         config = { text = loc(empty_key, empty_text), colour = G.C.UI.TEXT_LIGHT, scale = 0.5 },
      }
   else
      local nodes = {}
      local offset = (page_num - 1) * per_page
      local max_index = math.min(#entries - offset, per_page)

      for i = 1, max_index do
         local entry = entries[offset + i]
         local global_index = offset + i
         if entry and not entry[REWINDER.ENTRY_SIGNATURE] and REWINDER.get_save_meta then
            REWINDER.get_save_meta(entry)
         end

         table.insert(nodes, REWINDER.build_save_node(entry, {
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

   local calculated_minh = per_page * 0.78 + 0.1
   return {
      n = G.UIT.ROOT,
      config = {
         align = (#entries == 0 and "cm" or "tm"),
         minw = Layout.SAVE_ENTRY_W,
         minh = calculated_minh,
         r = 0.1,
         colour = G.C.CLEAR,
      },
      nodes = { content },
   }
end

return {}
