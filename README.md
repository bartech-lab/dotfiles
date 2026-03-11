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
| `top` | `btm` (bottom) | Visual system monitor |
| `du` | `dust` | Visual disk usage |
| `df` | `duf` | Colorful disk free |

### Media Processing

- `optimize-images [path]` - Batch optimize JPEG/PNG
- `video-to-gif <input>` - Convert videos to GIF
- `video-remux [path]` - Lossless container conversion
- `video-encode-cpu/gpu [path]` - H.265 encoding

### Development Utilities

- `extract <archive>` - Universal archive extractor
- `archive [name] [--dry-run] [-gzip]` - Create reproducible archives
- `repo-check` - Pre-archive sanity checker
- `dotfiles-doctor` - Environment health check

### Git & macOS Helpers

- `git-cleanup` - Clean merged branches
- `git-open` - Open repo in browser
- `macos-defaults` - Apply comprehensive system preferences (Dock, Finder, Screenshots, Keyboard, UI)
- `macos-defaults-export` - Export current macOS settings to a backup script
- `macos-disable-notification-sounds` - Turn off notification sounds across apps, skipping locked entries
- `cpwd` - Copy current path to clipboard

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

## Requirements

- **macOS** 14+ (Sonoma and later)
- **zsh** (pre-installed)
- **Homebrew** (auto-installed by `./install.sh`)

## License

Personal dotfiles - feel free to use as inspiration for your own setup.
