--- Save Rewinder - StateSignature.lua
--
-- Helper module for extracting game state info from run_data.
-- Signature format matches entry fields for unified comparison.
local Logger = require("Logger")
local M = {}
M.debug_log = Logger.create("StateSignature")

-- Encode signature as a string for fast comparison
-- Format: "ante:round:display_type:discards_used:hands_played:money"
-- This matches entry fields for unified structure
function M.encode_signature(ante, round, display_type, discards_used, hands_played, money)
   return string.format("%d:%d:%s:%d:%d:%d", 
      ante or 0, 
      round or 0, 
      display_type or "?",
      discards_used or 0,
      hands_played or 0,
      money or 0
   )
end

-- Compare two signature strings (fast path)
function M.signatures_equal(sig_a, sig_b)
   if not sig_a or not sig_b then return false end
   return sig_a == sig_b
end

-- Extract raw state info from run_data (does NOT compute display_type)
-- Returns a table with fields needed for display_type computation
function M.get_state_info(run_data)
   if not run_data or type(run_data) ~= "table" then return nil end
   local game = run_data.GAME or {}
   local ante = (game.round_resets and tonumber(game.round_resets.ante)) or tonumber(game.ante) or 0
   local round = tonumber(game.round or 0) or 0
   local state = run_data.STATE
   local has_action = M.has_action(run_data)
   
   -- Check if opening pack (SHOP state with ACTION)
   local is_opening_pack = false
   local st = G and G.STATES
   if has_action and st and state == st.SHOP then
      is_opening_pack = true
   end
   
   -- Robust money check
   local money = 0
   if game.dollars then money = tonumber(game.dollars) end
   if game.money then money = tonumber(game.money) end
   if game.current_round and game.current_round.dollars then 
      money = tonumber(game.current_round.dollars) 
   end
   
   -- Extract action tracking values for play/discard detection
   local current_round = game.current_round or {}
   local discards_used = tonumber(current_round.discards_used) or 0
   local hands_played = tonumber(current_round.hands_played) or 0
   
   -- Extract blind key for displaying blind icon in UI
   local blind_key = nil
   if game.blind_on_deck and game.round_resets and game.round_resets.blind_choices then
      local blind_type = game.blind_on_deck
      if round == 0 then
         blind_type = 'Small'
      end
      blind_key = game.round_resets.blind_choices[blind_type]
   elseif game.round_resets and game.round_resets.blind_choices then
      local blind_type = (round == 0 and 'Small') or (round == 1 and 'Small') or (round == 2 and 'Big') or 'Boss'
      blind_key = game.round_resets.blind_choices[blind_type]
   end
   
   return {
      ante = ante,
      round = round,
      state = state,
      money = money or 0,
      is_opening_pack = is_opening_pack,
      discards_used = discards_used,
      hands_played = hands_played,
      blind_key = blind_key,
   }
end

-- Check if save data has a pending ACTION (e.g., opening a booster pack)
function M.has_action(run_data)
   local action = run_data and run_data.ACTION
   return action and type(action) == "table" and next(action) ~= nil
end

-- Compute display_type code from game state fields
-- Returns: S=shop (reroll), F=first_shop, O=opening_pack, A=after_pack (shop after pack closed),
--          R=start_round, P=play, D=discard, H=selecting_hand, E=end_round, B=choose_blind, ?=unknown
-- is_start_round: true if SELECTING_HAND with hands_played=0 and discards_used=0
-- is_after_pack: true if last save was O (opening pack) and we're back in regular shop
function M.compute_display_type(state, action_type, is_opening_pack, is_first_shop, is_start_round, is_after_pack)
   local st = G and G.STATES
   if not st then return "?" end

   if state == st.SHOP then
      if is_opening_pack then return "O" end
      if is_first_shop then return "F" end
      if is_after_pack then return "A" end  -- Shop after pack closed (not reroll)
      return "S"  -- Reroll shop
   elseif state == st.SELECTING_HAND then
      if is_start_round then return "R" end  -- Start of round (hands=0, discards=0)
      if action_type == "play" then return "P" end
      if action_type == "discard" then return "D" end
      return "H"
   elseif state == st.ROUND_EVAL or state == st.HAND_PLAYED then
      return "E"
   elseif state == st.BLIND_SELECT then
      return "B"
   end
   return "?"
end

-- Display type to label mapping (for describe functions)
local DISPLAY_TYPE_TO_LABEL = {
   S = "shop",
   A = "in shop",
   F = "entering shop",
   O = "opening pack",
   R = "start of round",
   P = "selecting hand (play)",
   D = "selecting hand (discard)",
   H = "selecting hand",
   E = "end of round",
   B = "choose blind",
   ["?"] = "in run",
}

-- Get label from display_type code
function M.get_label_from_display_type(display_type)
   return DISPLAY_TYPE_TO_LABEL[display_type or "?"] or "save"
end

-- Describe a save for logging
function M.describe_save(ante, round, display_type)
   local label = M.get_label_from_display_type(display_type)
   return string.format("Ante %s Round %s (%s)", 
      tostring(ante or "?"), 
      tostring(round or "?"), 
      label)
end

return M
