#!/bin/bash

# Git Auto-Pull Setup Script
# Run this on new machines to set up automatic git pulling

set -e

echo "🔄 Setting up Git Auto-Pull..."

# Create directories
mkdir -p ~/.config/git-auto-pull
mkdir -p ~/Library/LaunchAgents

# Get the directory where this script is located
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Copy the pull script
cp "$DOTFILES_DIR/git-auto-pull/pull.sh" ~/.config/git-auto-pull/pull.sh
chmod +x ~/.config/git-auto-pull/pull.sh

# Create empty config file if it doesn't exist
if [[ ! -f ~/.config/git-auto-pull/repos.conf ]]; then
    cat > ~/.config/git-auto-pull/repos.conf << 'EOF'
# Git Auto-Pull Configuration
# Format: /path/to/repo:branch-name
# Lines starting with # are ignored
#
# Example:
# ~/Projects/my-app:main
# ~/work/legacy-api:master
# ~/side-project:develop
EOF
    echo "✅ Created empty config file at ~/.config/git-auto-pull/repos.conf"
else
    echo "ℹ️ Config file already exists, keeping existing"
fi

# Create LaunchAgent plist from template
PLIST_PATH="$HOME/Library/LaunchAgents/com.user.gitautopull.plist"
cat > "$PLIST_PATH" << EOF
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
    <integer>14400</integer>
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
EOF

echo "✅ Created LaunchAgent at $PLIST_PATH"

# Load the LaunchAgent (refresh if already present)
LAUNCH_DOMAIN="gui/$(id -u)"
launchctl bootout "$LAUNCH_DOMAIN"/com.user.gitautopull >/dev/null 2>&1 || true

if launchctl bootstrap "$LAUNCH_DOMAIN" "$PLIST_PATH" >/dev/null 2>&1; then
    echo "✅ LaunchAgent bootstrapped"
else
    echo "⚠️  Failed to bootstrap LaunchAgent"
fi

# Verify LaunchAgent is loaded and configured
if launchctl print "$LAUNCH_DOMAIN"/com.user.gitautopull >/dev/null 2>&1; then
    echo "✅ LaunchAgent load verified"
else
    echo "⚠️  LaunchAgent not visible in launchctl print"
fi

# Trigger one immediate run for startup verification
if launchctl kickstart -k "$LAUNCH_DOMAIN"/com.user.gitautopull >/dev/null 2>&1; then
    echo "✅ LaunchAgent startup run triggered"
else
    echo "⚠️  Could not kickstart LaunchAgent"
fi

echo ""
echo "✨ Setup complete!"
echo ""
echo "Next steps:"
echo "1. Edit ~/.config/git-auto-pull/repos.conf to add your repositories"
echo "2. Format: /path/to/repo:branch-name"
echo "3. Test with: bash ~/.config/git-auto-pull/pull.sh"
echo ""
echo "The script runs every 4 hours automatically."
echo "Logs: ~/.config/git-auto-pull/pull.log"
