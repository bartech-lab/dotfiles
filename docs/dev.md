# Development Utilities

Archive handling, environment diagnostics, and development helpers.

## extract

Universal archive extractor with smart directory handling.

```bash
extract <archive-file>
```

**Supported formats:**
- Compressed tarballs: `.tar.zst`, `.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tgz`, `.tbz2`
- Archives: `.tar`, `.zip`, `.rar`, `.7z`
- Compressed files: `.gz`, `.bz2`, `.xz`, `.Z`

**Features:**
- Auto-detects format from file extension
- Creates extraction directory named after archive
- Handles name collisions (creates `name-2/`, `name-3/`, etc.)
- Uses `zstd`, `unar` as needed

**Examples:**
```bash
extract project.tar.zst          # Extract to project/
extract backup.zip               # Extract to backup/
extract "My Backup.tar.gz"       # Handles spaces: My Backup/
```

**Smart collision handling:**
```bash
extract data.tar.gz              # Creates data/
extract data.tar.gz              # Creates data-2/ (data/ exists)
extract data.tar.gz              # Creates data-3/
```

**Requirements:**
- `zstd` - For .tar.zst files
- `unar` - For zip, rar, 7z (auto-installs if missing)

## archive

Create reproducible, deterministic archives.

```bash
archive [name] [--dry-run|-n] [-gzip]
```

**Arguments:**
- `name` - Archive base name (defaults to current directory name)
- `--dry-run` or `-n` - Preview what would be archived
- `-gzip` - Use gzip -6 instead of zstd (creates .tar.gz)

**Default behavior:**
- Uses zstd with level 19 compression
- Creates `.tar.zst` archives
- Deterministic output (same content = same archive)
- Excludes development artifacts

**With `-gzip` flag:**
- Uses `gzip -6` compression
- Creates `.tar.gz` archives
- Better compatibility with older systems

**Exclusions (automatic):**
```
# Version control
.git

# Editors
.idea, .vscode

# Dependencies
node_modules, venv, .venv

# Task runners
.sisyphus

# Build output
dist, build, target

# Caches
.eslintcache, .parcel-cache, __pycache__

# Temporary
tmp, temp, *.log

# Secrets
.env, .env.*

# Other archives
*.tar, *.tar.gz, *.zip
```

**Examples:**
```bash
archive                          # Create name-20240222-1430.tar.zst
archive myproject                # Create myproject-20240222-1430.tar.zst
archive --dry-run                # Preview files to be archived
archive -n                       # Same as --dry-run
archive -gzip                    # Use gzip instead of zstd
archive myproject -gzip          # Create .tar.gz archive
```

**Reproducibility:**
When GNU tar is available:
- Sorted file list
- Fixed timestamp (2020-01-01)
- Owner/group set to 0

This means identical source creates byte-identical archives.

## repo-check

Pre-archive sanity checker for repositories.

```bash
repo-check              # Run all checks
repo-check --strict     # Treat warnings as errors
```

**Checks performed:**

### Security
- ❌ `.env` files in git (not in .gitignore)
- ❌ Secret files (`.pem`, `.key`, `id_rsa`)
- ❌ Files >100MB (GitHub limit)

### Repository Health
- ⚠️  Uncommitted changes
- ⚠️  Untracked files
- ⚠️  No README.md
- ⚠️  No LICENSE

### Accidental Inclusions
- ❌ `node_modules/` tracked in git
- ❌ `vendor/` directories tracked
- ❌ Build output committed
- ❌ `.DS_Store` files

**Output:**
```
🔍 Repository Health Check
==========================

Security:
  ❌ .env file found: config/.env
  ✅ No large files
  ✅ No secret keys

Repository:
  ⚠️  Uncommitted changes (3 files)
  ⚠️  No LICENSE file
  ✅ README.md present

Accidental Inclusions:
  ❌ node_modules/ tracked in git
  ✅ No .DS_Store files

Summary: 3 errors, 2 warnings

Archive anyway? [y/N]:
```

**Usage with archive:**
```bash
repo-check && archive   # Only archive if checks pass
```

## dotfiles-doctor

Comprehensive health check for your dotfiles environment.

```bash
dotfiles-doctor         # Full diagnostics
dotfiles-doctor --fix   # Auto-fix common issues
```

**Checks performed:**

### System
- ✅ macOS version compatibility
- ✅ Command Line Tools installed
- ✅ Homebrew installed

### Critical Tools
- ✅ `zstd` - Archive compression
- ✅ `gtar` - GNU tar for reproducibility
- ✅ `ffmpeg` - Media processing
- ✅ `cjpeg` (mozjpeg) - JPEG optimization
- ✅ `parallel` - Parallel processing

### Dotfiles Setup
- ✅ Loader symlinked (`~/.config/zsh-dotfiles-loader.zsh`)
- ✅ Sourced in `~/.zshrc`
- ✅ Functions loading correctly

### PATH Configuration
- ✅ mozjpeg before Homebrew bin
- ✅ No duplicates
- ✅ Correct order

### Shell Plugins
- ✅ zinit installed
- ✅ powerlevel10k loaded
- ✅ zsh-syntax-highlighting active
- ✅ zsh-autosuggestions active

### Fonts (for powerlevel10k)
- ✅ Nerd Fonts installed
- ✅ Font configured in terminal

### Git Configuration
- ✅ Git installed
- ✅ User name set
- ✅ User email set
- ✅ Default branch configured

**Output:**
```
🔧 Dotfiles Doctor
==================

System:
  ✅ macOS 14.2
  ✅ Command Line Tools
  ✅ Homebrew 4.2.0

Critical Tools:
  ✅ zstd 1.5.5
  ✅ gtar (GNU tar) 1.35
  ✅ ffmpeg 6.1.1
  ✅ cjpeg (mozjpeg) 4.1.1
  ✅ parallel 20240101

Dotfiles:
  ✅ Loader symlinked
  ✅ Sourced in .zshrc
  ✅ Functions loaded (40 functions)

PATH:
  ✅ mozjpeg priority correct
  ✅ No duplicates

Shell:
  ✅ zinit 3.13.0
  ✅ powerlevel10k active
  ✅ Syntax highlighting
  ✅ Auto-suggestions

Fonts:
  ✅ MesloLGS Nerd Font

Git:
  ✅ Git 2.43.0
  ✅ User configured

Status: All systems operational ✅
```

**Auto-fix mode:**
```bash
dotfiles-doctor --fix   # Attempt to fix common issues
```

Fixes include:
- Re-linking loader if broken
- Fixing PATH order
- Installing missing tools via Homebrew
- Suggesting font installation

## install.sh --dry-run

Preview what the installer would do without making changes.

```bash
./install.sh --dry-run
```

**Shows:**
- Homebrew installation status
- Packages that would be installed
- Symlinks that would be created
- Backup location
- Critical dependency status

**Example output:**
```
🚀 Dotfiles Installer (DRY RUN)
===============================

Homebrew:
  ✅ Already installed

Packages to install:
  → eza (modern ls)
  → ripgrep (modern grep)
  → dust (modern du)
  → zstd (archive compression)
  → gnu-tar (reproducible archives)

Symlinks:
  → ~/.config/zsh-dotfiles-loader.zsh → ~/dotfiles/zsh/functions.zsh

Backup location:
  → ~/.dotfiles-backup-20240222-143000/

Critical dependencies:
  ✅ zstd (will be installed)
  ✅ gtar (will be installed)
  ⚠️  cjpeg (install mozjpeg)

No changes made (dry run mode)
```

## Development Best Practices

### Before Archiving

Always check first:
```bash
repo-check && archive --dry-run && archive
```

### Environment Verification

After setup or when troubleshooting:
```bash
dotfiles-doctor
```

### Safe Installation

Test on existing machines:
```bash
./install.sh --dry-run  # Review changes first
./install.sh            # Execute if satisfied
```

## Function Files

Development utilities are organized in `zsh/functions/40-dev.zsh`:

```zsh
# Archive/Extract
extract() { ... }
archive() { ... }

# Repository checking
repo-check() { ... }

# Diagnostics
dotfiles-doctor() { ... }
```

## Troubleshooting

### "archive: command not found"

```bash
# Check if function is defined
type archive

# Reload functions
source ~/.zshrc
```

### "zstd not found" when archiving

```bash
# Install zstd
brew install zstd

# Or run full bundle
brew bundle --file=~/dotfiles/Brewfile
```

### Large archives created

Check exclusions:
```bash
archive --dry-run | grep -E "(node_modules|build|dist)"
```

### dotfiles-doctor reports PATH issues

Common fix:
```bash
# Add to ~/.zshrc, BEFORE /opt/homebrew/bin
path=(
  "/opt/homebrew/opt/mozjpeg/bin"
  "/opt/homebrew/bin"
  ...
)
```

## Git Auto-Pull

Automatic background syncing for git repositories. Keeps local repos in sync with remote without manual intervention.

### Setup

One-time setup for new machines:

```bash
cd ~/dotfiles/git-auto-pull
bash setup.sh
```

This creates:
- `~/.config/git-auto-pull/repos.conf` - Config file for repositories
- LaunchAgent to run every 4 hours
- Empty log files

### Configuration

Edit the config file:

```bash
nano ~/.config/git-auto-pull/repos.conf
```

Format: one repo per line as `path:branch`

```
~/Projects/my-app:main
~/work/api:master
~/side-project:develop
```

### How It Works

- **Interval:** 4 hours (14400 seconds)
- **Logging:** Updates to `pull.log` and failures to `error.log`
- **Parallel processing:** All repos checked simultaneously
- **Smart pulling:** Only fetches when local is behind remote
- **Logs:** `~/.config/git-auto-pull/pull.log` and `~/.config/git-auto-pull/error.log`

### Testing

Run manually:

```bash
bash ~/.config/git-auto-pull/pull.sh
```

Check status:

```bash
# See what was updated
cat ~/.config/git-auto-pull/pull.log

# Verify service is running
launchctl list | grep gitautopull
```

### Management

```bash
# Stop service
launchctl unload ~/Library/LaunchAgents/com.user.gitautopull.plist

# Start service
launchctl load ~/Library/LaunchAgents/com.user.gitautopull.plist

# Restart after config changes
launchctl unload ~/Library/LaunchAgents/com.user.gitautopull.plist
launchctl load ~/Library/LaunchAgents/com.user.gitautopull.plist
```

### Uninstall

```bash
launchctl unload ~/Library/LaunchAgents/com.user.gitautopull.plist
rm ~/Library/LaunchAgents/com.user.gitautopull.plist
rm -rf ~/.config/git-auto-pull
```

### Machine-Specific Configs

The repos.conf is **not** in dotfiles - it's machine-specific. This allows different repos on different machines while sharing the same script and setup process.

See [git-auto-pull/README.md](../git-auto-pull/README.md) for full documentation.

## LaunchAgent Heartbeat

Lightweight monitor for user LaunchAgents to verify they are loading and running.

### Setup

```bash
cd ~/dotfiles/launchd-heartbeat
bash setup.sh
```

### Configuration

Edit monitored labels:

```bash
nano ~/.config/launchd-heartbeat/monitored-labels.conf
```

Format: one label per line.

### How It Works

- **Interval:** 1 hour (3600 seconds)
- **Checks:** `launchctl print gui/$(id -u)/<label>` for each configured label
- **Heartbeat log:** `~/.config/launchd-heartbeat/heartbeat.log`
- **Error log:** `~/.config/launchd-heartbeat/error.log`

### Testing

```bash
launchctl kickstart -k gui/$(id -u)/com.user.launchdheartbeat
cat ~/.config/launchd-heartbeat/heartbeat.log
```

See [launchd-heartbeat/README.md](../launchd-heartbeat/README.md) for full documentation.

## Future Additions

Possible new utilities:
- `repo-init` - Initialize new repo with standard files
- `backup` - Incremental backup with excludes
- `sync` - Dotfiles sync across machines
- `deps-check` - Verify project dependencies
