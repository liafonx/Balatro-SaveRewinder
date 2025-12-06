--- Fast Save Loader - UI/ButtonCallbacks.lua
--
-- Button callbacks for the backups UI.

if not LOADER then LOADER = {} end

function G.FUNCS.loader_backup_open(e)
   if not G.FUNCS or not G.FUNCS.overlay_menu then return end
   G.FUNCS.overlay_menu({
      definition = G.UIDEF.fast_loader_backups(),
   })
   LOADER.backups_open = true
end

function G.FUNCS.loader_backup_reload(e)
   if not G.FUNCS or not G.FUNCS.exit_overlay_menu or not G.FUNCS.overlay_menu then return end
   G.FUNCS.exit_overlay_menu()
   G.FUNCS.overlay_menu({
      definition = G.UIDEF.fast_loader_backups(),
   })
   LOADER.backups_open = true
end

function G.FUNCS.loader_backup_delete_all(e)
   local dir = LOADER.get_backup_dir()
   if love.filesystem.getInfo(dir) then
      for _, file in ipairs(love.filesystem.getDirectoryItems(dir)) do
         love.filesystem.remove(dir .. "/" .. file)
      end
   end
   G.FUNCS.loader_backup_reload(e)
end

function G.FUNCS.loader_backup_restore(e)
   if not e or not e.config or not e.config.ref_table then return end
   local file = e.config.ref_table.file
   if not file then return end

   -- Make long-press stepping line up with restores done via the UI.
   if LOADER and LOADER.get_backup_files then
      local entries = LOADER.get_backup_files()
      for i, entry in ipairs(entries) do
         if entry.file == file then
            LOADER.pending_index = i
            break
         end
      end
   end

   if LOADER and LOADER.debug_log then
      local label = file
      if LOADER.describe_backup then
        label = LOADER.describe_backup({ file = file })
      end
      LOADER.debug_log("restore", "UI click -> loading " .. label)
   end
   LOADER.load_and_start_from_file(file)
end

function G.FUNCS.loader_backup_update_page(args)
   if not args or not args.cycle_config then return end
   local callback_args = args.cycle_config.opt_args

   local backups_object = callback_args.ui
   local backups_wrap = backups_object.parent

   backups_wrap.config.object:remove()
   backups_wrap.config.object = UIBox({
      definition = LOADER.get_backups_page({
         entries = callback_args.entries,
         per_page = callback_args.per_page,
         page_num = args.to_key,
      }),
      config = { parent = backups_wrap, type = "cm" },
   })
   backups_wrap.UIBox:recalculate()
end
