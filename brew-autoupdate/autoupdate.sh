#!/bin/sh
# Homebrew auto-update, formulae only.
#
# Casks are excluded on purpose. macOS attributes the App Management (or Full
# Disk Access) grant to the responsible app bundle, and a launchd job has none.
# An unattended `brew upgrade --cask` therefore registers Homebrew's Ruby
# interpreter by its versioned path in System Settings > Privacy & Security >
# App Management, as a row named "ruby", and mints a new row on every
# portable-ruby release.
#
# Upgrade casks from a terminal instead: `brewup`.

set -eu

PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
export PATH

BREW=/opt/homebrew/bin/brew
[ -x "$BREW" ] || exit 0

LOG_DIR="$HOME/Library/Logs/brew-autoupdate"
LOG="$LOG_DIR/brew-autoupdate.log"
mkdir -p "$LOG_DIR"

# Keep the log bounded; launchd runs this daily and never rotates it.
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 1048576 ]; then
    mv "$LOG" "$LOG.1"
fi

exec >> "$LOG" 2>&1

echo "=== $(date) ==="
"$BREW" update
"$BREW" upgrade --formula
"$BREW" cleanup
echo "=== done $(date) ==="
