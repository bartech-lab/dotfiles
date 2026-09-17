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
config.window_close_confirmation = 'NeverPrompt'

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

-- The Mac's non-interactive SSH PATH is /usr/bin:/bin:/usr/sbin:/sbin, so the
-- implicit SSHMUX:mac domain cannot find `wezterm`.  Name the app bundle path
-- explicitly and connect with `wezterm connect mac`.
if not wezterm.target_triple:find('darwin') then
  config.ssh_domains = {
    {
      name = 'mac',
      remote_address = 'mac',
      multiplexing = 'WezTerm',
      remote_wezterm_path = '/Applications/WezTerm.app/Contents/MacOS/wezterm',
    },
  }
end

-- Use Metal through WebGpu on macOS.  OpenGL remains the conservative Linux
-- default for the current desktop driver stack.
if wezterm.target_triple:find('darwin') then
  config.front_end = 'WebGpu'
  -- Match the built-in display's 120 Hz cap.
  config.max_fps = 120
else
  config.front_end = 'OpenGL'
  -- Keep the opaque background preferred in the performance trial.
  config.window_background_opacity = 1.0
end

-- Keep routine tab navigation on direct, familiar shortcuts.  The explicit
-- disconnect action preserves the mux server and all agent processes.
local tab_mod = wezterm.target_triple:find('darwin') and 'SUPER' or 'CTRL|SHIFT'
config.keys = {
  { key = 'LeftArrow', mods = tab_mod, action = act.SendString '\x01' },
  { key = 'RightArrow', mods = tab_mod, action = act.SendString '\x05' },
  { key = 't', mods = tab_mod, action = act.SpawnTab 'CurrentPaneDomain' },
  { key = 'w', mods = 'CTRL|SHIFT', action = act.CloseCurrentTab { confirm = false } },
  { key = 'w', mods = 'SUPER', action = act.CloseCurrentTab { confirm = false } },
  { key = 'Enter', mods = 'SHIFT', action = act.SendString '\x1b[13;2u' },
  { key = '[', mods = 'SUPER|SHIFT', action = act.ActivateTabRelative(-1) },
  { key = ']', mods = 'SUPER|SHIFT', action = act.ActivateTabRelative(1) },
  { key = 'PageUp', mods = 'CTRL', action = act.ActivateTabRelative(-1) },
  { key = 'PageDown', mods = 'CTRL', action = act.ActivateTabRelative(1) },
  { key = 'D', mods = 'CTRL|SHIFT', action = act.DetachDomain 'CurrentPaneDomain' },
}

-- Send conventional word deletion sequences on both platforms.
table.insert(config.keys, { key = 'Backspace', mods = 'ALT', action = act.SendString '\x1b\x7f' })
table.insert(config.keys, { key = 'Backspace', mods = 'CTRL', action = act.SendString '\x17' })

-- Match Ghostty's macOS line deletion shortcut.
if wezterm.target_triple:find('darwin') then
  table.insert(config.keys, { key = 'Backspace', mods = 'SUPER', action = act.SendString '\x15' })
end

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

-- Maximize each GUI window once, including windows created after attachment.
-- GLOBAL survives config reloads, so later reloads preserve manual resizing.
local function maximize_once(window)
  local key = 'initial-maximize-' .. window:window_id()
  if not wezterm.GLOBAL[key] then
    window:maximize()
    wezterm.GLOBAL[key] = true
  end
end

wezterm.on('window-config-reloaded', maximize_once)
wezterm.on('gui-attached', function()
  for _, window in ipairs(wezterm.mux.all_windows()) do
    local gui = window:gui_window()
    if gui then
      maximize_once(gui)
    end
  end
end)

return config
