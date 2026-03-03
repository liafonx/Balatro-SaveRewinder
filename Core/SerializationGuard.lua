--- Save Rewinder - SerializationGuard.lua
--
-- Serialization safety checks and recovery routines for save_run payloads.
-- Loaded as a module (require("SerializationGuard")) by GamePatches.lua.

if not REWINDER then REWINDER = {} end
local Logger = require("Logger")
local log = Logger.create("SerializationGuard")

local function _contains_object_ref_bounded(root, max_nodes)
   if type(root) ~= "table" then return false, 0, false end
   local stack = { root }
   local seen = {}
   local visited = 0
   local truncated = false
   local limit = max_nodes or 12000

   while #stack > 0 do
      local node = stack[#stack]
      stack[#stack] = nil
      if type(node) == "table" and not seen[node] then
         seen[node] = true
         visited = visited + 1
         if visited >= limit then
            truncated = true
            break
         end
         if Object and node.is and type(node.is) == "function" and node:is(Object) then
            return true, visited, truncated
         end
         for _, value in pairs(node) do
            if type(value) == "table" and not seen[value] then
               stack[#stack + 1] = value
            end
         end
      end
   end
   return false, visited, truncated
end

local function _is_channel_serializable(v)
   local t = type(v)
   return t == "nil" or t == "boolean" or t == "number" or t == "string" or t == "table"
end

local function _find_first_nonserializable_path(root, max_nodes)
   if type(root) ~= "table" then return nil, nil, false end

   local seen = {}
   local stack = { { value = root, path = "save_run" } }
   local visited = 0
   local limit = max_nodes or 25000

   while #stack > 0 do
      local node = stack[#stack]
      stack[#stack] = nil
      local value = node.value

      if type(value) == "table" then
         if not seen[value] then
            seen[value] = true
            visited = visited + 1
            if visited >= limit then
               return nil, nil, true
            end
            for k, v in pairs(value) do
               local suffix
               if type(k) == "string" then
                  suffix = "." .. k
               else
                  suffix = "[" .. tostring(k) .. "]"
               end
               if type(v) == "table" then
                  stack[#stack + 1] = { value = v, path = node.path .. suffix }
               elseif not _is_channel_serializable(v) then
                  return node.path .. suffix, type(v), false
               end
            end
         end
      elseif not _is_channel_serializable(value) then
         return node.path, type(value), false
      end
   end

   return nil, nil, false
end

local function _is_back_center_nonserializable_path(path)
   return type(path) == "string" and path:match("^save_run%.BACK%.effect%.center")
end

local function _get_back_center_desc(save_table)
   if type(save_table) ~= "table" then return "key=?, mod=?" end
   local back = save_table.BACK
   local center = back and back.effect and back.effect.center
   if type(center) ~= "table" then return "key=?, mod=?" end
   local key = center.key or "?"
   local mod = center.mod
   local mod_id = (type(mod) == "table" and (mod.id or mod.name or mod.prefix)) or center.mod_id or "?"
   return string.format("key=%s mod=%s", tostring(key), tostring(mod_id))
end

local function _sanitize_back_snapshot_only(save_table)
   if type(save_table) ~= "table" or not recursive_table_cull then return false end
   local back = save_table.BACK
   if type(back) ~= "table" then return false end
   local ok, culled_back = pcall(recursive_table_cull, back)
   if not ok or type(culled_back) ~= "table" then return false end
   save_table.BACK = culled_back
   return true
end

-- Returns true if BACK-only sanitize resolved the issue (no remaining bad paths).
-- Side effect: syncs G.ARGS.save_run and G.culled_table BACK field on success.
-- bad_path: the already-found bad path (pass nil to let this function scan first).
local function _try_back_sanitize_and_verify(save_table, bad_path)
   local path = bad_path or _find_first_nonserializable_path(save_table, 25000)
   if not _is_back_center_nonserializable_path(path) then return false end
   if not _sanitize_back_snapshot_only(save_table) then return false end
   local next_bad = _find_first_nonserializable_path(save_table, 25000)
   if next_bad then return false end
   if G and G.ARGS and G.ARGS.save_run then G.ARGS.save_run.BACK = save_table.BACK end
   if G and G.culled_table then G.culled_table.BACK = save_table.BACK end
   return true
end

function REWINDER.recover_save_run_payload(save_table, push_err)
   if type(save_table) ~= "table" or not recursive_table_cull then return save_table end
   local bad_path, bad_type = _find_first_nonserializable_path(save_table, 25000)
   if _is_back_center_nonserializable_path(bad_path) and _try_back_sanitize_and_verify(save_table, bad_path) then
      if not REWINDER._back_snapshot_sanitize_noted then
         REWINDER._back_snapshot_sanitize_noted = true
         log("warning", string.format(
            "save_run push recovered by BACK-only sanitize (%s, %s)",
            _get_back_center_desc(save_table), tostring(push_err)
         ))
      end
      return save_table
   end
   local ok_recull, reculled = pcall(recursive_table_cull, save_table)
   if ok_recull and type(reculled) == "table" then
      REWINDER._force_save_run_recull = true
      if G and G.ARGS then G.ARGS.save_run = reculled end
      if G then G.culled_table = reculled end
      if not REWINDER._save_run_recull_noted then
         REWINDER._save_run_recull_noted = true
         if bad_path then
            log("warning", string.format(
               "save_run push recovered by recursive recull; root cause: non-serializable %s at %s (%s). Compatibility recull mode enabled.",
               tostring(bad_type), tostring(bad_path), tostring(push_err)
            ))
         else
            log("warning", "save_run push recovered by recursive recull (" .. tostring(push_err) .. "). Compatibility recull mode enabled.")
         end
      end
      return reculled
   end
   return save_table
end

function REWINDER.validate_culled_table_once(culled_table)
   if REWINDER._culled_validate_done then return end
   REWINDER._culled_validate_done = true
   if type(culled_table) ~= "table" then return end

   local bad_path, bad_type, truncated = _find_first_nonserializable_path(culled_table, 25000)
   if bad_path then
      if _is_back_center_nonserializable_path(bad_path) and _try_back_sanitize_and_verify(culled_table, bad_path) then
         log("warning", string.format(
            "Selective cull compatibility: sanitized BACK center snapshot (%s)",
            _get_back_center_desc(culled_table)
         ))
         return
      end
      REWINDER._force_save_run_recull = true
      if recursive_table_cull then
         local ok, reculled = pcall(recursive_table_cull, culled_table)
         if ok and type(reculled) == "table" then
            if G and G.ARGS then G.ARGS.save_run = reculled end
            if G then G.culled_table = reculled end
         end
      end
      log("warning", string.format(
         "Selective cull compatibility mode: detected non-serializable %s at %s%s",
         tostring(bad_type), tostring(bad_path), truncated and " (bounded scan reached)" or ""
      ))
      return
   end

   if not Logger.is_verbose() then return end

   local has_object_ref, visited, truncated_obj = _contains_object_ref_bounded(culled_table.cardAreas, 20000)
   if has_object_ref then
      log("warning", "Selective cull check: Object ref found in cardAreas (unexpected)")
      return
   end
   local suffix = truncated_obj and " (bounded scan reached)" or ""
   log("debug", string.format("Selective cull check passed: cardAreas scanned=%d%s", visited, suffix))
end

return
