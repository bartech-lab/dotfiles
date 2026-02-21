#!/bin/bash
set -e

DOTFILES_DIR="$HOME/dotfiles"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# Critical dependencies that must be present
# Note: cjpeg is the binary from mozjpeg package
CRITICAL_DEPS=("eza" "fd" "rg" "dust" "btm" "duf" "parallel" "ffmpeg" "cjpeg")

echo "🚀 Installing dotfiles..."

# Install Homebrew if not present
if ! command -v brew &>/dev/null; then
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

# Create backup directory
mkdir -p "$BACKUP_DIR"
echo "📦 Backup location: $BACKUP_DIR"

# Install Homebrew dependencies if Brewfile exists
if [[ -f "$DOTFILES_DIR/Brewfile" ]]; then
    echo "📦 Installing Homebrew packages..."
    brew bundle --file="$DOTFILES_DIR/Brewfile" || {
        echo "⚠️ Some Brewfile entries may have failed (check above)"
    }
else
    echo "⚠️ No Brewfile found. Skipping package installation."
fi

# Create necessary directories
mkdir -p ~/.config
echo "✓ Created ~/.config"

# Backup existing loader if present (not symlink)
if [[ -f ~/.config/zsh-dotfiles-loader.zsh && ! -L ~/.config/zsh-dotfiles-loader.zsh ]]; then
    cp ~/.config/zsh-dotfiles-loader.zsh "$BACKUP_DIR/"
    echo "✓ Backed up existing zsh-dotfiles-loader.zsh"
fi

# Symlink the functions loader
if [[ -L ~/.config/zsh-dotfiles-loader.zsh ]]; then
    # Update existing symlink
    ln -sf "$DOTFILES_DIR/zsh/functions.zsh" ~/.config/zsh-dotfiles-loader.zsh
    echo "✓ Updated existing symlink"
else
    ln -sf "$DOTFILES_DIR/zsh/functions.zsh" ~/.config/zsh-dotfiles-loader.zsh
    echo "✓ Linked functions loader"
fi

# Add to .zshrc if not present
if ! grep -q "zsh-dotfiles-loader.zsh" ~/.zshrc 2>/dev/null; then
    echo "" >> ~/.zshrc
    echo "# Load dotfiles functions" >> ~/.zshrc
    echo 'source ~/.config/zsh-dotfiles-loader.zsh' >> ~/.zshrc
    echo "✓ Added to ~/.zshrc"
else
    echo "✓ Already in ~/.zshrc"
fi

# Dependency check and auto-install
echo ""
echo "🔍 Checking critical dependencies..."

missing_deps=()
for dep in "${CRITICAL_DEPS[@]}"; do
    if ! command -v "$dep" &>/dev/null; then
        missing_deps+=("$dep")
        echo "  ❌ $dep"
    else
        echo "  ✅ $dep"
    fi
done

# Auto-install missing critical dependencies
if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo ""
    echo "📦 Installing missing critical dependencies..."
    for dep in "${missing_deps[@]}"; do
        echo "  → Installing $dep..."
        # Special case: cjpeg comes from mozjpeg package
        if [[ "$dep" == "cjpeg" ]]; then
            brew install "mozjpeg" 2>/dev/null || echo "  ⚠️ Failed to install mozjpeg"
        else
            brew install "$dep" 2>/dev/null || {
                # Try alternate formula names
                case "$dep" in
                    "rg") brew install "ripgrep" ;;
                    "btm") brew install "bottom" ;;
                    *) echo "  ⚠️ Failed to install $dep" ;;
                esac
            }
        fi
    done
    
    # Re-check
    echo ""
    echo "🔍 Verifying installations..."
    still_missing=()
    for dep in "${missing_deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            still_missing+=("$dep")
            echo "  ❌ $dep (still missing)"
        else
            echo "  ✅ $dep (installed)"
        fi
    done
    
    if [[ ${#still_missing[@]} -gt 0 ]]; then
        echo ""
        echo "⚠️ Warning: Some dependencies could not be installed: ${still_missing[*]}"
    fi
fi

echo ""
echo "📋 Available functions:"
echo ""
echo "Shell:"
echo "  ls, ll, lt                          - Modern file listing with eza"
echo "  find                                - fd (modern find replacement)"
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
echo "✅ Done! Restart your terminal or run: source ~/.zshrc"
echo ""
