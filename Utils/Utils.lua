--- Fast Save Loader - Utils.lua
--
-- Shared utility functions used across modules.

local M = {}

-- Deep copy utility for safely copying tables
function M.deepcopy(orig)
    local orig_type = type(orig)
    if orig_type ~= 'table' then return orig end
    local copy = {}
    for orig_key, orig_value in pairs(orig) do
        copy[M.deepcopy(orig_key)] = M.deepcopy(orig_value)
    end
    return copy
end

return M

