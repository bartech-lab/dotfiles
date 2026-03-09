# macOS System Functions
# macOS defaults and system helpers

# Apply macOS system defaults
# This function configures various macOS system preferences for a better
# development experience. Run this after setting up a new Mac or when
# you want to reset system preferences to your preferred defaults.
#
# Settings applied:
# - Dock: auto-hide with immediate appearance, tile size 66, process indicators
# - Dock: disable all hot corners, translucent hidden apps, no recent apps
# - Finder: show path bar, status bar, all extensions, folders first
# - Finder: new window opens to ~/timac/, show Library folder
# - Finder: disable animations, extension change warnings
# - Finder: no .DS_Store on network/USB volumes
# - Screenshots: save to Downloads, disable shadow, PNG format
# - Keyboard: disable press-and-hold, enable fast key repeat
# - Keyboard: disable auto-capitalization, smart quotes, auto-correct
# - UI: faster window resize, expanded save panels, always show scrollbars
# - Security: disable quarantine dialog, login window info
# - System: disable boot sound, Photos auto-open
# - Apps: VS Code, Spotify, Docker, Slack defaults
macos-defaults() {
    echo "Applying macOS system defaults..."
    
    # ============================================
    # SYSTEM SETTINGS (Require sudo)
    # ============================================
    
    # System: disable boot sound
    sudo nvram SystemAudioVolume=" "
    
    # System: show IP address, hostname, OS version when clicking clock at login
    sudo defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName
    
    # ============================================
    # DOCK SETTINGS
    # ============================================
    
    # Dock: auto-hide
    defaults write com.apple.dock autohide -bool true
    
    # Dock: show almost immediately (no delay, no animation)
    defaults write com.apple.dock autohide-delay -float 0
    defaults write com.apple.dock autohide-time-modifier -float 0
    
    # Dock: set tile size to 66 pixels
    defaults write com.apple.dock tilesize -int 66
    
    # Dock: show indicator lights for open applications
    defaults write com.apple.dock show-process-indicators -bool true
    
    # Dock: make hidden application icons translucent
    defaults write com.apple.dock showhidden -bool true
    
    # Dock: don't show recent applications
    defaults write com.apple.dock show-recents -bool false
    
    # Dock: speed up Mission Control animations
    defaults write com.apple.dock expose-animation-duration -float 0.1
    
    # Dock: don't automatically rearrange Spaces based on most recent use
    defaults write com.apple.dock mru-spaces -bool false
    
    # Dock: use scale effect for minimizing windows (faster than genie)
    defaults write com.apple.dock mineffect -string "scale"
    
    # Dock: minimize windows into their application's icon
    defaults write com.apple.dock minimize-to-application -bool true
    
    # Dock: don't animate opening applications
    defaults write com.apple.dock launchanim -bool false
    
    # Dock: clear "Others" section (Downloads, etc.) but keep pinned apps
    defaults write com.apple.dock persistent-others -array
    
    # Dock: disable all hot corners (set all to 0 = no action)
    defaults write com.apple.dock wvous-tl-corner -int 0
    defaults write com.apple.dock wvous-tl-modifier -int 0
    defaults write com.apple.dock wvous-tr-corner -int 0
    defaults write com.apple.dock wvous-tr-modifier -int 0
    defaults write com.apple.dock wvous-bl-corner -int 0
    defaults write com.apple.dock wvous-bl-modifier -int 0
    defaults write com.apple.dock wvous-br-corner -int 0
    defaults write com.apple.dock wvous-br-modifier -int 0
    
    # ============================================
    # FINDER SETTINGS
    # ============================================
    
    # Finder: show path bar
    defaults write com.apple.finder ShowPathbar -bool true
    
    # Finder: show status bar
    defaults write com.apple.finder ShowStatusBar -bool true
    
    # Finder: show all filename extensions
    defaults write NSGlobalDomain AppleShowAllExtensions -bool true
    
    # Finder: keep folders on top when sorting by name
    defaults write com.apple.finder _FXSortFoldersFirst -bool true
    
    # Finder: search the current folder by default
    defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
    
    # Finder: disable the warning when changing a file extension
    defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
    
    # Finder: disable window animations and Get Info animations
    defaults write com.apple.finder DisableAllAnimations -bool true
    
    # Finder: show full POSIX path as window title
    defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
    
    # Finder: allow quitting via ⌘ + Q
    defaults write com.apple.finder QuitMenuItem -bool true
    
    # Finder: set new window target to ~/timac/
    defaults write com.apple.finder NewWindowTarget -string "PfLo"
    defaults write com.apple.finder NewWindowTargetPath -string "file:///Users/timac/"
    
    # Finder: show the ~/Library folder
    chflags nohidden ~/Library
    
    # Finder: avoid creating .DS_Store files on network volumes
    defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
    
    # Finder: avoid creating .DS_Store files on USB volumes
    defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true

    # Finder: don't show icons on desktop (hide clutter)
    defaults write com.apple.finder CreateDesktop -bool false

    # ============================================
    # SCREENSHOT SETTINGS
    # ============================================
    
    # Screenshots: save to Downloads
    defaults write com.apple.screencapture location -string "${HOME}/Downloads"
    
    # Screenshots: disable shadow around windows
    defaults write com.apple.screencapture disable-shadow -bool true
    
    # Screenshots: save in PNG format (better quality than JPG)
    defaults write com.apple.screencapture type -string "png"
    
    # ============================================
    # KEYBOARD SETTINGS
    # ============================================
    
    # Keyboard: disable press-and-hold for keys in favor of key repeat
    # This allows keys to repeat when held down instead of showing accent menu
    defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false
    
    # Keyboard: set fast but comfortable key repeat rate (2 = fast, 6 = default)
    defaults write NSGlobalDomain KeyRepeat -int 5
    
    # Keyboard: set short delay before key repeat starts (10 = shortest)
    defaults write NSGlobalDomain InitialKeyRepeat -int 25
    
    # Keyboard: enable full keyboard access for all controls
    # Allows Tab to work in modal dialogs, not just text fields
    defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
    
    # ============================================
    # TYPING / TEXT SETTINGS
    # ============================================
    
    # Typing: disable automatic capitalization
    defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false
    
    # Typing: disable smart dashes (converts -- to em-dash)
    defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
    
    # Typing: disable automatic period substitution (double-space)
    defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool false
    
    # Typing: disable smart quotes (converts " to curly quotes)
    defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
    
    # Typing: disable auto-correct
    defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false
    
    # ============================================
    # UI / WINDOW SETTINGS
    # ============================================
    
    # UI: disable window animations globally
    defaults write -g NSAutomaticWindowAnimationsEnabled -bool false
    
    # UI: increase window resize speed for Cocoa applications
    defaults write NSGlobalDomain NSWindowResizeTime -float 0.001
    
    # UI: disable QuickLook panel animations
    defaults write -g QLPanelAnimationDuration -float 0
    
    # UI: expand save panel by default (shows sidebar, favorites)
    defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
    defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true
    
    # UI: expand print panel by default
    defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true
    defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool true
    
    # UI: always show scrollbars (not just when scrolling)
    defaults write NSGlobalDomain AppleShowScrollBars -string "Always"
    
    # UI: disable the over-the-top focus ring animation
    defaults write NSGlobalDomain NSUseAnimatedFocusRing -bool false
    
    # UI: reduce motion (disable animations)
    defaults write com.apple.universalaccess reduceMotion -bool true
    
    # UI: reduce transparency (better performance)
    defaults write com.apple.universalaccess reduceTransparency -bool true
    
    # UI: disable window manager (Stage Manager)
    defaults write com.apple.WindowManager GloballyEnabled -bool false
    
    # UI: disable the "Are you sure you want to open this application?" dialog
    defaults write com.apple.LaunchServices LSQuarantine -bool false
    
    # ============================================
    # TRACKPAD SETTINGS
    # ============================================
    
    # Trackpad: enable tap to click
    defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
    defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
    defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
    
    # ============================================
    # PHOTOS SETTINGS
    # ============================================
    
    # Photos: prevent from opening automatically when devices are plugged in
    defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool true
    
    # ============================================
    # CHROME SETTINGS
    # ============================================
    
    # Chrome: disable backswipe on trackpad (prevents accidental navigation)
    defaults write com.google.Chrome AppleEnableSwipeNavigateWithScrolls -bool false
    defaults write com.google.Chrome.canary AppleEnableSwipeNavigateWithScrolls -bool false
    
    # Chrome: use system-native print preview dialog
    defaults write com.google.Chrome DisablePrintPreview -bool true
    defaults write com.google.Chrome.canary DisablePrintPreview -bool true
    
    # Chrome: expand print dialog by default
    defaults write com.google.Chrome PMPrintingExpandedStateForPrint2 -bool true
    defaults write com.google.Chrome.canary PMPrintingExpandedStateForPrint2 -bool true
    
    # ============================================
    # VS CODE / VSCODIUM SETTINGS
    # ============================================
    
    # VS Code: disable smooth scrolling (better performance)
    defaults write com.microsoft.VSCode ApplePressAndHoldEnabled -bool false
    defaults write com.vscodium ApplePressAndHoldEnabled -bool false
    
    # VS Code: disable native full screen (use macOS full screen)
    defaults write com.microsoft.VSCode AppleWindowTabbingMode -string "manual"
    defaults write com.vscodium AppleWindowTabbingMode -string "manual"
    
    # ============================================
    # SPOTIFY SETTINGS
    # ============================================
    
    # Spotify: disable auto-start on login
    defaults write com.spotify.client AutoStart -bool false
    
    # ============================================
    # DOCKER DESKTOP SETTINGS
    # ============================================
    
    # Docker: disable automatic startup
    defaults write com.docker.docker AutoStart -bool false
    
    # Docker: disable analytics
    defaults write com.docker.docker analyticsEnabled -bool false
    
    # ============================================
    # SLACK SETTINGS
    # ============================================
    
    # Slack: disable spell checking
    defaults write com.tinyspeck.slackmacgap SpellCheckingEnabled -bool false
    
    # Slack: disable smart quotes and dashes
    defaults write com.tinyspeck.slackmacgap AutomaticQuoteSubstitutionEnabled -bool false
    defaults write com.tinyspeck.slackmacgap AutomaticDashSubstitutionEnabled -bool false
    
    # ============================================
    # RESTART AFFECTED APPLICATIONS
    # ============================================
    
    echo "Restarting affected applications..."
    
    # Restart Finder to apply changes
    killall Finder 2>/dev/null || true
    
    # Restart Dock to apply changes
    killall Dock 2>/dev/null || true
    
    # Restart SystemUIServer for some UI changes
    killall SystemUIServer 2>/dev/null || true
    
    echo ""
    echo "✅ macOS defaults applied successfully!"
    echo ""
    echo "Some changes may require a logout/restart to take full effect."
    echo ""
    echo "Key changes:"
    echo "  • Dock auto-hides with immediate appearance (size: 66px)"
    echo "  • All hot corners disabled"
    echo "  • Finder opens to ~/timac/, Library folder visible"
    echo "  • Desktop icons hidden (clutter-free)"
    echo "  • No .DS_Store files on network/USB drives"
    echo "  • Screenshots saved to Downloads as PNG (no shadow)"
    echo "  • Fast key repeat, no press-and-hold"
    echo "  • Disabled auto-correct, smart quotes, auto-capitalization"
    echo "  • Reduced motion and transparency (better performance)"
    echo "  • Window animations disabled globally"
    echo "  • Stage Manager disabled"
    echo "  • Boot sound disabled"
    echo "  • Chrome backswipe disabled"
    echo "  • Photos won't auto-open on device connect"
}

# Debloat macOS by removing unnecessary apps and disabling services
# WARNING: This function makes destructive changes. Review carefully before running.
# Apps can be re-downloaded from App Store if needed.
macos-debloat() {
    echo "⚠️  macOS Debloat - Destructive Operations"
    echo "=========================================="
    echo ""
    echo "This will:"
    echo "  • Remove optional Apple apps (re-downloadable from App Store)"
    echo "  • Disable non-essential background services"
    echo "  • Optionally clean Xcode dev files"
    echo ""
    echo "Protected services (will NOT be touched):"
    echo "  • Notification Center, Mail, Messages, iCloud"
    echo "  • System security services (trustd, securityd)"
    echo "  • Networking (mDNSResponder, apsd)"
    echo ""
    
    local confirm
    echo -n "Continue? (y/N): "
    read confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        return 1
    fi
    
    echo ""
    echo "Starting debloat process..."
    echo ""

    # ============================================
    # APP REMOVAL (Re-downloadable from App Store)
    # ============================================
    
    echo "📦 Checking for removable Apple apps..."
    
    local apps_to_remove=(
        "GarageBand.app"
        "iMovie.app"
        "Keynote.app"
        "Pages.app"
        "Numbers.app"
        "TV.app"
        "Podcasts.app"
        "Home.app"
        "Stocks.app"
        "News.app"
        "Tips.app"
        "Freeform.app"
        "Chess.app"
        "Photo Booth.app"
        "VoiceMemos.app"
        "Books.app"
    )
    
    local removed_count=0
    for app in "${apps_to_remove[@]}"; do
        if [[ -d "/Applications/$app" ]]; then
            echo "  Removing: $app"
            sudo rm -rf "/Applications/$app"
            ((removed_count++))
        fi
    done
    
    if [[ $removed_count -eq 0 ]]; then
        echo "  No removable apps found (already removed or not present)"
    else
        echo "  Removed $removed_count app(s)"
    fi
    
    echo ""

    # ============================================
    # SERVICE DISABLING (User-level only)
    # ============================================
    
    echo "🔧 Disabling non-essential background services..."
    
    # Tips app - shows "helpful" tips
    echo "  Disabling: Tips"
    launchctl disable gui/$(id -u)/com.apple.Tips 2>/dev/null || true
    
    # Game Center - gaming social features
    echo "  Disabling: Game Center"
    launchctl disable gui/$(id -u)/com.apple.gamed 2>/dev/null || true
    
    # Photo analysis - face detection, scene recognition
    echo "  Disabling: Photo Analysis"
    launchctl disable gui/$(id -u)/com.apple.photoanalysisd 2>/dev/null || true
    
    # Cloud photo daemon - if not using iCloud Photos
    echo "  Disabling: Cloud Photos"
    launchctl disable gui/$(id -u)/com.apple.cloudphotod 2>/dev/null || true
    
    # Siri - voice assistant
    echo "  Disabling: Siri"
    defaults write com.apple.Siri StatusMenuVisible -bool false
    defaults write com.apple.assistant.support "Assistant Enabled" -bool false
    launchctl disable gui/$(id -u)/com.apple.siri 2>/dev/null || true
    
    echo ""

    # ============================================
    # XCODE CLEANUP (Optional)
    # ============================================
    
    if [[ -d "$HOME/Library/Developer/Xcode" ]]; then
        echo "🛠️  Xcode cleanup detected"
        echo ""
        echo "The following can be safely cleaned:"
        echo "  1. DerivedData (build artifacts)"
        echo "  2. iOS DeviceSupport (old device debug symbols)"
        echo "  3. Unavailable simulators"
        echo ""
        
        local xcode_choice
        echo -n "Run Xcode cleanup? (y/N): "
        read xcode_choice
        
        if [[ "$xcode_choice" =~ ^[Yy]$ ]]; then
            echo ""
            echo "Cleaning Xcode files..."
            
            # DerivedData - build artifacts, safe to delete
            if [[ -d "$HOME/Library/Developer/Xcode/DerivedData" ]]; then
                echo "  Cleaning DerivedData..."
                rm -rf "$HOME/Library/Developer/Xcode/DerivedData"/*
            fi
            
            # iOS DeviceSupport - debug symbols for old devices
            if [[ -d "$HOME/Library/Developer/Xcode/iOS DeviceSupport" ]]; then
                echo "  Cleaning old iOS DeviceSupport files..."
                # Keep only the latest iOS version for each device
                find "$HOME/Library/Developer/Xcode/iOS DeviceSupport" -maxdepth 1 -type d -mtime +30 -exec rm -rf {} + 2>/dev/null || true
            fi
            
            # Unavailable simulators
            if command -v xcrun &> /dev/null; then
                echo "  Removing unavailable simulators..."
                xcrun simctl delete unavailable 2>/dev/null || true
            fi
            
            echo "  Xcode cleanup complete"
        else
            echo "  Skipped Xcode cleanup"
        fi
    fi
    
    echo ""
    echo "✅ Debloat complete!"
    echo ""
    echo "Summary:"
    echo "  • Removed $removed_count optional Apple app(s)"
    echo "  • Disabled: Tips, Game Center, Photo Analysis, Cloud Photos, Siri"
    echo ""
    echo "To re-enable any service:"
    echo "  launchctl enable gui/\$(id -u)/com.apple.SERVICE"
    echo ""
    echo "To restore apps: Download from Mac App Store"
}

# Analyze system launchctl services (diagnostic only)
# This function provides advisory information about running services.
# It does NOT make any changes - review output and disable manually if desired.
macos-system-analysis() {
    echo "🔍 macOS System Analysis"
    echo "========================"
    echo ""
    echo "This will analyze system services and provide recommendations."
    echo "No changes will be made automatically."
    echo ""
    
    local confirm
    echo -n "Continue? (y/N): "
    read confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        return 1
    fi
    
    echo ""
    echo "Gathering system information..."
    echo ""

    # ============================================
    # USER SERVICES ANALYSIS
    # ============================================
    
    echo "📊 User Services (gui/$(id -u))"
    echo "--------------------------------"
    
    # Get list of user services
    local user_services=$(launchctl print gui/$(id -u) 2>/dev/null | grep -E "^\s+[0-9]+" | awk '{print $NF}' | sort -u)
    
    local apple_core=()
    local apple_optional=()
    local third_party=()
    
    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        
        if [[ "$service" == com.apple.* ]]; then
            # Classify Apple services
            case "$service" in
                # Core system - NEVER disable
                com.apple.WindowServer|com.apple.distnoted|com.apple.notificationcenterui|\
                com.apple.apsd|com.apple.cloudd|com.apple.mDNSResponder|\
                com.apple.trustd|com.apple.securityd|com.apple.identityservicesd|\
                com.apple.accountsd|com.apple.loginwindow|com.apple.dock|\
                com.apple.finder|com.apple.systemuiserver)
                    apple_core+=("$service")
                    ;;
                # Optional - can be reviewed
                *)
                    apple_optional+=("$service")
                    ;;
            esac
        else
            third_party+=("$service")
        fi
    done <<< "$user_services"
    
    echo ""
    echo "🔒 Apple Core Services (${#apple_core[@]}):"
    echo "   (Protected - do not disable)"
    for svc in "${apple_core[@]}"; do
        echo "     • $svc"
    done
    
    echo ""
    echo "⚙️  Apple Optional Services (${#apple_optional[@]}):"
    echo "   (Review these - some can be disabled)"
    
    # Highlight commonly disabled services
    for svc in "${apple_optional[@]}"; do
        local note=""
        case "$svc" in
            *gamed*) note=" ← Game Center (safe to disable if not gaming)" ;;
            *Tips*) note=" ← Tips app (safe to disable)" ;;
            *siri*) note=" ← Siri (safe to disable if not using voice)" ;;
            *photoanalysisd*) note=" ← Photo analysis (safe to disable)" ;;
            *cloudphotod*) note=" ← iCloud Photos (disable if not using iCloud Photos)" ;;
        esac
        echo "     • $svc$note"
    done
    
    echo ""
    echo "🔌 Third-Party Services (${#third_party[@]}):"
    for svc in "${third_party[@]}"; do
        echo "     • $svc"
    done
    
    echo ""

    # ============================================
    # SYSTEM SERVICES ANALYSIS (requires sudo)
    # ============================================
    
    echo "📊 System Services"
    echo "------------------"
    echo ""
    echo "Note: Full system service list requires sudo."
    echo "Run manually if needed: sudo launchctl print system"
    echo ""
    
    # Try to get system services without sudo (limited)
    local system_services=$(launchctl print system 2>/dev/null | head -50)
    
    if [[ -n "$system_services" ]]; then
        echo "System services (first 50 lines):"
        echo "$system_services"
    else
        echo "Unable to read system services without elevated privileges."
    fi
    
    echo ""

    # ============================================
    # RECOMMENDATIONS
    # ============================================
    
    echo "📋 Recommendations"
    echo "------------------"
    echo ""
    echo "Safe to disable (if not using):"
    echo "  • com.apple.gamed - Game Center social features"
    echo "  • com.apple.Tips - Help tips popup"
    echo "  • com.apple.photoanalysisd - Photo face/scene detection"
    echo "  • com.apple.cloudphotod - iCloud Photos sync"
    echo "  • com.apple.siri* - Voice assistant"
    echo ""
    echo "⚠️  NEVER disable these (will break system):"
    echo "  • WindowServer, distnoted, notificationcenterui"
    echo "  • apsd (push notifications), cloudd (iCloud)"
    echo "  • mDNSResponder (AirDrop, network discovery)"
    echo "  • trustd, securityd (security validation)"
    echo "  • identityservicesd, accountsd (sign-in)"
    echo ""
    echo "To disable a service:"
    echo "  launchctl disable gui/\$(id -u)/com.apple.SERVICE"
    echo ""
    echo "To re-enable:"
    echo "  launchctl enable gui/\$(id -u)/com.apple.SERVICE"
    echo ""
    echo "✅ Analysis complete. Review the list above and disable services manually."
}

# Export current macOS defaults to a shell script
# Useful for backing up or migrating settings to another Mac
# Usage: macos-defaults-export > ~/macos-settings-backup.sh
macos-defaults-export() {
    echo "#!/usr/bin/env zsh"
    echo "# macOS Defaults Export"
    echo "# Generated: $(date)"
    echo "# This script will restore your macOS system preferences"
    echo ""
    echo "set -euo pipefail"
    echo ""
    echo 'echo "Restoring macOS defaults..."'
    echo ""
    
    # System settings (require sudo)
    echo "# System settings (require sudo)"
    echo "sudo nvram SystemAudioVolume=\" \""
    sudo defaults read /Library/Preferences/com.apple.loginwindow AdminHostInfo 2>/dev/null && echo "sudo defaults write /Library/Preferences/com.apple.loginwindow AdminHostInfo HostName"
    
    echo ""
    
    # Dock settings
    echo "# Dock settings"
    defaults read com.apple.dock autohide 2>/dev/null && echo "defaults write com.apple.dock autohide -bool $(defaults read com.apple.dock autohide)"
    defaults read com.apple.dock autohide-delay 2>/dev/null && echo "defaults write com.apple.dock autohide-delay -float $(defaults read com.apple.dock autohide-delay)"
    defaults read com.apple.dock autohide-time-modifier 2>/dev/null && echo "defaults write com.apple.dock autohide-time-modifier -float $(defaults read com.apple.dock autohide-time-modifier)"
    defaults read com.apple.dock tilesize 2>/dev/null && echo "defaults write com.apple.dock tilesize -int $(defaults read com.apple.dock tilesize)"
    defaults read com.apple.dock show-process-indicators 2>/dev/null && echo "defaults write com.apple.dock show-process-indicators -bool $(defaults read com.apple.dock show-process-indicators)"
    defaults read com.apple.dock showhidden 2>/dev/null && echo "defaults write com.apple.dock showhidden -bool $(defaults read com.apple.dock showhidden)"
    defaults read com.apple.dock show-recents 2>/dev/null && echo "defaults write com.apple.dock show-recents -bool $(defaults read com.apple.dock show-recents)"
    defaults read com.apple.dock expose-animation-duration 2>/dev/null && echo "defaults write com.apple.dock expose-animation-duration -float $(defaults read com.apple.dock expose-animation-duration)"
    defaults read com.apple.dock mru-spaces 2>/dev/null && echo "defaults write com.apple.dock mru-spaces -bool $(defaults read com.apple.dock mru-spaces)"
    defaults read com.apple.dock mineffect 2>/dev/null && echo "defaults write com.apple.dock mineffect -string '$(defaults read com.apple.dock mineffect)'"
    defaults read com.apple.dock minimize-to-application 2>/dev/null && echo "defaults write com.apple.dock minimize-to-application -bool $(defaults read com.apple.dock minimize-to-application)"
    defaults read com.apple.dock launchanim 2>/dev/null && echo "defaults write com.apple.dock launchanim -bool $(defaults read com.apple.dock launchanim)"
    defaults read com.apple.dock wvous-tl-corner 2>/dev/null && echo "defaults write com.apple.dock wvous-tl-corner -int $(defaults read com.apple.dock wvous-tl-corner)"
    defaults read com.apple.dock wvous-tl-modifier 2>/dev/null && echo "defaults write com.apple.dock wvous-tl-modifier -int $(defaults read com.apple.dock wvous-tl-modifier)"
    defaults read com.apple.dock wvous-tr-corner 2>/dev/null && echo "defaults write com.apple.dock wvous-tr-corner -int $(defaults read com.apple.dock wvous-tr-corner)"
    defaults read com.apple.dock wvous-tr-modifier 2>/dev/null && echo "defaults write com.apple.dock wvous-tr-modifier -int $(defaults read com.apple.dock wvous-tr-modifier)"
    defaults read com.apple.dock wvous-bl-corner 2>/dev/null && echo "defaults write com.apple.dock wvous-bl-corner -int $(defaults read com.apple.dock wvous-bl-corner)"
    defaults read com.apple.dock wvous-bl-modifier 2>/dev/null && echo "defaults write com.apple.dock wvous-bl-modifier -int $(defaults read com.apple.dock wvous-bl-modifier)"
    defaults read com.apple.dock wvous-br-corner 2>/dev/null && echo "defaults write com.apple.dock wvous-br-corner -int $(defaults read com.apple.dock wvous-br-corner)"
    defaults read com.apple.dock wvous-br-modifier 2>/dev/null && echo "defaults write com.apple.dock wvous-br-modifier -int $(defaults read com.apple.dock wvous-br-modifier)"
    
    echo ""
    
    # Finder settings
    echo "# Finder settings"
    defaults read com.apple.finder ShowPathbar 2>/dev/null && echo "defaults write com.apple.finder ShowPathbar -bool $(defaults read com.apple.finder ShowPathbar)"
    defaults read com.apple.finder ShowStatusBar 2>/dev/null && echo "defaults write com.apple.finder ShowStatusBar -bool $(defaults read com.apple.finder ShowStatusBar)"
    defaults read com.apple.finder _FXSortFoldersFirst 2>/dev/null && echo "defaults write com.apple.finder _FXSortFoldersFirst -bool $(defaults read com.apple.finder _FXSortFoldersFirst)"
    defaults read com.apple.finder FXDefaultSearchScope 2>/dev/null && echo "defaults write com.apple.finder FXDefaultSearchScope -string '$(defaults read com.apple.finder FXDefaultSearchScope)'"
    defaults read com.apple.finder FXEnableExtensionChangeWarning 2>/dev/null && echo "defaults write com.apple.finder FXEnableExtensionChangeWarning -bool $(defaults read com.apple.finder FXEnableExtensionChangeWarning)"
    defaults read com.apple.finder DisableAllAnimations 2>/dev/null && echo "defaults write com.apple.finder DisableAllAnimations -bool $(defaults read com.apple.finder DisableAllAnimations)"
    defaults read com.apple.finder _FXShowPosixPathInTitle 2>/dev/null && echo "defaults write com.apple.finder _FXShowPosixPathInTitle -bool $(defaults read com.apple.finder _FXShowPosixPathInTitle)"
    defaults read com.apple.finder QuitMenuItem 2>/dev/null && echo "defaults write com.apple.finder QuitMenuItem -bool $(defaults read com.apple.finder QuitMenuItem)"
    defaults read com.apple.finder NewWindowTarget 2>/dev/null && echo "defaults write com.apple.finder NewWindowTarget -string '$(defaults read com.apple.finder NewWindowTarget)'"
    defaults read com.apple.finder NewWindowTargetPath 2>/dev/null && echo "defaults write com.apple.finder NewWindowTargetPath -string '$(defaults read com.apple.finder NewWindowTargetPath)'"
    defaults read com.apple.desktopservices DSDontWriteNetworkStores 2>/dev/null && echo "defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool $(defaults read com.apple.desktopservices DSDontWriteNetworkStores)"
    defaults read com.apple.desktopservices DSDontWriteUSBStores 2>/dev/null && echo "defaults write com.apple.desktopservices DSDontWriteUSBStores -bool $(defaults read com.apple.desktopservices DSDontWriteUSBStores)"
    
    echo ""
    
    # Screenshot settings
    echo "# Screenshot settings"
    defaults read com.apple.screencapture location 2>/dev/null && echo "defaults write com.apple.screencapture location -string '$(defaults read com.apple.screencapture location)'"
    defaults read com.apple.screencapture disable-shadow 2>/dev/null && echo "defaults write com.apple.screencapture disable-shadow -bool $(defaults read com.apple.screencapture disable-shadow)"
    defaults read com.apple.screencapture type 2>/dev/null && echo "defaults write com.apple.screencapture type -string '$(defaults read com.apple.screencapture type)'"
    
    echo ""
    
    # Global settings (NSGlobalDomain)
    echo "# Global settings"
    defaults read NSGlobalDomain AppleShowAllExtensions 2>/dev/null && echo "defaults write NSGlobalDomain AppleShowAllExtensions -bool $(defaults read NSGlobalDomain AppleShowAllExtensions)"
    defaults read NSGlobalDomain ApplePressAndHoldEnabled 2>/dev/null && echo "defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool $(defaults read NSGlobalDomain ApplePressAndHoldEnabled)"
    defaults read NSGlobalDomain KeyRepeat 2>/dev/null && echo "defaults write NSGlobalDomain KeyRepeat -int $(defaults read NSGlobalDomain KeyRepeat)"
    defaults read NSGlobalDomain InitialKeyRepeat 2>/dev/null && echo "defaults write NSGlobalDomain InitialKeyRepeat -int $(defaults read NSGlobalDomain InitialKeyRepeat)"
    defaults read NSGlobalDomain AppleKeyboardUIMode 2>/dev/null && echo "defaults write NSGlobalDomain AppleKeyboardUIMode -int $(defaults read NSGlobalDomain AppleKeyboardUIMode)"
    defaults read NSGlobalDomain NSAutomaticCapitalizationEnabled 2>/dev/null && echo "defaults write NSGlobalDomain NSAutomaticCapitalizationEnabled -bool $(defaults read NSGlobalDomain NSAutomaticCapitalizationEnabled)"
    defaults read NSGlobalDomain NSAutomaticDashSubstitutionEnabled 2>/dev/null && echo "defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool $(defaults read NSGlobalDomain NSAutomaticDashSubstitutionEnabled)"
    defaults read NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled 2>/dev/null && echo "defaults write NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled -bool $(defaults read NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled)"
    defaults read NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled 2>/dev/null && echo "defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool $(defaults read NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled)"
    defaults read NSGlobalDomain NSAutomaticSpellingCorrectionEnabled 2>/dev/null && echo "defaults write NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool $(defaults read NSGlobalDomain NSAutomaticSpellingCorrectionEnabled)"
    defaults read NSGlobalDomain NSWindowResizeTime 2>/dev/null && echo "defaults write NSGlobalDomain NSWindowResizeTime -float $(defaults read NSGlobalDomain NSWindowResizeTime)"
    defaults read NSGlobalDomain NSNavPanelExpandedStateForSaveMode 2>/dev/null && echo "defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool $(defaults read NSGlobalDomain NSNavPanelExpandedStateForSaveMode)"
    defaults read NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 2>/dev/null && echo "defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool $(defaults read NSGlobalDomain NSNavPanelExpandedStateForSaveMode2)"
    defaults read NSGlobalDomain PMPrintingExpandedStateForPrint 2>/dev/null && echo "defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool $(defaults read NSGlobalDomain PMPrintingExpandedStateForPrint)"
    defaults read NSGlobalDomain PMPrintingExpandedStateForPrint2 2>/dev/null && echo "defaults write NSGlobalDomain PMPrintingExpandedStateForPrint2 -bool $(defaults read NSGlobalDomain PMPrintingExpandedStateForPrint2)"
    defaults read NSGlobalDomain AppleShowScrollBars 2>/dev/null && echo "defaults write NSGlobalDomain AppleShowScrollBars -string '$(defaults read NSGlobalDomain AppleShowScrollBars)'"
    defaults read NSGlobalDomain NSUseAnimatedFocusRing 2>/dev/null && echo "defaults write NSGlobalDomain NSUseAnimatedFocusRing -bool $(defaults read NSGlobalDomain NSUseAnimatedFocusRing)"
    defaults read NSGlobalDomain com.apple.mouse.tapBehavior 2>/dev/null && echo "defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int $(defaults read NSGlobalDomain com.apple.mouse.tapBehavior)"
    
    echo ""
    
    # LaunchServices
    echo "# Security settings"
    defaults read com.apple.LaunchServices LSQuarantine 2>/dev/null && echo "defaults write com.apple.LaunchServices LSQuarantine -bool $(defaults read com.apple.LaunchServices LSQuarantine)"
    
    echo ""
    
    # Trackpad
    echo "# Trackpad settings"
    defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking 2>/dev/null && echo "defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool $(defaults read com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking)"
    
    echo ""
    
    # Photos
    echo "# Photos settings"
    defaults read -currentHost com.apple.ImageCapture disableHotPlug 2>/dev/null && echo "defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool $(defaults read -currentHost com.apple.ImageCapture disableHotPlug)"
    
    echo ""
    
    # Chrome
    echo "# Chrome settings"
    defaults read com.google.Chrome AppleEnableSwipeNavigateWithScrolls 2>/dev/null && echo "defaults write com.google.Chrome AppleEnableSwipeNavigateWithScrolls -bool $(defaults read com.google.Chrome AppleEnableSwipeNavigateWithScrolls)"
    defaults read com.google.Chrome.canary AppleEnableSwipeNavigateWithScrolls 2>/dev/null && echo "defaults write com.google.Chrome.canary AppleEnableSwipeNavigateWithScrolls -bool $(defaults read com.google.Chrome.canary AppleEnableSwipeNavigateWithScrolls)"
    defaults read com.google.Chrome DisablePrintPreview 2>/dev/null && echo "defaults write com.google.Chrome DisablePrintPreview -bool $(defaults read com.google.Chrome DisablePrintPreview)"
    defaults read com.google.Chrome.canary DisablePrintPreview 2>/dev/null && echo "defaults write com.google.Chrome.canary DisablePrintPreview -bool $(defaults read com.google.Chrome.canary DisablePrintPreview)"
    defaults read com.google.Chrome PMPrintingExpandedStateForPrint2 2>/dev/null && echo "defaults write com.google.Chrome PMPrintingExpandedStateForPrint2 -bool $(defaults read com.google.Chrome PMPrintingExpandedStateForPrint2)"
    defaults read com.google.Chrome.canary PMPrintingExpandedStateForPrint2 2>/dev/null && echo "defaults write com.google.Chrome.canary PMPrintingExpandedStateForPrint2 -bool $(defaults read com.google.Chrome.canary PMPrintingExpandedStateForPrint2)"
    
    echo ""
    
    # VS Code
    echo "# VS Code settings"
    defaults read com.microsoft.VSCode ApplePressAndHoldEnabled 2>/dev/null && echo "defaults write com.microsoft.VSCode ApplePressAndHoldEnabled -bool $(defaults read com.microsoft.VSCode ApplePressAndHoldEnabled)"
    defaults read com.vscodium ApplePressAndHoldEnabled 2>/dev/null && echo "defaults write com.vscodium ApplePressAndHoldEnabled -bool $(defaults read com.vscodium ApplePressAndHoldEnabled)"
    defaults read com.microsoft.VSCode AppleWindowTabbingMode 2>/dev/null && echo "defaults write com.microsoft.VSCode AppleWindowTabbingMode -string '$(defaults read com.microsoft.VSCode AppleWindowTabbingMode)'"
    defaults read com.vscodium AppleWindowTabbingMode 2>/dev/null && echo "defaults write com.vscodium AppleWindowTabbingMode -string '$(defaults read com.vscodium AppleWindowTabbingMode)'"
    
    echo ""
    
    # Spotify
    echo "# Spotify settings"
    defaults read com.spotify.client AutoStart 2>/dev/null && echo "defaults write com.spotify.client AutoStart -bool $(defaults read com.spotify.client AutoStart)"
    defaults read com.spotify.client DisableHardwareAcceleration 2>/dev/null && echo "defaults write com.spotify.client DisableHardwareAcceleration -bool $(defaults read com.spotify.client DisableHardwareAcceleration)"
    
    echo ""
    
    # Docker
    echo "# Docker settings"
    defaults read com.docker.docker AutoStart 2>/dev/null && echo "defaults write com.docker.docker AutoStart -bool $(defaults read com.docker.docker AutoStart)"
    defaults read com.docker.docker analyticsEnabled 2>/dev/null && echo "defaults write com.docker.docker analyticsEnabled -bool $(defaults read com.docker.docker analyticsEnabled)"
    
    echo ""
    
    # Slack
    echo "# Slack settings"
    defaults read com.tinyspeck.slackmacgap SpellCheckingEnabled 2>/dev/null && echo "defaults write com.tinyspeck.slackmacgap SpellCheckingEnabled -bool $(defaults read com.tinyspeck.slackmacgap SpellCheckingEnabled)"
    defaults read com.tinyspeck.slackmacgap AutomaticQuoteSubstitutionEnabled 2>/dev/null && echo "defaults write com.tinyspeck.slackmacgap AutomaticQuoteSubstitutionEnabled -bool $(defaults read com.tinyspeck.slackmacgap AutomaticQuoteSubstitutionEnabled)"
    defaults read com.tinyspeck.slackmacgap AutomaticDashSubstitutionEnabled 2>/dev/null && echo "defaults write com.tinyspeck.slackmacgap AutomaticDashSubstitutionEnabled -bool $(defaults read com.tinyspeck.slackmacgap AutomaticDashSubstitutionEnabled)"
    
    echo ""
    echo 'echo "Restarting affected applications..."'
    echo "killall Finder 2>/dev/null || true"
    echo "killall Dock 2>/dev/null || true"
    echo "killall SystemUIServer 2>/dev/null || true"
    echo ""
    echo 'echo "✅ macOS defaults restored!"'
}

# Disable notification sounds for macOS apps listed in System Settings.
# Uses Accessibility automation, skips locked or MDM-managed apps, and
# supports dry-run and exact-name exclusions.
macos-disable-notification-sounds() {
    local script_path="${DOTFILES_DIR:-$HOME/dotfiles}/scripts/macos-disable-notification-sounds.sh"

    if [[ ! -x "$script_path" ]]; then
        echo "❌ Script not found or not executable: $script_path"
        return 1
    fi

    "$script_path" "$@"
}

# Copy current directory to clipboard
cpwd() {
    pwd | tr -d '\n' | pbcopy
    echo "📋 Path copied: $(pwd)"
}
