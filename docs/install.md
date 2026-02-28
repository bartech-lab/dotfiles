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
- Link dotfiles functions loader
- Auto-install any missing critical dependencies
- Check and report status

## What Gets Installed

### Shell Replacements

Your commands are automatically upgraded:

| Command | What You Get | Why It's Better |
|---------|--------------|-----------------|
| `ls`, `ll`, `lt` | `eza` | Icons, git status, tree view |
| `rg` | ripgrep | Fast grep replacement (use `rg`, not aliased to `grep`)
| `top` | `btm` (bottom) | Graphs, process tree, mouse support |
| `du` | `dust` | Visual disk usage, sorted by size |
| `df` | `duf` | Colorful, sortable disk free |

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

See [functions.md](functions.md) for full command reference.

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

The installer handles:
- Installing Homebrew
- Installing all Brewfile dependencies
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
