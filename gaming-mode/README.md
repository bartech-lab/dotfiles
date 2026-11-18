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

## New games

`game-quirks` lists every installed Steam and Lutris game with its frame generation decision, kept in `games.conf`. `game-quirks.path` runs it when a game is installed, and `ops notify` names any game without a decision.

| Command | Effect |
|---|---|
| `game-quirks` | show every game; exit 1 if one needs attention |
| `game-quirks afmf steam:<appid>` or `lutris:<slug>` | turn `afmf-linux` on for that game. Steam must be closed |
| `game-quirks afmf-off lutris:<slug> [why]` | turn it off again, for a measured baseline |
| `game-quirks skip <game> <why>` | record that the game stays without it |

Lutris reads environment variables from `system: env:`. It ignores `game: env:`.

## Path of Exile 2 session recorder

The game's desktop icon runs `poe2-session`. It switches game mode on, starts the game
through Lutris, records until the game exits, then switches game mode off (unless it was
already on), writes a report and sends `ops notify` with three numbers and the report path.
Nothing runs between sessions.

| Command | Effect |
|---|---|
| `gamelog list` | recorded sessions |
| `gamelog report [SESSION]` | rebuild a session's `report.html` and print its path |
| `gamelog compare` | current settings against the previous ones; needs 3 sessions each |
| `gamelog next` | what is worth testing next and why; nothing is applied |
| `gamelog backfill` | crashes, disconnects and memory warnings in the game's old log |
| `gamelog install-env` | once: make Lutris start the game with the frame-logging MangoHud config |

Each session is a directory in `~/.local/state/gaming/poe2/sessions/`:

- `frames/`: every frame's length, from MangoHud (`~/.config/gaming/poe2-mangohud.conf`).
  A small fps counter is visible in the game; Right Shift+F12 hides it.
- `sampler.csv`: one row per second. CPU per core, the game's busiest threads, CPU power and
  temperature; graphics card load, memory, clocks, power, temperature and throttle reasons;
  the game's memory, files and disk use; pressure stall; round trip of the game's own
  server connection; shader cache size.
- `events.jsonl`: start, renderer, area changes, loading screens, focus changes, memory
  warnings and the exit, from the game's `Client.txt`. Chat lines and server addresses are
  never stored.
- `meta.json`, `config.ini`: versions and settings in effect, including the environment
  the game process really got, the Proton build and the sync method in use.
- `summary.json`, `report.html`: numbers, findings and charts. The report is one offline file.

Numbers leave out loading screens and time with the window unfocused. A stutter is a frame
at least 2.5 times the local median and at least 25 ms. `compare` groups sessions by the
settings you chose; kernel, driver and package updates are listed, not grouped, so a rolling
system still reaches three sessions per group.

The recorder only reads: the game's log and config, OS counters and MangoHud's log. It never
reads game memory and never sends input. `gamelog install-env` is the one setting it writes.
Frame logs are deleted after 30 days, the rest of a session after 180, summaries stay.

## What `on` stops

Only units that are running are recorded in `$XDG_RUNTIME_DIR/gaming/state`, and `off`
starts only those, in reverse order. A reboot clears the state; the units autostart anyway.

- `bonsai.service` (llama-server: about 12 GB VRAM, 20 GB RAM). `bonsai-cc-proxy.service`
  keeps running and answers every request with HTTP 503 and a `game_mode` error naming the
  start time, so agents on both machines see why Bonsai is down. `bonsai.sh` then falls back
  to OpenRouter.
- `docker.socket`, `docker.service`, through `sudo -n`. Without a passwordless rule they are
  reported as not stopped; `sudoers.example` holds a narrow rule.
- `system-update.timer`, `toolsmith.timer`, `logbook-sync.timer`. A run already in progress is
  left alone and named in the notification.
- Desktop apps matching the globs in `~/.config/gaming/apps.conf` (monitors by default; Discord stays open).
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
`gaming-toggle.desktop` entry and the Meta+Shift+G shortcut. It also links `game-quirks`,
`gamelog` and `poe2-session`. For the recorder, point the game's desktop icon at
`~/.local/bin/poe2-session` and run `gamelog install-env` once.

## GPU log

While game mode is on, `gaming-gpu-log.service` appends a row every second to
`~/.local/state/gaming/gpu-log-YYYY-MM-DD.csv`: graphics memory used and total, and
for Chrome's graphics process its memory, open file handles and handle limit.
It is a diagnostic for `VK_ERROR_OUT_OF_DEVICE_MEMORY` in browser games. Find the
error times with `journalctl --user | grep VK_ERROR` and read the rows around them.

## Tests

```bash
bash ~/dotfiles/gaming-mode/tests/test-gaming.sh
bash ~/dotfiles/gaming-mode/tests/test-poe2-session.sh
python3 -m unittest discover -s ~/dotfiles/gaming-mode/tests -p 'test_*.py'
```
