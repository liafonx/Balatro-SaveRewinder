--- Save Rewinder - Init.lua
--
-- Main entry point. Bootstraps the mod by loading sub-modules
-- and setting up the global REWINDER namespace.

if not REWINDER then REWINDER = {} end

-- 1. Load Core Modules
local StateSignature = require("StateSignature")
local SaveManager = require("SaveManager")

-- 2. Export API to REWINDER namespace (for UI and Hooks)
REWINDER.PATHS = SaveManager.PATHS

-- State & Logic
REWINDER.mark_loaded_state = SaveManager.mark_loaded_state
REWINDER.consume_skip_on_save = SaveManager.consume_skip_on_save
REWINDER.describe_save = SaveManager.describe_save

-- StateSignature helpers
REWINDER.StateSignature = StateSignature -- Expose StateSignature module itself for GamePatches to pass to SaveManager

-- File/Save Management
REWINDER.get_save_dir = SaveManager.get_save_dir
REWINDER.get_save_files = SaveManager.get_save_files
REWINDER.get_save_meta = SaveManager.get_save_meta
REWINDER.preload_all_metadata = SaveManager.preload_all_metadata
REWINDER.load_save = SaveManager.load_save_file
REWINDER.load_and_start_from_file = SaveManager.load_and_start_from_file
REWINDER.revert_to_previous_save = SaveManager.revert_to_previous_save
REWINDER.load_save_at_index = SaveManager.load_save_at_index
REWINDER.clear_all_saves = SaveManager.clear_all_saves
REWINDER.find_current_index = SaveManager.find_current_index

-- Internal State Access (via module reference, since scalars are copied by value)
-- Expose the SaveManager module itself so callbacks can access/modify internal state
REWINDER._SaveManager = SaveManager

-- Export entry index constants for UI access
REWINDER.ENTRY_FILE = SaveManager.ENTRY_FILE
REWINDER.ENTRY_ANTE = SaveManager.ENTRY_ANTE
REWINDER.ENTRY_ROUND = SaveManager.ENTRY_ROUND
REWINDER.ENTRY_INDEX = SaveManager.ENTRY_INDEX
REWINDER.ENTRY_MODTIME = SaveManager.ENTRY_MODTIME
REWINDER.ENTRY_STATE = SaveManager.ENTRY_STATE
REWINDER.ENTRY_ACTION_TYPE = SaveManager.ENTRY_ACTION_TYPE
REWINDER.ENTRY_IS_OPENING_PACK = SaveManager.ENTRY_IS_OPENING_PACK
REWINDER.ENTRY_MONEY = SaveManager.ENTRY_MONEY
REWINDER.ENTRY_SIGNATURE = SaveManager.ENTRY_SIGNATURE
REWINDER.ENTRY_DISCARDS_USED = SaveManager.ENTRY_DISCARDS_USED
REWINDER.ENTRY_HANDS_PLAYED = SaveManager.ENTRY_HANDS_PLAYED
REWINDER.ENTRY_IS_CURRENT = SaveManager.ENTRY_IS_CURRENT
REWINDER.ENTRY_BLIND_KEY = SaveManager.ENTRY_BLIND_KEY

-- Convenience getters/setters for internal state
REWINDER.get_pending_index = function() return SaveManager.pending_index end
REWINDER.set_pending_index = function(v) SaveManager.pending_index = v end
REWINDER.get_current_index = function() return SaveManager.current_index end
REWINDER.set_current_index = function(v) SaveManager.current_index = v end

-- UI State
REWINDER.saves_open = false

-- Debug Logging (centralized via Logger module)
local Logger = require("Logger")
REWINDER._debug_alert = nil
REWINDER.debug_log = Logger.log  -- Simple log without module name

-- Deferred cache initialization - runs after Steamodded is ready
-- Hook into Game.set_render_settings like Blueprint does for asset loading
-- This ensures we initialize after "Steamodded v1.0.0~BETA" log message
REWINDER._cache_initialized = false

local _game_set_render_settings = Game.set_render_settings
function Game:set_render_settings(...)
   local ret = _game_set_render_settings(self, ...)
   
   -- Initialize cache once after Steamodded is fully ready
   if not REWINDER._cache_initialized then
      REWINDER._cache_initialized = true
      local success, err = pcall(function()
         if SaveManager and SaveManager.get_save_files then
            local entries = SaveManager.get_save_files(true)
            local count = entries and #entries or 0
            REWINDER.debug_log("step", "Initialized with " .. count .. " save(s)")
         end
      end)
      if not success then
         REWINDER.debug_log("error", "Cache init failed: " .. tostring(err))
      end
   end
   
   return ret
end

-- UI Helper (Alert Box) - Remains in Init.lua for now.
function REWINDER.show_save_debug(ante, round, label)
   if not G or not G.ROOM_ATTACH or not UIBox or not G.UIT then return end
   label = label or ""
   local text = string.format("Save: Ante %d  Round %d%s", ante or 0, round or 0,
      (label ~= "" and ("  (" .. label .. ")")) or "")
   REWINDER.debug_log("save", text)

   if REWINDER._debug_alert and REWINDER._debug_alert.remove then
      REWINDER._debug_alert:remove()
      REWINDER._debug_alert = nil
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
   REWINDER._debug_alert = box

   if G.E_MANAGER and Event then
      G.E_MANAGER:add_event(Event({
         trigger = "after",
         delay = 1.6,
         no_delete = true,
         blocking = false,
         timer = "REAL",
         func = function()
            if REWINDER._debug_alert == box then
               if box.remove then box:remove() end
               REWINDER._debug_alert = nil
            end
            return true
         end,
      }))
   end
end

G.FUNCS = G.FUNCS or {}
G.FUNCS.rewinder_config_change = function(args)
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
