# Git Auto-Pull

Automatically pull updates from git repositories every 4 hours on macOS.

## Overview

This setup creates a LaunchAgent that runs a shell script periodically to fetch and pull updates from configured git repositories. It runs silently in the background with minimal resource usage.

## Components

- **pull.sh** - The main script that checks and pulls updates
- **setup.sh** - One-time setup script for new machines
- **repos.conf** - Configuration file listing repositories and their main branches (machine-specific, not in dotfiles)

## Installation

### First Time Setup

1. Make sure this directory is part of your dotfiles repository
2. Run the setup script:

```bash
cd ~/dotfiles/git-auto-pull
bash setup.sh
```

### Adding Repositories

Edit the config file:

```bash
nano ~/.config/git-auto-pull/repos.conf
```

Add one repo per line in this format:
```
/path/to/repo:branch-name
```

Examples:
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

Check the log to see what was updated:

```bash
cat ~/.config/git-auto-pull/pull.log
```

## Configuration

- **Interval:** 4 hours (14400 seconds)
- **Log location:** `~/.config/git-auto-pull/pull.log`
- **Error log:** `~/.config/git-auto-pull/error.log`

## Management

### Check if running:
```bash
launchctl list | grep gitautopull
```

### Stop the service:
```bash
launchctl unload ~/Library/LaunchAgents/com.user.gitautopull.plist
```

### Start the service:
```bash
launchctl load ~/Library/LaunchAgents/com.user.gitautopull.plist
```

### Restart after config changes:
```bash
launchctl unload ~/Library/LaunchAgents/com.user.gitautopull.plist
launchctl load ~/Library/LaunchAgents/com.user.gitautopull.plist
```

## How It Works

1. **LaunchAgent** (macOS service scheduler) triggers the script every 4 hours
2. **pull.sh** reads `repos.conf` and for each repo:
   - Fetches the remote branch quietly
   - Compares local vs remote commits
   - Pulls only if there are new commits
   - Logs updates to `pull.log`
3. All repos are processed in parallel (background jobs)
4. No output if nothing changed (silent operation)

## Notes

- The script only logs when it actually updates something
- No updates = no log entries (keeps logs clean)
- Very low resource usage (~0.1% CPU for 1-2 seconds per repo)
- Runs as background process (won't interrupt your work)
- Only works when you're online (fails silently if no internet)

## Uninstallation

```bash
launchctl unload ~/Library/LaunchAgents/com.user.gitautopull.plist
rm ~/Library/LaunchAgents/com.user.gitautopull.plist
rm -rf ~/.config/git-auto-pull
```
