# Dotfiles

Personal shell functions, aliases, and scripts for macOS 14+. Clean, minimal, and automated setup for new machines.

## Quick Start

```bash
# Prerequisite (fresh Mac only)
xcode-select --install

git clone https://github.com/bartech-lab/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
source ~/.zshrc
```

The installer is idempotent and safe to re-run.

It also enables daily Homebrew autoupdate with `brew autoupdate start 86400 --upgrade --cleanup` when autoupdate is not already running.

## Global Git Ignore

Global Git ignore rules are managed from `git/gitignore_global` and linked to `~/.gitignore_global` by `./install.sh`.

Included defaults:
- OS files: `.DS_Store`, `._*`, `Thumbs.db`
- Editor temp files: `*~`, `*.swp`, `*.swo`
- Python bytecode: `__pycache__/`, `*.pyc`
- Local AI/tool directories: `.sisyphus`, `.opencode`, `.agents/`, `.agent-browser/`, `.skill-lock.json`, `.llm/`
- Agent instruction files: `agents.md`, `AGENTS.md`

To apply or refresh the symlink manually:

```bash
./install.sh
```

## Validation

After installation, verify everything is working:

```bash
~/dotfiles/scripts/validate-setup.sh
```

This checks:
- System requirements (macOS version, Command Line Tools)
- Homebrew and critical packages
- Homebrew autoupdate status
- Dotfiles structure and symlinks
- Shell integration
- Powerlevel10k and gitstatus setup
- Console output compatibility (instant prompt)

## Safety First

```bash
# Preview changes before installing
./install.sh --dry-run

# Diagnose your environment
dotfiles-doctor
```

## What's Included

### Modern CLI Replacements

| Command | Replacement | Why |
|---------|-------------|-----|
| `ls`, `ll`, `lt` | `eza` | Icons, git status, tree view |
| `grep` | `rg` (ripgrep) | Fast search, smart defaults |
| `find` | `fd` | Simpler syntax, fast file discovery |
| `sed` (simple edits) | `sd` | More intuitive find/replace |
| JSON parsing | `jq` | Deterministic machine-readable transforms |
| YAML parsing | `yq` | Structured YAML queries and edits |
| `top` | `btm` (bottom) | Visual system monitor |
| `du` | `dust` | Visual disk usage |
| `df` | `duf` | Colorful disk free |

### Media Processing

- `optimize-images [path]` - Batch optimize JPEG/PNG
- `video-to-gif <input>` - Convert videos to GIF
- `video-remux [path] [--subdir]` - Lossless container conversion
- `video-encode-cpu/gpu [path] [--subdir]` - H.265 encoding

### OpenCode Profiles

- `oco` - Clean OpenCode (vanilla)
- `omo` - Oh-My-OpenCode with Sisyphus agent
- `ecc` - Everything Claude Code (full ECC workflow with auto-update)
- `ocp` - List all OpenCode profiles
- `ocfix` - Clean orphaned opencode processes

### Development Utilities

- `extract <archive>` - Universal archive extractor
- `archive [name] [--dry-run] [-gzip]` - Create reproducible archives
- `repo-check` - Pre-archive sanity checker
- `dotfiles-doctor` - Environment health check
- `discord-openasar-setup [flags]` - Manual OpenAsar persistence setup (opt-in)
- `discord-openasar-status` - Check OpenAsar LaunchAgent status

### Git & macOS Helpers

- `git-cleanup` - Clean merged branches
- `git-open` - Open repo in browser
- `macos-defaults` - Apply comprehensive system preferences (Dock, Finder, Screenshots/Screen Recording, Keyboard, UI)
- `macos-defaults-export` - Export current macOS settings to a backup script
- `macos-disable-notification-sounds` - Turn off notification sounds across apps, skipping locked entries
- `cpwd` - Copy current path to clipboard

### Git Auto-Pull

Automatic background syncing for git repositories.

- `setup.sh` - One-time setup for new machines
- Runs every hour
- Configurable per-machine repos with different main branches
- Logs updates to `pull.log` and failures to `error.log`

See [Git Auto-Pull README](git-auto-pull/README.md) for setup details.

### LaunchAgent Heartbeat

Optional lightweight monitor for user LaunchAgents.

- `launchd-heartbeat/setup.sh` - One-time setup
- Runs every hour
- Logs `loaded`/`missing` status for configured LaunchAgent labels

See [LaunchAgent Heartbeat README](launchd-heartbeat/README.md) for setup details.

### Calendar Ghost Invite Fix

Manual one-command fix for recurring ghost RSVP invites in macOS Calendar.

- `calendar-ghost-fix/run-now.sh` - Runs the repair immediately

See [Calendar Ghost Fix README](calendar-ghost-fix/README.md) for setup details.

## Migration

Moving to a new Mac? Use the migration scripts:

```bash
# On old machine - backs up SSH keys, npm packages, Ghostty config, and ALL macOS defaults
~/dotfiles/scripts/migrate-backup.sh

# On new machine - restores everything including comprehensive macOS system preferences
~/dotfiles/scripts/migrate-restore.sh ~/migration-backup.tar.gz
```

**What gets backed up:**
- SSH keys (password-protected zip)
- Global npm packages list
- Ghostty terminal configuration
- **Comprehensive macOS system preferences** (Dock, Finder, Screenshots, Keyboard, Trackpad, UI settings)
- List of installed App Store apps

The macOS defaults backup includes 30+ settings covering Dock behavior, Finder visibility options, screenshot preferences, keyboard repeat rates, typing auto-corrections, window animations, and more.

See [Installation Guide](docs/install.md#migrating-to-a-new-mac) for details.

## Documentation

- [📥 Installation Guide](docs/install.md) - Setup, prerequisites, troubleshooting
- [🏗️ Architecture](docs/architecture.md) - How it works, file structure, extending
- [📚 Functions Reference](docs/functions.md) - Complete command reference
- [🎬 Media Processing](docs/media.md) - Video/image optimization
- [🛠️ Development Utilities](docs/dev.md) - Archives, diagnostics, helpers
- [💬 Discord OpenAsar](docs/discord-openasar.md) - Persistent OpenAsar + minimal CSS setup

## Requirements

- **macOS** 14+ (Sonoma and later)
- **zsh** (pre-installed)
- **Homebrew** (auto-installed by `./install.sh`)

## License

Personal dotfiles - feel free to use as inspiration for your own setup.
