# Service Heartbeat Monitor

Lightweight heartbeat monitor for background services.

Supports **macOS** (LaunchAgents) and **Linux** (systemd user units). Detects platform automatically and uses the appropriate service manager.

## What it does

- Runs every hour
- Checks a configurable list of service labels/units
- Logs active/missing status
- Writes errors to a separate log file

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
com.github.domt4.homebrew-autoupdate
```

**Linux** (systemd unit names):
```
git-auto-pull.service
launchd-heartbeat.service
system-update.service
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
