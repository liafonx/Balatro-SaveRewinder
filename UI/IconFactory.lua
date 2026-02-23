if not REWINDER then REWINDER = {} end

local Layout = require("UILayout")
local UIShared = require("UIShared")

local M = {}

-- Custom triangle arrow indicator (replaces built-in 'chosen' which has hardcoded positioning)
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

   prep_draw(self, 1)
   love.graphics.scale(1 / G.TILESIZE)

   local scale = 2
   local anim_offset = math.min(0.6 * math.sin(G.TIMERS.REAL * 9) * scale + 0.2, 0)

   local w = self.VT.w * G.TILESIZE
   local h = self.VT.h * G.TILESIZE
   local cx = w * 1.4 + anim_offset
   local cy = h / 2
   local tri_size = 3 * scale

   if G.SETTINGS.GRAPHICS.shadows == "On" then
      love.graphics.setColor(0, 0, 0, 0.3)
      love.graphics.polygon("fill",
         cx - tri_size + 1, cy - tri_size * 0.6 + 1,
         cx + 1, cy + 1,
         cx - tri_size + 1, cy + tri_size * 0.6 + 1
      )
   end

   love.graphics.setColor(self.colour)
   love.graphics.polygon("fill",
      cx - tri_size, cy - tri_size * 0.6,
      cx, cy,
      cx - tri_size, cy + tri_size * 0.6
   )

   love.graphics.pop()
end

function REWINDER.create_triangle_arrow(colour)
   return TriangleArrow(0.25, 0.4, colour)
end

-- Base class for cacheable icon shapes.
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

function CachedIcon:_compute_points(w_px, h_px)
   return nil
end

function CachedIcon:_build_mesh()
   if not self.VT then return end
   local w_px = self.VT.w * G.TILESIZE
   local h_px = self.VT.h * G.TILESIZE
   local points = self:_compute_points(w_px, h_px)
   if not points then
      self._mesh_ready = true
      return
   end

   self._points = points
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
      return
   end

   local points = self._points
   if dx == 0 and dy == 0 then
      love.graphics.polygon("fill", points)
      return
   end

   local shifted = {}
   for i = 1, #points, 2 do
      shifted[#shifted + 1] = points[i] + dx
      shifted[#shifted + 1] = points[i + 1] + dy
   end
   love.graphics.polygon("fill", shifted)
end

function CachedIcon:draw()
   if not self.VT then return end
   if not self._mesh_ready then self:_build_mesh() end
   if not self._points then return end

   prep_draw(self, 1)
   love.graphics.scale(1 / G.TILESIZE)

   if G.SETTINGS.GRAPHICS.shadows == "On" then
      self:_draw_shape(1, 1, 0, 0, 0, 0.3)
   end
   local c = self.colour
   self:_draw_shape(0, 0, c[1], c[2], c[3], c[4] or 1)

   love.graphics.pop()
end

local TriangleIcon = CachedIcon:extend()

function TriangleIcon:_compute_points(w_px, h_px)
   local cx = w_px * 0.5
   local cy = h_px * 0.5
   local tri = math.max(2, math.min(w_px, h_px) * 0.58)
   return {
      cx - tri * 0.45, cy - tri * 0.55,
      cx + tri * 0.55, cy,
      cx - tri * 0.45, cy + tri * 0.55,
   }
end

function REWINDER.create_triangle_icon(colour, w, h)
   return TriangleIcon(w or 0.40, h or 0.40, colour)
end

local StarIcon = CachedIcon:extend()

function StarIcon:_compute_points(w_px, h_px)
   local cx = w_px * 0.5
   local cy = h_px * 0.5
   local outer = math.max(2, math.min(w_px, h_px) * 0.42)
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

local PencilIcon = CachedIcon:extend()

function PencilIcon:_compute_points(w_px, h_px)
   local cx = w_px * 0.5
   local cy = h_px * 0.5
   local size = math.min(w_px, h_px)
   local angle = math.pi / 4
   local dir_x = math.cos(angle)
   local dir_y = math.sin(angle)
   local perp_x = -dir_y
   local perp_y = dir_x

   local body_len = size * 0.66
   local half_w = size * 0.15
   local tip_len = size * 0.18

   local tail_cx = cx - dir_x * (body_len * 0.56)
   local tail_cy = cy - dir_y * (body_len * 0.56)
   local head_cx = cx + dir_x * (body_len * 0.44)
   local head_cy = cy + dir_y * (body_len * 0.44)

   local tail_top_x = tail_cx + perp_x * half_w
   local tail_top_y = tail_cy + perp_y * half_w
   local tail_bot_x = tail_cx - perp_x * half_w
   local tail_bot_y = tail_cy - perp_y * half_w
   local head_top_x = head_cx + perp_x * half_w
   local head_top_y = head_cy + perp_y * half_w
   local head_bot_x = head_cx - perp_x * half_w
   local head_bot_y = head_cy - perp_y * half_w
   local tip_x = head_cx + dir_x * tip_len
   local tip_y = head_cy + dir_y * tip_len

   return {
      tail_top_x, tail_top_y,
      tail_bot_x, tail_bot_y,
      head_bot_x, head_bot_y,
      tip_x, tip_y,
      head_top_x, head_top_y,
   }
end

function REWINDER.create_pencil_icon(colour, w, h)
   return PencilIcon(w or 0.40, h or 0.40, colour)
end

local PendingDotIcon = Moveable:extend()

function PendingDotIcon:init(w, h, outer_colour, inner_colour)
   Moveable.init(self, 0, 0, w or 0.20, h or 0.20)
   self.outer_colour = outer_colour or G.C.RED
   self.inner_colour = inner_colour
   self.states = {
      drag = { can = false },
      hover = { can = false },
      collide = { can = false },
   }
end

function PendingDotIcon:draw()
   if not self.VT then return end

   prep_draw(self, 1)
   love.graphics.scale(1 / G.TILESIZE)

   local w_px = self.VT.w * G.TILESIZE
   local h_px = self.VT.h * G.TILESIZE
   local cx = w_px * 0.5
   local cy = h_px * 0.5
   local outer_r = math.max(1.5, math.min(w_px, h_px) * 0.48)
   local inner_r = outer_r * 0.58

   if G.SETTINGS.GRAPHICS.shadows == "On" then
      love.graphics.setColor(0, 0, 0, 0.28)
      love.graphics.circle("fill", cx + 1, cy + 1, outer_r)
   end

   local oc = self.outer_colour
   love.graphics.setColor(oc[1], oc[2], oc[3], oc[4] or 1)
   love.graphics.circle("fill", cx, cy, outer_r)

   if self.inner_colour then
      local ic = self.inner_colour
      love.graphics.setColor(ic[1], ic[2], ic[3], ic[4] or 1)
      love.graphics.circle("fill", cx, cy, inner_r)
   end

   love.graphics.pop()
end

function REWINDER.create_pending_dot_icon(outer_colour, inner_colour, w, h)
   return PendingDotIcon(w or 0.20, h or 0.20, outer_colour or G.C.RED, inner_colour)
end

-- Download/export icon: centered solid down arrow.
local DownloadIcon = Moveable:extend()

function DownloadIcon:init(w, h, colour)
   Moveable.init(self, 0, 0, w or 0.40, h or 0.40)
   self.colour = colour or G.C.WHITE
   self.states = {
      drag     = { can = false },
      hover    = { can = false },
      collide  = { can = false },
   }
end

function DownloadIcon:draw()
   if not self.VT then return end

   prep_draw(self, 1)
   love.graphics.scale(1 / G.TILESIZE)

   local w_px = self.VT.w * G.TILESIZE
   local h_px = self.VT.h * G.TILESIZE
   local c = self.colour
   local min_dim = math.min(w_px, h_px)
   local cx = w_px * 0.5
   local shaft_w = math.max(2.2, min_dim * 0.24)
   local shaft_top = math.floor(h_px * 0.12 + 0.5) + 0.5
   local head_top = math.floor(h_px * 0.55 + 0.5) + 0.5
   local head_tip = math.floor(h_px * 0.82 + 0.5) + 0.5
   local head_half_w = math.max(2.7, min_dim * 0.285)

   local function _draw_symbol(dx, dy, r, g, b, a)
      love.graphics.setColor(r, g, b, a)

      -- Single-silhouette arrow using a shaft rectangle + connected triangle head.
      love.graphics.rectangle("fill",
         cx - shaft_w * 0.5 + dx, shaft_top + dy,
         shaft_w, (head_top - shaft_top)
      )
      love.graphics.polygon("fill",
         cx - head_half_w + dx, head_top + dy,
         cx + head_half_w + dx, head_top + dy,
         cx + dx, head_tip + dy
      )

   end

   if G.SETTINGS.GRAPHICS.shadows == "On" then
      _draw_symbol(1, 1, 0, 0, 0, 0.3)
   end
   _draw_symbol(0, 0, c[1], c[2], c[3], c[4] or 1)

   love.graphics.pop()
end

function REWINDER.create_download_icon(colour, w, h)
   return DownloadIcon(w or 0.40, h or 0.40, colour)
end

function M.build_icon_button(opts)
   local border_colour = opts.border_colour or G.C.UI.TEXT_LIGHT or {0.85, 0.85, 0.85, 1}
   local disabled_border_colour = opts.disabled_border_colour or UIShared.get_icon_button_disabled_border_colour()
   local icon_colour = opts.icon_colour or UIShared.get_icon_button_icon_colour()
   local disabled_icon_colour = opts.disabled_icon_colour or UIShared.get_icon_button_disabled_icon_colour()
   local border = math.max(0, Layout.ICON_BUTTON_BORDER or 0)
   -- Keep inner/outer rounded rectangles concentric so border thickness is uniform.
   local inner_r = math.max(0.01, (Layout.ICON_BUTTON_RADIUS or 0) - border)
   local inner_side = math.max(0.01, (Layout.ICON_BUTTON_SIDE or 0) - border * 2)
   local enabled = (opts.enabled ~= false)
   local icon_obj = opts.icon
   if icon_obj and type(icon_obj.colour) == "table" then
      local c = enabled and icon_colour or disabled_icon_colour
      icon_obj.colour = { c[1] or 1, c[2] or 1, c[3] or 1, c[4] or 1 }
   end
   return {
      n = G.UIT.C,
      config = { align = "cm", padding = 0.08 },
      nodes = {
         {
            n = G.UIT.R,
            config = {
               id = opts.id,
               button = enabled and opts.button or nil,
               align = "cm",
               colour = enabled and border_colour or disabled_border_colour,
               minw = Layout.ICON_BUTTON_SIDE,
               minh = Layout.ICON_BUTTON_SIDE,
               padding = 0,
               r = Layout.ICON_BUTTON_RADIUS,
               hover = enabled,
               can_collide = enabled,
               shadow = enabled,
               ref_table = opts.ref_table,
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
                     padding = Layout.ICON_BUTTON_PADDING,
                     r = inner_r,
                     can_collide = false,
                     shadow = false,
                  },
                  nodes = {
                     {
                        n = G.UIT.O,
                        config = {
                           id = (opts.id and (opts.id .. "_icon")) or nil,
                           object = icon_obj,
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

return M
