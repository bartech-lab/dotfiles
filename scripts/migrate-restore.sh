#!/usr/bin/env bash
set -euo pipefail

ARCHIVE="${1:-$HOME/migration-backup.tar.gz}"

if [[ ! -f "$ARCHIVE" ]]; then
    echo "❌ Archive not found: $ARCHIVE"
    echo ""
    echo "Usage: migrate-restore.sh <path-to-archive>"
    exit 1
fi

echo "🔄 Migration Restore"
echo "===================="
echo ""

if [[ ! -d "$HOME/dotfiles" ]]; then
    echo "❌ Dotfiles not found at ~/dotfiles"
    echo ""
    echo "Clone them first:"
    echo "  git clone git@github.com:bartech-lab/dotfiles.git ~/dotfiles"
    exit 1
fi

EXTRACT_DIR=$(mktemp -d)
trap 'rm -rf "$EXTRACT_DIR"' EXIT

echo "→ Extracting archive..."
tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR" --strip-components=1

if [[ $(uname -m) == "arm64" ]]; then
    echo "→ Installing Rosetta (Apple Silicon)..."
    softwareupdate --install-rosetta --agree-to-license 2>/dev/null || true
fi

if ! xcode-select -p &>/dev/null; then
    echo "→ Installing Xcode CLI tools..."
    xcode-select --install 2>/dev/null || true
    echo ""
    echo "⏳  Complete the Xcode installation popup, then re-run this script"
    exit 0
fi

if ! command -v brew &>/dev/null; then
    echo "→ Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

if [[ -f /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
elif [[ -f /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
fi

echo "→ Restoring SSH keys..."
mkdir -p ~/.ssh
chmod 700 ~/.ssh
if [[ -f "$EXTRACT_DIR/ssh-keys.zip" ]]; then
    unzip -o -P "${SSH_ARCHIVE_PASSWORD:-changeme}" "$EXTRACT_DIR/ssh-keys.zip" -d ~/.ssh/ 2>/dev/null || true
    chmod 600 ~/.ssh/id_ed25519 2>/dev/null || true
    chmod 644 ~/.ssh/id_ed25519.pub 2>/dev/null || true
    chmod 644 ~/.ssh/known_hosts 2>/dev/null || true
    chmod 644 ~/.ssh/config 2>/dev/null || true
    ssh-add --apple-use-keychain ~/.ssh/id_ed25519 2>/dev/null || true
fi

echo "→ Running dotfiles installer..."
cd ~/dotfiles
./install.sh

echo "→ Running brew doctor..."
brew doctor 2>/dev/null || echo "  ⚠️  brew doctor reported issues (may be safe to ignore)"

echo "→ Installing npm global packages..."
if [[ -f "$EXTRACT_DIR/npm-global.txt" ]] && [[ -s "$EXTRACT_DIR/npm-global.txt" ]]; then
    xargs -a "$EXTRACT_DIR/npm-global.txt" npm install -g 2>/dev/null || true
fi

echo "→ Restoring Ghostty config..."
mkdir -p ~/Library/Application\ Support/com.mitchellh.ghostty
if [[ -d "$EXTRACT_DIR/ghostty-config" ]]; then
    cp -r "$EXTRACT_DIR/ghostty-config/"* ~/Library/Application\ Support/com.mitchellh.ghostty/ 2>/dev/null || true
fi

echo "→ Applying macOS defaults..."
if [[ -f "$EXTRACT_DIR/macos-defaults.sh" ]]; then
    bash "$EXTRACT_DIR/macos-defaults.sh"
fi

echo ""
echo "✅ Restore complete!"
echo ""
echo "🔄 Reboot recommended:"
echo "   sudo shutdown -r now"
echo ""
echo "📝 Manual steps:"
echo "   1. Import Chrome bookmarks"
echo "   2. Redownload App Store apps (see appstore-apps.txt)"
echo ""
