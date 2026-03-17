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

Apply comprehensive macOS system preferences optimized for development.

```bash
macos-defaults              # Apply all system defaults
macos-defaults-export       # Export current settings to a script
macos-disable-notification-sounds [--dry-run] [--verbose] [--exclude "App Name"]
```

**Changes:**

#### Dock
- Auto-hide with immediate appearance (no delay)
- Tile size: 66 pixels
- Show indicator lights for open applications
- Fast animation (0.15s)
- Translucent icons for hidden applications
- No recent applications section
- Fast Mission Control animations (0.1s)
- Don't auto-rearrange Spaces
- Scale minimize effect (faster than genie)
- Minimize to application icon
- No launch animation

#### Finder
- Show path bar and status bar
- Show all filename extensions
- Keep folders on top when sorting
- Search current folder by default
- Disable extension change warnings
- Disable all animations
- Show full POSIX path in title bar
- Allow quitting with ⌘Q
- New window opens to ~/timac/
- Show Library folder (~/Library)
- No .DS_Store files on network or USB volumes

#### Screenshots & Screen Recording
- **Screenshots**: Go to clipboard (⌘V to paste)
- **Screen Recordings**: Save to file in ~/Downloads
- PNG format (better quality)
- No window shadow
- No floating thumbnail (captures immediately)

#### Keyboard & Typing
- Disable press-and-hold (enables key repeat)
- Fast key repeat rate (2 = fast, between default and blazing)
- Short delay before repeat (10 = shortest)
- Full keyboard access (Tab in dialogs)
- Disable auto-capitalization
- Disable smart dashes
- Disable auto-period (double-space)
- Disable smart quotes
- Disable auto-correct

#### UI/UX
- Fast window resizing (0.001s)
- Expanded save and print panels
- Always show scrollbars
- Disable focus ring animation
- Disable "Are you sure?" dialog for downloaded apps

#### Trackpad
- Enable tap to click

#### System
- Disable boot sound
- Show IP/hostname/OS version in login window (click clock)

#### Hot Corners
- All corners disabled (no accidental triggers)

#### Photos
- Don't auto-open when devices are plugged in

#### Chrome
- Disable backswipe on trackpad (prevents accidental navigation)
- Use system-native print dialog

#### VS Code
- Disable press-and-hold for key repeat
- Disable native full screen (use macOS full screen)

#### Spotify
- Disable auto-start on login

#### Docker Desktop
- Disable automatic startup
- Disable analytics

#### Slack
- Disable spell checking
- Disable smart quotes and dashes

**Exporting settings:**
```bash
# Export current settings to a backup script
macos-defaults-export > ~/macos-backup.sh

# Later, restore on another machine
zsh ~/macos-backup.sh
```

### macos-disable-notification-sounds

Disable `Play sound for notification` for every app listed in `System Settings > Notifications`.

```bash
macos-disable-notification-sounds
macos-disable-notification-sounds --dry-run --verbose
macos-disable-notification-sounds --exclude "Microsoft Defender"
macos-disable-notification-sounds --list
```

Options:
- `--dry-run` - report what would change without toggling anything
- `--verbose` - print per-app progress, including already-off entries
- `--exclude "App Name"` - skip an exact app name as shown in Notifications; repeat as needed
- `--list` - print discovered notification entries and exit

Behavior:
- Opens the Notifications pane automatically and walks each app entry
- Turns off notification sounds where macOS allows it
- Skips apps that are locked, disabled, or managed by MDM instead of failing the whole run
- Requires Accessibility access for your terminal app because it automates System Settings

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

Clean up detached opencode processes (safe with multiple terminals).

```bash
opencode-clean        # Clean detached processes
ocfix                 # Alias for opencode-clean
```

**What it does:**
- Scans all opencode processes
- Keeps processes attached to terminals (active sessions)
- Only terminates detached processes (not attached to any TTY)
- Uses graceful termination (TERM) first, then force kill (KILL) if needed
- Safe to use with multiple Ghostty tabs open

**When to use:**
- When you notice high kernel_task CPU usage
- When opencode processes accumulate over time
- When system feels sluggish due to zombie processes

### ecc

Launch Everything Claude Code (ECC) profile with auto-update check.

```bash
ecc                   # Start ECC (checks for updates first)
```

**Features:**
- Automatically checks for ECC updates on launch
- Prompts to update if new version available
- Preserves your model settings during updates
- Full ECC workflow: planning, TDD, code review, security

**Available commands in ECC:**
- `/plan` — Create implementation plans
- `/tdd` — Test-driven development workflow
- `/code-review` — Code quality review
- `/security` — Security vulnerability scan
- `/build-fix` — Fix build errors
- `/e2e` — Playwright E2E tests
- Plus 20+ more commands

**Configuration:**
- Settings stored in: `~/.config/opencode/profiles/ecc/user-settings.json`
- Models: Claude Opus for planning/security/TDD, Sonnet for reviews
- Auto-merges your settings during updates

### ecc-update

Force update ECC to latest version (preserves your settings).

```bash
ecc-update            # Update ECC now
```

**What it does:**
- Pulls latest ECC from GitHub
- Reinstalls commands, agents, and tools
- Backs up current config before update
- Merges your `user-settings.json` into new config
- Uses `jq` for safe JSON merging

### ecc-status

Check ECC repository status and update availability.

```bash
ecc-status            # Show ECC status
```

**Output:**
- Current commit hash
- Branch name
- Update availability status

### ecc-clean

Clean up ECC backup files.

```bash
ecc-clean             # Remove old backups
```

**Backup location:** `~/.config/opencode/profiles/ecc/.backup/`

**When to use:**
- After successful updates to free disk space
- When backups accumulate over time

### ecc-upgrade

Alias for `ecc-update`.

```bash
ecc-upgrade           # Same as ecc-update
```

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
- Task runners (.sisyphus)
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

## Discord Utilities

### discord-openasar-setup

Manual, opt-in setup for persistent OpenAsar on Discord updates.

```bash
discord-openasar-setup [--app <Discord.app path>] [--refresh-openasar] [--no-theme]
```

**Options:**
- `--app <path>` - Target app bundle (`/Applications/Discord.app` by default)
- `--refresh-openasar` - Re-download latest OpenAsar nightly
- `--no-theme` - Skip syncing custom CSS to OpenAsar settings

### discord-openasar-status

Show LaunchAgent state for automatic OpenAsar reapply.

```bash
discord-openasar-status
```

For the full workflow and file paths, see [discord-openasar.md](discord-openasar.md).

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
| Discord | `66-discord.zsh` | OpenAsar setup/status helpers |
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
