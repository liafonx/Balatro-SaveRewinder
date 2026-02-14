--- Save Rewinder - NaNProtection.lua
--
-- Centralized NaN/inf protections for save/load/runtime display.

local Logger = require("Logger")
local debug_log = Logger.create("NaN")

local M = {}

M.MAX_SAFE_SCORE = 1.7976931348623157e308
M.LARGE_NUMBER_THRESHOLD = 1e290

local function is_nan(v)
    return type(v) == "number" and v ~= v
end

local function is_inf(v)
    return type(v) == "number" and (v == math.huge or v == -math.huge)
end

local function parse_special_chip_text(chip_text)
    if type(chip_text) ~= "string" then return nil end
    local txt = string.lower(chip_text):gsub("%s+", "")
    if txt:find("nan", 1, true) then
        return txt:sub(1, 1) == "-" and -0/0 or 0/0
    end
    if txt:find("inf", 1, true) then
        return txt:sub(1, 1) == "-" and -1/0 or 1/0
    end
    return nil
end

local function should_clamp_infinity()
    if REWINDER and REWINDER.config and REWINDER.config.clamp_infinity_scores ~= nil then
        return REWINDER.config.clamp_infinity_scores
    end
    return false
end

local function is_known_big_mod_loaded()
    local mods = SMODS and SMODS.Mods
    if type(mods) ~= "table" then return false end

    local ids = { "Talisman", "Amulet", "talisman", "amulet" }
    for _, id in ipairs(ids) do
        local m = mods[id]
        if type(m) == "table" and m.can_load ~= false and m.disabled ~= true then
            return true
        end
    end
    return false
end

local function to_big_returns_big_type()
    if type(to_big) ~= "function" then return false end
    local ok, v = pcall(to_big, 1)
    if not ok then return false end
    return type(v) ~= "number"
end

-- Session-local cache: nil = not yet checked, true/false = cached result.
-- Mods don't load/unload mid-session so this is safe to cache permanently.
local _big_backend_cached = nil

function M.has_big_backend()
    if _big_backend_cached ~= nil then return _big_backend_cached end
    if type(Big) == "table" and type(Big.is) == "function" then
        _big_backend_cached = true
        return true
    end
    if to_big_returns_big_type() then
        _big_backend_cached = true
        return true
    end
    if is_known_big_mod_loaded() then
        _big_backend_cached = true
        return true
    end
    _big_backend_cached = false
    return false
end

-- Lightweight sanitizer for hot paths (event easing values).
function M.sanitize_inline(v)
    -- Only recover nil. Preserve NaN/inf so overflow displays are not coerced to 0 mid-animation.
    if v == nil then return 0 end
    return v
end

-- Comparison helper that stays compatible with to_big environments.
function M.score_gt(amt, current)
    if amt == nil then return false end

    -- Fast path: regular finite numbers (common case).
    if type(amt) == "number" and type(current) == "number" and
       amt == amt and current == current and
       amt ~= math.huge and amt ~= -math.huge then
        return math.floor(amt) > current
    end

    if type(amt) ~= "number" then
        -- Big-number backend compatibility: compare via to_big if available.
        if M.has_big_backend() and type(to_big) == "function" then
            local ok_l, l = pcall(to_big, amt)
            local ok_r, r = pcall(to_big, current or 0)
            if ok_l and ok_r then
                return l > r
            end
        end

        if type(amt) == "table" and type(amt.to_number) == "function" then
            local ok, v = pcall(function() return amt:to_number() end)
            if ok and type(v) == "number" then
                amt = v
            else
                return false
            end
        else
            return false
        end
    end

    if is_nan(amt) then
        return not (type(current) == "number" and is_nan(current))
    end

    if amt == math.huge then
        return current ~= math.huge
    end
    if amt == -math.huge then
        return false
    end

    local lhs = math.floor(amt)
    local rhs = current
    if type(rhs) ~= "number" then
        rhs = tonumber(rhs) or 0
    end
    if is_nan(rhs) then
        return false
    end

    if type(to_big) == "function" and M.has_big_backend() then
        local ok_l, l = pcall(to_big, lhs)
        local ok_r, r = pcall(to_big, rhs)
        if ok_l and ok_r then
            return l > r
        end
    end
    return lhs > rhs
end

local function normalize_score_value(amt)
    if type(amt) ~= "number" then
        -- Preserve big-number objects in big backend mode.
        if M.has_big_backend() then
            return amt
        end
        if type(amt) == "table" and type(amt.to_number) == "function" then
            local ok, v = pcall(function() return amt:to_number() end)
            if ok and type(v) == "number" then
                amt = v
            else
                return 0
            end
        else
            return 0
        end
    end
    if is_nan(amt) then
        return 0/0
    end
    if is_inf(amt) then
        if should_clamp_infinity() then
            return amt < 0 and -M.MAX_SAFE_SCORE or M.MAX_SAFE_SCORE
        end
        return amt
    end
    return math.floor(amt)
end

-- Continue panel score assignment.
function M.sanitize_round_score_assignment(amt)
    return normalize_score_value(amt)
end

-- Profile high score assignment.
function M.sanitize_high_score_assignment(amt)
    return normalize_score_value(amt)
end

-- Restore blind chips from saved chip_text if numeric chips were lost in legacy/corrupt saves.
function M.recover_blind_chips(chips, chip_text, fallback)
    if chips ~= nil then
        return chips
    end

    local special = parse_special_chip_text(chip_text)
    if special ~= nil then return special end

    if type(chip_text) == "string" then
        local numeric = tonumber(chip_text:gsub(",", ""))
        if numeric ~= nil then return numeric end
    end

    return fallback
end

function M.recover_blind_chip_text(chip_text, chips)
    if chip_text == nil or chip_text == "" then
        return number_format(chips)
    end
    return chip_text
end

-- Ensure a blind table always has a usable numeric chips field.
-- Preserves NaN/inf semantics when chip_text encodes them.
function M.ensure_blind_chips(blind)
    if type(blind) ~= "table" then return 0 end
    if blind.chips ~= nil then return blind.chips end

    local recovered = M.recover_blind_chips(nil, blind.chip_text, nil)
    if recovered ~= nil then
        blind.chips = recovered
        return recovered
    end

    blind.chips = 0
    if blind.chip_text == nil or blind.chip_text == "" then
        blind.chip_text = "0"
    end
    debug_log("warning", "Recovered nil blind.chips as 0")
    return blind.chips
end

function M.ensure_game_chips(game)
    if type(game) ~= "table" then return 0 end
    if game.chips ~= nil then return game.chips end

    local fallback = 0
    local ch = game.current_round and game.current_round.current_hand
    if ch and type(ch.chip_total) == "number" then
        fallback = ch.chip_total
    end

    game.chips = fallback
    debug_log("warning", "Recovered nil G.GAME.chips as " .. tostring(fallback))
    return game.chips
end

-- Post-load: recover nil target chips in serialized G.GAME.blind state.
function M.sanitize_game_blind(game)
    if not game then return end
    M.ensure_blind_chips(game.blind)
    M.ensure_game_chips(game)
end

-- Returns true when accumulated chips have met or exceeded the blind target.
-- Safely recovers nil chips on either side so callers don't need inline guards.
function M.chips_met_target()
    local game = G and G.GAME
    local blind = game and game.blind
    if type(game) == "table" and type(blind) == "table" and
       type(game.chips) == "number" and type(blind.chips) == "number" then
        return game.chips - blind.chips >= 0
    end
    local bc = M.ensure_blind_chips(blind)
    local gc = M.ensure_game_chips(game)
    return gc - bc >= 0
end

-- Computes the safe ease_to value for the score accumulation event.
-- Recovers nil G.GAME.chips and respects SMODS.calculate_round_score when present.
function M.safe_ease_chips(hand_chips, mult)
    local game = G and G.GAME
    local chips = (type(game) == "table" and type(game.chips) == "number") and game.chips or M.ensure_game_chips(game)

    -- Fast path: vanilla numeric score computation.
    if type(hand_chips) == "number" and type(mult) == "number" and
       hand_chips == hand_chips and mult == mult and
       hand_chips ~= math.huge and hand_chips ~= -math.huge and
       mult ~= math.huge and mult ~= -math.huge then
        return chips + math.floor(hand_chips * mult)
    end

    local score = (SMODS and SMODS.calculate_round_score and SMODS.calculate_round_score())
        or ((hand_chips or 0) * (mult or 0))
    if type(score) ~= "number" then score = tonumber(score) or 0 end
    return chips + math.floor(score)
end

-- Post-load: NaN in round_scores often unpacks as nil.
function M.sanitize_round_scores(game)
    if not game or not game.round_scores then return end

    local fixed = {}
    for k, v in pairs(game.round_scores) do
        if v and v.amt == nil then
            v.amt = 0
            table.insert(fixed, k)
        end
    end

    if #fixed > 0 then
        debug_log("info", "Fixed nil in " .. table.concat(fixed, ", "))
    end
end

-- Pre-save: optionally clamp inf for round_scores.
function M.sanitize_round_scores_presave(game)
    if not game or not game.round_scores then return end

    local clamp_inf = should_clamp_infinity()
    local fixed_inf = {}

    for k, v in pairs(game.round_scores) do
        if v and type(v.amt) == "number" then
            local a = v.amt
            if clamp_inf and is_inf(a) then
                v.amt = a < 0 and -M.MAX_SAFE_SCORE or M.MAX_SAFE_SCORE
                table.insert(fixed_inf, k)
            end
        end
    end

    if #fixed_inf > 0 then
        debug_log("info", "inf in " .. table.concat(fixed_inf, ", ") .. " (clamped)")
    end
end

-- number_format hook helper.
function M.sanitize_number_format(num)
    -- Fast path: standard finite numbers in normal range.
    if type(num) == "number" and num == num and num ~= math.huge and num ~= -math.huge then
        local abs_num = math.abs(num)
        if abs_num < M.LARGE_NUMBER_THRESHOLD then
            return num, false
        end
        local exp = math.floor(math.log10(abs_num))
        local mantissa = num / (10 ^ exp)
        return string.format("%.1fe%d", mantissa, exp), true
    end

    if num == nil then
        return "0", true
    end

    if type(num) == "string" then
        if num ~= "" then
            return num, true
        end
        return "0", true
    end

    if type(num) ~= "number" then
        -- Big-number mods may pass objects with :to_number(); convert when possible.
        if type(num) == "table" and type(num.to_number) == "function" then
            local ok, v = pcall(function() return num:to_number() end)
            if ok and type(v) == "number" then
                num = v
            else
                return tostring(num), true
            end
        else
            return tostring(num), true
        end
    end

    -- Preserve runtime-specific NaN string behavior (nan/-nan) by letting game format it.
    if is_nan(num) then
        return num, false
    end

    if is_inf(num) then
        if should_clamp_infinity() then
            num = num < 0 and -M.MAX_SAFE_SCORE or M.MAX_SAFE_SCORE
        else
            return num, false
        end
    end

    local abs_num = math.abs(num)
    if abs_num >= M.LARGE_NUMBER_THRESHOLD then
        local exp = math.floor(math.log10(abs_num))
        local mantissa = num / (10 ^ exp)
        return string.format("%.1fe%d", mantissa, exp), true
    end

    return num, false
end

-- Continue menu best-hand scale helper.
-- Keeps overflow/non-finite values at base scale, independent of external scale_number overrides.
function M.scale_continue_best_hand(amt, base_scale, max_scale_point)
    local scale = type(base_scale) == "number" and base_scale or 0.3

    if type(amt) ~= "number" then
        return scale
    end
    if is_nan(amt) or is_inf(amt) then
        return scale
    end
    if math.abs(amt) >= M.LARGE_NUMBER_THRESHOLD then
        return scale
    end

    if type(scale_number) == "function" then
        return scale_number(amt, scale, max_scale_point)
    end
    return scale
end

return M
