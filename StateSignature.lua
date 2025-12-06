--- Fast Save Loader - StateSignature.lua
--
-- Helper module for analyzing and comparing game state signatures.
-- Used to determine if a backup should be skipped or kept.

local M = {}

function M.describe_state_label(state)
   if not state then return nil end

   -- Primary mapping via G.STATES.
   local st = G and G.STATES
   if st then
      if state == st.SHOP then return "shop" end
      if state == st.BLIND_SELECT then return "choose blind" end
      if state == st.SELECTING_HAND then return "selecting hand" end
      if state == st.ROUND_EVAL or state == st.HAND_PLAYED then return "end of round" end
      if state == st.DRAW_TO_HAND then return "start of round" end
   end
   return nil
end

function M.get_signature(run_data)
   if not run_data or type(run_data) ~= "table" then return nil end
   local game = run_data.GAME or {}
   local ante = (game.round_resets and tonumber(game.round_resets.ante)) or tonumber(game.ante) or 0
   local round = tonumber(game.round or 0) or 0
   local state = run_data.STATE
   local label = M.describe_state_label(state) or "state"
   
   -- robust money check
   local money = 0
   if game.dollars then money = tonumber(game.dollars) end
   if game.money then money = tonumber(game.money) end
   if game.current_round and game.current_round.dollars then 
        -- Prefer current_round dollars if available as it is often the active state
        money = tonumber(game.current_round.dollars) 
   end
   
   local sig = {
      ante = ante,
      round = round,
      state = state,
      label = label,
      money = money or 0,
   }

   return sig
end

function M.signatures_equal(a, b)
   if not a or not b then return false end
   local keys = {
      "ante", "round", "state", "label", "money",
   }
   for _, k in ipairs(keys) do
      local va, vb = a[k], b[k]
      if (va ~= nil or vb ~= nil) and va ~= vb then
         return false
      end
   end
   return true
end

function M.describe_signature(sig)
   if not sig then return "save" end
   local state = sig.label or "state"
   return string.format("Ante %s Round %s (%s)", tostring(sig.ante or "?"), tostring(sig.round or "?"), tostring(state))
end

function M.is_shop_signature(sig)
   if not sig then return false end
   local state = sig.state
   if state and G and G.STATES and G.STATES.SHOP and state == G.STATES.SHOP then
      return true
   end
   local label = sig.label or sig.debug_label
   if label and type(label) == "string" then
      return label:lower() == "shop"
   end
   return false
end

return M
