local SaveManager = require("SaveManager")
local MetaFile = require("MetaFile")
local Logger = require("Logger")
local EntrySchema = require("SaveManagerEntrySchema")

local KeySaves = {}
local debug_log = Logger.create("KeySaves")

local _pending = {}

local function _meta_path_for_file(file)
   local dir = SaveManager.get_save_dir()
   return dir .. "/" .. EntrySchema.meta_filename(tostring(file))
end

local function _clear_pending()
   _pending = {}
end

local function _write_key_flag(file, new_is_key)
   local meta_path = _meta_path_for_file(file)
   local meta = MetaFile.read_meta_file(meta_path)
   if not meta then
      debug_log("warning", "Failed to read key save meta: " .. tostring(file))
      return false
   end
   meta.is_key = (new_is_key == true)
   if not MetaFile.write_meta_file(meta_path, meta) then
      debug_log("warning", "Failed to write key save meta: " .. tostring(file))
      return false
   end
   SaveManager.update_entry_is_key(file, new_is_key)
   return true
end

local function _pending_count()
   local count = 0
   for _ in pairs(_pending) do
      count = count + 1
   end
   return count
end

function KeySaves.is_key(entry)
   return entry and entry[SaveManager.ENTRY_IS_KEY] == true
end

function KeySaves.effective_is_key(entry)
   if not entry then return false, false end
   local file = entry[SaveManager.ENTRY_FILE]
   if _pending[file] ~= nil then
      return _pending[file], true
   end
   return entry[SaveManager.ENTRY_IS_KEY] == true, false
end

function KeySaves.toggle_pending(file)
   local entry = SaveManager.get_entry_with_meta(file)
   if not entry then
      debug_log("warning", "toggle_pending failed: entry not found for file=" .. tostring(file))
      return nil
   end

   local committed = entry[SaveManager.ENTRY_IS_KEY] == true
   local effective
   if _pending[file] ~= nil then
      local new_val = not _pending[file]
      if new_val == committed then
         _pending[file] = nil
         effective = committed
      else
         _pending[file] = new_val
         effective = new_val
      end
   else
      _pending[file] = not committed
      effective = _pending[file]
   end

   debug_log("debug", string.format("toggle_pending file=%s effective=%s pending=%d", tostring(file), tostring(effective), _pending_count()))
   return effective
end

function KeySaves.commit_pending()
   local success, fail = 0, 0
   local pending_before = _pending_count()
   debug_log("debug", "Committing pending key-save changes count=" .. tostring(pending_before))
   for file, new_is_key in pairs(_pending) do
      if _write_key_flag(file, new_is_key) then
         success = success + 1
      else
         fail = fail + 1
      end
   end

   _clear_pending()
   debug_log("info", string.format("Committed key-save changes success=%d fail=%d", success, fail))
   return success, fail
end

function KeySaves.discard_pending()
   _clear_pending()
   debug_log("debug", "Discarded pending key-save changes")
end

function KeySaves.has_pending()
   return next(_pending) ~= nil
end

function KeySaves.get_key_saves(entries)
   if not entries then return {}, {} end
   local filtered = {}
   local index_map = {}
   local loaded_meta = 0

   if SaveManager.ensure_key_flags_loaded then
      loaded_meta = SaveManager.ensure_key_flags_loaded(entries) or 0
   end

   for i, entry in ipairs(entries) do
      if entry[SaveManager.ENTRY_IS_KEY] == nil and SaveManager.get_save_meta and not SaveManager.ensure_key_flags_loaded then
         if SaveManager.get_save_meta(entry) then loaded_meta = loaded_meta + 1 end
      end
      if entry[SaveManager.ENTRY_IS_KEY] == true then
         filtered[#filtered + 1] = entry
         index_map[#filtered] = i
      end
   end

   debug_log("debug", string.format("get_key_saves total=%d filtered=%d loaded_meta=%d", #entries, #filtered, loaded_meta))
   return filtered, index_map
end

return KeySaves
