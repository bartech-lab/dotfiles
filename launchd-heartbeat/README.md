# LaunchAgent Heartbeat

Lightweight heartbeat monitor for user LaunchAgents on macOS.

It writes small status snapshots every hour so you can quickly confirm launchd jobs are actually loading and running.

## What it does

- Runs every hour via LaunchAgent (`StartInterval=3600`)
- Checks a configurable list of LaunchAgent labels
- Logs `loaded`/`missing` status plus `state` and `runs`
- Writes errors to a separate log file

## Setup

```bash
cd ~/dotfiles/launchd-heartbeat
bash setup.sh
```

## Configuration

Edit monitored labels:

```bash
nano ~/.config/launchd-heartbeat/monitored-labels.conf
```

Format: one LaunchAgent label per line.

Example:
```
com.user.gitautopull
com.github.domt4.homebrew-autoupdate
```

## Logs

- Heartbeat log: `~/.config/launchd-heartbeat/heartbeat.log`
- Error log: `~/.config/launchd-heartbeat/error.log`

## Management

```bash
# Check service
launchctl print gui/$(id -u)/com.user.launchdheartbeat

# Trigger immediate run
launchctl kickstart -k gui/$(id -u)/com.user.launchdheartbeat

# Stop service
launchctl bootout gui/$(id -u)/com.user.launchdheartbeat

# Start service
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.launchdheartbeat.plist
```

## Uninstall

```bash
launchctl bootout gui/$(id -u)/com.user.launchdheartbeat
rm ~/Library/LaunchAgents/com.user.launchdheartbeat.plist
rm -rf ~/.config/launchd-heartbeat
```
