-- Pull in the wezterm API
local wezterm = require("wezterm")
local config = wezterm.config_builder()

config.keys = require("keys")

config.default_prog = { "fish", "-l" }

-- Kitty graphics protocol, so terminal programs can draw images inline
config.enable_kitty_graphics = true

-- Colors follow Noctalia, which renders colors/Noctalia.toml from its palette
-- and rewrites it when the wallpaper or theme changes (modules/home/noctalia.nix).
-- Watching the file reloads this config, so open windows recolor too. Until
-- Noctalia has written it once, WezTerm keeps its default colors and tab bar.
local noctalia_scheme = wezterm.config_dir .. "/colors/Noctalia.toml"
wezterm.add_to_config_reload_watch_list(noctalia_scheme)
local has_scheme, color_scheme = pcall(wezterm.color.load_scheme, noctalia_scheme)
if has_scheme then
	config.color_schemes = { Noctalia = color_scheme }
	config.color_scheme = "Noctalia"
end
config.window_background_opacity = 0.95
local accent = has_scheme and color_scheme.tab_bar.active_tab.bg_color -- Noctalia primary

-- Plain Maple Mono has no Nerd Font icons or CJK. NF CN has both, so they stay
-- Maple instead of falling through to WezTerm's built-ins and Unifont.
config.font = wezterm.font_with_fallback({ "Maple Mono", "Maple Mono NF CN" })
config.font_size = 14

config.use_fancy_tab_bar = false
config.tab_bar_at_bottom = true
config.tab_max_width = 48

-- This function returns the suggested title for a tab.
-- It prefers the title that was set via `tab:set_title()`
-- or `wezterm cli set-tab-title`, but falls back to the
-- title of the active pane in that tab.
local function tab_title(tab_info)
	local title = tab_info.tab_title
	if not title or #title == 0 then
		title = tab_info.active_pane.title
	end
	if not title:find(" ") then
		title = " " .. title
	elseif title:find(".+@.+:%s.+") then
		title = "󰣀 " .. title
	elseif title:find("^sudo ") then
		title = "󰦝 " .. title
	elseif title:find("^ Gemini") then
		title = title:gsub("^ Gemini", " ")
	elseif title:find("^nv ") or title:find("^nvim ") then
		title = title:gsub("^nv ", " "):gsub("^nvim ", " ")
	elseif title:find("^vim ") then
		title = title:gsub("^vim ", " ")
	elseif title:find("^cargo ") then
		title = title:gsub("^cargo ", " ")
	elseif title:find("^yay ") or title:find("^pacman ") or title:find("^paru ") then
		title = title:gsub("^yay ", " "):gsub("^pacman ", " "):gsub("^paru ", " ")
	elseif title:find("^nix") or title:find("^nh ") then
		title = title:gsub("^nix", "󱄅 "):gsub("^nh", "󱄅 ")
	elseif title:find("^Yazi:") then
		title = title:gsub("^Yazi:", " ")
	elseif title:find("^deno ") then
		title = title:gsub("^deno ", "🦖 ")
	elseif title:find("^node ") then
		title = title:gsub("^node ", " ")
	elseif title:find("^bundle ") or title:find("^irb ") then
		title = title:gsub("^bundle ", " "):gsub("^irb ", " ")
	end
	return title
end

wezterm.on("format-tab-title", function(tab, _, _, _, hover, max_width)
	if not has_scheme then
		return
	end
	local edge_background = color_scheme.tab_bar.background
	local edge_foreground = color_scheme.tab_bar.new_tab.bg_color
	local text_background = color_scheme.tab_bar.new_tab.bg_color
	local text_foreground = color_scheme.tab_bar.new_tab_hover.fg_color
	local left_edge = ""
	local right_edge = ""
	local italic = false

	if tab.is_active then
		edge_foreground = accent
		text_background = accent
		text_foreground = color_scheme.tab_bar.active_tab.fg_color
		italic = true
	elseif hover then
		edge_foreground = color_scheme.tab_bar.new_tab_hover.bg_color
		text_background = color_scheme.tab_bar.new_tab_hover.bg_color
	end

	local title = tab_title(tab)
	title = tab.tab_index + 1 .. " " .. wezterm.truncate_right(title, max_width - 6)

	return {
		{ Background = { Color = edge_background } },
		{ Foreground = { Color = edge_foreground } },
		{ Text = left_edge },
		{ Background = { Color = text_background } },
		{ Foreground = { Color = text_foreground } },
		{ Attribute = { Italic = italic } },
		{ Text = title },
		{ Background = { Color = edge_background } },
		{ Foreground = { Color = edge_foreground } },
		{ Text = right_edge },
	}
end)

wezterm.on("update-right-status", function(window, pane)
	if not has_scheme then
		return
	end
	-- nil until the pane's shell reports a directory (OSC 7)
	local cwd_url = pane:get_current_working_dir()
	if not cwd_url then
		window:set_right_status("")
		return
	end
	local cwd = cwd_url.file_path
	local cells = {
		{ Background = { Color = color_scheme.tab_bar.background } },
		{ Foreground = { Color = accent } },
		{ Text = "" },
		{ Background = { Color = accent } },
		{ Foreground = { Color = color_scheme.tab_bar.background } },
		{ Text = "  " .. cwd .. " " },
	}
	window:set_right_status(wezterm.format(cells))
end)

return config
