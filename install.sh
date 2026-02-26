#!/usr/bin/env zsh

DOTFILES_DIR="$HOME/dotfiles"
BACKUP_ROOT="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups"
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y-%m-%d_%H-%M-%S)"
BACKUP_CREATED=false
DRY_RUN=false

# Runtime-critical dependencies (not install-time)
# These prevent installer from running in broken environments
CRITICAL_DEPS=("git" "zsh")

# Enforce ~/dotfiles location
if [[ "$PWD" != "$HOME/dotfiles" ]]; then
  print -u2 "❌ Please clone dotfiles into ~/dotfiles"
  print -u2 "   Current location: $PWD"
  print -u2 ""
  print -u2 "Example:"
  print -u2 "  git clone https://github.com/bartech-lab/dotfiles.git ~/dotfiles"
  exit 1
fi

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=true
            ;;
        --help|-h)
            echo "Usage: install.sh [--dry-run]"
            echo ""
            echo "Install dotfiles and dependencies"
            echo ""
            echo "Options:"
            echo "  --dry-run    Show what would be installed without making changes"
            echo "  --help       Show this help message"
            exit 0
            ;;
    esac
done

if [[ "$DRY_RUN" == true ]]; then
    echo "🚀 Dotfiles Installer (DRY RUN)"
    echo "================================"
    echo ""
else
    echo "🚀 Installing dotfiles..."
    set -e
fi

# Check runtime-critical dependencies
for dep in "${CRITICAL_DEPS[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
        echo "❌ Critical dependency missing: $dep"
        echo "   This environment cannot run the installer"
        exit 1
    fi
done

# Helper: create backup dir only when needed
ensure_backup_dir() {
    if [[ "$BACKUP_CREATED" == false ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo ""
            echo "Backup:"
            echo "  → Would create: $BACKUP_DIR"
        else
            mkdir -p "$BACKUP_DIR"
            echo ""
            echo "📦 Backup location: $BACKUP_DIR"
            
            # Keep only last 5 backups
            if ls -1d "$BACKUP_ROOT"/* 2>/dev/null | grep -q .; then
                ls -1dt "$BACKUP_ROOT"/* 2>/dev/null | tail -n +6 | xargs -r rm -rf
            fi
        fi
        BACKUP_CREATED=true
    fi
}

# Install Homebrew if missing
if [[ ! -x /opt/homebrew/bin/brew ]]; then
    echo "📦 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Hard guarantee brew works in THIS shell
if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    echo "❌ Homebrew installation failed"
    exit 1
fi

echo "✓ Homebrew ready"

# Check Brewfile packages (dry-run only, with more detail)
if [[ "$DRY_RUN" == true && -f "$DOTFILES_DIR/Brewfile" ]]; then
    echo ""
    echo "Homebrew packages to install:"
    
    # Cache brew lists once for fast lookup
    installed_formulae=$(brew list --formula 2>/dev/null)
    installed_casks=$(brew list --cask 2>/dev/null)
    
    missing=0
    while read -r type name; do
        if [[ "$type" == "brew" ]]; then
            if ! echo "$installed_formulae" | grep -qx "$name"; then
                echo "  → $name"
                ((missing++))
            fi
        else
            if ! echo "$installed_casks" | grep -qx "$name"; then
                echo "  → $name (cask)"
                ((missing++))
            fi
        fi
    done < <(
        rg '^(brew|cask)[[:space:]]+"' "$DOTFILES_DIR/Brewfile" |
        sed -E 's/^(brew|cask)[[:space:]]+"([^"]+)".*/\1 \2/'
    )
    
    if [[ $missing -eq 0 ]]; then
        echo "  ✓ All Brewfile packages already installed"
    fi
fi

# Install Homebrew dependencies (actual run)
if [[ "$DRY_RUN" == false && -f "$DOTFILES_DIR/Brewfile" ]]; then
    echo "📦 Installing Homebrew packages (this may take a minute)..."

    # Ensure bundle tap is available (required for brew bundle)
    brew tap homebrew/bundle 2>/dev/null || true

    set +e
    brew_output=$(brew bundle --file="$DOTFILES_DIR/Brewfile" 2>&1)
    brew_status=$?
    set -e

    # Parse results using ripgrep if available, fallback to grep
    if command -v rg > /dev/null 2>&1; then
        match() { rg -c "$1" <<< "$brew_output" 2>/dev/null || echo 0; }
        filter() { rg "$1" <<< "$brew_output" 2>/dev/null; }
    else
        match() { grep -c "$1" <<< "$brew_output" 2>/dev/null || echo 0; }
        filter() { grep -E "$1" <<< "$brew_output" 2>/dev/null; }
    fi

    installed=$(match '^Installing'); installed=${installed:-0}
    upgraded=$(match '^Upgrading'); upgraded=${upgraded:-0}
    failed=$(match 'Error|failed|Failure|Warning'); failed=${failed:-0}

    if (( brew_status == 0 )); then
        if (( installed > 0 || upgraded > 0 )); then
            echo "✓ Brew updated: $installed installed, $upgraded upgraded"
        else
            echo "✓ Brew already up to date"
        fi
    else
        echo "✗ Brew bundle failed (exit code: $brew_status)"
    fi

    # Show errors if any
    if (( brew_status != 0 || failed > 0 )); then
        echo ""
        echo "⚠️ Brew reported issues:"
        filter 'Error|failed|Failure|Warning'
    fi
fi

# Create ~/.config if needed
if [[ ! -d ~/.config ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo "Directories:"
        echo "  → Would create: ~/.config"
    else
        mkdir -p ~/.config
        echo "✓ Created ~/.config"
    fi
fi

# Backup existing loader if present (not symlink)
if [[ -f ~/.config/zsh-dotfiles-loader.zsh && ! -L ~/.config/zsh-dotfiles-loader.zsh ]]; then
    ensure_backup_dir
    if [[ "$DRY_RUN" == true ]]; then
        echo "  → Would backup: ~/.config/zsh-dotfiles-loader.zsh"
    else
        cp ~/.config/zsh-dotfiles-loader.zsh "$BACKUP_DIR/"
        echo "✓ Backed up existing zsh-dotfiles-loader.zsh"
    fi
fi

# Symlink the functions loader
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "Symlinks:"
    if [[ -L ~/.config/zsh-dotfiles-loader.zsh ]]; then
        echo "  → Would update: ~/.config/zsh-dotfiles-loader.zsh → $DOTFILES_DIR/zsh/functions.zsh"
    else
        echo "  → Would create: ~/.config/zsh-dotfiles-loader.zsh → $DOTFILES_DIR/zsh/functions.zsh"
    fi
else
    if [[ -L ~/.config/zsh-dotfiles-loader.zsh ]]; then
        ln -sf "$DOTFILES_DIR/zsh/functions.zsh" ~/.config/zsh-dotfiles-loader.zsh
        echo "✓ Updated loader symlink"
    else
        ln -sf "$DOTFILES_DIR/zsh/functions.zsh" ~/.config/zsh-dotfiles-loader.zsh
        echo "✓ Linked functions loader"
    fi
fi

# Add to .zshrc if not present
if ! grep -q "zsh-dotfiles-loader.zsh" ~/.zshrc 2>/dev/null; then
    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo "Shell integration:"
        echo "  → Would add to ~/.zshrc: source ~/.config/zsh-dotfiles-loader.zsh"
    else
        echo "" >> ~/.zshrc
        echo "# Load dotfiles functions" >> ~/.zshrc
        echo 'source ~/.config/zsh-dotfiles-loader.zsh' >> ~/.zshrc
        echo "✓ Added loader to ~/.zshrc"
    fi
fi

# Count available functions
func_count=$(find "$DOTFILES_DIR/zsh/functions" -name "*.zsh" -type f 2>/dev/null | wc -l | tr -d ' ')

if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "📝 Dry run complete - No changes made"
    echo "Run without --dry-run to install"
else
    echo ""
    echo "✅ Dotfiles installed"
    echo "✓ Functions loaded: $func_count"
    echo ""
    echo "Run: dotfiles-doctor if anything fails"
    echo "Run: macos-defaults to apply system preferences"
fi
echo ""
