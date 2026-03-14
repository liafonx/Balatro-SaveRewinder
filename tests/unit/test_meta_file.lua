-- tests/unit/test_meta_file.lua
-- Tests for Utils/MetaFile.lua

local lu = require("luaunit")
local MF = require("MetaFile")
local LoveFs = dofile("tests/mocks/love_fs.lua")

TestMetaFile = {}

function TestMetaFile:setUp()
   -- Install a fresh mock filesystem for each test.
   self.fs = LoveFs.new()
   love.filesystem = self.fs
end

function TestMetaFile:tearDown()
   -- Restore Layer 0 stubs.
   love.filesystem = {
      getInfo = function() return nil end,
      read    = function() return nil end,
      write   = function() return true end,
      remove  = function() return true end,
      getDirectoryItems = function() return {} end,
      getSaveDirectory  = function() return "/mock/save" end,
      createDirectory   = function() return true end,
   }
end

-- ── serialize_meta ──────────────────────────────────────────────────────────

function TestMetaFile:test_serialize_nil_returns_nil()
   lu.assertIsNil(MF.serialize_meta(nil))
end

function TestMetaFile:test_serialize_no_signature_returns_nil()
   lu.assertIsNil(MF.serialize_meta({}))
end

function TestMetaFile:test_serialize_basic_contains_signature()
   local result = MF.serialize_meta({
      signature = "1:1:S:0:0:5", display_type = "S",
      money = 5, discards_used = 0, hands_played = 0,
      blind_idx = 1, ordinal = 1,
   })
   lu.assertIsString(result)
   lu.assertStrContains(result, "signature=1:1:S:0:0:5")
end

function TestMetaFile:test_serialize_contains_all_required_fields()
   local result = MF.serialize_meta({
      signature = "1:1:S:0:0:5", display_type = "S",
      money = 10, discards_used = 1, hands_played = 2,
      blind_idx = 3, ordinal = 5,
   })
   lu.assertStrContains(result, "money=10")
   lu.assertStrContains(result, "discards_used=1")
   lu.assertStrContains(result, "hands_played=2")
   lu.assertStrContains(result, "blind_idx=3")
   lu.assertStrContains(result, "display_type=S")
   lu.assertStrContains(result, "ordinal=5")
end

function TestMetaFile:test_serialize_is_key_true_included()
   local result = MF.serialize_meta({
      signature = "sig", display_type = "S",
      money = 0, discards_used = 0, hands_played = 0,
      blind_idx = 0, ordinal = 1, is_key = true,
   })
   lu.assertStrContains(result, "is_key=1")
end

function TestMetaFile:test_serialize_is_key_false_not_included()
   local result = MF.serialize_meta({
      signature = "sig", display_type = "S",
      money = 0, discards_used = 0, hands_played = 0,
      blind_idx = 0, ordinal = 1, is_key = false,
   })
   lu.assertNotStrContains(result, "is_key")
end

function TestMetaFile:test_serialize_custom_state_name_included()
   local result = MF.serialize_meta({
      signature = "sig", display_type = "S",
      money = 0, discards_used = 0, hands_played = 0,
      blind_idx = 0, ordinal = 1,
      custom_state_name = "My Lucky Save",
   })
   lu.assertStrContains(result, "custom_state_name=My Lucky Save")
end

function TestMetaFile:test_serialize_custom_state_name_strips_newlines()
   local result = MF.serialize_meta({
      signature = "sig", display_type = "S",
      money = 0, discards_used = 0, hands_played = 0,
      blind_idx = 0, ordinal = 1,
      custom_state_name = "bad\nnewline",
   })
   lu.assertNotStrContains(result, "\n\n")
   lu.assertStrContains(result, "custom_state_name=bad newline")
end

-- ── read_meta_file ──────────────────────────────────────────────────────────

function TestMetaFile:test_read_meta_file_not_found_returns_nil()
   lu.assertIsNil(MF.read_meta_file("nonexistent.meta"))
end

function TestMetaFile:test_read_meta_file_valid_data()
   local data = "money=10\nsignature=1:2:S:0:0:10\ndiscards_used=0\nhands_played=0\nblind_idx=1\ndisplay_type=S\nordinal=3"
   self.fs._files["test.meta"] = data
   local meta = MF.read_meta_file("test.meta")
   lu.assertIsTable(meta)
   lu.assertEquals(meta.money, 10)
   lu.assertEquals(meta.signature, "1:2:S:0:0:10")
   lu.assertEquals(meta.ordinal, 3)
   lu.assertEquals(meta.display_type, "S")
end

function TestMetaFile:test_read_meta_file_no_signature_returns_nil()
   local data = "money=10\ndisplay_type=S\nblind_idx=1"
   self.fs._files["bad.meta"] = data
   lu.assertIsNil(MF.read_meta_file("bad.meta"))
end

function TestMetaFile:test_read_meta_file_is_key_parsed_as_boolean()
   local data = "signature=s\ndisplay_type=S\nis_key=1\nmoney=0\ndiscards_used=0\nhands_played=0\nblind_idx=0\nordinal=1"
   self.fs._files["key.meta"] = data
   local meta = MF.read_meta_file("key.meta")
   lu.assertIsTable(meta)
   lu.assertTrue(meta.is_key)
end

-- ── round-trip ───────────────────────────────────────────────────────────────

function TestMetaFile:test_serialize_then_read_round_trips_correctly()
   local original = {
      signature = "3:2:P:1:4:50",
      display_type = "P",
      money = 50,
      discards_used = 1,
      hands_played = 4,
      blind_idx = 7,
      ordinal = 12,
      is_key = true,
   }
   local content = MF.serialize_meta(original)
   self.fs._files["rt.meta"] = content
   local parsed = MF.read_meta_file("rt.meta")
   lu.assertEquals(parsed.signature,     original.signature)
   lu.assertEquals(parsed.display_type,  original.display_type)
   lu.assertEquals(parsed.money,         original.money)
   lu.assertEquals(parsed.discards_used, original.discards_used)
   lu.assertEquals(parsed.hands_played,  original.hands_played)
   lu.assertEquals(parsed.blind_idx,     original.blind_idx)
   lu.assertEquals(parsed.ordinal,       original.ordinal)
   lu.assertEquals(parsed.is_key,        original.is_key)
end
