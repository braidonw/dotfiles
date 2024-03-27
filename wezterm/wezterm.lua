-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local config = wezterm.config_builder()

-- config.font = wezterm.font("Iosevka Term", { stretch = "Expanded", weight = "Regular" })
-- config.font = wezterm.font("Berkeley Mono")
config.font = wezterm.font("JetBrainsMono Nerd Font")
-- config.font = wezterm.font("Fira Code", { weight = "Medium" })
config.font_size = 14
config.line_height = 1.2
config.color_scheme_dirs = { "~/.config/wezterm/colors" }
config.color_scheme = "Bamboo"
-- config.color_scheme = "Oxocarbon Dark (Gogh)"
-- config.color_scheme = "Gruvbox dark, hard (base16)"

config.tab_bar_at_bottom = false

config.window_frame = {
	font = wezterm.font({ family = "Berkeley Mono", size = 14, weight = "Regular" }),
}

return config
