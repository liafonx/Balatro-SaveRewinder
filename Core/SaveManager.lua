--- Save Rewinder - SaveManager.lua
--
-- Facade module that composes SaveManager services from Core/SaveManager/.

local Logger = require("Logger")
local StateSignature = require("StateSignature")
local FileIO = require("FileIO")
local MetaFile = require("MetaFile")
local Pruning = require("Pruning")

local EntrySchema = require("SaveManagerEntrySchema")
local RuntimeState = require("SaveManagerRuntimeState")
local IndexStore = require("SaveManagerIndexStore")
local MetaCache = require("SaveManagerMetaCache")
local OrdinalTracker = require("SaveManagerOrdinalTracker")
local RetentionService = require("SaveManagerRetentionService")
local SkipService = require("SaveManagerSkipService")
local LoadService = require("SaveManagerLoadService")
local CreateService = require("SaveManagerCreateService")
local QueueService = require("SaveManagerQueueService")

local M = {}

for _, key in ipairs(EntrySchema.ENTRY_KEYS) do
   M["ENTRY_" .. key] = EntrySchema["ENTRY_" .. key]
end

M.PATHS = { SAVES = "SaveRewinder" }
M.debug_log = Logger.create("SaveManager")
M.META_CACHE_BASE_LIMIT = 32

M._last_generated_id = 0
M._overlay_open = false

-- Transitional compatibility fields (one release cycle).
M._last_loaded_file = nil
M._pending_skip_reason = nil
M._loaded_mark_applied = nil
M._loaded_ante = nil
M._loaded_round = nil
M._loaded_money = nil
M._loaded_discards = nil
M._loaded_hands = nil
M._loaded_display_type = nil
M._restore_active = false
M.skip_next_save = false
M.skipping_pack_open = nil
M.pending_future_prune_boundary = nil
M.current_index = nil
M.pending_index = nil
M._rw_queue = {}
M._rw_queue_head = 1
M._rw_queue_tail = 0
M._rw_cancelled_files = {}

function M.generate_unique_id()
   local now_ms = os.time() * 1000
   if now_ms <= (M._last_generated_id or 0) then
      now_ms = (M._last_generated_id or 0) + 1
   end
   M._last_generated_id = now_ms
   return now_ms
end

function M.blind_key_to_index(blind_key)
   return EntrySchema.blind_key_to_index(blind_key)
end

function M.index_to_blind_key(index)
   return EntrySchema.index_to_blind_key(index)
end

function M.get_profile()
   return FileIO.get_profile()
end

function M.get_save_dir()
   return FileIO.get_save_dir(M.PATHS.SAVES)
end

function M.set_current_index(idx)
   M.current_index = idx
end

-- Queue infrastructure (ring buffer, flush, sync fallback) lives in QueueService.
-- Functions are installed directly on M by QueueService(ctx).

local S = RuntimeState.new(M.META_CACHE_BASE_LIMIT)
local ctx = {
   M = M,
   S = S,
   E = EntrySchema.E,
   Logger = Logger,
   StateSignature = StateSignature,
   MetaFile = MetaFile,
   FileIO = FileIO,
   Pruning = Pruning,
}

ctx.index = IndexStore(ctx)
ctx.meta = MetaCache(ctx)
ctx.ordinal = OrdinalTracker(ctx)
ctx.retention = RetentionService(ctx)
ctx.skip = SkipService(ctx)
ctx.load = LoadService(ctx)
ctx.create = CreateService(ctx)
ctx.queue = QueueService(ctx)

function M.get_entry_with_meta(file)
   if not file then return nil end
   local entry = M.get_entry_by_file(file)
   if not entry then
      M.debug_log("warning", "get_entry_with_meta: entry not found for file=" .. tostring(file))
      return nil
   end
   if entry[M.ENTRY_IS_KEY] == nil then
      local ok = M.get_save_meta(entry)
      M.debug_log("debug", string.format("get_entry_with_meta: loaded key metadata file=%s ok=%s", tostring(file), tostring(ok)))
   end
   return entry
end

function M.update_entry_is_key(file, is_key)
   if not file then return end
   local entry = M.get_entry_by_file(file)
   local normalized = (is_key == true)
   if entry then
      entry[M.ENTRY_IS_KEY] = normalized
   else
      M.debug_log("warning", "update_entry_is_key: cache entry missing for file=" .. tostring(file))
   end

   if S.meta_cache[file] then
      S.meta_cache[file].is_key = normalized
      S.meta_lru_clock = S.meta_lru_clock + 1
      S.meta_lru_ts[file] = S.meta_lru_clock
   end
   S.bucket_counts = nil
   M.debug_log("debug", string.format("update_entry_is_key: file=%s is_key=%s", tostring(file), tostring(normalized)))
end

function M.describe_save(opts)
   opts = opts or {}
   local entry = opts.entry or (opts.file and M.get_entry_by_file(opts.file))
   if entry then
      return StateSignature.describe_save(
         entry[M.ENTRY_ANTE],
         entry[M.ENTRY_ROUND],
         entry[M.ENTRY_DISPLAY_TYPE]
      )
   end

   if opts.run_data then
      local state_info = StateSignature.get_state_info(opts.run_data)
      if state_info then
         local st = G and G.STATES
         local is_start_round = (st and state_info.state == st.SELECTING_HAND and
            state_info.hands_played == 0 and state_info.discards_used == 0)
         local display_type = StateSignature.compute_display_type(state_info.state, nil, state_info.is_opening_pack, false, is_start_round, false)
         return StateSignature.describe_save(state_info.ante, state_info.round, display_type)
      end
   end

   return "Save"
end

return M
