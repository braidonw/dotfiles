-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local config = wezterm.config_builder()

config.font = wezterm.font("Iosevka Term", { stretch = "Expanded", weight = "Medium" })
config.font_size = 14
config.color_scheme_dirs = { "~/.config/wezterm/colors" }
config.color_scheme = "Bamboo"

config.tab_bar_at_bottom = false

return config
