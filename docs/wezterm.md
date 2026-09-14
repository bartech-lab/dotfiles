# WezTerm

WezTerm runs alongside Ghostty. Its configuration is linked from
`config/wezterm/wezterm.lua` to `~/.wezterm.lua` on Linux and macOS.
The package lists include WezTerm for Arch and Homebrew.

## Appearance

The configuration matches Ghostty's Pro palette, custom blue slots, MesloLGS NF
at 11 points, 10px padding, 97% background opacity, cyan bar cursor, and selection
colors. Mouse selection copies to the clipboard. Attached windows maximize.
Font rasterization differs between terminals; Ghostty's font thickening and
synthetic-font controls are not reproduced exactly. macOS uses WebGpu, which can
use Metal. Linux uses OpenGL. Install MesloLGS NF before comparing appearance.

## Start and finish work

Open WezTerm from the application menu or run `wezterm`. Both startup paths use
the persistent local server. Enter a project directory and run `claude`, `codex`,
or another ordinary terminal program. No agent wrapper or hook is required.

| Action | Linux | macOS |
| --- | --- | --- |
| New tab | Ctrl+Shift+T | Cmd+T |
| Close tab | Ctrl+Shift+W | Cmd+W |
| Previous/next tab | Ctrl+PageUp / Ctrl+PageDown | Cmd+Shift+[ / Cmd+Shift+] |
| Leave running | Ctrl+Shift+D | Ctrl+Shift+D |

Closing a tab terminates its panes and normally their child processes.
Saved native conversations remain on disk. Independently detached processes can
remain running. Use the explicit disconnect shortcut when work must continue.
Do not assume the window close button is equivalent to disconnect.
Run `wezterm` to reconnect locally. Opening a new application window through
`wezterm start` can create another tab; it still belongs to the persistent server.

The server and retained terminal buffers consume memory while disconnected.
Closing finished tabs releases their process resources. Persistence does not
preserve live processes through reboot or server termination.

## Remote access

Install compatible WezTerm versions on both machines. Start local persistent
terminals before testing access from the peer. Use the existing SSH aliases:

```sh
# From Linux, for terminals running on the Mac:
wezterm connect SSHMUX:mac

# From macOS, for terminals running on Linux:
wezterm connect SSHMUX:linux
```

These commands can start the remote multiplexer. They are human-operated under
the existing local-only agent policy. Remote setup and configuration changes
must be performed by the agent running locally on that machine.

SSH uses the existing Tailscale route. No additional VPN, relay account, or
public listener is required. Validate authentication and host-key handling with
your specific SSH configuration before relying on remote use. A working plain
SSH read is not proof of a working WezTerm remote connection.

Check the host and project directory before giving an agent work. Remote tabs
remain on their original host. An existing agent in an ordinary Ghostty tab is
not adopted automatically. Resume its saved conversation in WezTerm after
exiting the original process, if needed.

## Validation

`wezterm show-keys` validates configuration loading. `wezterm cli --prefer-mux
--no-auto-start list` inspects the local background server without starting one.
Use a disposable terminal for disconnect and close tests. Never kill another
session's pane to test cleanup.

Ordinary agents retain their native transcript locations when their environment
is unchanged. Validate the local logbook exporter against a new conversation
before treating end-to-end export as confirmed.

Official references:

- https://wezterm.org/multiplexing.html
- https://wezterm.org/config/lua/config/default_domain.html
- https://wezterm.org/config/lua/config/front_end.html
