# gaming-mode

Linux only. Frees the GPU, RAM and disk for a game, then restores what it stopped.

## Use

Press **Meta+Shift+G**, or type `gaming`. Press or type it again after the game.

| Command | Effect |
|---|---|
| `gaming` | toggle |
| `gaming on` / `gaming off` | explicit |
| `gaming status` | what is stopped, since when, VRAM free |
| `gaming run -- %command%` | Steam launch option: on before the game, off after it exits |

## What `on` stops

Only units that are running are recorded in `$XDG_RUNTIME_DIR/gaming/state`, and `off`
starts only those, in reverse order. A reboot clears the state; the units autostart anyway.

- `bonsai-cc-proxy.service`, `bonsai.service` (llama-server: about 12 GB VRAM, 20 GB RAM).
  Clients of `bonsai.sh` fall back to OpenRouter while it is down.
- `docker.socket`, `docker.service`, through `sudo -n`. Without a passwordless rule they are
  reported as not stopped; `sudoers.example` holds a narrow rule.
- `system-update.timer`, `toolsmith.timer`, `logbook-sync.timer`. A run already in progress is
  left alone and named in the notification.
- Desktop apps matching the globs in `~/.config/gaming/apps.conf` (monitors by default).
  These are not reopened.

`off` returns at once and notifies when Bonsai answers `/health` again (up to 6 minutes).

## Heartbeat

`on` writes `$XDG_RUNTIME_DIR/heartbeat-pause`. The heartbeat reports the listed checks as
`paused` instead of failing, and raises `pause-gaming` as stale after 12 hours, so a forgotten
`gaming off` reaches ntfy.

## Install

```bash
bash ~/dotfiles/gaming-mode/setup.sh
```

Installs `~/.local/bin/gaming`, `~/.config/gaming/apps.conf` (kept if present), the
`gaming-toggle.desktop` entry and the Meta+Shift+G shortcut.

## Tests

```bash
bash ~/dotfiles/gaming-mode/tests/test-gaming.sh
```
