--- Save Rewinder - UI/RewinderUI.lua
--
-- In-game UI for listing and restoring saves, plus an Options button.

if not REWINDER then REWINDER = {} end

local SAVE_ENTRY_W = 8.9  -- Reduced from 8.8 to give arrow more space

-- Custom triangle arrow indicator (replaces built-in 'chosen' which has hardcoded positioning)
-- Extends Moveable to create a custom drawable object
local TriangleArrow = Moveable:extend()

function TriangleArrow:init(w, h)
   Moveable.init(self, 0, 0, w or 0.25, h or 0.4)
   self.states = {
      drag = { can = false },
      hover = { can = false },
      collide = { can = false },
   }
end

function TriangleArrow:draw()
   if not self.VT then return end
   
   -- Use prep_draw like the game does for proper coordinate transformation
   prep_draw(self, 1)
   
   -- Scale to pixel space for polygon drawing
   love.graphics.scale(1 / G.TILESIZE)
   
   -- Triangle size and animation (matching game's chosen triangle)
   local scale = 2
   local anim_offset = math.min(0.6 * math.sin(G.TIMERS.REAL * 9) * scale + 0.2, 0)
   
   -- Get dimensions in screen space
   local w = self.VT.w * G.TILESIZE
   local h = self.VT.h * G.TILESIZE
   
   -- Triangle centered in our bounds, pointing right
   -- Arrow shift right within the bounds for better positioning
   local cx = w * 1.4 + anim_offset
   local cy = h / 2
   -- Make more equilateral: equal width and height
   local tri_size = 3 * scale
   
   -- Draw shadow
   if G.SETTINGS.GRAPHICS.shadows == 'On' then
      love.graphics.setColor(0, 0, 0, 0.3)
      love.graphics.polygon("fill",
         cx - tri_size + 1, cy - tri_size * 0.6 + 1,
         cx + 1, cy + 1,
         cx - tri_size + 1, cy + tri_size * 0.6 + 1
      )
   end
   
   -- Draw white triangle pointing right (contrasts with orange background)
   love.graphics.setColor(G.C.WHITE)
   love.graphics.polygon("fill",
      cx - tri_size, cy - tri_size * 0.6,
      cx, cy,
      cx - tri_size, cy + tri_size * 0.6
   )
   
   love.graphics.pop()
end

-- Factory function to create a triangle arrow
function REWINDER.create_triangle_arrow()
   return TriangleArrow(0.25, 0.4)
end

-- Cache for blind sprite configurations (not the sprites themselves, since UI objects
-- get destroyed when removed). We cache the config lookup to avoid repeated G.P_BLINDS access.
local blind_config_cache = {}

-- Get cached blind config (atlas key and position)
local function get_blind_config_cached(blind_key)
   if not blind_key then return nil end
   
   -- Check cache first
   if blind_config_cache[blind_key] then
      return blind_config_cache[blind_key]
   end
   
   -- Lookup and cache
   if not G or not G.P_BLINDS then return nil end
   local blind_config = G.P_BLINDS[blind_key]
   if not blind_config then return nil end
   
   local atlas_key = blind_config.atlas or 'blind_chips'
   if not G.ANIMATION_ATLAS or not G.ANIMATION_ATLAS[atlas_key] then return nil end
   
   -- Cache the config (immutable data)
   blind_config_cache[blind_key] = {
      atlas_key = atlas_key,
      pos = blind_config.pos,
   }
   
   return blind_config_cache[blind_key]
end
-- Clear blind config cache (call when game reloads or mods change)
function REWINDER.clear_blind_cache()
   blind_config_cache = {}
end
-- Create a blind sprite that looks like UnBlind (with shade/border)
-- Uses AnimatedSprite with dissolve shader for the shadow effect, but doesn't animate
-- Returns a sprite object suitable for UI display
-- Note: Sprites cannot be reused across UI rebuilds, but config lookup is cached
function REWINDER.create_blind_sprite(blind_key, width, height)
   local config = get_blind_config_cached(blind_key)
   if not config then return nil end
   
   local atlas = G.ANIMATION_ATLAS[config.atlas_key]
   if not atlas then return nil end
   
   -- Use AnimatedSprite like UnBlind for shader support (shadow/shade effect)
   -- Size 0.45x0.45 to be visible but still fit in entry height
   local sprite = AnimatedSprite(0, 0, width or 0.45, height or 0.45, atlas, config.pos)
   
   -- Calculate shadow parallax based on screen position (like game does)
   -- This makes shadow offset vary based on horizontal position
   -- For consistent appearance, we set a fixed offset similar to right-side sprites
   sprite.shadow_parrallax = {x = 1.5, y = -0.5}
   
   -- Apply dissolve shader with shadow for UnBlind-like appearance
   -- shadow_height 0.05 matches UnBlind
   sprite:define_draw_steps({
      {shader = 'dissolve', shadow_height = 0.05},
      {shader = 'dissolve'}
   })
   
   -- Check if effects (animation + hover sound) are enabled
   local effects_enabled = REWINDER.config and REWINDER.config.animate_blind_image
   
   -- Stop animation by setting to single frame (prevents cycling through frames)
   -- Only stop if effects are disabled in config
   if not effects_enabled then
      sprite.animation.frames = 1
      sprite.current_animation.frames = 1
   end
   
   sprite.states.drag.can = false
   
   -- Enable hover effects (sound + juice) when effects are enabled
   if effects_enabled then
      sprite.float = true
      sprite.states.hover.can = true
      sprite.states.collide.can = true
      sprite.hover = function()
         if not G.CONTROLLER.dragging.target or G.CONTROLLER.using_touch then
            if not sprite.hovering and sprite.states.visible then
               sprite.hovering = true
               sprite.hover_tilt = 3
               sprite:juice_up(0.05, 0.02)
               play_sound('chips1', math.random()*0.1 + 0.55, 0.12)
               Node.hover(sprite)
            end
         end
      end
      sprite.stop_hover = function()
         sprite.hovering = false
         sprite.hover_tilt = 0
         Node.stop_hover(sprite)
      end
   else
      sprite.states.hover.can = false
      sprite.states.collide.can = false
   end
   
   return sprite
end

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
-- Display type lookup table: maps display_type code to localization key and prefix
-- Format: { loc_key, has_prefix, show_ordinal }
local DISPLAY_TYPE_LABELS = {
   S = { "rewinder_state_shop", false, true },           -- Shop
   F = { "rewinder_state_entering_shop", true, false },  -- First shop (entering)
   O = { "rewinder_state_opening_pack", false, true },   -- Opening pack
   R = { "rewinder_state_start_round", true, false },    -- Start of round (highlighted like entering shop)
   P = { "rewinder_state_selecting_hand_play", false, true },    -- Selecting hand (play)
   D = { "rewinder_state_selecting_hand_discard", false, true }, -- Selecting hand (discard)
   H = { "rewinder_state_selecting_hand", false, true }, -- Selecting hand (unknown)
   E = { "rewinder_state_end_of_round", false, false },  -- End of round
   B = { "rewinder_state_choose_blind", false, true },   -- Choose blind
   ["?"] = { "rewinder_state_in_run", false, true },     -- Unknown/other
}
-- Get label text from display_type code (fast path, no computation)
local function get_label_from_display_type(display_type)
   local info = DISPLAY_TYPE_LABELS[display_type or "?"] or DISPLAY_TYPE_LABELS["?"]
   local loc_key, has_prefix, show_ordinal = info[1], info[2], info[3]
   local text = (localize and localize(loc_key)) or loc_key
   if has_prefix then
      text = "+> " .. text
   end
   return text, show_ordinal
end

function REWINDER.build_save_node(entry, is_first_entry, opts)
   -- Use entry as array (no keys, accessed by index)
   if not entry then return nil end
   opts = opts or {}


   -- Check if we should show blind image instead of round number
   local show_blind_image = REWINDER.config and REWINDER.config.show_blind_image
   
   -- Build ante text
   local ante_text = ""
   if entry[REWINDER.ENTRY_ANTE] then
      local ante_label = (localize and localize("rewinder_ante_label")) or "Ante"
      ante_text = ante_label .. " " .. tostring(entry[REWINDER.ENTRY_ANTE])
   end

   -- Fast path: use pre-computed display_type from entry
   local state_text = ""
      local show_ordinal = true
   local display_type = entry[REWINDER.ENTRY_DISPLAY_TYPE]
   
   if display_type then
      -- Use fast lookup table (no computation needed)
      state_text, show_ordinal = get_label_from_display_type(display_type)
   else
      -- Fallback for saves without display_type (shouldn't happen with new format)
      state_text = localize and localize("rewinder_state_in_run") or "in run"
   end

   -- Build tailing number text using pre-computed ordinal
   local tailing_number_text = ""
   local ordinal = entry[REWINDER.ENTRY_ORDINAL]
   
      if show_ordinal and ordinal and ordinal > 0 then
      tailing_number_text = tostring(ordinal)
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
   end
   
   -- Build text nodes - separate nodes for text and colored separator/blind image
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
   
   -- Add separator or blind image between ante and state
   if ante_text ~= "" then
         if show_blind_image and entry[REWINDER.ENTRY_BLIND_IDX] then
         -- Show blind image instead of round number (convert idx to key)
         local blind_key = REWINDER._SaveManager and REWINDER._SaveManager.index_to_blind_key(entry[REWINDER.ENTRY_BLIND_IDX])
         local blind_sprite = blind_key and REWINDER.create_blind_sprite(blind_key)
         if blind_sprite then
            -- Check if effects are enabled for hover
            local effects_enabled = REWINDER.config and REWINDER.config.animate_blind_image
            -- Add horizontal spacing around the blind image (left spacer + image + right spacer)
            local h_spacing = 0.06
            table.insert(text_nodes, {
               n = G.UIT.C,
               config = { minw = h_spacing },  -- Left spacer
            })
            table.insert(text_nodes, {
               n = G.UIT.C,
               config = {
                  align = "cm",
                  padding = 0,  -- No extra padding (avoid vertical spacing)
               },
               nodes = {
                  {
                     n = G.UIT.O,
                     config = {
                        object = blind_sprite,
                        focus_with_object = effects_enabled,  -- Enable focus for hover events
                     },
                  },
               },
            })
            table.insert(text_nodes, {
               n = G.UIT.C,
               config = { minw = h_spacing },  -- Right spacer
            })
         else
            -- Fallback to separator if sprite creation fails
            local separator = (localize and localize("rewinder_separator")) or " | "
            table.insert(text_nodes, {
               n = G.UIT.T,
               config = {
                  text = separator,
                  colour = dot_colour,
                  scale = 0.45,
               },
            })
         end
      else
         -- Show colored separator with round number (original behavior)
         local round_text = ""
         if entry[REWINDER.ENTRY_ROUND] ~= nil then
            local round_label = (localize and localize("rewinder_round_label")) or "Round"
            local spacing = (localize and localize("rewinder_ante_round_spacing")) or " "
            round_text = spacing .. round_label .. " " .. tostring(entry[REWINDER.ENTRY_ROUND])
         end
         
         if round_text ~= "" then
            table.insert(text_nodes, {
               n = G.UIT.T,
               config = {
                  text = round_text,
                  colour = default_text_colour,  -- Use normal text color, not colored dot
                  scale = 0.45,
               },
            })
         end
         
         local separator = (localize and localize("rewinder_separator")) or " | "
         table.insert(text_nodes, {
            n = G.UIT.T,
            config = {
               text = separator,
               colour = dot_colour,
               scale = 0.45,
            },
         })
      end
   end
   
   -- Build state and tailing number text
   local state_tailing_text = ""
   if state_text ~= "" then
      state_tailing_text = state_text
      if tailing_number_text ~= "" then
         -- Use different spacing for selecting_hand types (P=play, D=discard, H=selecting)
         local is_selecting_hand = (display_type == "P" or display_type == "D" or display_type == "H")

         local spacing
         if is_selecting_hand then
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
   
   -- Add left padding spacer to text nodes, and arrow indicator for current save
   local padded_text_nodes = {}
   
   -- Left padding for all entries
   local left_padding = 0.06
   
   if is_current then
      -- For current save: small left pad + arrow (no gap - arrow bounds provide spacing)
      table.insert(padded_text_nodes, {
         n = G.UIT.C,
         config = { minw = left_padding },
      })
      local arrow = REWINDER.create_triangle_arrow()
      table.insert(padded_text_nodes, {
         n = G.UIT.O,
         config = {
            object = arrow,
            can_collide = false,
         },
      })
      -- Small gap between arrow and text
      table.insert(padded_text_nodes, {
         n = G.UIT.C,
         config = { minw = 0.03 },
      })
   else
      -- For normal entries: just left padding
      table.insert(padded_text_nodes, {
         n = G.UIT.C,
         config = { minw = left_padding },
      })
   end
   
   for _, node in ipairs(text_nodes) do
      table.insert(padded_text_nodes, node)
   end
   
   return {
      n = G.UIT.R,
      config = { align = "cm", padding = 0.06 },
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
               padding = 0.08,
               r = 0.1,
               hover = true,
               can_collide = true,
               shadow = true,
               focus_args = { snap_to = opts.snap_to == true },
               ref_table = { file = entry[REWINDER.ENTRY_FILE] },
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

      -- Single-loop rendering: use pre-computed display_type and ordinal from entry
      -- Only load metadata on-demand if not already loaded
      for i = 1, max_index do
         local entry = entries[offset + i]
         local global_index = offset + i
         
         -- Load metadata on-demand if not loaded
         if entry and not entry[REWINDER.ENTRY_SIGNATURE] and REWINDER.get_save_meta then
            REWINDER.get_save_meta(entry)
         end

         local is_first_entry = (global_index == 1)
                  table.insert(nodes, REWINDER.build_save_node(entry, is_first_entry, {
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
      back_func = "exit_overlay_menu",
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