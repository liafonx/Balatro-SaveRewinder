--- Fast Save Loader - Init.lua
--
-- Main entry point. Bootstraps the mod by loading sub-modules
-- and setting up the global LOADER namespace.

if not LOADER then LOADER = {} end

-- 1. Load Core Modules
local StateSignature = require("StateSignature")
local SaveManager = require("SaveManager")

-- 2. Export API to LOADER namespace (for UI and Hooks)
LOADER.PATHS = SaveManager.PATHS

-- State & Logic
LOADER.mark_loaded_state = SaveManager.mark_loaded_state
LOADER.consume_skip_on_save = SaveManager.consume_skip_on_save
LOADER.describe_save = SaveManager.describe_save

-- StateSignature helpers
LOADER.describe_state_label = StateSignature.describe_state_label
LOADER.StateSignature = StateSignature -- Expose StateSignature module itself for GamePatches to pass to SaveManager

-- File/Save Management
LOADER.get_save_dir = SaveManager.get_save_dir
LOADER.get_save_files = SaveManager.get_save_files
LOADER.get_save_meta = SaveManager.get_save_meta
LOADER.preload_all_metadata = SaveManager.preload_all_metadata
LOADER.load_save = SaveManager.load_save_file
LOADER.load_and_start_from_file = SaveManager.load_and_start_from_file
LOADER.revert_to_previous_save = SaveManager.revert_to_previous_save
LOADER.load_save_at_index = SaveManager.load_save_at_index
LOADER.clear_all_saves = SaveManager.clear_all_saves
LOADER.find_current_index = SaveManager.find_current_index

-- Internal State Access (via module reference, since scalars are copied by value)
-- Expose the SaveManager module itself so callbacks can access/modify internal state
LOADER._SaveManager = SaveManager

-- Export entry index constants for UI access
LOADER.ENTRY_FILE = SaveManager.ENTRY_FILE
LOADER.ENTRY_ANTE = SaveManager.ENTRY_ANTE
LOADER.ENTRY_ROUND = SaveManager.ENTRY_ROUND
LOADER.ENTRY_INDEX = SaveManager.ENTRY_INDEX
LOADER.ENTRY_MODTIME = SaveManager.ENTRY_MODTIME
LOADER.ENTRY_STATE = SaveManager.ENTRY_STATE
LOADER.ENTRY_ACTION_TYPE = SaveManager.ENTRY_ACTION_TYPE
LOADER.ENTRY_IS_OPENING_PACK = SaveManager.ENTRY_IS_OPENING_PACK
LOADER.ENTRY_MONEY = SaveManager.ENTRY_MONEY
LOADER.ENTRY_SIGNATURE = SaveManager.ENTRY_SIGNATURE
LOADER.ENTRY_DISCARDS_USED = SaveManager.ENTRY_DISCARDS_USED
LOADER.ENTRY_HANDS_PLAYED = SaveManager.ENTRY_HANDS_PLAYED
LOADER.ENTRY_IS_CURRENT = SaveManager.ENTRY_IS_CURRENT

-- Convenience getters/setters for internal state
LOADER.get_pending_index = function() return SaveManager.pending_index end
LOADER.set_pending_index = function(v) SaveManager.pending_index = v end
LOADER.get_current_index = function() return SaveManager.current_index end
LOADER.set_current_index = function(v) SaveManager.current_index = v end

-- UI State
LOADER.saves_open = false

-- Debug Logging (Init.lua owns the debug output mechanism)
LOADER._debug_alert = nil
LOADER._debug_prefix = "[FastSL]"
LOADER.debug_log = function(tag, msg)
   local always_log = (tag == "step" or tag == "list" or tag == "error" or tag == "prune" or tag == "restore" or tag == "monitor")
   if not always_log then
      if not LOADER or not LOADER.config or not LOADER.config.debug_saves then return end
   end

   local prefix = LOADER._debug_prefix or "[FastSL]"
   local full_msg
   if tag and tag ~= "" then
      full_msg = prefix .. "[" .. tostring(tag) .. "] " .. tostring(msg)
   else
      full_msg = prefix .. " " .. tostring(msg)
   end

   -- Wrap the print call in a protected call (pcall).
   -- This prevents the entire game from crashing if another mod
   -- has a buggy hook on the global `print` function that causes a stack overflow.
   pcall(print, full_msg)
end

-- Inject the real logger into modules that have already been loaded.
SaveManager.debug_log = LOADER.debug_log
StateSignature.debug_log = LOADER.debug_log

-- Initialize cache during game loading (deferred to avoid blocking startup)
-- This pre-builds the save list so UI opens instantly
-- Uses get_save_files which loads first page eagerly, then background-loads the rest
if G and G.E_MANAGER and Event then
   G.E_MANAGER:add_event(Event({
      trigger = 'after',
      delay = 0.1,  -- Small delay to let game finish initializing
      func = function()
         if SaveManager and SaveManager.get_save_files then
            -- Force reload to scan directory, but let background loading handle metadata
            -- get_save_files loads META_FIRST_PASS_COUNT (12) entries eagerly for UI,
            -- then schedules remaining entries in chunks via _schedule_meta_load
            local entries = SaveManager.get_save_files(true)
            local count = entries and #entries or 0
            LOADER.debug_log("", "Initialized with " .. count .. " save(s)")
         end
         return true
      end
   }))
end

-- UI Helper (Alert Box) - Remains in Init.lua for now.
function LOADER.show_save_debug(ante, round, label)
   if not G or not G.ROOM_ATTACH or not UIBox or not G.UIT then return end
   label = label or ""
   local text = string.format("Save: Ante %d  Round %d%s", ante or 0, round or 0,
      (label ~= "" and ("  (" .. label .. ")")) or "")
   LOADER.debug_log("save", text)

   if LOADER._debug_alert and LOADER._debug_alert.remove then
      LOADER._debug_alert:remove()
      LOADER._debug_alert = nil
   end

   local definition = {
      n = G.UIT.ROOT,
      config = { align = "tm", padding = 0.05, colour = G.C.CLEAR },
      nodes = {
         {
            n = G.UIT.R,
            config = {
               align = "cm",
               r = 0.1,
               padding = 0.12,
               minw = 3.8,
               colour = G.C.BLACK,
               shadow = true,
            },
            nodes = {
               {
                  n = G.UIT.T,
                  config = {
                     text = text,
                     scale = 0.32,
                     colour = G.C.UI.TEXT_LIGHT,
                     shadow = true,
                  },
               },
            },
         },
      },
   }

   local box = UIBox({
      definition = definition,
      config = {
         instance_type = "ALERT",
         align = "tm",
         major = G.ROOM_ATTACH,
         offset = { x = 0, y = -0.2 },
         bond = "Weak",
      },
   })
   LOADER._debug_alert = box

   if G.E_MANAGER and Event then
      G.E_MANAGER:add_event(Event({
         trigger = "after",
         delay = 1.6,
         no_delete = true,
         blocking = false,
         timer = "REAL",
         func = function()
            if LOADER._debug_alert == box then
               if box.remove then box:remove() end
               LOADER._debug_alert = nil
            end
            return true
         end,
      }))
   end
end

G.FUNCS = G.FUNCS or {}
G.FUNCS.fastsl_config_change = function(args)
   args = args or {}
   if args.cycle_config and args.cycle_config.ref_table and args.cycle_config.ref_value then
      local ref_value = args.cycle_config.ref_value
      args.cycle_config.ref_table[ref_value] = args.to_key
      
      -- If keep_antes changed, immediately apply retention policy
      if ref_value == "keep_antes" and SaveManager then
         local Pruning = require("Pruning")
         local EntryConstants = require("EntryConstants")
         local dir = SaveManager.get_save_dir()
         local entries = SaveManager.get_save_files()
         if entries and #entries > 0 then
            Pruning.apply_retention_policy(dir, entries, EntryConstants)
            -- Force reload to rebuild cache index after pruning
            SaveManager.get_save_files(true)
         end
      end
   end
end
