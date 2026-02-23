return {
	save_on_blind = true,
	save_on_selecting_hand = true,
	save_on_round_end = true,
	save_on_shop = true,
	debug_saves = false,
	keep_antes = 3,  -- Index: 1=1, 2=2, 3=4, 4=6, 5=8, 6=16, 7=All
	max_saves_per_type_per_round = 2,  -- Index: 1=8, 2=16, 3=64, 4=128, 5=All
	show_blind_image = true,  -- Show blind image instead of round number in save list
	animate_blind_image = true,  -- Enable animation and hover effects for blind images
	clamp_infinity_scores = false,  -- Convert infinity scores to max safe value (1.8e308) to prevent crashes
	export_dir = nil,           -- nil → computed default (<save_root>/SW-Exports/<profile>)
	export_full_seed_non_seeded = false, -- non-seeded runs: false=first4…last4, true=full (seeded runs always full)
	export_seed_mode = 1,       -- legacy compatibility: 1 = first4…last4, 2 = full
	export_include_meta = false, -- also copy .meta sidecar alongside .jkr
	keybinds = {
		step_back = {
			keyboard = { s = true },
			controller = { gp_leftstick = true },
		},
		toggle_saves = {
			keyboard = { ctrl = true, s = true },
			controller = { gp_x = true },
		},
		quick_saveload = {
			keyboard = { l = true },
			controller = { gp_rightstick = true },
		},
	},
}
