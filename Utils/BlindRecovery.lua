--- Save Rewinder - BlindRecovery.lua
--
-- Blind chip and round-score recovery routines.
-- Depends on NaNProtection for is_nan/is_inf primitives.

local NaN = require("NaNProtection")
local Logger = require("Logger")
local debug_log = Logger.create("BlindRecovery")

local M = {}

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

local should_clamp_infinity = NaN.should_clamp_infinity

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
       ((type(game.chips) == "number" and type(blind.chips) == "number")
        or (NaN.has_big_backend() and game.chips ~= nil and blind.chips ~= nil)) then
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

    -- Big-number path: Talisman/Amulet FFI cdata fails the type checks above.
    -- Their metamethods handle *, +, and math.floor correctly, so delegate directly.
    if NaN.has_big_backend() and hand_chips ~= nil and mult ~= nil then
        return chips + math.floor(hand_chips * mult)
    end

    debug_log("warning", "safe_ease_chips slow path: hand_chips type=" .. type(hand_chips) .. " mult type=" .. type(mult))
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
            if clamp_inf and NaN.is_inf(a) then
                v.amt = a < 0 and -NaN.MAX_SAFE_SCORE or NaN.MAX_SAFE_SCORE
                table.insert(fixed_inf, k)
            end
        end
    end

    if #fixed_inf > 0 then
        debug_log("info", "inf in " .. table.concat(fixed_inf, ", ") .. " (clamped)")
    end
end

-- Continue menu best-hand scale helper.
-- Keeps overflow/non-finite values at base scale, independent of external scale_number overrides.
function M.scale_continue_best_hand(amt, base_scale, max_scale_point)
    local scale = type(base_scale) == "number" and base_scale or 0.3

    if type(amt) ~= "number" then
        return scale
    end
    if NaN.is_nan(amt) or NaN.is_inf(amt) then
        return scale
    end
    if math.abs(amt) >= NaN.LARGE_NUMBER_THRESHOLD then
        return scale
    end

    if type(scale_number) == "function" then
        return scale_number(amt, scale, max_scale_point)
    end
    return scale
end

return M
