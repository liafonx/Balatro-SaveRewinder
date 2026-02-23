if not REWINDER then REWINDER = {} end

local M = {}

function M.loc(key, fallback)
   if localize then
      return localize(key) or fallback
   end
   return fallback
end

function M.schedule_after_delay(delay, func)
   if G and G.E_MANAGER and Event then
      G.E_MANAGER:add_event(Event({
         trigger = "after",
         delay = delay or 0,
         func = function()
            func()
            return true
         end,
      }))
      return
   end
   func()
end

function M.run_after_frame(func)
   M.schedule_after_delay(0, func)
end

function M.clamp_page(page, total_pages)
   local p = tonumber(page) or 1
   local total = math.max(1, tonumber(total_pages) or 1)
   if p < 1 then p = 1 end
   if p > total then p = total end
   return p
end

function M.build_page_numbers(total_pages)
   local pattern = M.loc("rewinder_page_label", "Page %d/%d")
   local page_numbers = {}
   for i = 1, total_pages do
      page_numbers[i] = string.format(pattern, i, total_pages)
   end
   return page_numbers
end

function M.get_pillar_namebox_colour()
   local c = G and G.P_BLINDS and G.P_BLINDS.bl_pillar and G.P_BLINDS.bl_pillar.boss_colour
   if c then return c end
   return { 0.494, 0.404, 0.322, 1 }
end

function M.get_icon_button_border_colour()
   return G.C.UI.TEXT_LIGHT or {0.85, 0.85, 0.85, 1}
end

function M.get_icon_button_disabled_border_colour()
   return G.C.BLACK or {0, 0, 0, 1}
end

function M.get_icon_button_icon_colour()
   return G.C.WHITE or {1, 1, 1, 1}
end

function M.get_icon_button_disabled_icon_colour()
   return {0.45, 0.45, 0.45, 1}
end

function M.dim_colour(colour, factor)
   if type(colour) ~= "table" then return colour end
   factor = factor or 0.45
   return {
      (colour[1] or 1) * factor,
      (colour[2] or 1) * factor,
      (colour[3] or 1) * factor,
      colour[4] or 1,
   }
end

function M.get_saves_outline_inactive_colour()
   return G.C.JOKER_GREY or {0.5, 0.5, 0.5, 1}
end

function M.get_saves_outline_colour()
   if REWINDER and (REWINDER._export_active or REWINDER._rename_active or REWINDER._mark_active) then
      return G.C.RED or {0.9, 0.2, 0.2, 1}
   end
   if REWINDER and REWINDER._filter_active then
      return REWINDER.KEY_SAVE_COLOR or {0.2, 0.7, 0.7, 1}
   end
   return M.get_saves_outline_inactive_colour()
end

REWINDER.get_pillar_namebox_colour = M.get_pillar_namebox_colour
REWINDER.get_icon_button_border_colour = M.get_icon_button_border_colour
REWINDER.get_icon_button_disabled_border_colour = M.get_icon_button_disabled_border_colour
REWINDER.get_icon_button_icon_colour = M.get_icon_button_icon_colour
REWINDER.get_icon_button_disabled_icon_colour = M.get_icon_button_disabled_icon_colour
REWINDER.get_saves_outline_inactive_colour = M.get_saves_outline_inactive_colour
REWINDER.get_saves_outline_colour = M.get_saves_outline_colour

return M
