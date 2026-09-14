-- WezTerm configuration for macOS and Linux.
--
-- Every GUI starts in the local unix domain.  The mux server keeps tabs and
-- panes alive when the GUI disconnects, so the same tabs can be reattached
-- locally or through an SSHMUX domain from the other machine.

local wezterm = require 'wezterm'
local act = wezterm.action

local config = wezterm.config_builder()

-- Use the same Pro palette as Ghostty.  The two blue slots are adjusted for
-- Claude Code's inline code and link rendering.
local pro = wezterm.color.get_builtin_schemes()['Pro']
pro.ansi[5] = '#7aa2f8'
pro.brights[5] = '#bb9af7'
pro.cursor_bg = '#00e5ff'
pro.cursor_fg = '#000000'
pro.selection_bg = '#1a1b26'
pro.selection_fg = '#c0caf5'

pro.background = '#000000'
pro.foreground = '#f2f2f2'

config.color_schemes = {
  ['Pro (bartech)'] = pro,
}
config.color_scheme = 'Pro (bartech)'

-- Match Ghostty's Meslo 11 appearance and 10px window padding.
config.font = wezterm.font_with_fallback { 'MesloLGS NF' }
config.font_size = 11
config.window_padding = {
  left = 10,
  right = 10,
  top = 10,
  bottom = 10,
}
config.window_background_opacity = 0.97
config.default_cursor_style = 'SteadyBar'
config.cursor_blink_rate = 0

-- Keep the tab bar visible so tabs remain easy to find with one tab or many.
config.hide_tab_bar_if_only_one_tab = false

-- The unix domain is the default for both `wezterm` and explicit `wezterm
-- start` launches.  The latter is used by desktop launchers and would bypass
-- default_gui_startup_args on its own.
config.unix_domains = {
  {
    name = 'unix',
  },
}
config.default_domain = 'unix'
config.default_gui_startup_args = { 'connect', 'unix' }

-- Use Metal through WebGpu on macOS.  OpenGL remains the conservative Linux
-- default for the current desktop driver stack.
if wezterm.target_triple:find('darwin') then
  config.front_end = 'WebGpu'
else
  config.front_end = 'OpenGL'
end

-- Keep routine tab navigation on direct, familiar shortcuts.  The explicit
-- disconnect action preserves the mux server and all agent processes.
local tab_mod = wezterm.target_triple:find('darwin') and 'SUPER' or 'CTRL|SHIFT'
config.keys = {
  { key = 't', mods = tab_mod, action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'w', mods = tab_mod, action = act.CloseCurrentTab { confirm = true } },
  { key = '[', mods = 'SUPER|SHIFT', action = act.ActivateTabRelative(-1) },
  { key = ']', mods = 'SUPER|SHIFT', action = act.ActivateTabRelative(1) },
  { key = 'PageUp', mods = 'CTRL', action = act.ActivateTabRelative(-1) },
  { key = 'PageDown', mods = 'CTRL', action = act.ActivateTabRelative(1) },
  { key = 'D', mods = 'CTRL|SHIFT', action = act.DetachDomain 'CurrentPaneDomain' },
}

-- Preserve the Ghostty setting that sends the right Option key as Alt on macOS.
config.send_composed_key_when_left_alt_is_pressed = true
config.send_composed_key_when_right_alt_is_pressed = false

-- Match Ghostty's selection copy behavior.
config.mouse_bindings = {
  {
    event = { Up = { streak = 1, button = 'Left' } },
    mods = 'NONE',
    action = act.CompleteSelection 'Clipboard',
  },
}

wezterm.on('gui-attached', function()
  for _, window in ipairs(wezterm.mux.all_windows()) do
    local ok, gui = pcall(function() return window:gui_window() end)
    if ok and gui then
      gui:maximize()
    end
  end
end)

return config
