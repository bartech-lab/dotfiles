# Dotfiles

Personal shell functions, aliases, and scripts for macOS. Clean, minimal, and automated setup for new machines.

## Prerequisites

- **macOS** - Tested on macOS Sonoma and later
- **zsh** - Default shell on macOS (pre-installed)
- **Homebrew** - Will be auto-installed by `./install.sh` if not present

## Quick Start

```bash
# 1. Clone repository
git clone <your-repo-url> ~/dotfiles
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

## What's Installed

### Modern CLI Replacements (Aliases)

These tools replace default macOS commands with modern alternatives:

- **`ls`, `ll`, `lt`** - Modern file listing with icons (`eza`)
  - `ls` - List with icons, directories first
  - `ll` - Detailed list with icons
  - `lt` - Tree view (2 levels deep)

- **`grep`** → `rg` (ripgrep) - Fast text search with better defaults
- **`top`** → `btm` (bottom) - Modern system monitor with graphs
- **`du`** → `dust` - Better disk usage visualization
- **`df`** → `duf` - Modern disk free viewer

### Media Functions

- **`optimize-images [path] [--lossless]`** - Optimize JPEG/PNG images
  - Uses parallel processing for speed
  - Default: Aggressive optimization (converts transparent PNGs to JPEG)
  - `--lossless`: Use lossless PNG optimization only
  - Requires: `parallel`, `mozjpeg` (cjpeg), `oxipng`, `pngquant`, `ffmpeg`

- **`video-remux [path]`** - Losslessly remux videos to MP4
  - No re-encoding, just container change
  - Supports: MOV, MKV, AVI → MP4

- **`video-encode-cpu [path]`** - High-quality H.265 CPU encoding
  - Best quality, slower processing
  - Uses libx265 codec

- **`video-encode-gpu [path]`** - Fast H.265 GPU encoding
  - Uses Apple VideoToolbox (hardware accelerated)
  - Good for quick encoding

- **`video-to-gif <input.mp4> [output.gif] [fps] [scale]`**
  - Convert videos to animated GIF
  - Defaults: 15fps, 480px width
  - Useful for documentation and GitHub issues

### Git Functions

- **`git-cleanup`** - Clean up git repository
  - Removes merged branches (except main/master)
  - Clears old stashes
  - Runs `git gc` for optimization

- **`git-open`** - Open current repository in browser
  - Supports GitHub, GitLab, Bitbucket, Azure DevOps
  - Handles SSH remotes automatically

### macOS Functions

- **`macos-defaults`** - Apply macOS system preferences
  - Finder: Show path bar
  - Dock: Auto-hide
  - Screenshots: Save to Downloads, disable shadow
  - Automatically restarts Finder and Dock

- **`cpwd`** - Copy current directory path to clipboard
  - Handy for sharing paths or documentation

### Dev Functions

- **`extract <archive-file>`** - Universal archive extractor
  - Supports: tar.bz2, tar.gz, tar.zst, tar.xz, bz2, rar, gz, tar, zip, Z, 7z, xz
  - Auto-detects format from extension
  - **Auto-creates directory**: Extracts to folder named after archive (e.g., `archive.tar.zst` → `archive/`)
  - **Smart collision handling**: If folder exists, creates `archive-2/`, `archive-3/`, etc.
  - Uses `unar` for zip, rar, 7z (shows error if not installed)

- **`archive [name] [--dry-run]`** - Create reproducible archive
  - Creates `.tar.zst` archives with deterministic output
  - Excludes: dev artifacts, caches, build output, temp files
  - `--dry-run`: Preview what would be archived without creating file
  - Uses zstd compression (-19)
  - Requires: `zstd`, `gnu-tar` (optional, for full reproducibility)
  - Auto-detects GNU tar; falls back to BSD tar if not available

### Homebrew

- **`brewup`** - Complete Homebrew maintenance
  - Updates Homebrew
  - Upgrades all formulae and casks
  - Runs `brew bundle` to sync with Brewfile
  - Cleans up old versions

### OpenCode

- **`opencode`** - Launch OpenCode with default profile
- **`omo`** - Launch Oh-My-OpenCode profile (auto-updates)
- **`oac`** - Launch OpenAgentsControl profile (auto-updates)
- **`ocp`** - List all available OpenCode profiles
- **`ocx-profile <name>`** - Launch OpenCode with specific profile

## Configuration Files

### Brewfile

All dependencies are defined in `Brewfile`. The installer uses `brew bundle` to install everything automatically.

**Key packages:**
- **Shell:** eza, ripgrep, dust, bottom, duf, fzf, zoxide
- **Media:** ffmpeg, parallel, mozjpeg, zstd, unar
- **Zsh:** zinit, powerlevel10k, zsh-syntax-highlighting, zsh-autosuggestions
- **Apps:** Ghostty, VS Code, Brave, and more (see Brewfile)

To update packages:
```bash
brew bundle --file=~/dotfiles/Brewfile
```

### Zsh Functions

Functions are organized in `zsh/functions/`:
- `00-core.zsh` - Zsh plugins and theme (zinit, powerlevel10k)
- `01-media.zsh` - Media processing functions
- `02-git.zsh` - Git helpers
- `03-brew.zsh` - Homebrew functions
- `03-shell.zsh` - Modern CLI aliases
- `04-macos.zsh` - macOS system functions
- `04-opencode.zsh` - OpenCode helpers
- `05-dev.zsh` - Development utilities

**Adding new functions:**
1. Create a file in `zsh/functions/` (e.g., `06-docker.zsh`)
2. Add your functions
3. They load automatically on next shell start (or run `source ~/.zshrc`)

### Zsh Plugins

**zsh-syntax-highlighting** and **zsh-autosuggestions** are loaded via dotfiles.

**Load order:**
1. Core settings and PATH configuration
2. Functions loader (`zsh-dotfiles-loader.zsh`) - loads all functions and plugins
3. Syntax highlighting (loaded last, after all aliases are defined)

## Fresh macOS Setup

On a completely fresh macOS machine:

1. **Install Command Line Tools** (if needed):
   ```bash
   xcode-select --install
   ```

2. **Clone and install**:
   ```bash
   git clone <your-repo-url> ~/dotfiles
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

## Agent-Only Tools

The following tools are installed but **not activated** for interactive use. They are available for automation and scripting:

- **`fzf`** - Fuzzy finder for interactive file/command selection
- **`zoxide`** - Smart directory jumper

These tools help with complex tasks but don't change your default shell behavior unless explicitly enabled in `~/.zshrc`.

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

### Media functions not working (empty output files)

If `optimize-images`, `video-encode-cpu`, or `video-encode-gpu` show success but produce empty files, check your PATH order. The `mozjpeg` keg-only formula must come BEFORE `/opt/homebrew/bin` in your PATH:

```bash
# In ~/.zshrc - mozjpeg MUST be first
path=(
  "/opt/homebrew/opt/mozjpeg/bin"  # ← This must come BEFORE brew bin
  "/opt/homebrew/bin"
  ...
)
```

**Why:** mozjpeg provides `cjpeg` which conflicts with the jpeg-turbo version. If jpeg-turbo's cjpeg is found first, it cannot read existing JPEG files (it only creates them from other formats), causing optimization to fail silently.

**Verify the fix:**
```bash
which -a cjpeg
# Should show mozjpeg version FIRST:
# /opt/homebrew/opt/mozjpeg/bin/cjpeg
# /opt/homebrew/bin/cjpeg
```

## Archive

Old/obsolete scripts from previous setups are kept in `archive/`:
- `archive/IEH/` - IEH game scripts
- `archive/Manjaro/` - Manjaro Linux scripts

These are not loaded automatically but kept for reference.

## License

Personal dotfiles - feel free to use as inspiration for your own setup.
