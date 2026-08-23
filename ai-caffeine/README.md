# ai-caffeine

Holds an OS-level keep-awake while AI agent processes (`claude`, `codex`, `omp`) are
running, and releases it when the last one exits. Prevents system sleep and
screen lock on Linux/KDE; prevents system sleep on macOS (display sleep stays
allowed). Every hold is self-expiring: if the watcher dies, normal sleep
behavior returns within ~45 seconds with no cleanup.

## Mechanisms

| OS | Hold | Blocks |
|----|------|--------|
| Linux | `systemd-inhibit --what=sleep:idle --mode=block`, self-refreshing | suspend via logind |
| Linux | `qdbus6 org.freedesktop.ScreenSaver /ScreenSaver SimulateUserActivity` | KDE idle pipeline: dim, blank, lock, idle suspend |
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
| `AI_CAFFEINE_LOCKDIR` | `/tmp/ai-caffeine.lock` | Single-instance lock directory |

## Troubleshooting

- If the KDE screen still locks while an agent runs, the
  `SimulateUserActivity` poke is not reaching the idle pipeline on your
  Plasma version — the mechanism needs revisiting.
- On macOS, never `pkill caffeinate` broadly: it also kills Claude Code's
  built-in keep-awake (`caffeinate -i -t 300`, spawned by the CLI itself
  while busy). This watcher's own `caffeinate` exits on its own via `-w`.
