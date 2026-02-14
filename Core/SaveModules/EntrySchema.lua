local M = {}

M.ENTRY_KEYS = {
   "FILE", "ANTE", "ROUND", "INDEX",
   "MONEY", "SIGNATURE", "DISCARDS_USED", "HANDS_PLAYED",
   "IS_CURRENT", "BLIND_IDX", "DISPLAY_TYPE", "ORDINAL", "IS_KEY",
}

for i, key in ipairs(M.ENTRY_KEYS) do
   M["ENTRY_" .. key] = i
end

M.E = {
   ENTRY_FILE = M.ENTRY_FILE,
   ENTRY_ANTE = M.ENTRY_ANTE,
   ENTRY_ROUND = M.ENTRY_ROUND,
   ENTRY_INDEX = M.ENTRY_INDEX,
   ENTRY_MONEY = M.ENTRY_MONEY,
   ENTRY_SIGNATURE = M.ENTRY_SIGNATURE,
   ENTRY_DISCARDS_USED = M.ENTRY_DISCARDS_USED,
   ENTRY_HANDS_PLAYED = M.ENTRY_HANDS_PLAYED,
   ENTRY_IS_CURRENT = M.ENTRY_IS_CURRENT,
   ENTRY_BLIND_IDX = M.ENTRY_BLIND_IDX,
   ENTRY_DISPLAY_TYPE = M.ENTRY_DISPLAY_TYPE,
   ENTRY_ORDINAL = M.ENTRY_ORDINAL,
   ENTRY_IS_KEY = M.ENTRY_IS_KEY,
}

local BLIND_KEYS = {
   "bl_small", "bl_big", "bl_ox", "bl_hook", "bl_mouth", "bl_fish",
   "bl_club", "bl_manacle", "bl_tooth", "bl_wall", "bl_house", "bl_mark",
   "bl_final_bell", "bl_wheel", "bl_arm", "bl_psychic", "bl_goad", "bl_water",
   "bl_eye", "bl_plant", "bl_needle", "bl_head", "bl_final_leaf", "bl_final_vessel",
   "bl_window", "bl_serpent", "bl_pillar", "bl_flint", "bl_final_acorn", "bl_final_heart",
}

local BLIND_KEY_TO_INDEX = {
   bl_undiscovered = 0,
}
for i, key in ipairs(BLIND_KEYS) do
   BLIND_KEY_TO_INDEX[key] = i
end

function M.blind_key_to_index(blind_key)
   if not blind_key then return 0 end
   return BLIND_KEY_TO_INDEX[blind_key] or 0
end

function M.index_to_blind_key(index)
   if not index then return nil end
   if index == 0 then return "bl_undiscovered" end
   return BLIND_KEYS[index]
end

return M
