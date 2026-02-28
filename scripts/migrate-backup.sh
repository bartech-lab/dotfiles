#!/usr/bin/env zsh
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

echo "→ Generating comprehensive macOS defaults backup..."

# Create the macOS defaults restoration script
cat > macos-defaults.sh << 'SCRIPT_EOF'
#!/usr/bin/env bash
set -euo pipefail

echo "→ Restoring macOS system defaults..."
echo ""

# ============================================
# DOCK SETTINGS
# ============================================

SCRIPT_EOF

# Export Dock settings
echo "# Dock: auto-hide settings" >> macos-defaults.sh
defaults read com.apple.dock autohide 2>/dev/null && echo "defaults write com.apple.dock autohide -bool $(defaults read com.apple.dock autohide)" >> macos-defaults.sh || echo "defaults write com.apple.dock autohide -bool true" >> macos-defaults.sh
defaults read com.apple.dock autohide-delay 2>/dev/null && echo "defaults write com.apple.dock autohide-delay -float $(defaults read com.apple.dock autohide-delay)" >> macos-defaults.sh || echo "defaults write com.apple.dock autohide-delay -float 0" >> macos-defaults.sh
defaults read com.apple.dock autohide-time-modifier 2>/dev/null && echo "defaults write com.apple.dock autohide-time-modifier -float $(defaults read com.apple.dock autohide-time-modifier)" >> macos-defaults.sh || echo "defaults write com.apple.dock autohide-time-modifier -float 0.15" >> macos-defaults.sh
defaults read com.apple.dock showhidden 2>/dev/null && echo "defaults write com.apple.dock showhidden -bool $(defaults read com.apple.dock showhidden)" >> macos-defaults.sh || echo "defaults write com.apple.dock showhidden -bool true" >> macos-defaults.sh
defaults read com.apple.dock show-recents 2>/dev/null && echo "defaults write com.apple.dock show-recents -bool $(defaults read com.apple.dock show-recents)" >> macos-defaults.sh || echo "defaults write com.apple.dock show-recents -bool false" >> macos-defaults.sh
defaults read com.apple.dock expose-animation-duration 2>/dev/null && echo "defaults write com.apple.dock expose-animation-duration -float $(defaults read com.apple.dock expose-animation-duration)" >> macos-defaults.sh || echo "defaults write com.apple.dock expose-animation-duration -float 0.1" >> macos-defaults.sh
defaults read com.apple.dock mru-spaces 2>/dev/null && echo "defaults write com.apple.dock mru-spaces -bool $(defaults read com.apple.dock mru-spaces)" >> macos-defaults.sh || echo "defaults write com.apple.dock mru-spaces -bool false" >> macos-defaults.sh
defaults read com.apple.dock mineffect 2>/dev/null && echo "defaults write com.apple.dock mineffect -string '$(defaults read com.apple.dock mineffect)'" >> macos-defaults.sh || echo "defaults write com.apple.dock mineffect -string 'scale'" >> macos-defaults.sh
defaults read com.apple.dock minimize-to-application 2>/dev/null && echo "defaults write com.apple.dock minimize-to-application -bool $(defaults read com.apple.dock minimize-to-application)" >> macos-defaults.sh || echo "defaults write com.apple.dock minimize-to-application -bool true" >> macos-defaults.sh
defaults read com.apple.dock launchanim 2>/dev/null && echo "defaults write com.apple.dock launchanim -bool $(defaults read com.apple.dock launchanim)" >> macos-defaults.sh || echo "defaults write com.apple.dock launchanim -bool false" >> macos-defaults.sh

cat >> macos-defaults.sh << 'SCRIPT_EOF'

# ============================================
# FINDER SETTINGS
# ============================================

SCRIPT_EOF

# Export Finder settings
echo "# Finder: visibility and behavior" >> macos-defaults.sh
defaults read com.apple.finder ShowPathbar 2>/dev/null && echo "defaults write com.apple.finder ShowPathbar -bool $(defaults read com.apple.finder ShowPathbar)" >> macos-defaults.sh || echo "defaults write com.apple.finder ShowPathbar -bool true" >> macos-defaults.sh
defaults read com.apple.finder ShowStatusBar 2>/dev/null && echo "defaults write com.apple.finder ShowStatusBar -bool $(defaults read com.apple.finder ShowStatusBar)" >> macos-defaults.sh || echo "defaults write com.apple.finder ShowStatusBar -bool true" >> macos-defaults.sh
defaults read com.apple.finder _FXSortFoldersFirst 2>/dev/null && echo "defaults write com.apple.finder _FXSortFoldersFirst -bool $(defaults read com.apple.finder _FXSortFoldersFirst)" >> macos-defaults.sh || echo "defaults write com.apple.finder _FXSortFoldersFirst -bool true" >> macos-defaults.sh
defaults read com.apple.finder FXDefaultSearchScope 2>/dev/null && echo "defaults write com.apple.finder FXDefaultSearchScope -string '$(defaults read com.apple.finder FXDefaultSearchScope)'" >> macos-defaults.sh || echo "defaults write com.apple.finder FXDefaultSearchScope -string 'SCcf'" >> macos-defaults.sh
defaults read com.apple.finder FXEnableExtensionChangeWarning 2>/dev/null && echo "defaults write com.apple.finder FXEnableExtensionChangeWarning -bool $(defaults read com.apple.finder FXEnableExtensionChangeWarning)" >> macos-defaults.sh || echo "defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false" >> macos-defaults.sh
defaults read com.apple.finder DisableAllAnimations 2>/dev/null && echo "defaults write com.apple.finder DisableAllAnimations -bool $(defaults read com.apple.finder DisableAllAnimations)" >> macos-defaults.sh || echo "defaults write com.apple.finder DisableAllAnimations -bool true" >> macos-defaults.sh
defaults read com.apple.finder _FXShowPosixPathInTitle 2>/dev/null && echo "defaults write com.apple.finder _FXShowPosixPathInTitle -bool $(defaults read com.apple.finder _FXShowPosixPathInTitle)" >> macos-defaults.sh || echo "defaults write com.apple.finder _FXShowPosixPathInTitle -bool true" >> macos-defaults.sh
defaults read com.apple.finder QuitMenuItem 2>/dev/null && echo "defaults write com.apple.finder QuitMenuItem -bool $(defaults read com.apple.finder QuitMenuItem)" >> macos-defaults.sh || echo "defaults write com.apple.finder QuitMenuItem -bool true" >> macos-defaults.sh
defaults read com.apple.desktopservices DSDontWriteNetworkStores 2>/dev/null && echo "defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool $(defaults read com.apple.desktopservices DSDontWriteNetworkStores)" >> macos-defaults.sh || echo "defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true" >> macos-defaults.sh
defaults read com.apple.desktopservices DSDontWriteUSBStores 2>/dev/null && echo "defaults write com.apple.desktopservices DSDontWriteUSBStores -bool $(defaults read com.apple.desktopservices DSDontWriteUSBStores)" >> macos-defaults.sh || echo "defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true" >> macos-defaults.sh

cat >> macos-defaults.sh << 'SCRIPT_EOF'

# ============================================
# SCREENSHOT SETTINGS
# ============================================

SCRIPT_EOF

# Export Screenshot settings
echo "# Screenshots: location, format, and appearance" >> macos-defaults.sh
defaults read com.apple.screencapture location 2>/dev/null && echo "defaults write com.apple.screencapture location -string '$(defaults read com.apple.screencapture location)'" >> macos-defaults.sh || echo "defaults write com.apple.screencapture location -string '\${HOME}/Downloads'" >> macos-defaults.sh
defaults read com.apple.screencapture disable-shadow 2>/dev/null && echo "defaults write com.apple.screencapture disable-shadow -bool $(defaults read com.apple.screencapture disable-shadow)" >> macos-defaults.sh || echo "defaults write com.apple.screencapture disable-shadow -bool true" >> macos-defaults.sh
defaults read com.apple.screencapture type 2>/dev/null && echo "defaults write com.apple.screencapture type -string '$(defaults read com.apple.screencapture type)'" >> macos-defaults.sh || echo "defaults write com.apple.screencapture type -string 'png'" >> macos-defaults.sh

cat >> macos-defaults.sh << 'SCRIPT_EOF'

# ============================================
# GLOBAL SETTINGS (NSGlobalDomain)
# ============================================

SCRIPT_EOF

# Export Global settings
echo "# Global: file extensions and UI behavior" >> macos-defaults.sh
defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null && echo "defaults write NSGlobalDomain AppleShowAllExtensions -bool $(defaults read NSGlobalDomain AppleShowAllExtensions)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain AppleShowAllExtensions -bool true" >> macos-defaults.sh

echo "" >> macos-defaults.sh
echo "# Global: keyboard behavior" >> macos-defaults.sh
defaults read NSGlobalDomain ApplePressAndHoldEnabled 2>/dev/null && echo "defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool $(defaults read NSGlobalDomain ApplePressAndHoldEnabled)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false" >> macos-defaults.sh
defaults read NSGlobalDomain KeyRepeat 2>/dev/null && echo "defaults write NSGlobalDomain KeyRepeat -int $(defaults read NSGlobalDomain KeyRepeat)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain KeyRepeat -int 1" >> macos-defaults.sh
defaults read NSGlobalDomain InitialKeyRepeat 2>/dev/null && echo "defaults write NSGlobalDomain InitialKeyRepeat -int $(defaults read NSGlobalDomain InitialKeyRepeat)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain InitialKeyRepeat -int 10" >> macos-defaults.sh
defaults read NSGlobalDomain AppleKeyboardUIMode 2>/dev/null && echo "defaults write NSGlobalDomain AppleKeyboardUIMode -int $(defaults read NSGlobalDomain AppleKeyboardUIMode)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain AppleKeyboardUIMode -int 3" >> macos-defaults.sh

echo "" >> macos-defaults.sh
echo "# Global: typing and text substitution" >> macos-defaults.sh
defaults read NSGlobalDomain NSAutomaticCapitalizationEnabled 2>/dev/null && echo "defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool $(defaults read NSGlobalDomain NSAutomaticCapitalizationEnabled)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false" >> macos-defaults.sh
defaults read NSGlobalDomain NSAutomaticDashSubstitutionEnabled 2>/dev/null && echo "defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool $(defaults read NSGlobalDomain NSAutomaticDashSubstitutionEnabled)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false" >> macos-defaults.sh
defaults read NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled 2>/dev/null && echo "defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool $(defaults read NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false" >> macos-defaults.sh
defaults read NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled 2>/dev/null && echo "defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool $(defaults read NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false" >> macos-defaults.sh
defaults read NSGlobalDomain NSAutomaticSpellingCorrectionEnabled 2>/dev/null && echo "defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool $(defaults read NSGlobalDomain NSAutomaticSpellingCorrectionEnabled)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false" >> macos-defaults.sh

echo "" >> macos-defaults.sh
echo "# Global: window and dialog behavior" >> macos-defaults.sh
defaults read NSGlobalDomain NSWindowResizeTime 2>/dev/null && echo "defaults write NSGlobalDomain NSWindowResizeTime -float $(defaults read NSGlobalDomain NSWindowResizeTime)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain NSWindowResizeTime -float 0.001" >> macos-defaults.sh
defaults read NSGlobalDomain NSNavPanelExpandedStateForSaveMode 2>/dev/null && echo "defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool $(defaults read NSGlobalDomain NSNavPanelExpandedStateForSaveMode)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true" >> macos-defaults.sh
defaults read NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 2>/dev/null && echo "defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool $(defaults read NSGlobalDomain NSNavPanelExpandedStateForSaveMode2)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true" >> macos-defaults.sh
defaults read NSGlobalDomain PMPrintingExpandedStateForPrint 2>/dev/null && echo "defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool $(defaults read NSGlobalDomain PMPrintingExpandedStateForPrint)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true" >> macos-defaults.sh
defaults read NSGlobalDomain PMPrintingExpandedStateForPrint2 2>/dev/null && echo "defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool $(defaults read NSGlobalDomain PMPrintingExpandedStateForPrint2)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true" >> macos-defaults.sh
defaults read NSGlobalDomain AppleShowScrollBars 2>/dev/null && echo "defaults write NSGlobalDomain AppleShowScrollBars -string '$(defaults read NSGlobalDomain AppleShowScrollBars)'" >> macos-defaults.sh || echo "defaults write NSGlobalDomain AppleShowScrollBars -string 'Always'" >> macos-defaults.sh
defaults read NSGlobalDomain NSUseAnimatedFocusRing 2>/dev/null && echo "defaults write NSGlobalDomain NSUseAnimatedFocusRing -bool $(defaults read NSGlobalDomain NSUseAnimatedFocusRing)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain NSUseAnimatedFocusRing -bool false" >> macos-defaults.sh
defaults read NSGlobalDomain com.apple.mouse.tapBehavior 2>/dev/null && echo "defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int $(defaults read NSGlobalDomain com.apple.mouse.tapBehavior)" >> macos-defaults.sh || echo "defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1" >> macos-defaults.sh

cat >> macos-defaults.sh << 'SCRIPT_EOF'

# ============================================
# SECURITY SETTINGS
# ============================================

SCRIPT_EOF

# Export Security settings
echo "# Security: disable quarantine dialog for downloaded apps" >> macos-defaults.sh
defaults read com.apple.LaunchServices LSQuarantine 2>/dev/null && echo "defaults write com.apple.LaunchServices LSQuarantine -bool $(defaults read com.apple.LaunchServices LSQuarantine)" >> macos-defaults.sh || echo "defaults write com.apple.LaunchServices LSQuarantine -bool false" >> macos-defaults.sh

cat >> macos-defaults.sh << 'SCRIPT_EOF'

# ============================================
# TRACKPAD SETTINGS
# ============================================

SCRIPT_EOF

# Export Trackpad settings
echo "# Trackpad: enable tap to click" >> macos-defaults.sh
defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking 2>/dev/null && echo "defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool $(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking)" >> macos-defaults.sh || echo "defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true" >> macos-defaults.sh

cat >> macos-defaults.sh << 'SCRIPT_EOF'

# ============================================
# RESTART AFFECTED APPLICATIONS
# ============================================

echo "Restarting affected applications..."
killall Finder 2>/dev/null || true
killall Dock 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true

echo ""
echo "✅ macOS defaults restored successfully!"
echo ""
echo "Some changes may require a logout/restart to take full effect."
SCRIPT_EOF

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
| `macos-defaults.sh` | macOS system preferences (comprehensive backup) |
| `appstore-apps.txt` | List of installed apps |

## macOS Defaults

The `macos-defaults.sh` script restores all your macOS system preferences including:

### Dock
- Auto-hide with immediate appearance
- Translucent hidden apps
- No recent apps
- Fast Mission Control animations
- Scale minimize effect

### Finder
- Path bar and status bar visible
- Show all file extensions
- Folders first when sorting
- No .DS_Store on network/USB
- Disable animations

### Screenshots
- Save to Downloads
- PNG format
- No window shadow

### Keyboard & Typing
- Fast key repeat (no press-and-hold)
- Disable auto-correct, smart quotes, auto-capitalization

### UI/UX
- Fast window resizing
- Expanded save/print panels
- Always show scrollbars
- Tap to click enabled

Run this script manually if needed:
```bash
bash macos-defaults.sh
```
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
