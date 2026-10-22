#!/bin/bash

# OpenAsar auto-reapply setup (Linux only)
# Installs openasar-patch, discord-check and the systemd watcher that
# reapplies OpenAsar after every Discord update. Safe to re-run.

set -euo pipefail

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"

if [[ "$(uname -s)" != Linux ]]; then
    echo "OpenAsar auto-reapply is Linux only" >&2
    exit 1
fi

mkdir -p "$HOME/.local/bin" "$UNIT_DIR"

for script in openasar-patch discord-check; do
    cp "$SRC_DIR/$script" "$HOME/.local/bin/$script.tmp"
    chmod +x "$HOME/.local/bin/$script.tmp"
    mv -f "$HOME/.local/bin/$script.tmp" "$HOME/.local/bin/$script"
done

cp "$SRC_DIR/openasar-patch.service" "$SRC_DIR/openasar-patch.path" "$UNIT_DIR/"
systemctl --user daemon-reload
systemctl --user enable --now openasar-patch.path

"$HOME/.local/bin/openasar-patch"
echo "Installed: ~/.local/bin/openasar-patch, ~/.local/bin/discord-check, openasar-patch.path"
