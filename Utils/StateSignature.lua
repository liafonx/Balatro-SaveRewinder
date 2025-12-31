--- Save Rewinder - StateSignature.lua
--
-- Helper module for analyzing and comparing game state signatures.
-- Used to determine if a save should be skipped or kept.
local Logger = require("Logger")
local M = {}
M.debug_log = Logger.create("StateSignature")
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
-- Encode signature as a string for fast comparison
-- Format: "ante:round:state:action_type:money" (action_type: nil="", "opening_pack", "play", "discard")
function M.encode_signature(ante, round, state, action_type, money)
   local action_str = ""
   if action_type then
      action_str = action_type
   end
   return string.format("%d:%d:%d:%s:%d", 
      ante or 0, 
      round or 0, 
      state or 0, 
      action_str,
      money or 0
   )
end
function M.get_signature(run_data)
   if not run_data or type(run_data) ~= "table" then return nil end
   local game = run_data.GAME or {}
   local ante = (game.round_resets and tonumber(game.round_resets.ante)) or tonumber(game.ante) or 0
   local round = tonumber(game.round or 0) or 0
   local state = run_data.STATE
   local has_action = M.has_action(run_data)
   
   -- Separate is_opening_pack from action_type for clarity
   -- action_type is only for SELECTING_HAND states (play/discard), determined later by comparison
   local action_type = nil  -- Will be set later for SELECTING_HAND states
   local is_opening_pack = false
   local st = G and G.STATES
   if has_action and st and state == st.SHOP then
      is_opening_pack = true
   end
   
   -- robust money check
   local money = 0
   if game.dollars then money = tonumber(game.dollars) end
   if game.money then money = tonumber(game.money) end
   if game.current_round and game.current_round.dollars then 
        -- Prefer current_round dollars if available as it is often the active state
        money = tonumber(game.current_round.dollars) 
   end
   
   -- Extract action tracking values for play/discard detection
   local current_round = game.current_round or {}
   local discards_used = tonumber(current_round.discards_used) or 0
   local hands_played = tonumber(current_round.hands_played) or 0
   
   -- Extract blind key for displaying blind icon in UI
   -- Use blind_on_deck to get the current/active blind (more accurate than round number mapping)
   local blind_key = nil
   if game.blind_on_deck and game.round_resets and game.round_resets.blind_choices then
      -- blind_on_deck contains 'Small', 'Big', or 'Boss'
      local blind_type = game.blind_on_deck
      -- Force Small blind for round 0 (blind selection phase)
      if round == 0 then
         blind_type = 'Small'
      end
      blind_key = game.round_resets.blind_choices[blind_type]
      M.debug_log("detail", "Extracted blind_key from blind_on_deck: " .. tostring(blind_type) .. " -> " .. tostring(blind_key))
   elseif game.round_resets and game.round_resets.blind_choices then
      -- Fallback: use round number if blind_on_deck is not available
      -- Round 0 = blind selection, 1 = Small, 2 = Big, 3 = Boss
      local blind_type = (round == 0 and 'Small') or (round == 1 and 'Small') or (round == 2 and 'Big') or 'Boss'
      blind_key = game.round_resets.blind_choices[blind_type]
      M.debug_log("detail", "Extracted blind_key from round number: round=" .. tostring(round) .. ", type=" .. tostring(blind_type) .. " -> " .. tostring(blind_key))
   else
      M.debug_log("detail", "Could not extract blind_key: blind_on_deck=" .. tostring(game.blind_on_deck) .. ", has_round_resets=" .. tostring(game.round_resets ~= nil) .. ", has_blind_choices=" .. tostring(game.round_resets and game.round_resets.blind_choices ~= nil))
   end
   
   local sig = {
      ante = ante,
      round = round,
      state = state,
      money = money or 0,
      action_type = action_type,  -- Only "play" or "discard" for SELECTING_HAND, nil otherwise
      is_opening_pack = is_opening_pack,  -- Boolean: true if shop state has ACTION
      discards_used = discards_used,
      hands_played = hands_played,
      blind_key = blind_key,  -- Blind key (e.g., "bl_small", "bl_final_acorn")
      signature = M.encode_signature(ante, round, state, action_type, money or 0),
   }

   return sig
end

function M.signatures_equal(a, b)
   if not a or not b then return false end
   -- Fast path: compare encoded signature strings
   if a.signature and b.signature then
      return a.signature == b.signature
   end
   -- Fallback: compare individual fields
   return (a.ante or 0) == (b.ante or 0) and
          (a.round or 0) == (b.round or 0) and
          (a.state or 0) == (b.state or 0) and
          (a.action_type or nil) == (b.action_type or nil) and
          (a.money or 0) == (b.money or 0)
end
-- Get label from state, action_type (play/discard), and is_opening_pack (boolean)
function M.get_label_from_state(state, action_type, is_opening_pack)
   local label = M.describe_state_label(state) or "state"
   -- Check if this is shop with opening pack action
   if label == "shop" and is_opening_pack then
      label = "opening pack"
   end
   -- For selecting_hand state, handle action type (play/discard)
   if label == "selecting hand" then
      if action_type then
         -- Has action type (play/discard)
         if action_type == "play" then
            label = "selecting hand (play)"
         elseif action_type == "discard" then
            label = "selecting hand (discard)"
         end
      else
         -- No action type - this is the start of round
         label = "start of round"
      end
   end
   return label
end
function M.describe_signature(sig)
   if not sig then return "save" end
   local label = M.get_label_from_state(sig.state, sig.action_type, sig.is_opening_pack)
   return string.format("Ante %s Round %s (%s)", tostring(sig.ante or "?"), tostring(sig.round or "?"), tostring(label))
end
function M.is_shop_signature(sig)
   if not sig then return false end
   local state = sig.state
   return state and G and G.STATES and G.STATES.SHOP and state == G.STATES.SHOP
end
-- Check if save data has a pending ACTION (e.g., opening a booster pack)
-- ACTION is stored as run_data.ACTION = { ... } when there's a pending action
function M.has_action(run_data)
   if not run_data then return false end
   local action = run_data.ACTION
   if action and type(action) == "table" and next(action) then
      return true
   end
   return false
end

return M