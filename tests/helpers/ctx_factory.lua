-- tests/helpers/ctx_factory.lua
-- Shared SaveModule ctx factory for unit tests.
-- Returns a fully-wired ctx suitable for calling SaveModule factory functions.

local RuntimeState  = require("SaveManagerRuntimeState")
local EntrySchema   = require("SaveManagerEntrySchema")
local Logger        = require("Logger")
local StateSignature = require("StateSignature")
local Pruning       = require("Pruning")

local CtxFactory = {}

-- Build a minimal mock SaveManager M with all fields SaveModule factories expect.
local function _make_mock_M(overrides)
   local M = overrides or {}
   M.debug_log              = M.debug_log              or function() end
   M.get_save_dir           = M.get_save_dir           or function() return "/mock/save" end
   M.get_current_file       = M.get_current_file       or function() return M._last_loaded_file end
   M._last_loaded_file      = M._last_loaded_file      -- nil by default
   M._overlay_open          = M._overlay_open          or false
   M.META_CACHE_BASE_LIMIT  = M.META_CACHE_BASE_LIMIT  or 32
   M.index_to_blind_key     = M.index_to_blind_key     or function(idx) return EntrySchema.index_to_blind_key(idx) end
   M.get_entry_by_file      = M.get_entry_by_file      or function() return nil end
   M.get_entry_by_id        = M.get_entry_by_id        or function() return nil end
   M.get_index_by_file      = M.get_index_by_file      or function() return nil end
   M.get_save_meta          = M.get_save_meta          or function() return false end
   M.get_save_files         = M.get_save_files         or function() return {} end
   M.skip_next_save         = M.skip_next_save         or false
   M._restore_active        = M._restore_active        or false
   M.reset_ordinal_state    = M.reset_ordinal_state    or function() end
   M.find_current_index     = M.find_current_index     or function() return nil end
   M._last_generated_id     = M._last_generated_id     or 0
   M.ensure_key_flags_loaded = M.ensure_key_flags_loaded or function() return 0 end
   return M
end

-- Build a minimal stub Pruning that exposes KEEP_ANTES_VALUES (from real Pruning)
-- but stubs apply_retention_policy for call tracking.
local function _make_stub_pruning(overrides)
   local calls = {}
   local stub = overrides or {}
   stub.KEEP_ANTES_VALUES       = stub.KEEP_ANTES_VALUES       or Pruning.KEEP_ANTES_VALUES
   stub.apply_retention_policy  = stub.apply_retention_policy  or function(dir, entries, E_ref, opts)
      calls[#calls + 1] = { dir = dir, entries = entries, E_ref = E_ref, opts = opts }
   end
   stub._calls = calls
   return stub
end

-- Build a minimal stub MetaFile with call recording.
local function _make_stub_meta_file(overrides)
   local calls = {}
   local stub = overrides or {}
   stub.read_meta_file  = stub.read_meta_file  or function(path)
      calls[#calls + 1] = { op = "read", path = path }
      return nil
   end
   stub.write_meta_file = stub.write_meta_file or function(path, meta)
      calls[#calls + 1] = { op = "write", path = path, meta = meta }
      return true
   end
   stub._calls = calls
   return stub
end

-- Build a minimal stub FileIO.
local function _make_stub_file_io(overrides)
   local stub = overrides or {}
   stub.file_exists_os          = stub.file_exists_os          or function() return false end
   stub.create_dir_os           = stub.create_dir_os           or function() end
   stub.copy_love_to_os         = stub.copy_love_to_os         or function() return false end
   stub.sanitize_path_component = stub.sanitize_path_component or function(s) return s end
   stub.get_save_dir            = stub.get_save_dir            or function() return "/mock/save" end
   stub.get_profile             = stub.get_profile             or function() return "1" end
   return stub
end

-- Stub cross-service index reference (replaced by real IndexStore api in IndexStore tests).
local function _make_stub_index(overrides)
   local stub = overrides or {}
   stub.is_async_pending         = stub.is_async_pending         or function() return false end
   stub.is_async_save_ready      = stub.is_async_save_ready      or function() return false end
   stub.clear_async_pending      = stub.clear_async_pending      or function() end
   stub.rebuild_file_index       = stub.rebuild_file_index       or function() end
   stub.invalidate_save_cache_view = stub.invalidate_save_cache_view or function() end
   stub.update_cache_current_flags = stub.update_cache_current_flags or function() end
   stub.get_entry_by_file        = stub.get_entry_by_file        or function() return nil end
   return stub
end

-- Stub cross-service meta reference.
local function _make_stub_meta(overrides)
   local stub = overrides or {}
   stub.purge_meta_cache = stub.purge_meta_cache or function() end
   stub.cache_meta       = stub.cache_meta       or function() end
   return stub
end

-- Stub cross-service ordinal reference.
local function _make_stub_ordinal(overrides)
   local stub = overrides or {}
   stub.init_ordinal_state_from_entry = stub.init_ordinal_state_from_entry or function() end
   stub.compute_display_type          = stub.compute_display_type          or function() return "S" end
   stub.reset_ordinal_state           = stub.reset_ordinal_state           or function() end
   stub.create_signature              = stub.create_signature              or function() return "1:1:S:0:0:5" end
   return stub
end

-- Public factory: returns a fully-wired ctx.
-- overrides: table of fields to override (M, S, E, MetaFile, FileIO, Pruning, index, meta, ordinal).
-- Each override is a partial table; missing fields are filled with defaults.
function CtxFactory.mk_save_module_ctx(overrides)
   overrides = overrides or {}

   local S = overrides.S or RuntimeState.new(32)
   local E = overrides.E or EntrySchema.E

   return {
      M              = _make_mock_M(overrides.M),
      S              = S,
      E              = E,
      Logger         = Logger,
      StateSignature = StateSignature,
      MetaFile       = _make_stub_meta_file(overrides.MetaFile),
      FileIO         = _make_stub_file_io(overrides.FileIO),
      Pruning        = _make_stub_pruning(overrides.Pruning),
      index          = _make_stub_index(overrides.index),
      meta           = _make_stub_meta(overrides.meta),
      ordinal        = _make_stub_ordinal(overrides.ordinal),
   }
end

return CtxFactory
