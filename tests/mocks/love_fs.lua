-- tests/mocks/love_fs.lua
-- Configurable love.filesystem stub for unit tests.
--
-- Usage:
--   local LoveFs = require("tests/mocks/love_fs")
--   love.filesystem = LoveFs.new()
--   love.filesystem._files["1/SaveRewinder/foo.jkr"] = "data"
--   -- run test ...
--   lu.assertEquals(love.filesystem._calls[1][1], "read")

local LoveFs = {}

-- Returns a fresh mock filesystem object.
-- Fields:
--   _files   { path -> data }  — pre-populated files (readable)
--   _dirs    { path -> true }  — pre-populated directories
--   _calls   array of { method, args... }
--   remove_ok  bool (default true)  — whether remove() succeeds
--   write_ok   bool (default true)  — whether write() succeeds
function LoveFs.new()
   local fs = {
      _files    = {},
      _dirs     = {},
      _calls    = {},
      remove_ok = true,
      write_ok  = true,
   }

   function fs.getInfo(path)
      fs._calls[#fs._calls + 1] = { "getInfo", path }
      if fs._files[path] then
         return { type = "file", size = #fs._files[path] }
      end
      if fs._dirs[path] then
         return { type = "directory" }
      end
      return nil
   end

   function fs.read(path)
      fs._calls[#fs._calls + 1] = { "read", path }
      return fs._files[path]
   end

   function fs.write(path, data)
      fs._calls[#fs._calls + 1] = { "write", path, data }
      if fs.write_ok then
         fs._files[path] = data
         return true
      end
      return false, "mock write error"
   end

   function fs.remove(path)
      fs._calls[#fs._calls + 1] = { "remove", path }
      if fs.remove_ok then
         fs._files[path] = nil
         fs._dirs[path] = nil
         return true
      end
      return false
   end

   function fs.getDirectoryItems(path)
      fs._calls[#fs._calls + 1] = { "getDirectoryItems", path }
      local items = {}
      for p in pairs(fs._files) do
         local dir = p:match("^(.*)/[^/]+$")
         if dir == path then
            items[#items + 1] = p:match("[^/]+$")
         end
      end
      return items
   end

   function fs.getSaveDirectory()
      return "/mock/save"
   end

   function fs.createDirectory(path)
      fs._dirs[path] = true
      return true
   end

   return fs
end

return LoveFs
