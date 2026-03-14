#!/usr/bin/env lua
-- scripts/validate_module_map.lua
-- CI check: verifies that every [patches.module] entry in lovely.toml is
-- covered by MODULE_MAP or EXCLUDED_MODULES, and vice versa.
--
-- Exit 0 → all checks pass
-- Exit 1 → drift detected (prints which names are missing where)

-- ── MODULE_MAP ───────────────────────────────────────────────────────────────
-- Must match tests/test_env.lua MODULE_MAP exactly.
local MODULE_MAP = {
   Logger                      = "Utils/Logger.lua",
   MetaFile                    = "Utils/MetaFile.lua",
   FileIO                      = "Utils/FileIO.lua",
   Pruning                     = "Utils/Pruning.lua",
   StateSignature              = "Utils/StateSignature.lua",
   NaNProtection               = "Utils/NaNProtection.lua",
   BlindRecovery               = "Utils/BlindRecovery.lua",
   SaveManagerEntrySchema      = "Core/SaveModules/EntrySchema.lua",
   SaveManagerRuntimeState     = "Core/SaveModules/RuntimeState.lua",
   SaveManagerQueueService     = "Core/SaveModules/QueueService.lua",
   SaveManager                 = "Core/SaveManager.lua",
   KeySaves                    = "Core/KeySaves.lua",
   SerializationGuard          = "Core/SerializationGuard.lua",
   ExportService               = "Core/ExportService.lua",
   SaveManagerIndexStore       = "Core/SaveModules/IndexStore.lua",
   SaveManagerMetaCache        = "Core/SaveModules/MetaCache.lua",
   SaveManagerOrdinalTracker   = "Core/SaveModules/OrdinalTracker.lua",
   SaveManagerRetentionService = "Core/SaveModules/RetentionService.lua",
   SaveManagerSkipService      = "Core/SaveModules/SkipService.lua",
   SaveManagerLoadService      = "Core/SaveModules/LoadService.lua",
   SaveManagerCreateService    = "Core/SaveModules/CreateService.lua",
}

-- Modules present in lovely.toml but intentionally not in the test harness
-- (game-coupled: threads, UI rendering, controller navigation).
local EXCLUDED_MODULES = {
   SaveThread           = true,
   ControllerNavigation = true,
   ScaleNumberHook      = true,
   SaveListSync         = true,
   UIShared             = true,
   UILayout             = true,
   UIIconFactory        = true,
   UISaveRows           = true,
   UIOverlayBuilder     = true,
   UIButtonCallbackHelpers = true,
}

-- ── TOML parser ──────────────────────────────────────────────────────────────
-- State-machine line scanner.  Handles:
--   [[patches]] section boundaries
--   [patches.module] section markers
--   name = "..." and source = "..." within module sections
--   """...""" multi-line payload blocks (skipped entirely)

local function parse_lovely_toml(path)
   local fh = assert(io.open(path, "r"), "Cannot open " .. path)
   local modules = {}   -- name -> source

   local in_module_patch = false
   local current_name    = nil
   local current_source  = nil
   local in_multiline    = false

   for line in fh:lines() do
      -- Count triple-quote occurrences to track multi-line block entry/exit.
      local tq_count = 0
      for _ in line:gmatch('"""') do tq_count = tq_count + 1 end

      if in_multiline then
         if tq_count % 2 == 1 then
            in_multiline = false
         end
         -- Skip all content inside multi-line blocks.
      else
         if tq_count % 2 == 1 then
            in_multiline = true
            -- The opening line may also contain section markers before the """;
            -- fall through so section detection still runs on this line.
         end

         if line:match("^%[%[patches%]%]") then
            -- Finalize the previous patch block.
            if in_module_patch and current_name and current_source then
               modules[current_name] = current_source
            end
            in_module_patch = false
            current_name    = nil
            current_source  = nil
         elseif line:match("^%[patches%.module%]") then
            in_module_patch = true
         elseif in_module_patch then
            local n = line:match('^name%s*=%s*"([^"]+)"')
            if n then current_name = n end
            local s = line:match('^source%s*=%s*"([^"]+)"')
            if s then current_source = s end
         end
      end
   end

   -- Finalize the last patch block.
   if in_module_patch and current_name and current_source then
      modules[current_name] = current_source
   end

   fh:close()
   return modules
end

-- ── Main validation ──────────────────────────────────────────────────────────

local function sorted_keys(t)
   local keys = {}
   for k in pairs(t) do keys[#keys + 1] = k end
   table.sort(keys)
   return keys
end

local toml_path = "lovely.toml"
local toml_modules = parse_lovely_toml(toml_path)

local errors = {}

-- Check 1: every MODULE_MAP entry must exist in lovely.toml.
for name in pairs(MODULE_MAP) do
   if not toml_modules[name] then
      errors[#errors + 1] = "MODULE_MAP has '" .. name .. "' but not found in lovely.toml"
   end
end

-- Check 2: every lovely.toml module must be in MODULE_MAP or EXCLUDED_MODULES.
for name in pairs(toml_modules) do
   if not MODULE_MAP[name] and not EXCLUDED_MODULES[name] then
      errors[#errors + 1] = "lovely.toml module '" .. name
         .. "' is not in MODULE_MAP or EXCLUDED_MODULES — add it to tests/test_env.lua"
   end
end

if #errors == 0 then
   print("validate_module_map: OK (" .. #sorted_keys(toml_modules) .. " modules checked)")
   os.exit(0)
else
   for _, e in ipairs(errors) do
      io.stderr:write("ERROR: " .. e .. "\n")
   end
   os.exit(1)
end
