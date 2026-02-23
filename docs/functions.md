# Functions Reference

Complete reference for all shell functions and aliases.

## Modern CLI Replacements

These replace default macOS commands with modern alternatives:

### File Listing (eza)

| Command | Description |
|---------|-------------|
| `ls` | List files with icons, directories first |
| `ll` | Detailed list with icons, human-readable sizes |
| `lt` | Tree view (2 levels deep) with icons |

**Examples:**
```bash
ls                    # Basic listing
ls -la               # All files including hidden
ll                   # Detailed view
lt                   # Tree view
lt -L 3              # Tree with 3 levels
```

### Text Search (ripgrep)

**Note:** Not aliased to `grep` to avoid breaking scripts. Use `rg` directly.

| Command | Description |
|---------|-------------|
| `rg` | Fast search with smart defaults |

**Examples:**
```bash
rg "pattern"           # Search in current directory
rg -i "pattern"        # Case-insensitive
rg -t md "TODO"        # Only markdown files
rg -l "pattern"        # Just filenames
rg -C 3 "pattern"      # 3 lines of context
```

### System Monitoring (bottom)

| Command | Description |
|---------|-------------|
| `top` | Modern system monitor with graphs |

**Features:**
- Process tree view
- CPU/Memory/Disk graphs
- Mouse support
- Temperature monitoring

### Disk Usage (dust)

| Command | Description |
|---------|-------------|
| `du` | Visual disk usage, sorted by size |

**Examples:**
```bash
du                   # Current directory
du -d 3             # Max depth 3
du ~/Downloads      # Specific directory
```

### Disk Free (duf)

| Command | Description |
|---------|-------------|
| `df` | Modern disk free viewer |

**Features:**
- Colorful output
- Sortable columns
- Mount point filtering

## Git Functions

### git-cleanup

Clean up git repository by removing merged branches and old stashes.

```bash
git-cleanup           # Clean merged branches and stashes
```

**What it does:**
- Removes branches already merged to main/master
- Clears old stashes
- Runs `git gc` for optimization

### git-open

Open current repository in browser.

```bash
git-open              # Open in GitHub/GitLab/Bitbucket
```

**Supports:** GitHub, GitLab, Bitbucket, Azure DevOps

**Handles:** SSH remotes automatically

## macOS Functions

### macos-defaults

Apply macOS system preferences.

```bash
macos-defaults        # Apply system defaults
```

**Changes:**
- Finder: Show path bar
- Dock: Auto-hide
- Screenshots: Save to Downloads, disable shadow
- Automatically restarts Finder and Dock

### cpwd

Copy current directory path to clipboard.

```bash
cpwd                  # Copy $PWD to clipboard
```

Handy for:
- Sharing paths in documentation
- Pasting into file dialogs
- Copying for remote commands

## Homebrew Functions

### brewup

Complete Homebrew maintenance.

```bash
brewup                # Update, upgrade, cleanup
```

**What it does:**
1. Updates Homebrew itself
2. Upgrades all formulae and casks
3. Cleans up old versions

**Note:** Does NOT run `brew bundle`. Run that separately when you want to sync packages with Brewfile.

## OpenCode Functions

### opencode

Launch OpenCode with default profile.

```bash
opencode              # Start OpenCode
```

### omo

Launch Oh-My-OpenCode profile.

```bash
omo                   # Oh-My-OpenCode
```

### oac

Launch OpenAgentsControl profile.

```bash
oac                   # OpenAgentsControl
```

### ocp

List all available OpenCode profiles.

```bash
ocp                   # List profiles
```

### ocx-profile

Launch OpenCode with specific profile.

```bash
ocx-profile <name>    # Use specific profile
```

### opencode-clean / ocfix

Clean up orphaned opencode processes (safe with multiple terminals).

```bash
opencode-clean        # Clean orphaned processes
ocfix                 # Alias for opencode-clean
```

**What it does:**
- Scans all opencode processes
- Keeps processes attached to terminals (active sessions)
- Only terminates orphaned processes (PPID=1, adopted by launchd)
- Uses graceful termination (TERM) first, then force kill (KILL) if needed
- Safe to use with multiple Ghostty tabs open

**When to use:**
- When you notice high kernel_task CPU usage
- When opencode processes accumulate over time
- When system feels sluggish due to zombie processes

## Development Utilities

### extract

Universal archive extractor.

```bash
extract <archive-file>
```

**Supported formats:** tar.bz2, tar.gz, tar.zst, tar.xz, bz2, rar, gz, tar, zip, Z, 7z, xz

**Features:**
- Auto-detects format from extension
- Creates directory named after archive
- Handles name collisions (archive-2/, archive-3/, etc.)
- Uses `unar` for zip, rar, 7z

**Examples:**
```bash
extract archive.tar.zst    # Extract to archive/
extract file.zip           # Extract to file/
extract "My File.tar.gz"   # Handles spaces
```

### archive

Create reproducible archives.

```bash
archive [name] [--dry-run] [-gzip]
```

**Options:**
- `name` - Archive name (defaults to current directory name)
- `--dry-run` or `-n` - Preview what would be archived
- `-gzip` - Use gzip -6 instead of zstd (creates .tar.gz)

**Default compression:** zstd -19 (creates .tar.zst)

**Exclusions:**
- Development artifacts (.git, .vscode, node_modules)
- Build output (dist, build, target)
- Caches and temp files
- Other archives

**Examples:**
```bash
archive                          # Create name-YYYYMMDD-HHMM.tar.zst
archive myproject                # Create myproject-*.tar.zst
archive --dry-run                # Preview what would be archived
archive -gzip                    # Create .tar.gz with gzip -6
archive myproject -gzip          # Create myproject-*.tar.gz
```

### repo-check

Pre-archive sanity checker (see [dev.md](dev.md)).

```bash
repo-check              # Check for issues before archiving
```

## Optional Tools

These tools are installed but **not activated** for interactive use:

### fzf

Fuzzy finder for interactive file/command selection.

**To enable:**
```bash
echo 'eval "$(fzf --zsh)"' >> ~/.zshrc
```

**Usage:**
```bash
Ctrl+R    # Search command history
Ctrl+T    # Find files
Alt+C     # Change directory
```

### zoxide

Smart directory jumper.

**To enable:**
```bash
echo 'eval "$(zoxide init zsh)"' >> ~/.zshrc
```

**Usage:**
```bash
z foo      # Jump to most frequent directory matching "foo"
zi         # Interactive selection
z foo bar  # Jump to directory matching "foo" and "bar"
```

## Environment Diagnostics

### dotfiles-doctor

Comprehensive health check for your dotfiles environment.

```bash
dotfiles-doctor        # Run full diagnostics
```

Checks:
- Homebrew installation
- Critical tool availability
- Loader symlink validity
- PATH ordering
- Shell plugins
- Fonts for powerlevel10k

See [dev.md](dev.md) for full documentation.

## Function Categories

| Category | File | Description |
|----------|------|-------------|
| Core | `00-core.zsh` | Zsh plugins and theme |
| Shell | `10-shell.zsh` | Modern CLI aliases |
| Brew | `20-brew.zsh` | Homebrew functions |
| Git | `30-git.zsh` | Git helpers |
| Dev | `40-dev.zsh` | Development utilities |
| Media | `50-media.zsh` | Image/video processing |
| macOS | `60-macos.zsh` | System functions |
| OpenCode | `70-opencode.zsh` | OpenCode helpers |

## Adding Custom Functions

1. Create a file in `zsh/functions/`:
   ```bash
   touch zsh/functions/80-custom.zsh
   ```

2. Add your function:
   ```zsh
   my-function() {
       echo "Hello from my function!"
   }
   ```

3. Reload:
   ```bash
   source ~/.zshrc
   ```

## Help

For more details on specific function categories:

- [Media functions](media.md) - Video/image processing
- [Development utilities](dev.md) - Archive, extract, diagnostics
