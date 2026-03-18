#!/bin/bash

# LaunchAgent Heartbeat Setup Script
# Run this on new machines to monitor LaunchAgent health

set -e

echo "Setting up LaunchAgent heartbeat..."

mkdir -p "$HOME/.config/launchd-heartbeat"
mkdir -p "$HOME/Library/LaunchAgents"

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cp "$DOTFILES_DIR/launchd-heartbeat/heartbeat.sh" "$HOME/.config/launchd-heartbeat/heartbeat.sh"
chmod +x "$HOME/.config/launchd-heartbeat/heartbeat.sh"

if [[ ! -f "$HOME/.config/launchd-heartbeat/monitored-labels.conf" ]]; then
    cat > "$HOME/.config/launchd-heartbeat/monitored-labels.conf" << 'EOF'
# LaunchAgent labels to monitor
# One label per line

com.user.gitautopull
com.github.domt4.homebrew-autoupdate
EOF
    echo "Created default monitored labels config"
else
    echo "Keeping existing monitored labels config"
fi

touch "$HOME/.config/launchd-heartbeat/heartbeat.log"
touch "$HOME/.config/launchd-heartbeat/error.log"

PLIST_PATH="$HOME/Library/LaunchAgents/com.user.launchdheartbeat.plist"
cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.launchdheartbeat</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$HOME/.config/launchd-heartbeat/heartbeat.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/dev/null</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.config/launchd-heartbeat/error.log</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF

echo "Created LaunchAgent at $PLIST_PATH"

LAUNCH_DOMAIN="gui/$(id -u)"
launchctl bootout "$LAUNCH_DOMAIN"/com.user.launchdheartbeat >/dev/null 2>&1 || true

if launchctl bootstrap "$LAUNCH_DOMAIN" "$PLIST_PATH" >/dev/null 2>&1; then
    echo "LaunchAgent bootstrapped"
else
    echo "Failed to bootstrap LaunchAgent"
fi

if launchctl print "$LAUNCH_DOMAIN"/com.user.launchdheartbeat >/dev/null 2>&1; then
    echo "LaunchAgent load verified"
else
    echo "LaunchAgent not visible in launchctl print"
fi

if launchctl kickstart -k "$LAUNCH_DOMAIN"/com.user.launchdheartbeat >/dev/null 2>&1; then
    echo "Startup heartbeat run triggered"
else
    echo "Could not kickstart LaunchAgent"
fi

echo ""
echo "Setup complete"
echo ""
echo "Logs:"
echo "- Heartbeat: ~/.config/launchd-heartbeat/heartbeat.log"
echo "- Errors: ~/.config/launchd-heartbeat/error.log"
echo ""
echo "Edit monitored labels at ~/.config/launchd-heartbeat/monitored-labels.conf"
