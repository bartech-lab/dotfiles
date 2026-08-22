#!/bin/bash

# ai-caffeine Setup Script
# Keeps the machine awake while AI agent sessions (claude, codex) run.
# macOS: LaunchAgent wrapping caffeinate. Linux: systemd user unit using
# logind inhibitors plus KDE idle pokes. Safe to re-run (idempotent).

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$DOTFILES_DIR/ai-caffeine"
LAUNCH_DOMAIN="gui/$(id -u)"

install_script() {
    # Atomic replace: a running bash keeps reading the old inode safely.
    cp "$SRC_DIR/ai-caffeine" "$1.tmp"
    chmod +x "$1.tmp"
    mv -f "$1.tmp" "$1"
}

if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "Setting up ai-caffeine (macOS LaunchAgent)..."

    mkdir -p "$HOME/.local/bin" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
    install_script "$HOME/.local/bin/ai-caffeine"

    sed "s|__HOME__|$HOME|g" "$SRC_DIR/com.bartech.ai-caffeine.plist" \
        > "$HOME/Library/LaunchAgents/com.bartech.ai-caffeine.plist"

    launchctl bootout "$LAUNCH_DOMAIN/com.bartech.ai-caffeine" >/dev/null 2>&1 || true
    launchctl bootstrap "$LAUNCH_DOMAIN" "$HOME/Library/LaunchAgents/com.bartech.ai-caffeine.plist"

    if launchctl print "$LAUNCH_DOMAIN/com.bartech.ai-caffeine" >/dev/null 2>&1; then
        echo "LaunchAgent loaded"
    else
        echo "Warning: LaunchAgent not visible in launchctl print" >&2
        exit 1
    fi

    echo ""
    echo "Setup complete."
    echo "Verify while an agent runs: pgrep -fl caffeinate"
    echo "Logs: ~/Library/Logs/ai-caffeine.log"
else
    echo "Setting up ai-caffeine (Linux systemd user unit)..."

    mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
    install_script "$HOME/.local/bin/ai-caffeine"

    cp "$SRC_DIR/ai-caffeine.service" "$HOME/.config/systemd/user/ai-caffeine.service"
    systemctl --user daemon-reload
    systemctl --user enable --now ai-caffeine.service

    if systemctl --user is-active --quiet ai-caffeine.service; then
        echo "Service active"
    else
        echo "Warning: service not active" >&2
        exit 1
    fi

    echo ""
    echo "Setup complete."
    echo "Verify while an agent runs: systemd-inhibit --list | grep ai-caffeine"
    echo "Logs: journalctl --user -u ai-caffeine -f"
fi
