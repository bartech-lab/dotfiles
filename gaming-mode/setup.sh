#!/bin/bash

# gaming-mode Setup Script (Linux only)
# Installs the `gaming` command, its app list and the Meta+Shift+G shortcut.
# Safe to re-run. Docker control needs sudoers.example installed by hand.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$DOTFILES_DIR/gaming-mode"

if [[ "$(uname -s)" != Linux ]]; then
    echo "gaming-mode is Linux only" >&2
    exit 1
fi

mkdir -p "$HOME/.local/bin" "$HOME/.config/gaming" "$HOME/.local/share/applications"

cp "$SRC_DIR/gaming" "$HOME/.local/bin/gaming.tmp"
chmod +x "$HOME/.local/bin/gaming.tmp"
mv -f "$HOME/.local/bin/gaming.tmp" "$HOME/.local/bin/gaming"

if [[ ! -f "$HOME/.config/gaming/apps.conf" ]]; then
    cp "$SRC_DIR/apps.conf" "$HOME/.config/gaming/apps.conf"
fi

sed "s|__HOME__|$HOME|g" "$SRC_DIR/gaming-toggle.desktop" \
    > "$HOME/.local/share/applications/gaming-toggle.desktop"
kbuildsycoca6 >/dev/null 2>&1 || true

# Meta+Shift+G (Meta+G is KWin's Grid View). Qt key code: META|SHIFT|Key_G.
action="['gaming-toggle.desktop','_launch','Toggle Game Mode','Toggle Game Mode']"
if gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
        --method org.kde.KGlobalAccel.doRegister "$action" >/dev/null 2>&1 \
    && gdbus call --session --dest org.kde.kglobalaccel --object-path /kglobalaccel \
        --method org.kde.KGlobalAccel.setShortcut "$action" "[301989959]" 6 >/dev/null 2>&1; then
    echo "Shortcut: Meta+Shift+G"
else
    echo "Shortcut not registered; set it in System Settings > Shortcuts > Toggle Game Mode" >&2
fi

echo "Installed: ~/.local/bin/gaming, ~/.config/gaming/apps.conf, gaming-toggle.desktop"
if ! sudo -n -l /usr/bin/systemctl stop docker.service >/dev/null 2>&1; then
    echo "Docker is skipped until you install the sudoers rule:"
    echo "  sudo install -m 440 $SRC_DIR/sudoers.example /etc/sudoers.d/gaming-docker && sudo visudo -c"
fi
