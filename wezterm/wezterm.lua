-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local config = wezterm.config_builder()

config.font = wezterm.font("Iosevka Term", { stretch = "Expanded", weight = "Medium" })
config.font_size = 15
config.color_scheme = "Gruvbox dark, hard (base16)"

return config
