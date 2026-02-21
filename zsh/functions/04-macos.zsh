# macOS System Functions
# macOS defaults and system helpers

# Apply macOS system defaults
macos-defaults() {
    # Finder: show path bar
    defaults write com.apple.finder ShowPathbar -bool true
    
    # Dock: auto-hide
    defaults write com.apple.dock autohide -bool true
    
    # Screenshots: save to Downloads, disable shadow
    defaults write com.apple.screencapture location -string "${HOME}/Downloads"
    defaults write com.apple.screencapture disable-shadow -bool true
    
    # Restart affected apps
    killall Finder
    killall Dock
    
    echo "✅ macOS defaults applied"
}

# Copy current directory to clipboard
cpwd() {
    pwd | tr -d '\n' | pbcopy
    echo "📋 Path copied: $(pwd)"
}
