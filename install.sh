#!/bin/bash

# Unified Automation Installer
# Sets up all background services: git-auto-pull, launchd-heartbeat, system-update
# Works on both macOS (LaunchAgents) and Linux (systemd user timers)

set -e

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS="$(uname -s)"

echo "==> OS detected: $OS"
echo "==> Dotfiles root: $DOTFILES_DIR"
echo ""

# ──────────────────────────────────────────────────
# 1. Git Auto-Pull
# ──────────────────────────────────────────────────
echo "── Setting up Git Auto-Pull ──"
mkdir -p ~/.config/git-auto-pull

cp "$DOTFILES_DIR/git-auto-pull/pull.sh" ~/.config/git-auto-pull/pull.sh
chmod +x ~/.config/git-auto-pull/pull.sh
echo "  pull.sh deployed"

if [[ ! -f ~/.config/git-auto-pull/repos.conf ]]; then
    cat > ~/.config/git-auto-pull/repos.conf << 'EOF'
# Git Auto-Pull Configuration
# Format: /path/to/repo:branch-name
# Lines starting with # are ignored
EOF
    echo "  Created default repos.conf (add your repos!)"
else
    echo "  repos.conf already exists, keeping it"
fi

if [[ "$OS" == Darwin ]]; then
    mkdir -p ~/Library/LaunchAgents
    PLIST=~/Library/LaunchAgents/com.user.gitautopull.plist
    cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.gitautopull</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$HOME/.config/git-auto-pull/pull.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/dev/null</string>
    <key>StandardErrorPath</key>
    <string>$HOME/.config/git-auto-pull/error.log</string>
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
PLISTEOF
    launchctl bootout gui/$(id -u)/com.user.gitautopull 2>/dev/null || true
    launchctl bootstrap gui/$(id -u) "$PLIST" 2>/dev/null
    launchctl kickstart -k gui/$(id -u)/com.user.gitautopull 2>/dev/null || true
    echo "  LaunchAgent installed ✓"
else
    cp "$DOTFILES_DIR/git-auto-pull/systemd/git-auto-pull.service" ~/.config/systemd/user/
    cp "$DOTFILES_DIR/git-auto-pull/systemd/git-auto-pull.timer"   ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now git-auto-pull.timer
    echo "  systemd timer enabled ✓"
fi

echo ""

# ──────────────────────────────────────────────────
# 2. LaunchAgent / Service Heartbeat
# ──────────────────────────────────────────────────
echo "── Setting up Heartbeat ──"
mkdir -p ~/.config/launchd-heartbeat

cp "$DOTFILES_DIR/launchd-heartbeat/heartbeat.sh" ~/.config/launchd-heartbeat/heartbeat.sh
chmod +x ~/.config/launchd-heartbeat/heartbeat.sh
echo "  heartbeat.sh deployed"

if [[ ! -f ~/.config/launchd-heartbeat/monitored-labels.conf ]]; then
    if [[ "$OS" == Darwin ]]; then
        cat > ~/.config/launchd-heartbeat/monitored-labels.conf << 'EOF'
# LaunchAgent labels to monitor
# One label per line
com.user.gitautopull
com.github.domt4.homebrew-autoupdate
EOF
    else
        cat > ~/.config/launchd-heartbeat/monitored-labels.conf << 'EOF'
# Monitored systemd user services
# One unit name per line
git-auto-pull.service
launchd-heartbeat.service
system-update.service
EOF
    fi
    echo "  Created default monitored-labels.conf"
else
    echo "  monitored-labels.conf already exists, keeping it"
fi

touch ~/.config/launchd-heartbeat/heartbeat.log
touch ~/.config/launchd-heartbeat/error.log

if [[ "$OS" == Darwin ]]; then
    mkdir -p ~/Library/LaunchAgents
    PLIST=~/Library/LaunchAgents/com.user.launchdheartbeat.plist
    cat > "$PLIST" << PLISTEOF
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
PLISTEOF
    launchctl bootout gui/$(id -u)/com.user.launchdheartbeat 2>/dev/null || true
    launchctl bootstrap gui/$(id -u) "$PLIST" 2>/dev/null
    launchctl kickstart -k gui/$(id -u)/com.user.launchdheartbeat 2>/dev/null || true
    echo "  LaunchAgent installed ✓"
else
    cp "$DOTFILES_DIR/launchd-heartbeat/systemd/launchd-heartbeat.service" ~/.config/systemd/user/
    cp "$DOTFILES_DIR/launchd-heartbeat/systemd/launchd-heartbeat.timer"   ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now launchd-heartbeat.timer
    echo "  systemd timer enabled ✓"
fi

echo ""

# ──────────────────────────────────────────────────
# 3. System Update (Daily)
# ──────────────────────────────────────────────────
echo "── Setting up System Update ──"

if [[ "$OS" == Darwin ]]; then
    echo "  Skipped — macOS uses com.user.topgrade LaunchAgent (configure separately)"
else
    cp "$DOTFILES_DIR/system-update/system-update.service" ~/.config/systemd/user/
    cp "$DOTFILES_DIR/system-update/system-update.timer"   ~/.config/systemd/user/
    systemctl --user daemon-reload
    systemctl --user enable --now system-update.timer
    echo "  systemd timer enabled ✓"
fi

echo ""
echo "══ Setup complete ══"
echo ""
echo "Check status:"
if [[ "$OS" == Darwin ]]; then
    echo "  launchctl list | grep -E 'gitautopull|launchdheartbeat'"
else
    echo "  systemctl --user status git-auto-pull.timer launchd-heartbeat.timer system-update.timer"
fi
