#!/usr/bin/env lua
-- tests/run_tests.lua
-- Entry point for the Save Rewinder unit test suite.
-- Usage:  lua tests/run_tests.lua
-- From project root only; paths are relative to CWD.

-- Luaunit lives in tests/lib/
package.path = "tests/lib/?.lua;" .. package.path

-- Bootstrap globals and module preloads before any require.
dofile("tests/test_env.lua")

local lu = require("luaunit")

-- Load test files (each declares a global TestXxx table).
dofile("tests/unit/test_entry_schema.lua")
dofile("tests/unit/test_runtime_state.lua")
dofile("tests/unit/test_state_signature.lua")
dofile("tests/unit/test_nan_protection.lua")
dofile("tests/unit/test_blind_recovery.lua")
dofile("tests/unit/test_meta_file.lua")
dofile("tests/unit/test_pruning.lua")
dofile("tests/unit/test_config.lua")
dofile("tests/unit/test_export_service.lua")
dofile("tests/unit/test_queue_service.lua")

-- Pass suite names explicitly (auto-discovery via pairs(_G) is unreliable on
-- Lua 5.5 where the global environment is not a plain table).
os.exit(lu.LuaUnit.run(
   "TestEntrySchema",
   "TestRuntimeState",
   "TestStateSignature",
   "TestNaNProtection",
   "TestBlindRecovery",
   "TestMetaFile",
   "TestPruning",
   "TestConfig",
   "TestExportService",
   "TestQueueService"
))
