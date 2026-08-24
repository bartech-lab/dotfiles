# ai-caffeine

Holds an OS-level keep-awake while AI agent processes (`claude`, `codex`, `omp`) are
running, and releases it when the last one exits. Prevents system sleep and
screen lock on Linux/KDE; prevents system sleep on macOS (display sleep stays
allowed). Every hold is self-expiring: if the watcher dies, normal sleep
behavior returns within ~45 seconds with no cleanup.

## Mechanisms

| OS | Hold | Blocks |
|----|------|--------|
| Linux | `systemd-inhibit --what=sleep --mode=block`, held for the whole engagement via a fifo handshake | suspend via logind (no `idle`: that would also block PowerDevil dim/blank) |
| Linux | `kscreenlockerrc` `Daemon/Autolock=false` while engaged, restored on release | screen lock only; DPMS dim/blank keeps working, wake shows an unlocked desktop |
| macOS | `caffeinate -i -w $$` | idle system sleep |

Detection is by exact process name (`comm`), polled every 15 s. Spawned child
sessions need no separate handling — the top-level agent process is what is
matched.

## Install

```sh
~/dotfiles/ai-caffeine/setup.sh
```

Idempotent; works on both macOS (LaunchAgent) and Arch Linux (systemd user
unit). The script replaces installed copies atomically, so re-running after
pulling changes is safe even while the watcher runs.

## Uninstall

Linux:

```sh
systemctl --user disable --now ai-caffeine.service
rm ~/.config/systemd/user/ai-caffeine.service ~/.local/bin/ai-caffeine
```

macOS:

```sh
launchctl bootout gui/$(id -u)/com.bartech.ai-caffeine
rm ~/Library/LaunchAgents/com.bartech.ai-caffeine.plist ~/.local/bin/ai-caffeine
```

## Tuning (environment overrides)

| Variable | Default | Meaning |
|----------|---------|---------|
| `AI_CAFFEINE_PROCESSES` | `claude codex omp` | Space-separated exact process names to watch |
| `AI_CAFFEINE_INTERVAL` | `15` | Seconds between checks |
| `AI_CAFFEINE_LOCKFILE` | `/tmp/ai-caffeine.lock` | Single-instance lock file (`flock`) |

## Troubleshooting

- If the KDE screen still locks while an agent runs, check System Settings →
  Power Management → Energy Saving: a "Lock Screen" idle action there bypasses
  `kscreenlockerrc` and must be disabled manually.
- kwin caches `Autolock` at session start; the watcher therefore calls
  `org.kde.screensaver.configure()` after every config write so the running
  locker re-reads it.
- On NVIDIA Wayland, DPMS-off appears in logs as an output disconnect
  (`There are no outputs - creating placeholder screen`). This is cosmetic;
  moving the mouse restores the output.
- PowerDevil's dim action needs a brightness display at daemon start. If
  powerdevil restarts while the panel is in standby, DDC detection finds 0
  displays and dimming silently never arms until the next restart with the
  screen awake. PowerDevil debug output:
  `systemctl --user set-environment QT_LOGGING_RULES=org.kde.powerdevil.debug=true`
  then restart `plasma-powerdevil.service`.
- On macOS, never `pkill caffeinate` broadly: it also kills Claude Code's
  built-in keep-awake (`caffeinate -i -t 300`, spawned by the CLI itself
  while busy). This watcher's own `caffeinate` exits on its own via `-w`.
