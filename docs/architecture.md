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
│       ├── 66-discord.zsh    # Discord OpenAsar helpers
│       └── 70-opencode.zsh   # OpenCode helpers
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
66-*.zsh         → Eighth (discord)
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

### Adding New Dependencies

Edit `Brewfile`:
```ruby
# Add new tool
brew "new-tool"
```

Then run:
```bash
brew bundle --file=~/dotfiles/Brewfile
```

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
