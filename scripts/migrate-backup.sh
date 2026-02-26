#!/usr/bin/env bash
set -euo pipefail

BACKUP_DIR="$HOME/migration-backup"
ARCHIVE="$HOME/migration-backup.tar.gz"

echo "📦 Migration Backup"
echo "==================="
echo ""

rm -rf "$BACKUP_DIR"
mkdir -p "$BACKUP_DIR"

cd "$BACKUP_DIR"

echo "→ Collecting npm global packages..."
npm list -g --depth=0 --parseable 2>/dev/null | tail -n +2 | xargs -n1 basename > npm-global.txt 2>/dev/null || touch npm-global.txt

echo "→ Backing up SSH keys..."
if [[ -d ~/.ssh ]]; then
    cd ~/.ssh
    zip -P "${SSH_ARCHIVE_PASSWORD:-changeme}" -r "$BACKUP_DIR/ssh-keys.zip" \
        id_ed25519 id_ed25519.pub known_hosts config 2>/dev/null || true
    cd "$BACKUP_DIR"
else
    echo "  (no ~/.ssh directory found)"
fi

echo "→ Backing up Ghostty config..."
mkdir -p "$BACKUP_DIR/ghostty-config"
if [[ -f ~/Library/Application\ Support/com.mitchellh.ghostty/config ]]; then
    cp ~/Library/Application\ Support/com.mitchellh.ghostty/config "$BACKUP_DIR/ghostty-config/"
fi

echo "→ Collecting App Store apps list..."
ls /Applications 2>/dev/null | grep -v "^\." | grep -v "^Utilities$" > appstore-apps.txt

echo "→ Generating macOS defaults script..."
cat > macos-defaults.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "→ Applying macOS defaults..."

# Dock
defaults write com.apple.dock autohide -bool true

# Finder
defaults write com.apple.finder AppleShowAllFiles -bool true

# Keyboard - Very Fast
defaults write NSGlobalDomain KeyRepeat -int 1
defaults write NSGlobalDomain InitialKeyRepeat -int 10
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false

# Typing
defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# Window
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001

# Trackpad (both settings for full coverage)
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
defaults -currentHost write NSGlobalDomain com.apple.trackpad.tapBehavior -int 1

# Apply changes immediately
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true

echo "✓ macOS defaults applied"
EOF
chmod +x macos-defaults.sh

echo "→ Creating README..."
cat > README.md << 'EOF'
# Migration Backup

This archive contains everything needed to set up a new Mac.

## Restore Instructions

1. Transfer this archive to new machine
2. Clone dotfiles first:
   ```bash
   git clone git@github.com:bartech-lab/dotfiles.git ~/dotfiles
   ```
3. Run restore:
   ```bash
   ~/dotfiles/scripts/migrate-restore.sh ~/migration-backup.tar.gz
   ```

## Manual Steps (not automated)

- **Chrome**: Export bookmarks manually (chrome://bookmarks → ⋮ → Export)
- **App Store apps**: Review `appstore-apps.txt` and redownload with new Apple ID

## Contents

| File | Description |
|------|-------------|
| `npm-global.txt` | Global npm packages |
| `ssh-keys.zip` | SSH keys (password protected) |
| `ghostty-config/` | Ghostty terminal config |
| `macos-defaults.sh` | macOS system preferences |
| `appstore-apps.txt` | List of installed apps |
EOF

echo "→ Creating archive..."
cd ~
tar -czvf "$ARCHIVE" migration-backup/
rm -rf "$BACKUP_DIR"

echo ""
echo "✅ Backup complete: $ARCHIVE"
echo ""
echo "⚠️  Manual steps needed:"
echo "   1. Chrome: Export bookmarks (chrome://bookmarks → ⋮ → Export)"
echo "   2. Review appstore-apps.txt for apps to redownload"
echo ""
