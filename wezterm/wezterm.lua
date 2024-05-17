-- Pull in the wezterm API
local wezterm = require("wezterm")

-- This will hold the configuration.
local c = wezterm.config_builder()

-- c.front_end = "WebGpu"
c.font = wezterm.font("Berkeley Mono")
-- c.font = wezterm.font("MesloLGM Nerd Font")
-- c.font = wezterm.font("Iosevka", { stretch = "Expanded", weight = "Regular" })
-- c.font = wezterm.font("JetBrainsMono Nerd Font")
-- c.font = wezterm.font("Fira Code")
-- c.font = wezterm.font("Iosevka Term", { weight = "Regular" })
c.font_size = 13
c.line_height = 1.25
-- c.color_scheme_dirs = { "~/.config/wezterm/colors" }
-- c.color_scheme = "Bamboo Light"
-- c.color_scheme = "Kanagawa (Gogh)"
-- c.color_scheme = "Bamboo"
-- c.color_scheme = "Oxocarbon Dark (Gogh)"
-- c.color_scheme = "Gruvbox dark, hard (base16)"
-- c.color_scheme = "GruvboxDarkHard"
c.color_scheme = "OneHalfDark"
-- -- c.color_scheme = "Solarized Dark Higher Contrast (Gogh)"
-- c.color_scheme = "Tokyo Night"

-- c.color_scheme = "OLEDppuccin"

c.window_decorations = "INTEGRATED_BUTTONS|RESIZE"
c.win32_system_backdrop = "Acrylic"
-- c.window_decorations = "RESIZE|INTEGRATED_BUTTONS"
c.adjust_window_size_when_changing_font_size = false
c.audible_bell = "Disabled"
c.inactive_pane_hsb = { brightness = 0.90 }

return c
