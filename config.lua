return {
	save_on_blind = true,
	save_on_selecting_hand = true,
	save_on_round_end = true,
	save_on_shop = true,
	debug_saves = false,
	keep_antes = 3,  -- Index: 1=1, 2=2, 3=4, 4=6, 5=8, 6=16, 7=All
	show_blind_image = true,  -- Show blind image instead of round number in save list
	animate_blind_image = true,  -- Enable animation and hover effects for blind images
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
