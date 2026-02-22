#!/bin/bash

DOTFILES_DIR="$HOME/dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"
DRY_RUN=false

# Enforce ~/dotfiles location
if [[ "$PWD" != "$HOME/dotfiles" ]]; then
  print -u2 "❌ Please clone dotfiles into ~/dotfiles"
  print -u2 "   Current location: $PWD"
  exit 1
fi

# Critical dependencies that must be present
# Note: cjpeg is the binary from mozjpeg package
CRITICAL_DEPS=("eza" "rg" "dust" "btm" "duf" "parallel" "ffmpeg" "cjpeg" "zstd" "gtar")

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

# Install Homebrew if not present
if ! command -v brew &>/dev/null; then
    if [[ "$DRY_RUN" == true ]]; then
        echo "Homebrew:"
        echo "  → Would install Homebrew"
        echo "  → Would configure PATH for Apple Silicon"
    else
        echo "📦 Homebrew not found. Installing..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Add to PATH for Apple Silicon Macs
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        elif [[ -f /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
        echo "✓ Homebrew installed"
    fi
else
    if [[ "$DRY_RUN" == true ]]; then
        echo "Homebrew:"
        echo "  ✅ Already installed ($(brew --version | head -1))"
    fi
fi

# Determine backup location
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "Backup:"
    echo "  → Would create: $BACKUP_DIR"
else
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    echo "📦 Backup location: $BACKUP_DIR"
fi

# Install Homebrew dependencies if Brewfile exists
if [[ -f "$DOTFILES_DIR/Brewfile" ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo "Homebrew packages to install:"
        # Parse Brewfile and show what would be installed
        while IFS= read -r line; do
            # Skip comments and empty lines
            [[ "$line" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$line" ]] && continue
            
            # Extract package names
            if [[ "$line" =~ ^brew[[:space:]]+["\']([^"\']+)["\'] ]]; then
                local pkg="${BASH_REMATCH[1]}"
                if ! command -v "$pkg" &>/dev/null 2>&1; then
                    echo "  → $pkg"
                fi
            elif [[ "$line" =~ ^cask[[:space:]]+["\']([^"\']+)["\'] ]]; then
                local cask="${BASH_REMATCH[1]}"
                echo "  → $cask (cask)"
            fi
        done < "$DOTFILES_DIR/Brewfile"
    else
        echo "📦 Installing Homebrew packages..."
        brew bundle --file="$DOTFILES_DIR/Brewfile" || {
            echo "⚠️ Some Brewfile entries may have failed (check above)"
        }
    fi
else
    echo "⚠️ No Brewfile found. Skipping package installation."
fi

# Create necessary directories
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "Directories:"
    echo "  → Would create: ~/.config"
else
    mkdir -p ~/.config
    echo "✓ Created ~/.config"
fi

# Backup existing loader if present (not symlink)
if [[ -f ~/.config/zsh-dotfiles-loader.zsh && ! -L ~/.config/zsh-dotfiles-loader.zsh ]]; then
    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo "Existing config:"
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
        # Update existing symlink
        ln -sf "$DOTFILES_DIR/zsh/functions.zsh" ~/.config/zsh-dotfiles-loader.zsh
        echo "✓ Updated existing symlink"
    else
        ln -sf "$DOTFILES_DIR/zsh/functions.zsh" ~/.config/zsh-dotfiles-loader.zsh
        echo "✓ Linked functions loader"
    fi
fi

# Add to .zshrc if not present
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "Shell integration:"
    if ! grep -q "zsh-dotfiles-loader.zsh" ~/.zshrc 2>/dev/null; then
        echo "  → Would add to ~/.zshrc:"
        echo "     # Load dotfiles functions"
        echo "     source ~/.config/zsh-dotfiles-loader.zsh"
    else
        echo "  ✅ Already sourced in ~/.zshrc"
    fi
else
    if ! grep -q "zsh-dotfiles-loader.zsh" ~/.zshrc 2>/dev/null; then
        echo "" >> ~/.zshrc
        echo "# Load dotfiles functions" >> ~/.zshrc
        echo 'source ~/.config/zsh-dotfiles-loader.zsh' >> ~/.zshrc
        echo "✓ Added to ~/.zshrc"
    else
        echo "✓ Already in ~/.zshrc"
    fi
fi

# Dependency check
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "Critical dependencies:"
fi

if [[ "$DRY_RUN" == false ]]; then
    echo ""
    echo "🔍 Checking critical dependencies..."
fi

missing_deps=()
for dep in "${CRITICAL_DEPS[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
        missing_deps+=("$dep")
        if [[ "$DRY_RUN" == true ]]; then
            echo "  ⚠️  $dep (would install)"
        else
            echo "  ❌ $dep"
        fi
    else
        if [[ "$DRY_RUN" == true ]]; then
            echo "  ✅ $dep"
        else
            echo "  ✅ $dep"
        fi
    fi
done

# Report missing dependencies with fix instructions
if [[ ${#missing_deps[@]} -gt 0 && "$DRY_RUN" == false ]]; then
    echo ""
    echo "❌ Missing dependencies - Add to Brewfile:"
    echo ""
    for dep in "${missing_deps[@]}"; do
        case "$dep" in
            cjpeg)
                echo "  brew \"mozjpeg\"  # provides cjpeg binary"
                ;;
            rg)
                echo "  brew \"ripgrep\"  # provides rg command"
                ;;
            btm)
                echo "  brew \"bottom\"   # provides btm command"
                ;;
            *)
                echo "  brew \"$dep\""
                ;;
        esac
    done
    echo ""
    echo "Then run: brew bundle --file=~/dotfiles/Brewfile"
    echo ""
fi

# Show available functions
if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "Available functions after installation:"
else
    echo ""
    echo "📋 Available functions:"
fi

echo ""
echo "Shell:"
echo "  ls, ll, lt                          - Modern file listing with eza"
echo "  grep                                - rg (ripgrep)"
echo "  top                                 - btm (system monitor)"
echo "  du                                  - dust (disk usage)"
echo "  df                                  - duf (disk free)"
echo ""
echo "Media:"
echo "  optimize-images [path] [--lossless] - Optimize JPEG/PNG images"
echo "  video-to-gif <input> [output]       - Convert video to GIF"
echo "  video-remux [path]                  - Lossless copy videos to MP4"
echo "  video-encode-cpu [path]             - High-quality CPU encoding"
echo "  video-encode-gpu [path]             - Fast GPU encoding"
echo ""
echo "Git:"
echo "  git-cleanup                         - Clean merged git branches"
echo "  git-open                            - Open repo in browser"
echo ""
echo "macOS:"
echo "  macos-defaults                      - Apply system defaults"
echo "  cpwd                                - Copy current path to clipboard"
echo ""
echo "Dev:"
echo "  extract <archive>                   - Extract any archive type"
echo "  archive [name] [--dry-run] [-gzip]  - Create reproducible archive"
echo "  repo-check                          - Pre-archive sanity checker"
echo "  dotfiles-doctor                     - Environment health check"
echo ""
echo "Homebrew:"
echo "  brewup                              - Update, upgrade, and cleanup"
echo ""
echo "OpenCode:"
echo "  opencode                            - Launch OpenCode with default profile"
echo "  omo                                 - Launch Oh-My-OpenCode"
echo "  oac                                 - Launch OpenAgentsControl"
echo "  ocp                                 - List available profiles"
echo "  ocx-profile <name>                  - Launch specific profile"
echo ""
echo "💡 Optional tools installed but not activated:"
echo "  fzf                                 - Add to ~/.zshrc: eval \"\$(fzf --zsh)\""
echo "  zoxide                              - Add to ~/.zshrc: eval \"\$(zoxide init zsh)\""
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "📝 Dry run complete - No changes made"
    echo "Run without --dry-run to install"
else
    echo "✅ Done! Restart your terminal or run: source ~/.zshrc"
fi
echo ""
