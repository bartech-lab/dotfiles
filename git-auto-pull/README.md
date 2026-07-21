# Git Auto-Pull

Automatically pull updates from git repositories every hour.

Supports **macOS** (LaunchAgents) and **Linux** (systemd user timers).

## Overview

Runs a shell script periodically to fetch and fast-forward configured branches in git repositories. Silent background operation with minimal resource usage.

## Components

- **pull.sh** - The main script that checks and pulls updates
- **install.sh** (`~/dotfiles/install.sh`) — Unified installer for all services on both macOS and Linux
- **setup.sh** - macOS-only setup (legacy; prefer `install.sh`)
- **repos.conf** - Machine-specific repository and branch overrides (not in dotfiles)
- **systemd/** - systemd user unit files for Linux

## Installation

### First Time Setup

Run the unified installer from dotfiles root:

```bash
bash ~/dotfiles/install.sh
```

Or for macOS-only legacy setup:

```bash
cd ~/dotfiles/git-auto-pull
bash setup.sh
```

### Adding Repositories or Branch Overrides

Edit the config file:

```bash
nano ~/.config/git-auto-pull/repos.conf
```

Add one repository per line in this format:
```
/path/to/repo:branch-name
```

Configured entries always win over auto-discovery. For example:
```
~/Projects/my-app:main
~/work/api:master
~/side-project:develop
```

Lines starting with `#` are ignored (comments).

### Testing

Run manually to test:

```bash
bash ~/.config/git-auto-pull/pull.sh
```

Run the isolated integration suite:

```bash
bash ~/dotfiles/git-auto-pull/tests/test.sh
```

Check the log to see what was updated:

```bash
cat ~/.config/git-auto-pull/pull.log
```

## Configuration

- **Interval:** 1 hour (3600 seconds)
- **Log location:** `~/.config/git-auto-pull/pull.log`
- **Error log:** `~/.config/git-auto-pull/error.log`

## Management

### macOS

```bash
# Check if running
launchctl list | grep gitautopull

# Stop
launchctl unload ~/Library/LaunchAgents/com.user.gitautopull.plist

# Start
launchctl load ~/Library/LaunchAgents/com.user.gitautopull.plist

# Restart after config changes
launchctl unload ~/Library/LaunchAgents/com.user.gitautopull.plist
launchctl load ~/Library/LaunchAgents/com.user.gitautopull.plist
```

### Linux

```bash
# Check status
systemctl --user status git-auto-pull.timer

# Trigger immediate run
systemctl --user start git-auto-pull.service

# View recent logs
journalctl --user -u git-auto-pull.service -n 20

# Stop
systemctl --user stop git-auto-pull.timer

# Start
systemctl --user start git-auto-pull.timer

# Disable
systemctl --user disable git-auto-pull.timer
```

## How It Works

1. **LaunchAgent** (macOS service scheduler) triggers the script every hour
2. **pull.sh** builds one repository list:
   - Entries in `repos.conf` use their explicitly configured branch
   - Repositories discovered in `~/Projects` and `~/dotfiles` use the remote's advertised default branch
   - Duplicate paths are processed once, with configuration taking precedence
3. Each repository is then processed by:
   - Fetching the selected remote branch quietly
   - Compare the local branch ref with the remote branch ref
   - Fast-forwards only the selected branch (never auto-merges/rebases)
   - Keeps your currently checked out branch unchanged unless it matches the configured branch
   - Logs updates to `pull.log`
4. All repos are processed in parallel (background jobs)
5. No output if nothing changed (silent operation)

## Notes

- The script only logs when it actually updates something
- No updates = no log entries (keeps logs clean)
- Very low resource usage (~0.1% CPU for 1-2 seconds per repo)
- Runs as background process (won't interrupt your work)
- Only works when you're online; a default-branch lookup or fetch failure is logged in `error.log`
- Diverged branches are skipped and logged in `error.log` (no automatic merge)

## Uninstallation

### macOS
```bash
launchctl unload ~/Library/LaunchAgents/com.user.gitautopull.plist
rm ~/Library/LaunchAgents/com.user.gitautopull.plist
rm -rf ~/.config/git-auto-pull
```

### Linux
```bash
systemctl --user disable --now git-auto-pull.timer
rm ~/.config/systemd/user/git-auto-pull.{service,timer}
rm -rf ~/.config/git-auto-pull
```
