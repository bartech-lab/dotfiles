#!/bin/bash

# filen-patches Setup Script
# Keeps the local Filen app.asar patches applied across Filen updates.
# macOS: LaunchAgent that reruns filen-fix-sync-retry when app.asar changes
# and at login. Linux: pacman hook that reruns filen-fix-window and
# filen-fix-sync-retry after every filen-desktop-bin install or upgrade
# (needs sudo). Safe to re-run. Opt-in: not called from install.sh.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$DOTFILES_DIR/filen-patches"
LABEL="com.bartech.filen-fix-sync-retry"

if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "Setting up filen-patches (macOS LaunchAgent)..."

    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
    plist="$HOME/Library/LaunchAgents/$LABEL.plist"
    sed -e "s|__HOME__|$HOME|g" -e "s|__DOTFILES__|$DOTFILES_DIR|g" \
        "$SRC_DIR/$LABEL.plist" > "$plist"

    domain="gui/$(id -u)"
    launchctl bootout "$domain/$LABEL" >/dev/null 2>&1 || true
    # bootout is asynchronous, so an immediate bootstrap can lose the race.
    for _ in 1 2 3; do
        launchctl bootstrap "$domain" "$plist" 2>/dev/null && break
        sleep 1
    done

    if launchctl print "$domain/$LABEL" >/dev/null 2>&1; then
        echo "LaunchAgent loaded"
    else
        echo "Warning: LaunchAgent not visible in launchctl print" >&2
        exit 1
    fi
    echo "Logs: ~/Library/Logs/filen-fix-sync-retry.log"
else
    echo "Setting up filen-patches (pacman hook, requires sudo)..."

    hook=/etc/pacman.d/hooks/filen-desktop-patches.hook
    sudo mkdir -p /etc/pacman.d/hooks
    sed "s|__DOTFILES__|$DOTFILES_DIR|g" "$SRC_DIR/filen-desktop-patches.hook" \
        | sudo tee "$hook" >/dev/null
    echo "Installed $hook"
fi

"$DOTFILES_DIR/scripts/bin/filen-fix-sync-retry" --check
