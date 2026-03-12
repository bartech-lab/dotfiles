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

AUTOUPDATE_INTERVAL=86400

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

# Configure Homebrew autoupdate (once per day)
autoupdate_status=$(brew autoupdate status 2>&1 || true)

if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "Homebrew autoupdate:"
    if [[ "$autoupdate_status" == *"installed and running"* ]]; then
        echo "  → Already running; would keep existing autoupdate settings"
    else
        echo "  → Would run: brew autoupdate start $AUTOUPDATE_INTERVAL --upgrade --cleanup"
    fi
else
    echo ""
    echo "🔄 Configuring Homebrew autoupdate..."

    if [[ "$autoupdate_status" == *"installed and running"* ]]; then
        echo "✓ Homebrew autoupdate already running"
    else
        set +e
        autoupdate_start_output=$(brew autoupdate start "$AUTOUPDATE_INTERVAL" --upgrade --cleanup 2>&1)
        autoupdate_start_status=$?
        set -e

        if (( autoupdate_start_status == 0 )); then
            echo "✓ Homebrew autoupdate enabled (daily upgrade + cleanup)"
        else
            echo "⚠️ Failed to enable Homebrew autoupdate"
            echo "$autoupdate_start_output"
        fi
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

# Backup existing global gitignore if present (not symlink)
if [[ -f ~/.gitignore_global && ! -L ~/.gitignore_global ]]; then
    ensure_backup_dir
    if [[ "$DRY_RUN" == true ]]; then
        echo "  → Would backup: ~/.gitignore_global"
    else
        cp ~/.gitignore_global "$BACKUP_DIR/"
        echo "✓ Backed up existing .gitignore_global"
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
    if [[ -L ~/.gitignore_global ]]; then
        echo "  → Would update: ~/.gitignore_global → $DOTFILES_DIR/git/gitignore_global"
    else
        echo "  → Would create: ~/.gitignore_global → $DOTFILES_DIR/git/gitignore_global"
    fi
    if [[ -L ~/.config/zsh-dotfiles-loader.zsh ]]; then
        echo "  → Would update: ~/.config/zsh-dotfiles-loader.zsh → $DOTFILES_DIR/zsh/functions.zsh"
    else
        echo "  → Would create: ~/.config/zsh-dotfiles-loader.zsh → $DOTFILES_DIR/zsh/functions.zsh"
    fi
else
    if [[ -L ~/.gitignore_global ]]; then
        ln -sf "$DOTFILES_DIR/git/gitignore_global" ~/.gitignore_global
        echo "✓ Updated global gitignore symlink"
    else
        ln -sf "$DOTFILES_DIR/git/gitignore_global" ~/.gitignore_global
        echo "✓ Linked global gitignore"
    fi

    if [[ -L ~/.config/zsh-dotfiles-loader.zsh ]]; then
        ln -sf "$DOTFILES_DIR/zsh/functions.zsh" ~/.config/zsh-dotfiles-loader.zsh
        echo "✓ Updated loader symlink"
    else
        ln -sf "$DOTFILES_DIR/zsh/functions.zsh" ~/.config/zsh-dotfiles-loader.zsh
        echo "✓ Linked functions loader"
    fi
fi

# Ghostty config
GHOSTTY_CONFIG_DIR="$HOME/Library/Application Support/com.mitchellh.ghostty"
GHOSTTY_CONFIG="$GHOSTTY_CONFIG_DIR/config"

if [[ -f "$GHOSTTY_CONFIG" && ! -L "$GHOSTTY_CONFIG" ]]; then
    ensure_backup_dir
    if [[ "$DRY_RUN" == true ]]; then
        echo "  → Would backup: $GHOSTTY_CONFIG"
    else
        cp "$GHOSTTY_CONFIG" "$BACKUP_DIR/ghostty-config"
        echo "✓ Backed up existing Ghostty config"
    fi
fi

if [[ "$DRY_RUN" == true ]]; then
    if [[ -L "$GHOSTTY_CONFIG" ]]; then
        echo "  → Would update: $GHOSTTY_CONFIG → $DOTFILES_DIR/ghostty/config"
    else
        echo "  → Would create: $GHOSTTY_CONFIG → $DOTFILES_DIR/ghostty/config"
    fi
else
    mkdir -p "$GHOSTTY_CONFIG_DIR"
    ln -sf "$DOTFILES_DIR/ghostty/config" "$GHOSTTY_CONFIG"
    echo "✓ Linked Ghostty config"
fi

# Ghostty XDG config (in addition to macOS path)
XDG_GHOSTTY_DIR="$HOME/.config/ghostty"
XDG_GHOSTTY_CONFIG="$XDG_GHOSTTY_DIR/config"

if [[ -f "$XDG_GHOSTTY_CONFIG" && ! -L "$XDG_GHOSTTY_CONFIG" ]]; then
    ensure_backup_dir
    if [[ "$DRY_RUN" == true ]]; then
        echo "  → Would backup: $XDG_GHOSTTY_CONFIG"
    else
        cp "$XDG_GHOSTTY_CONFIG" "$BACKUP_DIR/ghostty-xdg-config"
        echo "✓ Backed up existing XDG Ghostty config"
    fi
fi

if [[ "$DRY_RUN" == true ]]; then
    if [[ -L "$XDG_GHOSTTY_CONFIG" ]]; then
        echo "  → Would update: $XDG_GHOSTTY_CONFIG → $DOTFILES_DIR/ghostty/config"
    else
        echo "  → Would create: $XDG_GHOSTTY_CONFIG → $DOTFILES_DIR/ghostty/config"
    fi
else
    mkdir -p "$XDG_GHOSTTY_DIR"
    ln -sf "$DOTFILES_DIR/ghostty/config" "$XDG_GHOSTTY_CONFIG"
    echo "✓ Linked XDG Ghostty config"
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

# Pre-download gitstatus binary to prevent console output on first run
# This ensures gitstatusd is ready before the first interactive shell session
if [[ "$DRY_RUN" == false ]]; then
    GITSTATUS_CACHE="$HOME/.cache/gitstatus"
    ARCH=$(uname -m)
    
    if [[ ! -f "$GITSTATUS_CACHE/gitstatusd-darwin-$ARCH" ]]; then
        # Try multiple locations where powerlevel10k might be installed
        p10k_paths=(
            "$HOME/.zinit/plugins/romkatv---powerlevel10k"
            "/opt/homebrew/opt/powerlevel10k"
            "/usr/local/opt/powerlevel10k"
        )
        
        for p10k_path in "${p10k_paths[@]}"; do
            if [[ -f "$p10k_path/gitstatus/install" ]]; then
                echo "Pre-caching gitstatus binary..."
                mkdir -p "$GITSTATUS_CACHE"
                # Run install script silently (downloads prebuilt binary)
                (cd "$p10k_path/gitstatus" && CC= CXX= ./install -f >/dev/null 2>&1) || true
                
                if [[ -f "$GITSTATUS_CACHE/gitstatusd-darwin-$ARCH" ]]; then
                    echo "✓ Gitstatus binary cached"
                fi
                break
            fi
        done
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
    echo "Run: macos-debloat to remove bloatware (destructive)"
    echo "Run: macos-system-analysis to review services"
    echo ""
    echo "📌 TG Pro: install manually → https://www.tunabellysoftware.com/tgpro/"
fi
echo ""
