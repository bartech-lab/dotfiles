# Service Heartbeat Monitor

Lightweight heartbeat monitor for background services.

Supports **macOS** (LaunchAgents) and **Linux** (systemd user units). Detects platform automatically and uses the appropriate service manager.

## What it does

- Runs every hour
- Checks a configurable list of service labels/units
- Logs active, failed, or missing status on Linux, including the service result.
- An active timer does not hide a failed service.
- Runs the probes in `probes.conf`. A probe is a shell command that must exit 0 within `HEARTBEAT_PROBE_TIMEOUT` seconds (default 20).
- Reads job health records in `~/.local/state/jobs/*.status`, written by `job-status`. A job is failed when its last failure is newer than its last success, and stale when its last success is older than its `max_age_hours`.
- Sends one desktop notification when the set of problems changes. It does not repeat while the set stays the same.
- Writes errors to a separate log file. Each log moves to `.1` above 1 MB.
- `launchd-heartbeat --status` prints one line per check and exits 2 when any check has a problem. It never notifies.
- Skips a run within `HEARTBEAT_BOOT_GRACE` seconds of boot (default 300, 0 disables), because a catch-up run at boot or login sees services that have not started yet. `--status` never skips.

## Setup

```bash
bash ~/dotfiles/install.sh
```

For macOS-only legacy setup:

```bash
cd ~/dotfiles/launchd-heartbeat
bash setup.sh
```

## Configuration

Edit monitored services:

```bash
nano ~/.config/launchd-heartbeat/monitored-labels.conf
```

Format — one service per line.

**macOS** (LaunchAgent labels):
```
com.user.gitautopull
com.user.brewautoupdate
```

**Linux** (systemd unit names):
```
git-auto-pull.service
launchd-heartbeat.service
system-update.service
```

### Probes

`~/.config/launchd-heartbeat/probes.conf`, one probe per line: a name, then the command.

```
bonsai-http curl -sf -m 5 http://127.0.0.1:8080/health
disk-root   test "$(df -P / | awk 'NR==2 {print int($5)}')" -lt 90
```

### Pause file

A deliberate stop (for example `gaming on`) writes `$XDG_RUNTIME_DIR/heartbeat-pause`
(override with `HEARTBEAT_PAUSE_FILE`). Every label or probe named in a `pause=` line is
reported as `paused` instead of checked. A pause older than `max_age_hours` is itself a
problem, `pause-<owner>` with status `stale`.

```
since=1761130000
owner=gaming
max_age_hours=12
pause=bonsai.service
pause=bonsai-http
```

### Job records

A scheduled job reports its own result, so the heartbeat can tell "loaded" from "succeeded recently":

```bash
job-status ok coderabbit --max-age 192       # success; stale after 8 days without another
job-status fail coderabbit "GitLab unreachable, VPN off?"
```

`job-status` is installed to `~/.local/bin/job-status`. Call it by absolute path from launchd or systemd jobs, which do not have `~/.local/bin` in `PATH`.

## Tests

```bash
bash launchd-heartbeat/tests/test.sh
bash launchd-heartbeat/tests/test-health.sh
```

## Logs

- Heartbeat log: `~/.config/launchd-heartbeat/heartbeat.log`
- Error log: `~/.config/launchd-heartbeat/error.log`

## Management

### macOS

```bash
# Check service
launchctl print gui/$(id -u)/com.user.launchdheartbeat

# Trigger immediate run
launchctl kickstart -k gui/$(id -u)/com.user.launchdheartbeat

# Stop
launchctl bootout gui/$(id -u)/com.user.launchdheartbeat

# Start
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.launchdheartbeat.plist
```

### Linux

```bash
# Check status
systemctl --user status launchd-heartbeat.timer

# Trigger immediate run
systemctl --user start launchd-heartbeat.service

# View recent logs
journalctl --user -u launchd-heartbeat.service -n 20

# Stop timer
systemctl --user stop launchd-heartbeat.timer

# Start timer
systemctl --user start launchd-heartbeat.timer
```

## Uninstall

### macOS
```bash
launchctl bootout gui/$(id -u)/com.user.launchdheartbeat
rm ~/Library/LaunchAgents/com.user.launchdheartbeat.plist
rm -rf ~/.config/launchd-heartbeat
```

### Linux
```bash
systemctl --user disable --now launchd-heartbeat.timer
rm ~/.config/systemd/user/launchd-heartbeat.{service,timer}
rm -rf ~/.config/launchd-heartbeat
```
