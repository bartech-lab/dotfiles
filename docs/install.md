# Installation Guide

## Prerequisites

- **macOS** - Tested on macOS Sonoma and later
- **zsh** - Default shell on macOS (pre-installed)
- **Homebrew** - Will be auto-installed by `./install.sh` if not present

## Quick Start

```bash
# 1. Clone repository
git clone https://github.com/bartech-lab/dotfiles.git ~/dotfiles
cd ~/dotfiles

# 2. Run installer (handles everything)
./install.sh

# 3. Restart terminal or reload
source ~/.zshrc
```

The installer will:
- Install Homebrew (if not present)
- Install all dependencies via `brew bundle`
- Enable daily Homebrew autoupdate with upgrade + cleanup
- Link dotfiles functions loader
- Link `~/.gitignore_global` to the tracked file in `~/dotfiles/git/gitignore_global`
- Auto-install any missing critical dependencies
- Check and report status

## Global Git Ignore

The repo tracks a global Git ignore file at `git/gitignore_global`.

During install, `./install.sh`:
- Backs up an existing non-symlink `~/.gitignore_global`
- Symlinks `~/.gitignore_global` to `~/dotfiles/git/gitignore_global`

This keeps your personal global ignore rules versioned in dotfiles while preserving the standard Git location.

Current defaults include:
- OS files: `.DS_Store`, `._*`, `Thumbs.db`
- Editor temp files: `*~`, `*.swp`, `*.swo`
- Python bytecode: `__pycache__/`, `*.pyc`
- Local AI/tool directories: `.sisyphus`, `.opencode`, `.agents/`, `.agent-browser/`, `.skill-lock.json`, `.llm/`
- Agent instruction files: `agents.md`, `AGENTS.md`

If Git is not already using `~/.gitignore_global`, set it once with:

```bash
git config --global core.excludesfile ~/.gitignore_global
```

## What Gets Installed

### Shell Replacements

Your commands are automatically upgraded:

| Command | What You Get | Why It's Better |
|---------|--------------|-----------------|
| `ls`, `ll`, `lt` | `eza` | Icons, git status, tree view |
| `rg` | ripgrep | Fast grep replacement (use `rg`, not aliased to `grep`)
| `find` | `fd` | Simpler syntax, very fast file discovery |
| `sed` (simple replace) | `sd` | Cleaner find/replace workflow |
| JSON parsing | `jq` | Machine-readable JSON transformations |
| YAML parsing | `yq` | Structured YAML queries and updates |
| `top` | `btm` (bottom) | Graphs, process tree, mouse support |
| `du` | `dust` | Visual disk usage, sorted by size |
| `df` | `duf` | Colorful, sortable disk free |

### Automation Toolchain Verification

After install, verify the preferred CLI automation stack is available:

```bash
which rg fd sd jq yq git gh
```

All commands should resolve to valid paths.

### Media Processing

Ready-to-use video/image processing:
- `optimize-images` - Batch optimize JPEG/PNG
- `video-to-gif` - Convert videos to animated GIFs
- `video-remux` - Lossless container conversion
- `video-encode-cpu/gpu` - H.265 encoding

### Development Tools

- `extract` - Universal archive extractor
- `archive` - Create reproducible archives
- `git-cleanup`, `git-open` - Git helpers
- `brewup` - Homebrew maintenance
- `git-auto-pull` - Automatic background repo syncing

See [functions.md](functions.md) for full command reference.

## Optional: Git Auto-Pull Setup

After installing dotfiles, you can optionally set up automatic git repository syncing:

```bash
cd ~/dotfiles/git-auto-pull
bash setup.sh
```

This sets up a background service that:
- Pulls updates from configured repos every hour
- Logs updates to `pull.log` and failures to `error.log`
- Supports different main branches per repo
- Is machine-specific (configure once per machine)

See [dev.md](dev.md#git-auto-pull) for configuration details.

## Optional: LaunchAgent Heartbeat Setup

If you want a quick way to confirm user LaunchAgents are alive on this machine:

```bash
cd ~/dotfiles/launchd-heartbeat
bash setup.sh
```

This sets up a background service that:
- Runs every hour
- Checks selected LaunchAgent labels
- Writes status snapshots to `~/.config/launchd-heartbeat/heartbeat.log`

See [LaunchAgent Heartbeat README](../launchd-heartbeat/README.md) for details.

## Fresh macOS Setup

On a completely fresh macOS machine:

1. **Install Command Line Tools** (if needed):
   ```bash
   xcode-select --install
   ```

2. **Clone and install**:
   ```bash
   git clone https://github.com/bartech-lab/dotfiles.git ~/dotfiles
   cd ~/dotfiles
   ./install.sh
   ```

3. **Restart terminal** - Everything will be ready!

4. **Validate setup** (optional but recommended):
   ```bash
   ~/dotfiles/scripts/validate-setup.sh
   ```
   
   This verifies all components are installed correctly and checks for instant prompt compatibility.

The installer handles:
- Installing Homebrew
- Installing all Brewfile dependencies
- Starting `brew autoupdate` once per day with `--upgrade --cleanup` (if not already running)
- Linking all function files
- Verifying critical dependencies
- Setting up shell integration

## Migrating to a New Mac

Two scripts handle machine-to-machine migration:

### On Old Machine

```bash
~/dotfiles/scripts/migrate-backup.sh
```

Creates `~/migration-backup.tar.gz` containing:
- **npm global packages** - List of globally installed npm packages
- **SSH keys (encrypted)** - Password-protected zip of your SSH keys
- **Ghostty terminal config** - Terminal emulator settings
- **Comprehensive macOS defaults script** - Complete backup of 30+ system preferences including:
  - Dock behavior (auto-hide, animation speed, recent apps)
  - Finder settings (path bar, status bar, extensions, .DS_Store behavior)
  - Screenshot preferences (location, format, shadows)
  - Keyboard settings (key repeat, press-and-hold, full access)
  - Typing preferences (auto-correct, smart quotes, auto-capitalization)
  - UI settings (window resize, scrollbars, save panels)
  - Trackpad settings (tap to click)
- **Installed apps list** - For reference when redownloading App Store apps

### On New Machine

```bash
# Clone dotfiles first (use HTTPS if SSH not set up yet)
git clone https://github.com/bartech-lab/dotfiles.git ~/dotfiles

# Run restore with the archive
~/dotfiles/scripts/migrate-restore.sh ~/migration-backup.tar.gz
```

The restore script:
1. Installs Rosetta (Apple Silicon)
2. Installs Xcode CLI tools
3. Installs Homebrew
4. Restores SSH keys
5. Runs dotfiles installer
6. Restores Ghostty config
7. **Applies comprehensive macOS defaults** - Restores all your system preferences from the backup (or applies dotfiles defaults if no backup found)

The macOS defaults restoration includes all your custom settings for Dock, Finder, Screenshots, Keyboard, Trackpad, and UI behavior.

### Manual Steps (not automated)

- **Chrome bookmarks**: Export manually at `chrome://bookmarks`
- **App Store apps**: Review list and redownload with new Apple ID

## Updating

To update packages:
```bash
brew bundle --file=~/dotfiles/Brewfile
```

To enable the same automatic daily updates manually:

```bash
brew autoupdate start 86400 --upgrade --cleanup
```

To get latest dotfiles changes:
```bash
cd ~/dotfiles && git pull
```

## Troubleshooting

### Missing dependencies after install

Run the install script again - it will auto-install any missing critical dependencies:
```bash
./install.sh
```

### Functions not loading

Check that the loader is sourced in `~/.zshrc`:
```bash
grep "zsh-dotfiles-loader" ~/.zshrc
```

Should show: `source ~/.config/zsh-dotfiles-loader.zsh`

### Homebrew not found

On Apple Silicon Macs, ensure Homebrew is in PATH:
```bash
echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
```

Then restart your terminal.

### PATH ordering issues

For media functions to work correctly, mozjpeg must be found before the system's cjpeg:

```bash
# Verify path order
which -a cjpeg
# Should show mozjpeg version FIRST:
# /opt/homebrew/opt/mozjpeg/bin/cjpeg
# /opt/homebrew/bin/cjpeg
```

See [troubleshooting](../README.md#troubleshooting) for more.

## Uninstallation

To remove dotfiles:

```bash
# Remove the source line from ~/.zshrc
# The loader symlink can stay (harmless)
# Remove the dotfiles directory
rm -rf ~/dotfiles

# Optional: remove Brewfile packages manually
# (Homebrew doesn't have a reverse-bundle command)
```

## Next Steps

- Check out [functions.md](functions.md) for all available commands
- Read [architecture.md](architecture.md) to understand how it works
- Set up your fonts for powerlevel10k (see troubleshooting)
- Explore optional tools: `fzf`, `zoxide` (add to `~/.zshrc` to enable)
