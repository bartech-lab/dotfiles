# Dotfiles

Personal shell functions, aliases, and scripts for macOS 14+ and Linux (EndeavourOS/Arch). Clean, minimal, and automated setup for new machines.

## Quick Start

### macOS

```bash
# Prerequisite (fresh Mac only)
xcode-select --install

git clone https://github.com/bartech-lab/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
source ~/.zshrc
```

### Linux (EndeavourOS / Arch)

```bash
# Prerequisites (fresh system only)
sudo pacman -S git zsh
chsh -s /usr/bin/zsh
# Log out and back in for the shell change, then:

git clone https://github.com/bartech-lab/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
source ~/.zshrc

# Optional: customize your prompt
p10k configure
```

The installer is idempotent and safe to re-run.

On macOS it also enables daily Homebrew autoupdate for formulae. On Linux it enables systemd timers for automatic git syncing, heartbeat monitoring, SSD TRIM, and mirror list refresh.

## Global Git Ignore

Global Git ignore rules are managed from `config/git/gitignore_global` and linked to `~/.gitignore_global` by `./install.sh`.

Included defaults:
- OS files: `.DS_Store`, `._*`, `Thumbs.db`
- Editor temp files: `*~`, `*.swp`, `*.swo`
- Python bytecode: `__pycache__/`, `*.pyc`
- Local AI/tool directories: `.agent-browser/`, `.llm/`, `.opencode/`, `.playwright-mcp/`, plus `.skill-lock.json`
- Local-only notes: `*.local.md`

Agent instruction files (`AGENTS.md`, `CLAUDE.md`) and agent directories (`.claude/`,
`.agents/`, `.codex/`, `.mcp.json`) are deliberately absent: repositories track some of
them, and a global ignore over a tracked path hides new files from `git status` and makes
`git add` refuse them without `-f`. Ignore those per repository in `.git/info/exclude`.

To apply or refresh the symlink manually:

```bash
./install.sh
```

## Validation

After installation, verify everything is working:

```bash
~/dotfiles/scripts/validate-setup.sh
```

For shell changes, inspect each file's shebang first: run
`shellcheck --severity=warning` only on Bash/POSIX `sh` files, and use
`zsh -n` for zsh files (including `.sh` files whose shebang selects zsh).
Keep the relevant `bash -n`/`sh -n` and integration tests, such as:

```bash
bash -n path/to/changed-bash-file.sh
sh -n path/to/changed-posix-file.sh
zsh -n path/to/changed-zsh-file.zsh
bash ~/dotfiles/scripts/tests/test-git-autoswitch.sh
bash ~/dotfiles/scripts/tests/test-git-local-patch.sh
bash ~/dotfiles/scripts/tests/test-claude-as.sh
bash ~/dotfiles/git-auto-pull/tests/test.sh
bash ~/dotfiles/scripts/gitlab-stats/tests/test.sh
```

This checks:
- System requirements (macOS version, Command Line Tools)
- Homebrew and critical packages
- Homebrew autoupdate status (`com.user.brewautoupdate`)
- Dotfiles structure and symlinks
- Shell integration
- Powerlevel10k and gitstatus setup
- Console output compatibility (see [Shell startup](docs/functions.md#shell-startup))

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
- `dng-to-jpg [path] [quality]` - Convert DNG raw files to JPEG
- `video-to-gif <input>` - Convert videos to GIF
- `video-remux [path] [--subdir]` - Lossless container conversion
- `video-encode-cpu/gpu [path] [--subdir]` - H.265 encoding

### Development Utilities

- `extract <archive>` - Universal archive extractor
- `archive [name] [--dry-run] [-gzip]` - Create reproducible archives
- `repo-check` - Pre-archive sanity checker
- `dotfiles-doctor` - Environment health check
- `gitlab-stats [options]` - GitLab merge request statistics
- `claude-as <name> [claude args]` - Run Claude Code signed in to a second subscription account, side by side with the default one (see [Functions Reference](docs/functions.md#claude-as))
- `discord-openasar-setup [flags]` - Manual OpenAsar persistence setup (opt-in)
- `discord-openasar-status` - Check OpenAsar LaunchAgent status
- `agent-skills-sync [name ...]` - Mirror skills from the Claude-synced skill bundle into ~/.agents/skills, which Codex and OMP both read

### Git & macOS Helpers

- `git-cleanup` - Clean merged branches
- `git-open` - Open repo in browser
- `git-autoswitch` - Wraps `git push` to switch back to the default branch after pushing a feature branch. Installed as a zsh function and as `git` shims in `scripts/shims` and `~/.local/bin` (see [Functions Reference](docs/functions.md))
- `git local-patch` - Keeps local-only edits on tracked files out of commits without breaking `git pull`, using a clean/smudge filter (see [Functions Reference](docs/functions.md#git-local-patch))
- [WezTerm configuration](docs/wezterm.md) - Pro theme, Meslo 11 font, persistent local tabs, and direct tab shortcuts
- `macos-defaults` - Apply comprehensive system preferences (Dock, Finder, Screenshots/Screen Recording, Keyboard, UI)
- `macos-defaults-export` - Export current macOS settings to a backup script
- `macos-disable-notification-sounds` - Turn off notification sounds across apps, skipping locked entries
- `cpwd` - Copy current path to clipboard

### Git Auto-Pull

Automatic background syncing for git repositories.

- `setup.sh` - One-time setup for new machines
- Runs every hour
- Configurable per-machine repos with different main branches
- Logs run summaries and updates to `pull.log`, and failures to `error.log`
- Retries failed Linux runs after 60 seconds, with three starts per 45-minute window

See [Git Auto-Pull README](git-auto-pull/README.md) for setup details.

### LaunchAgent Heartbeat

Optional lightweight monitor for user LaunchAgents.

- `launchd-heartbeat/setup.sh` - One-time setup
- Runs every hour
- Logs configured service status and reports failed Linux services, even when their timers remain active

See [LaunchAgent Heartbeat README](launchd-heartbeat/README.md) for setup details.

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

- **macOS** 14+ (Sonoma and later) or **Linux** (EndeavourOS/Arch)
- **zsh** (auto-installed by `./install.sh` on Linux, pre-installed on macOS)
- **ShellCheck** (installed by `Brewfile` on macOS or `linux/pkglist/pacman.txt` on Linux)
- **Homebrew** (auto-installed by `./install.sh` on macOS)

## License

Personal dotfiles - feel free to use as inspiration for your own setup.
