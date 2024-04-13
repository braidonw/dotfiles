-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local c = wezterm.config_builder()

-- c.font = wezterm.font("Iosevka", { stretch = "Expanded", weight = "Regular" })
c.font = wezterm.font("Berkeley Mono")
-- c.font = wezterm.font("JetBrainsMono Nerd Font")
-- c.font = wezterm.font("Fira Code")
-- c.font = wezterm.font("Iosevka Term", { weight = "Regular" })
c.font_size = 14
c.line_height = 1.4
-- c.color_scheme_dirs = { "~/.config/wezterm/colors" }
-- c.color_scheme = "Bamboo Light"
-- c.color_scheme = "Kanagawa (Gogh)"
-- c.color_scheme = "Bamboo"
-- c.color_scheme = "Oxocarbon Dark (Gogh)"
-- c.color_scheme = "Gruvbox dark, hard (base16)"
c.color_scheme = "GruvboxDarkHard"
-- c.color_scheme = "Oxocarbon Dark (Gogh)"
-- -- c.color_scheme = "Solarized Dark Higher Contrast (Gogh)"
-- c.color_scheme = "Tokyo Night"

local custom = wezterm.color.get_builtin_schemes()["Catppuccin Mocha"]
custom.background = "#000000"
custom.tab_bar.background = "#040404"
custom.tab_bar.inactive_tab.bg_color = "#0f0f0f"
custom.tab_bar.new_tab.bg_color = "#080808"
c.color_schemes = {
	["OLEDppuccin"] = custom,
}
-- c.color_scheme = "OLEDppuccin"

c.tab_bar_at_bottom = true
c.use_fancy_tab_bar = false

-- c.window_decorations = "RESIZE|INTEGRATED_BUTTONS"
c.window_padding = { left = 0, right = 0, top = 10, bottom = 0 }
c.adjust_window_size_when_changing_font_size = false
c.audible_bell = "Disabled"
c.inactive_pane_hsb = { brightness = 0.90 }

return c
