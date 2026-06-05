# KDE Plasma 6 System Defaults — Linux equivalent of macos-defaults
# Requires: Plasma 6 (kwriteconfig6, qdbus6, balooctl6)
[[ "$DOTFILES_OS" != linux ]] && return 0

kde-defaults() {
    echo "Applying KDE Plasma 6 system defaults..."
    echo ""

    # ============================================
    # ANIMATIONS — Disable globally
    # ============================================

    # AnimationDurationFactor 0 disables all Qt/Plasma UI animations
    kwriteconfig6 --file kdeglobals --group KDE --key AnimationDurationFactor 0

    echo "  ✓ Animations: globally disabled (AnimationDurationFactor=0)"

    # ============================================
    # COMPOSITOR — Keep enabled, disable visual effects
    # ============================================

    kwriteconfig6 --file kwinrc --group Compositing --key Enabled true

    # Allow tearing for gaming (reduces input latency in fullscreen)
    kwriteconfig6 --file kwinrc --group Compositing --key AllowTearing true

    # Disable ALL animated/visual desktop effects individually
    local effects=(
        backgroundcontrast
        blur
        diminactive
        fade
        fadingpopups
        frozenapp
        glide
        login
        logout
        magiclamp
        maximize
        overview
        scale
        screenedge
        shakecursor
        slide
        slidingpopups
        squash
        translucency
        windowview
        zoom
    )

    for effect in "${effects[@]}"; do
        kwriteconfig6 --file kwinrc --group Plugins --key "${effect}Enabled" false
    done

    echo "  ✓ Desktop effects: all disabled (${#effects[@]} effects)"

    # ============================================
    # BALOO — Disable file indexer (major CPU/IO drain)
    # ============================================

    if command -v balooctl6 &>/dev/null; then
        balooctl6 suspend 2>/dev/null || true
        balooctl6 disable 2>/dev/null || true
        balooctl6 purge 2>/dev/null || true
        echo "  ✓ Baloo: file indexer disabled and purged"
    else
        echo "  ⚠ Baloo: balooctl6 not found, skipping"
    fi

    # ============================================
    # SPLASH SCREEN — Disable
    # ============================================

    kwriteconfig6 --file ksplashrc --group KSplash --key Engine none
    kwriteconfig6 --file ksplashrc --group KSplash --key Theme None

    echo "  ✓ Splash screen: disabled"

    # ============================================
    # SCREEN EDGES — Disable hot corners
    # ============================================

    kwriteconfig6 --file kwinrc --group Effect-overview --key BorderActivate 9

    echo "  ✓ Screen edges: hot corners disabled"

    # ============================================
    # LAUNCH FEEDBACK — Disable bouncing cursor
    # ============================================

    kwriteconfig6 --file klaunchrc --group BusyCursorSettings --key Bouncing false
    kwriteconfig6 --file klaunchrc --group FeedbackStyle --key BusyCursor false

    echo "  ✓ Launch feedback: bouncing cursor disabled"

    # ============================================
    # KEYBOARD — Fast key repeat, no delays
    # ============================================

    kwriteconfig6 --file kcminputrc --group Keyboard --key RepeatRate 30
    kwriteconfig6 --file kcminputrc --group Keyboard --key RepeatDelay 250

    # Disable sticky keys / slow keys
    kwriteconfig6 --file kaccessrc --group Keyboard --key StickyKeys false
    kwriteconfig6 --file kaccessrc --group Keyboard --key SlowKeys false
    kwriteconfig6 --file kaccessrc --group Keyboard --key BounceKeys false

    echo "  ✓ Keyboard: 250ms delay, 30 repeats/sec"

    # ============================================
    # TOUCHPAD — Tap to click
    # ============================================

    kwriteconfig6 --file kcminputrc --group Touchpad --key TapToClick true

    echo "  ✓ Touchpad: tap-to-click enabled"

    # ============================================
    # DOLPHIN (File Manager)
    # ============================================

    kwriteconfig6 --file dolphinrc --group General --key ShowFullPath true
    kwriteconfig6 --file dolphinrc --group General --key ShowHiddenFiles true
    kwriteconfig6 --file dolphinrc --group General --key ViewMode 1
    kwriteconfig6 --file dolphinrc --group KFileDialogSettings --key SortFoldersFirst true

    echo "  ✓ Dolphin: full path, hidden files, folders first"

    # ============================================
    # SPECTACLE (Screenshots) — Save to Downloads
    # ============================================

    kwriteconfig6 --file spectaclerc --group General --key SaveLocation "$HOME/Downloads"
    kwriteconfig6 --file spectaclerc --group General --key AutoSave true

    echo "  ✓ Spectacle: auto-save to Downloads"

    # ============================================
    # KDE GLOBALS — Performance
    # ============================================

    kwriteconfig6 --file kdeglobals --group KDE --key ShowIconsInMenu false

    # Disable recent documents tracking
    kwriteconfig6 --file kdeglobals --group RecentDocuments --key MaxEntries 0

    echo "  ✓ KDE globals: menu icons off, recent documents off"

    # ============================================
    # PANEL (Taskbar) — Centered icons, auto-hide, 60px
    # ============================================

    # Auto-hide
    kwriteconfig6 --file plasmashellrc --group PlasmaViews --group "Panel 2" --key panelVisibility 1

    # Thickness (height)
    kwriteconfig6 --file plasmashellrc --group PlasmaViews --group "Panel 2" --group Defaults --key thickness 60

    # Floating panel
    kwriteconfig6 --file plasmashellrc --group PlasmaViews --group "Panel 2" --key floating 1

    echo "  ✓ Panel: auto-hide enabled, 60px thickness, floating"

    # ============================================
    # PANEL LAYOUT — Spacers to center Icons-Only Task Manager
    # ============================================

    # Add flexible spacers around icontasks widget for centered app icons
    # Note: Full layout is deployed via install.sh from linux/plasma/ configs
    # This sets the key properties programmatically

    local appletsrc="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"

    # Left spacer (applet 25)
    kwriteconfig6 --file "$appletsrc" --group Containments --group 2 --group Applets --group 25 --key immutability 1
    kwriteconfig6 --file "$appletsrc" --group Containments --group 2 --group Applets --group 25 --key plugin org.kde.plasma.panelspacer
    kwriteconfig6 --file "$appletsrc" --group Containments --group 2 --group Applets --group 25 --group Configuration --group General --key expanding true

    # Right spacer (applet 26)
    kwriteconfig6 --file "$appletsrc" --group Containments --group 2 --group Applets --group 26 --key immutability 1
    kwriteconfig6 --file "$appletsrc" --group Containments --group 2 --group Applets --group 26 --key plugin org.kde.plasma.panelspacer
    kwriteconfig6 --file "$appletsrc" --group Containments --group 2 --group Applets --group 26 --group Configuration --group General --key expanding true

    # Applet order: kickoff(3) pager(4) spacer(25) icontasks(5) marg(6) spacer(26) systray(7) clock(21) showdesktop(22)
    kwriteconfig6 --file "$appletsrc" --group Containments --group 2 --group General --key AppletOrder "3;4;25;5;6;26;7;21;22"

    echo "  ✓ Panel layout: centered app icons (flexible spacers)"

    # ============================================
    # APPLY CHANGES (Wayland-safe)
    # ============================================

    echo ""
    echo "Applying changes..."

    # Reconfigure KWin compositor (Wayland-safe, no restart needed)
    qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true

    echo ""
    echo "KDE Plasma 6 defaults applied!"
    echo ""
    echo "Key changes:"
    echo "  • All animations disabled (AnimationDurationFactor=0)"
    echo "  • All desktop effects disabled (${#effects[@]} effects)"
    echo "  • Baloo file indexer disabled"
    echo "  • Splash screen disabled"
    echo "  • Hot corners disabled"
    echo "  • Launch feedback disabled"
    echo "  • Fast key repeat: 250ms delay, 30 chars/sec"
    echo "  • Dolphin: full paths, hidden files, folders first"
    echo "  • Spectacle screenshots auto-saved to Downloads"
    echo "  • Allow tearing enabled (lower input latency)"
    echo ""
    echo "Some changes may require logout/login to take full effect."
}

kde-audit-effects() {
    if ! command -v qdbus6 &>/dev/null; then
        echo "qdbus6 not found (not in a Plasma 6 session?)"
        return 1
    fi

    local effects
    effects=$(qdbus6 org.kde.KWin /Effects org.kde.kwin.Effects.loadedEffects 2>/dev/null)

    if [[ -z "$effects" ]]; then
        echo "No effects loaded (or KWin not running)"
        return 0
    fi

    echo "Currently loaded KWin effects:"
    echo "$effects" | while read -r effect; do
        echo "  • $effect"
    done
    echo ""
    echo "Total: $(echo "$effects" | wc -l | tr -d ' ') effects"
    echo ""
    echo "To disable a specific effect:"
    echo "  kwriteconfig6 --file kwinrc --group Plugins --key <name>Enabled false"
    echo "  qdbus6 org.kde.KWin /KWin reconfigure"
}
