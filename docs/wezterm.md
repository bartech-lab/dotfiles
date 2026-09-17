# WezTerm

WezTerm runs alongside Ghostty. Its configuration is linked from
`config/wezterm/wezterm.lua` to `~/.wezterm.lua` on Linux and macOS.
The package lists include WezTerm for Arch and Homebrew.

## Connection quick reference

Run the command on the machine you are using:

| Connection | Command |
| --- | --- |
| Mac to Linux | `wezterm connect SSHMUX:linux` |
| Linux to Mac | `wezterm connect SSHMUX:mac` |
| Reconnect to local terminals | `wezterm connect unix` |

Both machines need compatible WezTerm versions and working SSH aliases. See [Remote access](#remote-access) for prerequisites.
Close the window normally to leave terminals running on the multiplexer server.
Run the same connection command to return to them.

## Appearance

The configuration matches Ghostty's Pro palette, custom blue slots, MesloLGS NF
at 11 points, 10px padding, cyan bar cursor, and selection colors. Backgrounds
are opaque on both platforms. Mouse selection copies to the clipboard.
Each GUI window maximizes once; later configuration reloads preserve manual resizing.
Font rasterization differs between terminals; Ghostty's font thickening and
synthetic-font controls are not reproduced exactly. macOS uses WebGpu, which can
use Metal. Linux uses OpenGL. Install MesloLGS NF before comparing appearance.
macOS uses a 120 fps cap for the built-in 120 Hz display; native Linux Wayland
does not use `max_fps`. The Linux opacity and Mac frame cap were retained after
subjective comparison; macOS also uses an opaque background by preference.
GPU or power savings from opacity are unmeasured. These changes do not resolve
the Linux GUI freeze.

On macOS, interactive WezTerm shells clear inherited `NO_COLOR` to keep application colors enabled.
Existing processes retain their environment. At an existing shell prompt, run
`unset NO_COLOR`, then restart the affected application. You can still set
`NO_COLOR=1` explicitly when launching an individual command.

## Start and finish work

### Shell features

Ghostty and WezTerm use the same zsh configuration, Powerlevel10k prompt,
Tab completion, history suggestions, syntax highlighting, aliases, and functions.
These features come from zsh, not the terminal application.
The shared loader initializes completion after loading completion plugins.
Open a new tab, or run `source ~/.zshrc` at a shell prompt, after updating shell configuration.
Existing persistent shells retain their loaded configuration until you reload it.
History suggestions use that shell's history; a remote Linux shell uses Linux history.

### Terminal controls

Open WezTerm from the application menu or run `wezterm`. Both startup paths use
the persistent local server. Enter a project directory and run `claude`, `codex`,
or another ordinary terminal program. No agent wrapper or hook is required.

| Action | Linux | macOS |
| --- | --- | --- |
| New tab | Ctrl+Shift+T | Cmd+T |
| Close tab | Ctrl+Shift+W | Cmd+W |
| New input line in compatible editors | Shift+Enter | Shift+Enter |
| Move to line start/end | Ctrl+Shift+Left / Ctrl+Shift+Right | Cmd+Left / Cmd+Right |
| Delete previous word | Alt+Backspace or Ctrl+Backspace | Option+Backspace or Control+Backspace |
| Delete backward to line start | Shell default | Cmd+Backspace |
| Previous/next tab | Ctrl+PageUp / Ctrl+PageDown | Cmd+Shift+[ / Cmd+Shift+] |
| Leave running | Close the window | Close the window |

Tabs and windows close without confirmation. Closing a tab terminates its panes and normally their child processes.
On macOS, Cmd+Backspace sends Ctrl+U, matching Ghostty.
Line navigation sends Ctrl+A for line start and Ctrl+E for line end.
The shell or editor determines their behavior; applications can assign different actions to these control characters.
On both platforms, Alt/Option+Backspace sends Escape+DEL; Ctrl/Control+Backspace sends Ctrl+W.
The shell or editor determines word boundaries and the exact Ctrl+U deletion range.
Shift+Enter sends the distinct `CSI 13;2u` key sequence for multiline input.
The application must support this sequence; it is not a universal editor command.
Saved native conversations remain on disk. Independently detached processes can
remain running. Closing the window disconnects from the unix or SSHMUX server and preserves its terminals.
This requires server-backed terminals, as configured here; standalone terminals do not have this protection.
Run `wezterm` to reconnect locally. The Linux application launcher uses `wezterm connect unix` to reconnect without
creating another window. Explicit `wezterm start` creates a new terminal, so use
`wezterm` or the application launcher for normal reattachment.

The server and retained terminal buffers consume memory while disconnected.
Closing finished tabs releases their process resources. Persistence does not
preserve live processes through reboot or server termination.

## Remote access

### Shared window sizes

Two GUI clients attached to the same mux tab share its terminal size.
Resizing one client changes the shared terminal dimensions and can disrupt the other view.
WezTerm has no documented independent-size setting for mirrored mux panes.
Close the other GUI window before working on the same session from this machine.
Window closure preserves the server-backed terminals. Closing a tab terminates it.
Separate SSH sessions avoid shared sizing but do not show the same running programs.
See [WezTerm issue #917](https://github.com/wezterm/wezterm/issues/917).

### Connection requirements

Install compatible WezTerm versions on both machines. Start local persistent
terminals before testing access from the peer. Use the commands in the [connection quick reference](#connection-quick-reference).

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

- [Window close detaches multiplexer domains (stable source)](https://github.com/wezterm/wezterm/blob/20240203-110809-5046fc22/mux/src/lib.rs)
- https://wezterm.org/multiplexing.html
- https://wezterm.org/config/lua/config/default_domain.html
- https://wezterm.org/config/lua/config/front_end.html
