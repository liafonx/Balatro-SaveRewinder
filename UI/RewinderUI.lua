--- Save Rewinder - UI/RewinderUI.lua
--
-- In-game UI for listing and restoring saves, plus an Options button.

if not REWINDER then REWINDER = {} end
local KeySaves = require("KeySaves")

local SAVE_ENTRY_W = 8.9  -- Reduced from 8.8 to give arrow more space
local KEY_SAVE_COLOR = {0.2, 0.7, 0.7, 1}
local FILTER_BUTTON_W = 3.6
local ICON_BUTTON_SIDE = 0.90
local ICON_BUTTON_ICON_SIZE = 0.60
local ICON_BUTTON_PADDING = 0.08
local ICON_BUTTON_RADIUS = 0.1
local ICON_BUTTON_BORDER = 0.04
local MODE_ROW_HALF_W = SAVE_ENTRY_W * 0.5
REWINDER.KEY_SAVE_COLOR = KEY_SAVE_COLOR
REWINDER._filter_active = REWINDER._filter_active or false
REWINDER._mark_active = REWINDER._mark_active or false

local function loc(key, fallback)
   if localize then
      return localize(key) or fallback
   end
   return fallback
end

-- Custom triangle arrow indicator (replaces built-in 'chosen' which has hardcoded positioning)
-- Extends Moveable to create a custom drawable object
local TriangleArrow = Moveable:extend()

function TriangleArrow:init(w, h, colour)
   Moveable.init(self, 0, 0, w or 0.25, h or 0.4)
   self.colour = colour or G.C.WHITE
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
   
   -- Draw triangle pointing right
   love.graphics.setColor(self.colour)
   love.graphics.polygon("fill",
      cx - tri_size, cy - tri_size * 0.6,
      cx, cy,
      cx - tri_size, cy + tri_size * 0.6
   )
   
   love.graphics.pop()
end

-- Factory function to create a triangle arrow
function REWINDER.create_triangle_arrow(colour)
   return TriangleArrow(0.25, 0.4, colour)
end

-- Base class for cacheable icon shapes (triangle, star, future shapes).
-- Subclasses override _compute_points(w_px, h_px) to define geometry.
-- Mesh is built once on first draw (VT not ready at init time) and cached.
-- Concave shapes (>3 vertices) are auto-triangulated for correct fill.
local CachedIcon = Moveable:extend()

function CachedIcon:init(w, h, colour)
   Moveable.init(self, 0, 0, w or 0.40, h or 0.40)
   self.colour = colour or G.C.WHITE
   self.states = {
      drag = { can = false },
      hover = { can = false },
      collide = { can = false },
   }
   self._mesh_ready = false
   self._points = nil
   self._triangles = nil
end

-- Override in subclasses: return flat {x1,y1, x2,y2, ...} points array
function CachedIcon:_compute_points(w_px, h_px)
   return nil
end

function CachedIcon:_build_mesh()
   if not self.VT then return end
   local w_px = self.VT.w * G.TILESIZE
   local h_px = self.VT.h * G.TILESIZE
   local points = self:_compute_points(w_px, h_px)
   if not points then self._mesh_ready = true; return end
   self._points = points
   -- Triangulate concave shapes (>3 vertices) for correct polygon fill
   if #points > 6 and love and love.math and love.math.triangulate then
      local ok, tris = pcall(love.math.triangulate, points)
      if ok and tris and #tris > 0 then
         self._triangles = tris
      end
   end
   self._mesh_ready = true
end

function CachedIcon:_draw_shape(dx, dy, r, g, b, a)
   love.graphics.setColor(r, g, b, a)
   local triangles = self._triangles
   if triangles then
      for _, tri in ipairs(triangles) do
         love.graphics.polygon("fill",
            tri[1] + dx, tri[2] + dy,
            tri[3] + dx, tri[4] + dy,
            tri[5] + dx, tri[6] + dy
         )
      end
   else
      local points = self._points
      if dx == 0 and dy == 0 then
         love.graphics.polygon("fill", points)
      else
         local shifted = {}
         for i = 1, #points, 2 do
            shifted[#shifted + 1] = points[i] + dx
            shifted[#shifted + 1] = points[i + 1] + dy
         end
         love.graphics.polygon("fill", shifted)
      end
   end
end

function CachedIcon:draw()
   if not self.VT then return end
   if not self._mesh_ready then self:_build_mesh() end
   if not self._points then return end

   prep_draw(self, 1)
   love.graphics.scale(1 / G.TILESIZE)

   if G.SETTINGS.GRAPHICS.shadows == 'On' then
      self:_draw_shape(1, 1, 0, 0, 0, 0.3)
   end
   local c = self.colour
   self:_draw_shape(0, 0, c[1], c[2], c[3], c[4] or 1)

   love.graphics.pop()
end

-- Compact triangle icon for button glyphs
local TriangleIcon = CachedIcon:extend()

function TriangleIcon:_compute_points(w_px, h_px)
   local cx = w_px * 0.5
   local cy = h_px * 0.5
   local tri = math.max(2, math.min(w_px, h_px) * 0.50)
   return {
      cx - tri * 0.45, cy - tri * 0.55,
      cx + tri * 0.55, cy,
      cx - tri * 0.45, cy + tri * 0.55,
   }
end

function REWINDER.create_triangle_icon(colour, w, h)
   return TriangleIcon(w or 0.40, h or 0.40, colour)
end

-- Compact star icon for mode buttons
local StarIcon = CachedIcon:extend()

function StarIcon:_compute_points(w_px, h_px)
   local cx = w_px * 0.5
   local cy = h_px * 0.5
   local outer = math.max(2, (math.min(w_px, h_px) * 0.42))
   local inner = outer * 0.40
   local points = {}
   for i = 0, 9 do
      local angle = -math.pi / 2 + i * math.pi / 5
      local radius = (i % 2 == 0) and outer or inner
      points[#points + 1] = cx + math.cos(angle) * radius
      points[#points + 1] = cy + math.sin(angle) * radius
   end
   return points
end

function REWINDER.create_star_icon(colour, w, h)
   return StarIcon(w or 0.40, h or 0.40, colour)
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
-- Build an icon button node (border + coloured fill + icon glyph).
-- opts: { id, button, fill_id, fill_colour, icon, focus_args, border_colour }
local function build_icon_button(opts)
   local border_colour = opts.border_colour or G.C.UI.TEXT_LIGHT or {0.85, 0.85, 0.85, 1}
   local inner_r = math.max(0.01, ICON_BUTTON_RADIUS - ICON_BUTTON_BORDER * 0.5)
   local inner_side = ICON_BUTTON_SIDE - ICON_BUTTON_BORDER * 2
   return {
      n = G.UIT.C,
      config = { align = "cm", padding = 0.08 },
      nodes = {
         {
            n = G.UIT.R,
            config = {
               id = opts.id,
               button = opts.button,
               align = "cm",
               colour = border_colour,
               minw = ICON_BUTTON_SIDE,
               minh = ICON_BUTTON_SIDE,
               padding = 0,
               r = ICON_BUTTON_RADIUS,
               hover = true,
               can_collide = true,
               shadow = true,
               focus_args = opts.focus_args or { nav = "wide" },
            },
            nodes = {
               {
                  n = G.UIT.R,
                  config = {
                     id = opts.fill_id,
                     align = "cm",
                     colour = opts.fill_colour,
                     minw = inner_side,
                     minh = inner_side,
                     padding = ICON_BUTTON_PADDING,
                     r = inner_r,
                     can_collide = false,
                     shadow = false,
                  },
                  nodes = {
                     {
                        n = G.UIT.O,
                        config = {
                           object = opts.icon,
                           can_collide = false,
                        },
                     },
                  },
               },
            },
         },
      },
   }
end

local function build_page_cycle_config(page_numbers, initial_page, saves_box, per_page, entries)
   return {
      options = page_numbers,
      current_option = initial_page,
      opt_callback = "rewinder_save_update_page",
      opt_args = { ui = saves_box, per_page = per_page, entries = entries },
   }
end

-- Setup common sprite properties (shadow, shaders, hover effects)
local function setup_blind_sprite(sprite)
   if sprite.parent then sprite:remove() end
   
   sprite.shadow_parrallax = {x = 1.5, y = -0.5}
   sprite:define_draw_steps({
      {shader = 'dissolve', shadow_height = 0.05},
      {shader = 'dissolve'}
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
            play_sound('chips1', math.random()*0.1 + 0.55, 0.12)
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

-- Create a blind sprite with UnBlind-like appearance (shadow/shader effects)
function REWINDER.create_blind_sprite(blind_key, width, height)
   local w, h = width or 0.45, height or 0.45
   
   -- Undiscovered blind uses G.b_undiscovered
   if blind_key == "bl_undiscovered" then
      if not G or not G.b_undiscovered or not G.ANIMATION_ATLAS or not G.ANIMATION_ATLAS['blind_chips'] then
         return nil
      end
      return setup_blind_sprite(AnimatedSprite(0, 0, w, h, G.ANIMATION_ATLAS['blind_chips'], G.b_undiscovered.pos))
   end
   
   -- Regular blinds from G.P_BLINDS
   local config = get_blind_config_cached(blind_key)
   if not config then return nil end
   local atlas = G.ANIMATION_ATLAS[config.atlas_key]
   if not atlas then return nil end
   
   return setup_blind_sprite(AnimatedSprite(0, 0, w, h, atlas, config.pos))
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
   S = { "rewinder_state_shop", false, true },           -- Shop (reroll)
   A = { "rewinder_state_after_pack", false, true },     -- After pack (shop after pack closed)
   F = { "rewinder_state_entering_shop", false, false },  -- First shop (entering)
   O = { "rewinder_state_opening_pack", false, true },   -- Opening pack
   R = { "rewinder_state_start_round", false, false },    -- Start of round (highlighted like entering shop)
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
   local text = loc(loc_key, loc_key)
   if has_prefix then
      text = "+> " .. text
   end
   return text, show_ordinal
end

function REWINDER.build_save_node(entry, opts)
   -- Use entry as array (no keys, accessed by index)
   if not entry then return nil end
   opts = opts or {}


   -- Check if we should show blind image instead of round number
   local show_blind_image = REWINDER.config and REWINDER.config.show_blind_image
   local is_mark_mode = REWINDER._mark_active == true
   
   -- Build ante text
   local ante_text = ""
   if entry[REWINDER.ENTRY_ANTE] then
      local ante_label = loc("rewinder_ante_label", "Ante")
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
      state_text = loc("rewinder_state_in_run", "in run")
   end

   -- Build tailing number text using pre-computed ordinal
   local tailing_number_text = ""
   local ordinal = entry[REWINDER.ENTRY_ORDINAL]
   
   if show_ordinal and ordinal and ordinal > 0 then
      tailing_number_text = tostring(ordinal)
   end

   -- Use cached is_current flag (always set by _update_cache_current_flags before UI build)
   local is_current = (entry[REWINDER.ENTRY_IS_CURRENT] == true)
   local is_key = (entry[REWINDER.ENTRY_IS_KEY] == true)
   local is_pending = false
   if is_mark_mode then
      is_key, is_pending = KeySaves.effective_is_key(entry)
   end
   
   -- Background color
   local button_colour = G.C.BLUE
   local default_text_colour = G.C.UI.TEXT_LIGHT

   if is_key then
      button_colour = KEY_SAVE_COLOR
      default_text_colour = G.C.WHITE
   elseif is_current then
      button_colour = G.C.ORANGE or {1, 0.6, 0.2, 1}
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

   -- Get dot color for round number (odd/even)
   local dot_colour = G.C.UI.TEXT_LIGHT
   if entry[REWINDER.ENTRY_ROUND] ~= nil then
      dot_colour = REWINDER.get_round_color(entry[REWINDER.ENTRY_ROUND])
   end

   if is_current then
      dot_colour = G.C.WHITE
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
         -- Blind icon is determined at save time, just display it
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
                  padding = 0,
               },
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
            
            table.insert(text_nodes, {
               n = G.UIT.C,
               config = { minw = h_spacing },  -- Right spacer
            })
         else
            -- Fallback to separator if sprite creation fails
            local separator = loc("rewinder_separator", " | ")
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
            local round_label = loc("rewinder_round_label", "Round")
            local spacing = loc("rewinder_ante_round_spacing", " ")
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
         
         local separator = loc("rewinder_separator", " | ")
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
   
   -- Add "$" indicator for "entering shop" (display_type "F")
   -- Note: Stickers atlas can't be used - it contains card-sized overlays with tiny icons in corners
   if display_type == "F" then
      local dollar_colour = is_current and G.C.WHITE or (G.C.GOLD or {0.9, 0.7, 0.2, 1})
      table.insert(text_nodes, {
         n = G.UIT.T,
         config = {
            text = "$",  -- Trailing space for separation from state text
            colour = dollar_colour,
            scale = 0.5,
         },
      })
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
            spacing = loc("rewinder_card_number_spacing", " ")
            if spacing == nil then spacing = " " end
         else
            spacing = loc("rewinder_tailing_number_spacing", " ")
            if spacing == nil then spacing = " " end
         end
         state_tailing_text = state_tailing_text .. spacing .. tailing_number_text
      end
   elseif tailing_number_text ~= "" then
      local spacing = loc("rewinder_tailing_number_spacing", " ")
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
   if is_pending then
      table.insert(text_nodes, {
         n = G.UIT.T,
         config = {
            text = (state_tailing_text ~= "" and " [?]" or "[?]"),
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
      local arrow = REWINDER.create_triangle_arrow(G.C.WHITE)
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
         config = { minw = 0.08 },
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
               button = is_mark_mode and "rewinder_save_toggle_key" or "rewinder_save_restore",
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
      local empty_key = REWINDER._filter_active and "rewinder_no_key_saves" or "rewinder_no_saves"
      local empty_text = REWINDER._filter_active and "No key saves marked" or "No saves yet"
      content = {
         n = G.UIT.T,
         config = {
            text = loc(empty_key, empty_text),
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

   -- Calculate minh based on per_page to keep consistent window size
   -- Each entry ~0.8 height including spacing and padding, plus container padding (0.05 * 2 = 0.1)
   -- Formula: per_page * entry_height + container_padding
   local calculated_minh = per_page * 0.78 + 0.1
   
   return {
      n = G.UIT.ROOT,
      config = {
         align = (#entries == 0 and "cm" or "tm"),
         minw = SAVE_ENTRY_W,
         minh = calculated_minh,
         r = 0.1,
         colour = G.C.CLEAR,
      },
      nodes = { content },
   }
end

function G.UIDEF.rewinder_saves()
   local get_entries = REWINDER._get_displayed_entries or REWINDER.get_save_files
   local entries = get_entries()
   local per_page = 8

   local total_pages = math.max(1, math.ceil(#entries / per_page))
   local page_numbers = {}
   for i = 1, total_pages do
      local pattern = loc("rewinder_page_label", "Page %d/%d")
      page_numbers[i] = string.format(pattern, i, total_pages)
   end

   -- Find which page contains the current (highlighted) save - O(1) via index
   local initial_page = 1
   local SM = REWINDER._SaveManager
   local current_idx = SM and (SM.current_index or SM.find_current_index and SM.find_current_index())
   local display_idx = current_idx
   if REWINDER._filter_active and current_idx then
      display_idx = REWINDER._key_save_reverse_map and REWINDER._key_save_reverse_map[current_idx] or nil
   end
   if display_idx and display_idx >= 1 then
      initial_page = math.ceil(display_idx / per_page)
   end
   if REWINDER.ensure_meta_window_for_page and not REWINDER._filter_active then
      REWINDER.ensure_meta_window_for_page(initial_page, per_page, 4)
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

   local mark_label = REWINDER._mark_active and loc("rewinder_mark_keys_active", "Save marking changes")
      or loc("rewinder_mark_keys", "Edit key saves")
   local filter_label = REWINDER._filter_active and loc("rewinder_filter_keys_active", "Return to all saves")
      or loc("rewinder_filter_keys", "Check key saves")
   local mark_button_colour = REWINDER._mark_active and (G.C.RED or {0.9, 0.2, 0.2, 1}) or (REWINDER.KEY_SAVE_COLOR or KEY_SAVE_COLOR)
   local filter_button_colour = G.C.BLUE
   -- User setting point: change this to customize the icon-button border color.
   local icon_button_border_colour = G.C.UI.TEXT_LIGHT or {0.85, 0.85, 0.85, 1}
   local mark_button_ref = { label = { text = mark_label } }
   local filter_button_ref = { label = { text = filter_label } }
   REWINDER._saves_ui_refs.mark_button_ref = mark_button_ref
   REWINDER._saves_ui_refs.filter_button_ref = filter_button_ref
   
   -- Create cycle config and store it for jump_to_current
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
            nodes = { page_cycle },
         },
         {
            n = G.UIT.R,
            config = { align = "cm", colour = G.C.CLEAR },
            nodes = {
               {
                  n = G.UIT.C,
                  config = { align = "cm", minw = MODE_ROW_HALF_W, padding = 0.05 },
                  nodes = {
                     UIBox_button({
                        id = "rewinder_btn_filter_keys",
                        button = "rewinder_btn_filter_keys",
                        label = {},
                        dynamic_label = filter_button_ref.label,
                        minw = FILTER_BUTTON_W,
                        scale = 0.42,
                        colour = filter_button_colour,
                        focus_args = { nav = "wide" },
                      }),
                  },
               },
               {
                  n = G.UIT.C,
                  config = { align = "cm", minw = MODE_ROW_HALF_W, padding = 0.05 },
                  nodes = {
                     {
                        n = G.UIT.R,
                        config = { align = "cm", colour = G.C.CLEAR },
                        nodes = {
                           build_icon_button({
                              id = "rewinder_btn_mark_keys",
                              button = "rewinder_btn_mark_keys",
                              fill_id = "rewinder_btn_mark_keys_fill",
                              fill_colour = mark_button_colour,
                              icon = REWINDER.create_star_icon(G.C.WHITE, ICON_BUTTON_ICON_SIZE, ICON_BUTTON_ICON_SIZE),
                              border_colour = icon_button_border_colour,
                              focus_args = { nav = "wide" },
                           }),
                           build_icon_button({
                              id = "rewinder_btn_jump_to_current",
                              button = "rewinder_save_jump_to_current",
                              fill_id = "rewinder_btn_jump_to_current_fill",
                              fill_colour = G.C.ORANGE or {1, 0.6, 0.2, 1},
                              icon = REWINDER.create_triangle_icon(G.C.WHITE, ICON_BUTTON_ICON_SIZE, ICON_BUTTON_ICON_SIZE),
                              border_colour = icon_button_border_colour,
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

--- Build "Rewind to Last Save" button for the Game Over panel.
-- Reloads the current save (same as "l" key). Returns nil when unavailable.
function REWINDER.create_game_over_rewind_button()
   if not REWINDER.quick_continue_from_menu then return nil end
   local label_text = loc('rewinder_game_over_button', 'Rewind')
   local label_obj = DynaText({
      string = label_text,
      colours = { G.C.UI.TEXT_DARK },
      scale = 0.3,
      shadow = false,
   })
   return {
      n = G.UIT.R,
      config = { align = 'cm' },
      nodes = {{
         n = G.UIT.C,
         config = {
            align = 'cm',
            padding = 0,
            r = 0.1,
            hover = true,
            colour = G.C.EDITION,
            button = 'rewinder_game_over_rewind',
            minh = 0.4,
            shadow = true,
            outline = 0.7,
            outline_colour = G.C.UI.TEXT_DARK,
            focus_args = { nav = 'wide' },
         },
         nodes = {{
            n = G.UIT.R,
            config = { align = 'cm', padding = 0, minw = 2.3, maxw = 2.1 },
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
         -- Logic to find the current controller bind for toggle_saves
         local focus_args = { nav = "wide" }
         if REWINDER.keybinds and REWINDER.keybinds.get_binding then
            local binding = REWINDER.keybinds.get_binding("toggle_saves")
            if binding and binding.controller and not binding.controller["[none]"] then
               -- Find the first button bound (usually just one)
               for k, v in pairs(binding.controller) do
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
