# Architecture

How this dotfiles setup works.

## Directory Structure

```
dotfiles/
├── docs/                      # Documentation
│   ├── install.md            # Installation guide
│   ├── architecture.md       # This file
│   ├── functions.md          # Function reference
│   ├── media.md              # Media functions
│   ├── dev.md                # Development utilities
│   └── discord-openasar.md   # Optional Discord OpenAsar setup
├── discord/
│   └── openasar/
│       ├── aggressive-minimal.css          # Optional OpenAsar custom CSS
│       ├── dev.openasar.reapply.plist.template  # LaunchAgent template
│       └── reapply-openasar.sh             # Reapply script for updates
├── git/
│   └── gitignore_global      # Global Git ignore rules
├── git-auto-pull/            # Automatic git repo syncing
│   ├── pull.sh               # Main syncing script
│   ├── setup.sh              # One-time setup for new machines
│   └── README.md             # Component documentation
├── launchd-heartbeat/        # LaunchAgent health heartbeat
│   ├── heartbeat.sh          # Main heartbeat script
│   ├── setup.sh              # One-time setup for new machines
│   └── README.md             # Component documentation
├── zsh/
│   ├── functions.zsh         # Main loader (sources all files)
│   └── functions/            # Individual function files
│       ├── 00-core.zsh       # Zsh plugins and theme
│       ├── 10-shell.zsh      # Modern CLI aliases
│       ├── 20-brew.zsh       # Homebrew functions
│       ├── 30-git.zsh        # Git helpers
│       ├── 40-dev.zsh        # Development utilities
│       ├── 50-media.zsh      # Media processing
│       ├── 60-macos.zsh      # macOS system functions
│       ├── 61-discord.zsh    # Discord OpenAsar helpers
│       └── 70-opencode.zsh   # OpenCode helpers (launch + cleanup)
├── install.sh                # One-command installer
├── Brewfile                  # Homebrew dependencies
└── README.md                 # Project entry point
```

## Loading Order

Functions load in a specific sequence controlled by filenames:

```
00-core.zsh      → First (zinit, powerlevel10k)
10-*.zsh         → Second (shell)
20-*.zsh         → Third (brew)
30-*.zsh         → Fourth (git)
40-*.zsh         → Fifth (dev)
50-*.zsh         → Sixth (media)
60-*.zsh         → Seventh (macos)
61-*.zsh         → Eighth (discord)
70-*.zsh         → Ninth (opencode)
```

The numbered prefix ensures consistent loading regardless of filesystem order.

## How Functions Load

### 1. Symlink Creation

```bash
~/.gitignore_global → ~/dotfiles/git/gitignore_global
~/.config/zsh-dotfiles-loader.zsh → ~/dotfiles/zsh/functions.zsh
```

### 2. Zshrc Integration

Your `~/.zshrc` contains:
```zsh
source ~/.config/zsh-dotfiles-loader.zsh
```

### 3. Functions.zsh Loader

This file:
- Sets up function path
- Sources all numbered files from `functions/`
- Loads zsh plugins in correct order

## Critical Design Decisions

### Why Symlinks?

- Allows updating dotfiles via `git pull`
- No need to reinstall when functions change
- Atomic updates (just pull, restart shell)

### Why Numbered Files?

- Core (plugins) must load before aliases
- Syntax highlighting must load last
- Clear dependency ordering

### Why Functions Instead of Aliases?

Most commands are functions, not aliases, because:
- Functions can have help text
- Functions can parse arguments
- Functions can have logic (conditionals, loops)

Example: `archive()` has `--dry-run` and `-gzip` flags.

### Why Brewfile?

- Single source of truth for dependencies
- Reproducible installations
- `brew bundle` installs everything at once
- Easy to audit what's installed

## Security Considerations

### Secrets Handling

- **Never** store secrets in dotfiles
- Functions that need secrets read from environment
- `.env` files are in .gitignore and archive excludes

### Safe Defaults

- Install script has `--dry-run` mode (see [dev.md](dev.md))
- `repo-check` validates before archiving
- All destructive operations have confirmation

## Extending This Setup

### Adding New Functions

1. Create file in `zsh/functions/`:
    ```bash
    touch zsh/functions/80-docker.zsh
    ```

2. Add your functions:
    ```zsh
    # zsh/functions/80-docker.zsh
   docker-clean() {
       docker system prune -f
   }
   ```

3. Reload or restart shell

## Platform Detection

The variable `$DOTFILES_OS` is set at shell startup in `zsh/zshrc.zsh`:

```zsh
case "$(uname -s)" in
  Darwin) export DOTFILES_OS=macos ;;
  Linux)  export DOTFILES_OS=linux ;;
esac
```

This is used throughout the codebase to:
- Skip macOS-only function files on Linux (`zsh/functions.zsh` loader)
- Branch PATH configuration for Homebrew vs native paths
- Select platform-appropriate CLI tools (pbcopy vs xclip/wl-copy)
- Choose GPU encoders (videotoolbox vs vaapi)
- Prevent macOS-specific script execution on Linux (migration, calfix)

### Loading Order (Post-Linux Support)

```
~/.zshrc
  └─ source ~/.config/zsh-dotfiles-loader.zsh
       └─ source zsh/functions.zsh
            ├─ source zsh/zshrc.zsh              ← SETS DOTFILES_OS
            ├─ source 00-core.zsh                ← zinit (cross-platform)
            ├─ source 10-shell.zsh               ← aliases + cpwd()
            ├─ source 20-brew.zsh                ← SKIPS on Linux
            ├─ source 21-pacman.zsh              ← SKIPS on macOS
            ├─ source 30-git.zsh                 ← cross-platform
            ├─ source 40-dev.zsh                 ← cross-platform (guarded checks)
            ├─ source 50-media.zsh               ← platform encoder
            ├─ source 51-download.zsh            ← cross-platform
            ├─ SKIP 60-macos.zsh on Linux
            ├─ source 61-discord.zsh             ← platform paths
            ├─ source 62-kde.zsh                 ← SKIPS on macOS
            └─ source 70-opencode.zsh            ← cross-platform
```

### Adding New Dependencies

**macOS**: Edit `Brewfile`
```ruby
# Add new tool
brew "new-tool"
```

**Linux**: Edit `pkglist/pacman.txt` (official repos) or `pkglist/aur.txt` (AUR).

### Linux Package Management

Instead of Homebrew, Linux uses pacman/yay natively:

- `pkglist/pacman.txt` — official repository packages (one per line)
- `pkglist/aur.txt` — AUR packages installed via yay

Background services use systemd user timers instead of LaunchAgents:
- `git-auto-pull/systemd/` — `.service` + `.timer` for hourly git sync
- `launchd-heartbeat/systemd/` — `.service` + `.timer` for service heartbeat

### Customizing Shell Theme

Edit `zsh/functions/00-core.zsh`:
- Change powerlevel10k configuration
- Modify prompt segments
- Adjust colors

## Performance

### Startup Time

- Zinit loads plugins asynchronously
- Functions are lazy-loaded (defined, not executed)
- Total shell startup: ~100-200ms

### What Gets Loaded When?

**Shell startup:**
- Functions.zsh (loader)
- Plugin manager (zinit)
- All function files

**Command execution:**
- Function body only runs when called
- No background processes
- No polling

## Testing Changes

Before committing function changes:

```bash
# Reload current shell
source ~/.zshrc

# Or open new terminal tab
```

Test edge cases:
```bash
# Does it handle missing args?
your-function

# Does it handle special characters?
your-function "file with spaces"

# Does dry-run work?
your-function --dry-run
```

## Debugging

### Function Not Found?

```bash
# Check if function is defined
type function-name

# See where it's defined
grep -r "function-name" ~/dotfiles/zsh/functions/

# Check load order
echo $fpath
```

### Plugin Not Loading?

```bash
# Check zinit status
zinit list

# Reload plugins
zinit update
```

### See Full Load Sequence

Add to top of `~/.zshrc`:
```zsh
zmodload zsh/zprof
```

And at bottom:
```zsh
zprof
```

## Philosophy

This dotfiles setup follows these principles:

1. **Minimal magic** - Everything is explicit and traceable
2. **Self-documenting** - Functions have clear names and usage
3. **Fail-safe** - Destructive operations require confirmation
4. **Reversible** - Easy to uninstall, no system modifications
5. **Maintainable** - Clear structure, one purpose per file
