#!/bin/bash

# Unified Automation Installer
# Sets up all background services: git-auto-pull, launchd-heartbeat, system-update
# Works on both macOS (LaunchAgents) and Linux (systemd user timers)

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

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

# Backup variables — used by ensure_backup_dir()
BACKUP_ROOT="$HOME/.dotfiles-backups"
BACKUP_DIR="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)"
BACKUP_CREATED=false

if [[ "$DRY_RUN" == true ]]; then
    echo "🚀 Dotfiles Installer (DRY RUN)"
    echo "================================"
    echo ""
else
    echo "🚀 Installing dotfiles..."
    set -e
fi

# Platform detection
case "$(uname -s)" in
  Darwin) DOTFILES_OS=macos ;;
  Linux)  DOTFILES_OS=linux ;;
  *)      print -u2 "❌ Unsupported OS: $(uname -s)"; exit 1 ;;
esac

echo "==> OS detected: $DOTFILES_OS"
echo "==> Dotfiles root: $DOTFILES_DIR"
echo ""

# Check runtime-critical dependencies
CRITICAL_DEPS=(git curl)
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

# Install Homebrew if missing (macOS only)
# macOS LaunchAgent plists for background services
ensure_launchagent_plist() {
    local label="$1" script="$2" interval="$3"
    local plist="$HOME/Library/LaunchAgents/${label}.plist"
    if [[ ! -f "$plist" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            echo "  → Would create: $plist"
        else
            mkdir -p "$HOME/Library/LaunchAgents"
            cat > "$plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
        <string>${script}</string>
    </array>
    <key>StartInterval</key>
    <integer>${interval}</integer>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST
            launchctl bootstrap "gui/$(id -u)" "$plist" 2>/dev/null || true
            echo "✓ Created and loaded $label"
        fi
    fi
}

if [[ "$DOTFILES_OS" == macos ]]; then
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

# macOS background services (git-auto-pull + heartbeat)
# Copy scripts to ~/.config (same as Linux, but use LaunchAgents)
if [[ "$DRY_RUN" == false ]]; then
    mkdir -p ~/.config/git-auto-pull
    cp "$DOTFILES_DIR/git-auto-pull/pull.sh" ~/.config/git-auto-pull/pull.sh
    chmod +x ~/.config/git-auto-pull/pull.sh

    mkdir -p ~/.config/launchd-heartbeat
    cp "$DOTFILES_DIR/launchd-heartbeat/heartbeat.sh" ~/.config/launchd-heartbeat/heartbeat.sh
    chmod +x ~/.config/launchd-heartbeat/heartbeat.sh

    if [[ ! -f ~/.config/git-auto-pull/repos.conf ]]; then
        cat > ~/.config/git-auto-pull/repos.conf << 'GITCONF'
# Git Auto-Pull Configuration
# Format: /path/to/repo:branch-name
# Lines starting with # are ignored
GITCONF
    fi
    if [[ ! -f ~/.config/launchd-heartbeat/monitored-labels.conf ]]; then
        cat > ~/.config/launchd-heartbeat/monitored-labels.conf << 'HEARTBEATCONF'
# Monitored services
git-auto-pull.service
launchd-heartbeat.service
HEARTBEATCONF
    fi
fi

ensure_launchagent_plist "com.user.gitautopull" "$HOME/.config/git-auto-pull/pull.sh" 3600
ensure_launchagent_plist "com.user.launchdheartbeat" "$HOME/.config/launchd-heartbeat/heartbeat.sh" 300

# Linux package installation (pacman/yay)
elif [[ "$DOTFILES_OS" == linux ]]; then

    # --- Ensure base-devel + git (needed for yay build) ---
    if [[ "$DRY_RUN" == false ]]; then
        sudo pacman -S --needed --noconfirm base-devel git
    fi

    # --- Install yay AUR helper ---
    if ! command -v yay &>/dev/null; then
        if [[ "$DRY_RUN" == false ]]; then
            echo "📦 Installing yay AUR helper..."
            yay_tmp=$(mktemp -d)
            git clone https://aur.archlinux.org/yay.git "$yay_tmp"
            (cd "$yay_tmp" && makepkg -si --noconfirm)
            rm -rf "$yay_tmp"
            echo "✓ yay installed"
        fi
    fi

    # --- Install official packages ---
    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo "Pacman packages to install (from pkglist/pacman.txt):"
        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" == \#* ]] && continue
            pacman -Qi "$pkg" &>/dev/null || echo "  → $pkg"
        done < "$DOTFILES_DIR/pkglist/pacman.txt"
    else
        echo "📦 Installing pacman packages..."
        pkgs=()
        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" == \#* ]] && continue
            pkgs+=("$pkg")
        done < "$DOTFILES_DIR/pkglist/pacman.txt"
        sudo pacman -S --needed --noconfirm "${pkgs[@]}"
        echo "✓ Pacman packages installed"
    fi

    # --- Install AUR packages ---
    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo "AUR packages to install (from pkglist/aur.txt):"
        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" == \#* ]] && continue
            yay -Qi "$pkg" &>/dev/null || echo "  → $pkg"
        done < "$DOTFILES_DIR/pkglist/aur.txt"
    else
        echo "📦 Installing AUR packages..."
        aur_pkgs=()
        while IFS= read -r pkg; do
            [[ -z "$pkg" || "$pkg" == \#* ]] && continue
            aur_pkgs+=("$pkg")
        done < "$DOTFILES_DIR/pkglist/aur.txt"
        yay -S --needed --noconfirm "${aur_pkgs[@]}"
        echo "✓ AUR packages installed"
    fi

    # --- fnm (Fast Node Manager) ---
    if ! command -v fnm &>/dev/null; then
        if [[ "$DRY_RUN" == false ]]; then
            echo "📦 Installing fnm..."
            curl -fsSL https://fnm.vercel.app/install | bash
            echo "✓ fnm installed"
        fi
    fi

    # --- Set zsh as default shell ---
    if [[ "$SHELL" != *zsh ]]; then
        if [[ "$DRY_RUN" == false ]]; then
            echo "Setting zsh as default shell..."
            chsh -s /usr/bin/zsh
        fi
    fi

    # --- pipx ensurepath ---
    if command -v pipx &>/dev/null; then
        if [[ "$DRY_RUN" == false ]]; then
            pipx ensurepath 2>/dev/null || true
        fi
    fi

    # --- git-auto-pull setup (script + config) ---
    mkdir -p ~/.config/git-auto-pull
    if [[ "$DRY_RUN" == false ]]; then
        cp "$DOTFILES_DIR/git-auto-pull/pull.sh" ~/.config/git-auto-pull/pull.sh
        chmod +x ~/.config/git-auto-pull/pull.sh
    fi

    if [[ ! -f ~/.config/git-auto-pull/repos.conf ]]; then
        if [[ "$DRY_RUN" == false ]]; then
            cat > ~/.config/git-auto-pull/repos.conf << 'GITCONF'
# Git Auto-Pull Configuration
# Format: /path/to/repo:branch-name
# Lines starting with # are ignored
#
# Example:
# ~/Projects/my-app:main
GITCONF
            echo "✓ Created git-auto-pull config"
        fi
    fi

    # --- heartbeat setup (script + config) ---
    mkdir -p ~/.config/launchd-heartbeat
    if [[ "$DRY_RUN" == false ]]; then
        cp "$DOTFILES_DIR/launchd-heartbeat/heartbeat.sh" ~/.config/launchd-heartbeat/heartbeat.sh
        chmod +x ~/.config/launchd-heartbeat/heartbeat.sh
    fi

    if [[ ! -f ~/.config/launchd-heartbeat/monitored-labels.conf ]]; then
        if [[ "$DRY_RUN" == false ]]; then
            cat > ~/.config/launchd-heartbeat/monitored-labels.conf << 'HEARTBEATCONF'
# Monitored systemd user services
# One unit name per line
git-auto-pull.service
launchd-heartbeat.service
HEARTBEATCONF
            echo "✓ Created heartbeat config"
        fi
    fi

    # --- systemd user timers ---
    if [[ "$DRY_RUN" == false ]]; then
        echo "⚙️  Setting up systemd user timers..."
        mkdir -p ~/.config/systemd/user
        cp "$DOTFILES_DIR/git-auto-pull/systemd/git-auto-pull.service" ~/.config/systemd/user/
        cp "$DOTFILES_DIR/git-auto-pull/systemd/git-auto-pull.timer" ~/.config/systemd/user/
        cp "$DOTFILES_DIR/launchd-heartbeat/systemd/launchd-heartbeat.service" ~/.config/systemd/user/
        cp "$DOTFILES_DIR/launchd-heartbeat/systemd/launchd-heartbeat.timer" ~/.config/systemd/user/
        cp "$DOTFILES_DIR/system-update/system-update.service" ~/.config/systemd/user/
        cp "$DOTFILES_DIR/system-update/system-update.timer" ~/.config/systemd/user/
        systemctl --user daemon-reload
        systemctl --user enable --now git-auto-pull.timer launchd-heartbeat.timer system-update.timer
        echo "✓ systemd user timers enabled"
    fi

    # --- System performance configs (sysctl, modprobe) ---
    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo "System configs to deploy (requires sudo):"
        echo "  → /etc/sysctl.d/99-performance.conf (vm.swappiness=10, vm.max_map_count)"
        echo "  → /etc/modprobe.d/nvidia.conf (blacklist nouveau/nova_core, DRM modeset)"
    else
        echo ""
        echo "⚙️  Deploying system performance configs..."
        sudo cp "$DOTFILES_DIR/linux/etc/sysctl.d/99-performance.conf" /etc/sysctl.d/
        sudo cp "$DOTFILES_DIR/linux/etc/modprobe.d/nvidia.conf" /etc/modprobe.d/
        sudo sysctl --system >/dev/null 2>&1
        echo "✓ System configs deployed (sysctl, modprobe)"
    fi

    # --- GameMode config ---
    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo "User configs to deploy:"
        echo "  → ~/.config/gamemode.ini"
    else
        mkdir -p ~/.config
        cp "$DOTFILES_DIR/linux/gamemode.ini" ~/.config/gamemode.ini
        echo "✓ GameMode config deployed"
    fi

    # --- Enable system timers (fstrim, reflector) ---
    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo "System timers to enable:"
        echo "  → fstrim.timer (weekly SSD TRIM)"
        echo "  → reflector.timer (mirror optimization)"
    else
        sudo systemctl enable --now fstrim.timer 2>/dev/null || true
        sudo systemctl enable --now reflector.timer 2>/dev/null || true
        echo "✓ fstrim.timer and reflector.timer enabled"
    fi

    # --- mkinitcpio instructions (never auto-modify) ---
    echo ""
    echo "📌 MANUAL STEP: Add NVIDIA modules to /etc/mkinitcpio.conf:"
    echo "   MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)"
    echo "   Then run: sudo mkinitcpio -P"

fi  # End Linux package install

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
    if ! git config --global core.excludesfile | grep -q "gitignore_global"; then
        echo "  → Would set: git config --global core.excludesfile ~/.gitignore_global"
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

    if ! git config --global core.excludesfile | grep -q "gitignore_global"; then
        git config --global core.excludesfile ~/.gitignore_global
        echo "✓ Set git core.excludesfile → ~/.gitignore_global"
    fi

    if [[ -L ~/.config/zsh-dotfiles-loader.zsh ]]; then
        ln -sf "$DOTFILES_DIR/zsh/functions.zsh" ~/.config/zsh-dotfiles-loader.zsh
        echo "✓ Updated loader symlink"
    else
        ln -sf "$DOTFILES_DIR/zsh/functions.zsh" ~/.config/zsh-dotfiles-loader.zsh
        echo "✓ Linked functions loader"
    fi
fi

# Ghostty config (macOS path)
if [[ "$DOTFILES_OS" == macos ]]; then
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

fi  # End macOS Ghostty config

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

# ============================================================================
# Cross-Platform Config Symlinks
# ============================================================================

config_symlinks() {
    local src="$1" dest="$2" label="$3"
    local dest_dir
    dest_dir="$(dirname "$dest")"
    if [[ "$DRY_RUN" == true ]]; then
        if [[ -L "$dest" ]]; then
            echo "  → Would update: $dest → $src"
        else
            echo "  → Would create: $dest → $src"
        fi
    else
        mkdir -p "$dest_dir"
        ln -sf "$src" "$dest"
        echo "✓ Linked $label"
    fi
}

# git global config
config_symlinks "$DOTFILES_DIR/git/gitconfig" "$HOME/.gitconfig" "git global config"

# curl
config_symlinks "$DOTFILES_DIR/curl/curlrc" "$HOME/.curlrc" "curl config"

# ripgrep
config_symlinks "$DOTFILES_DIR/ripgrep/ripgreprc" "$HOME/.ripgreprc" "ripgrep config"

# yt-dlp
config_symlinks "$DOTFILES_DIR/yt-dlp/config" "$HOME/.config/yt-dlp/config" "yt-dlp config"

# aria2
config_symlinks "$DOTFILES_DIR/aria2/aria2.conf" "$HOME/.aria2/aria2.conf" "aria2 config"

# bottom
config_symlinks "$DOTFILES_DIR/bottom/bottom.toml" "$HOME/.config/bottom/bottom.toml" "bottom config"

# GitHub CLI
config_symlinks "$DOTFILES_DIR/gh/config.yml" "$HOME/.config/gh/config.yml" "gh config"

# VS Code (shared settings.json, different target per platform)
if [[ "$DOTFILES_OS" == macos ]]; then
    config_symlinks "$DOTFILES_DIR/vscode/settings.json" "$HOME/Library/Application Support/Code/User/settings.json" "VS Code settings"
else
    config_symlinks "$DOTFILES_DIR/vscode/settings.json" "$HOME/.config/Code/User/settings.json" "VS Code settings"
fi

# ============================================================================
# macOS-Specific Symlinks
# ============================================================================

if [[ "$DOTFILES_OS" == macos ]]; then
    # IINA mpv config
    config_symlinks "$DOTFILES_DIR/iina/mpv.conf" "$HOME/Library/Application Support/iina/mpv.conf" "IINA mpv config"
fi

# ============================================================================
# Linux-Specific Config Symlinks
# ============================================================================

if [[ "$DOTFILES_OS" == linux ]]; then
    # Brave GPU flags
    config_symlinks "$DOTFILES_DIR/linux/brave-flags.conf" "$HOME/.config/brave-flags.conf" "Brave flags"

    # Desktop overrides (Wayland for Electron apps)
    config_symlinks "$DOTFILES_DIR/linux/desktop-overrides/code.desktop" "$HOME/.local/share/applications/code.desktop" "VS Code desktop"
    config_symlinks "$DOTFILES_DIR/linux/desktop-overrides/standardnotes-desktop.desktop" "$HOME/.local/share/applications/standardnotes-desktop.desktop" "Standard Notes desktop"
    config_symlinks "$DOTFILES_DIR/linux/desktop-overrides/filen-desktop.desktop" "$HOME/.local/share/applications/filen-desktop.desktop" "Filen Desktop desktop"

    # Plasma desktop session config
    config_symlinks "$DOTFILES_DIR/linux/plasma/plasmashellrc" "$HOME/.config/plasmashellrc" "Plasma shell config"
fi

# p10k prompt theme
if [[ -f "$HOME/.p10k.zsh" && ! -L "$HOME/.p10k.zsh" ]]; then
    ensure_backup_dir
    if [[ "$DRY_RUN" == true ]]; then
        echo "  → Would backup: ~/.p10k.zsh"
    else
        cp "$HOME/.p10k.zsh" "$BACKUP_DIR/p10k.zsh"
        echo "✓ Backed up existing .p10k.zsh"
    fi
fi
config_symlinks "$DOTFILES_DIR/zsh/p10k.zsh" "$HOME/.p10k.zsh" "p10k theme"

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
    
    # Platform-aware binary name
    case "$DOTFILES_OS" in
        macos) local gs_os="darwin" ;;
        linux) local gs_os="linux" ;;
    esac
    
    if [[ ! -f "$GITSTATUS_CACHE/gitstatusd-${gs_os}-$ARCH" ]]; then
        # Try multiple locations where powerlevel10k might be installed
        p10k_paths=(
            "$HOME/.zinit/plugins/romkatv---powerlevel10k"
            "/opt/homebrew/opt/powerlevel10k"
            "/usr/local/opt/powerlevel10k"
            "/usr/share/zsh/plugins/powerlevel10k"
        )
        
        for p10k_path in "${p10k_paths[@]}"; do
            if [[ -f "$p10k_path/gitstatus/install" ]]; then
                echo "Pre-caching gitstatus binary..."
                mkdir -p "$GITSTATUS_CACHE"
                # Run install script silently (downloads prebuilt binary)
                (cd "$p10k_path/gitstatus" && CC= CXX= ./install -f >/dev/null 2>&1) || true
                
                if [[ -f "$GITSTATUS_CACHE/gitstatusd-${gs_os}-$ARCH" ]]; then
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
    if [[ "$DOTFILES_OS" == macos ]]; then
        echo "Run: macos-defaults to apply system preferences"
        echo "Run: macos-debloat to remove bloatware (destructive)"
        echo "Run: macos-system-analysis to review services"
        echo ""
        echo "📌 TG Pro: install manually → https://www.tunabellysoftware.com/tgpro/"
    elif [[ "$DOTFILES_OS" == linux ]]; then
        echo "Run: pacup to update all packages"
        echo "Run: pacman-optimize to optimize pacman.conf"
        echo "Run: kde-defaults to apply KDE Plasma 6 preferences"
        echo "Run: kde-audit-effects to verify disabled effects"
    fi
fi
