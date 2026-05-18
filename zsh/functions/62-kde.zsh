# KDE Plasma System Defaults — Linux equivalent of macos-defaults
[[ "$DOTFILES_OS" != linux ]] && return 0

kde-defaults() {
    echo "Applying KDE Plasma system defaults..."
    echo ""

    # ============================================
    # COMPOSITOR — Disable animations and bling
    # ============================================

    # Animation speed: instant (0 = no animations)
    kwriteconfig5 --file kwinrc --group Compositing --key AnimationSpeed 0

    # Disable all desktop effects (blur, slide, fade, etc.)
    kwriteconfig5 --file kwinrc --group Plugins --key kwin4_effect_fadingEnabled false
    kwriteconfig5 --file kwinrc --group Plugins --key kwin4_effect_frozenappEnabled false
    kwriteconfig5 --file kwinrc --group Plugins --key kwin4_effect_loginEnabled false
    kwriteconfig5 --file kwinrc --group Plugins --key kwin4_effect_logoutEnabled false
    kwriteconfig5 --file kwinrc --group Plugins --key kwin4_effect_maximizeEnabled false
    kwriteconfig5 --file kwinrc --group Plugins --key kwin4_effect_slidingpopupsEnabled false
    kwriteconfig5 --file kwinrc --group Plugins --key kwin4_effect_translucencyEnabled false
    kwriteconfig5 --file kwinrc --group Plugins --key kwin4_effect_windowapertureEnabled false
    kwriteconfig5 --file kwinrc --group Plugins --key kwin4_effect_zoomEnabled false
    kwriteconfig5 --file kwinrc --group Plugins --key kwin4_effect_morphingpopupsEnabled false
    kwriteconfig5 --file kwinrc --group Plugins --key kwin4_effect_squashEnabled false
    kwriteconfig5 --file kwinrc --group Plugins --key kwin4_effect_scaleEnabled false
    kwriteconfig5 --file kwinrc --group Plugins --key kwin4_effect_magiclampEnabled false

    # Keep compositing on (handles v-sync), just disable animations
    kwriteconfig5 --file kwinrc --group Compositing --key Enabled true

    echo "  ✓ Compositor: animations disabled"

    # ============================================
    # PANEL (Taskbar) — Auto-hide, minimal
    # ============================================

    # Auto-hide panel
    kwriteconfig5 --file plasmashellrc --group PlasmaViews --group "Panel 1" --key panelVisibility 1

    # ============================================
    # KEYBOARD — Fast key repeat, no delays
    # ============================================

    # Key repeat: moderately fast (KDE defaults are 25 repeats/sec, 600ms delay)
    # macOS KeyRepeat=5 maps to ~30 repeats/sec; InitialKeyRepeat=25 maps to ~250ms
    kwriteconfig5 --file kcminputrc --group Keyboard --key KeyRepeat 30
    kwriteconfig5 --file kcminputrc --group Keyboard --key RepeatDelay 250

    # Disable sticky keys / slow keys
    kwriteconfig5 --file kaccessrc --group Keyboard --key StickyKeys false
    kwriteconfig5 --file kaccessrc --group Keyboard --key SlowKeys false
    kwriteconfig5 --file kaccessrc --group Keyboard --key BounceKeys false

    echo "  ✓ Keyboard: 250ms delay, 30 repeats/sec"

    # ============================================
    # MOUSE / TOUCHPAD — Tap to click
    # ============================================

    kwriteconfig5 --file kcminputrc --group Touchpad --key TapToClick true

    echo "  ✓ Touchpad: tap-to-click enabled"

    # ============================================
    # DOLPHIN (File Manager)
    # ============================================

    # Show full path in title bar
    kwriteconfig5 --file dolphinrc --group General --key ShowFullPath true

    # Show hidden files
    kwriteconfig5 --file dolphinrc --group General --key ShowHiddenFiles true

    # Detailed view by default
    kwriteconfig5 --file dolphinrc --group General --key ViewMode 1

    # Sort by name, folders first
    kwriteconfig5 --file dolphinrc --group KFileDialogSettings --key SortFoldersFirst true

    echo "  ✓ Dolphin: full path, hidden files, folders first"

    # ============================================
    # SPECTACLE (Screenshots) — Save to Downloads
    # ============================================

    kwriteconfig5 --file spectaclerc --group General --key SaveLocation "$HOME/Downloads"
    kwriteconfig5 --file spectaclerc --group General --key AutoSave true

    echo "  ✓ Spectacle: auto-save to Downloads"

    # ============================================
    # KDE GLOBALS — Performance
    # ============================================

    # Disable animations everywhere
    kwriteconfig5 --file kdeglobals --group KDE --key AnimationDurationFactor 0

    # Disable menu transparency (performance)
    kwriteconfig5 --file kdeglobals --group KDE --key ShowIconsInMenu false

    echo "  ✓ KDE globals: animations off, menu icons off"

    # ============================================
    # LAUNCH FEEDBACK — Disable
    # ============================================

    kwriteconfig5 --file klaunchrc --group BusyCursorSettings --key BusyCursor None
    kwriteconfig5 --file klaunchrc --group FeedbackStyle --key FeedbackStyle None

    # ============================================
    # APPLY CHANGES
    # ============================================

    echo ""
    echo "Restarting KDE components..."

    # Reload KWin compositor
    kwin_x11 --replace &>/dev/null & disown
    sleep 0.5

    # Reload Plasma shell
    plasmashell --replace &>/dev/null & disown
    sleep 0.5

    # Restart krunner
    kquitapp5 krunner 2>/dev/null || true
    kstart5 krunner &>/dev/null & disown

    echo ""
    echo "✅ KDE Plasma defaults applied!"
    echo ""
    echo "Key changes:"
    echo "  • All animations disabled (instant transitions)"
    echo "  • Desktop effects disabled (fade, slide, blur, zoom)"
    echo "  • Fast key repeat: 250ms delay, 30 chars/sec"
    echo "  • Tap-to-click enabled"
    echo "  • Dolphin: full paths, hidden files, folders first"
    echo "  • Spectacle screenshots auto-saved to Downloads"
    echo "  • Launch feedback disabled (no busy cursor)"
    echo ""
    echo "Some changes may require logout/login to take full effect."
}
