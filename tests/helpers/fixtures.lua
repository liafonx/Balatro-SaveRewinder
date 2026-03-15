-- tests/helpers/fixtures.lua
-- Shared fixture factories for unit tests.
-- Loaded by test files that need common sample data.

local Fixtures = {}

-- Entry schema constants (loaded lazily to avoid circular issues).
local _E = nil
local function E()
   if not _E then
      _E = require("SaveManagerEntrySchema")
   end
   return _E
end

-- Build a minimal save entry array suitable for Pruning / IndexStore tests.
-- All fields default to sensible values; override via the opts table.
function Fixtures.make_entry(opts)
   opts = opts or {}
   local schema = E()
   local entry = {}
   entry[schema.ENTRY_FILE]          = opts.file         or "save_001.jkr"
   entry[schema.ENTRY_ANTE]          = opts.ante         or 1
   entry[schema.ENTRY_ROUND]         = opts.round        or 1
   entry[schema.ENTRY_INDEX]         = opts.index        or 1
   entry[schema.ENTRY_MONEY]         = opts.money        or 5
   entry[schema.ENTRY_SIGNATURE]     = opts.signature    or "1:1:S:0:0:5"
   entry[schema.ENTRY_DISCARDS_USED] = opts.discards_used or 0
   entry[schema.ENTRY_HANDS_PLAYED]  = opts.hands_played  or 0
   entry[schema.ENTRY_IS_CURRENT]    = opts.is_current   or false
   entry[schema.ENTRY_BLIND_IDX]     = opts.blind_idx    or 1
   entry[schema.ENTRY_DISPLAY_TYPE]  = opts.display_type or "S"
   entry[schema.ENTRY_ORDINAL]       = opts.ordinal      or 1
   entry[schema.ENTRY_IS_KEY]        = opts.is_key       or false
   return entry
end

-- Build a minimal meta table (as passed to MetaFile.serialize_meta).
function Fixtures.make_meta(opts)
   opts = opts or {}
   return {
      money         = opts.money         or 5,
      signature     = opts.signature     or "1:1:S:0:0:5",
      discards_used = opts.discards_used or 0,
      hands_played  = opts.hands_played  or 0,
      blind_idx     = opts.blind_idx     or 1,
      display_type  = opts.display_type  or "S",
      ordinal       = opts.ordinal       or 1,
      is_key        = opts.is_key        or false,
      custom_state_name = opts.custom_state_name or nil,
   }
end

-- Serialized meta string matching make_meta defaults (no is_key, no custom_state_name).
Fixtures.DEFAULT_META_STRING = table.concat({
   "money=5",
   "signature=1:1:S:0:0:5",
   "discards_used=0",
   "hands_played=0",
   "blind_idx=1",
   "display_type=S",
   "ordinal=1",
}, "\n")

-- Sample run_data table exercising get_state_info / encode_signature paths.
function Fixtures.make_run_data(opts)
   opts = opts or {}
   return {
      STATE = opts.state or 1,   -- SHOP by default
      GAME  = {
         ante  = opts.ante  or 1,
         round = opts.round or 1,
         round_resets = {
            ante = opts.ante or 1,
            blind_choices = { Small = "bl_small", Big = "bl_big", Boss = "bl_hook" },
         },
         dollars        = opts.money or 5,
         current_round  = {
            discards_used = opts.discards_used or 0,
            hands_played  = opts.hands_played  or 0,
         },
         blind_on_deck  = opts.blind_on_deck or "Small",
      },
      ACTION = opts.action or nil,
   }
end

-- Build n save-cache entries with incrementing index/file names.
-- opts.ante: base ante (default 1)
-- opts.display_type: display type for all entries (default "S")
-- opts.is_key: is_key flag (default false)
function Fixtures.make_save_cache(n, opts)
   opts = opts or {}
   local cache = {}
   for i = 1, n do
      cache[i] = Fixtures.make_entry({
         file         = string.format("%d-%d-%d.jkr", opts.ante or 1, 1, i),
         ante         = opts.ante,
         round        = opts.round,
         money        = opts.money,
         index        = i,
         ordinal      = i,
         display_type = opts.display_type,
         is_key       = opts.is_key,
      })
   end
   return cache
end

return Fixtures
