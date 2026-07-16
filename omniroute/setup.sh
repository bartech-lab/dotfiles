#!/bin/bash

# omniroute Service Setup Script
# Run this on macOS to set up the omniroute LaunchAgent.
# On Linux, the systemd user unit is set up by install.sh
# (or manually: see README.md).

set -e

[[ "$(uname -s)" != Darwin ]] && { echo "Use install.sh for Linux setup (systemd user unit)"; exit 0; }

if [[ ! -d "$HOME/omniroute" ]]; then
    echo "⏭️  ~/omniroute not present on this machine — skipping"
    exit 0
fi

echo "🚀 Setting up omniroute service..."

mkdir -p ~/.config/omniroute
mkdir -p ~/Library/LaunchAgents
mkdir -p ~/omniroute/logs

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cp "$DOTFILES_DIR/omniroute/run.sh" ~/.config/omniroute/run.sh
chmod +x ~/.config/omniroute/run.sh

PLIST_PATH="$HOME/Library/LaunchAgents/com.user.omniroute.plist"
cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<!-- Managed by dotfiles/omniroute/setup.sh. run.sh execs node directly
     (not npm) so KeepAlive tracks the real server PID. -->
<dict>
    <key>Label</key>
    <string>com.user.omniroute</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/sh</string>
        <string>$HOME/.config/omniroute/run.sh</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$HOME/omniroute</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ThrottleInterval</key>
    <integer>10</integer>
    <key>ExitTimeOut</key>
    <integer>15</integer>
    <key>StandardOutPath</key>
    <string>$HOME/omniroute/logs/launchd.out.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/omniroute/logs/launchd.err.log</string>
</dict>
</plist>
EOF

# Reload the agent
launchctl bootout "gui/$(id -u)/com.user.omniroute" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"

echo "✅ omniroute LaunchAgent installed and started"
echo "   Logs: ~/omniroute/logs/launchd.{out,err}.log"
echo "   Status: launchctl print gui/$(id -u)/com.user.omniroute | head"
