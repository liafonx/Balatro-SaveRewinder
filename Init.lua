--- Fast Save Loader - Init.lua
--
-- Main entry point. Bootstraps the mod by loading sub-modules
-- and setting up the global LOADER namespace.

if not LOADER then LOADER = {} end

-- 1. Load Core Modules
local StateSignature = require("StateSignature")
local BackupManager = require("BackupManager")

-- 2. Export API to LOADER namespace (for UI and Hooks)
LOADER.PATHS = BackupManager.PATHS

-- State & Logic
LOADER.mark_loaded_state = BackupManager.mark_loaded_state
LOADER.consume_skip_on_save = BackupManager.consume_skip_on_save
LOADER.describe_backup = BackupManager.describe_backup

-- StateSignature helpers
LOADER.describe_state_label = StateSignature.describe_state_label
LOADER.StateSignature = StateSignature -- Expose StateSignature module itself for GamePatches to pass to SaveManager

-- File/Backup Management
LOADER.get_backup_dir = BackupManager.get_backup_dir
LOADER.get_backup_files = BackupManager.get_backup_files
LOADER.get_backup_meta = BackupManager.get_backup_meta
LOADER.load_backup = BackupManager.load_backup_file
LOADER.load_and_start_from_file = BackupManager.load_and_start_from_file
LOADER.revert_to_previous_backup = BackupManager.revert_to_previous_backup
LOADER.load_backup_at_index = BackupManager.load_backup_at_index

-- Internal State Exposure (for hooks)
LOADER.pending_future_prune = BackupManager.pending_future_prune
LOADER.current_index = BackupManager.current_index
LOADER.pending_index = BackupManager.pending_index
LOADER.skipping_pack_open = BackupManager.skipping_pack_open
LOADER.restore_skip_count = BackupManager.restore_skip_count

-- Debug Logging (Init.lua owns the debug output mechanism)
LOADER._debug_alert = nil
LOADER._debug_prefix = "[FastSL]"
LOADER.debug_log = function(tag, msg)
   local always_log = (tag == "step" or tag == "list")
   if not always_log then
      if not LOADER or not LOADER.config or not LOADER.config.debug_backups then return end
   end

   local prefix = LOADER._debug_prefix or "[FastSL]"
   if tag and tag ~= "" then
      print(prefix .. "[" .. tostring(tag) .. "] " .. tostring(msg))
   else
      print(prefix .. " " .. tostring(msg))
   end
end

-- Inject debug logger back into BackupManager (circular dep fix)
BackupManager.debug_log = LOADER.debug_log

-- UI Helper (Alert Box) - Remains in Init.lua for now.
function LOADER.show_backup_debug(ante, round, label)
   if not G or not G.ROOM_ATTACH or not UIBox or not G.UIT then return end
   label = label or ""
   local text = string.format("Backup: Ante %d  Round %d%s", ante or 0, round or 0,
      (label ~= "" and ("  (" .. label .. ")")) or "")
   LOADER.debug_log("backup", text)

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
      args.cycle_config.ref_table[args.cycle_config.ref_value] = args.to_key
   end
end