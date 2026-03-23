#!/bin/bash

# Calendar Ghost Invite Fix - Setup Script
# Automatically fixes recurring ghost RSVP invites in macOS Calendar
# 
# Usage: ./setup.sh           - Install and start the service
#        ./setup.sh uninstall - Remove the service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${HOME}/.config/calendar-ghost-fix"
LAUNCH_AGENT_DIR="${HOME}/Library/LaunchAgents"
PLIST_NAME="com.user.calendarghostfix.plist"
PLIST_PATH="${LAUNCH_AGENT_DIR}/${PLIST_NAME}"
LAUNCH_DOMAIN="gui/$(id -u)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_success() {
    echo -e "${GREEN}✅${NC} $1"
}

print_info() {
    echo -e "ℹ️  $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️${NC} $1"
}

print_error() {
    echo -e "${RED}❌${NC} $1"
}

uninstall() {
    echo "🗑️  Uninstalling Calendar Ghost Fix..."
    
    # Stop the LaunchAgent
    if launchctl print "$LAUNCH_DOMAIN/com.user.calendarghostfix" >/dev/null 2>&1; then
        if launchctl bootout "$LAUNCH_DOMAIN"/com.user.calendarghostfix >/dev/null 2>&1; then
            print_success "Stopped LaunchAgent"
        else
            print_warning "Could not stop LaunchAgent (may already be stopped)"
        fi
    else
        print_info "LaunchAgent not running"
    fi
    
    # Remove plist
    if [[ -f "$PLIST_PATH" ]]; then
        rm "$PLIST_PATH"
        print_success "Removed LaunchAgent plist"
    else
        print_info "LaunchAgent plist not found"
    fi
    
    # Ask about config directory
    if [[ -d "$CONFIG_DIR" ]]; then
        echo ""
        read -p "Remove config directory and logs? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$CONFIG_DIR"
            print_success "Removed config directory: $CONFIG_DIR"
        else
            print_info "Kept config directory: $CONFIG_DIR"
        fi
    fi
    
    echo ""
    print_success "Uninstall complete"
}

install() {
    echo "📅 Setting up Calendar Ghost Invite Fix..."
    echo ""
    
    # Create directories
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$LAUNCH_AGENT_DIR"
    print_success "Created directories"
    
    # Copy the fix script
    cp "$SCRIPT_DIR/fix.sh" "$CONFIG_DIR/fix.sh"
    chmod +x "$CONFIG_DIR/fix.sh"
    print_success "Installed fix script"
    
    # Create log files
    touch "$CONFIG_DIR/fix.log"
    touch "$CONFIG_DIR/error.log"
    print_success "Created log files"
    
    # Create LaunchAgent plist
    cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.calendarghostfix</string>
    
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>${CONFIG_DIR}/fix.sh</string>
    </array>
    
    <key>StartInterval</key>
    <integer>3600</integer>
    
    <key>RunAtLoad</key>
    <true/>
    
    <key>StandardOutPath</key>
    <string>${CONFIG_DIR}/fix.log</string>
    
    <key>StandardErrorPath</key>
    <string>${CONFIG_DIR}/error.log</string>
    
    <key>ProcessType</key>
    <string>Background</string>
</dict>
</plist>
EOF
    print_success "Created LaunchAgent"
    
    # Unload if already exists (refresh)
    launchctl bootout "$LAUNCH_DOMAIN"/com.user.calendarghostfix >/dev/null 2>&1 || true
    
    # Load the LaunchAgent
    if launchctl bootstrap "$LAUNCH_DOMAIN" "$PLIST_PATH" >/dev/null 2>&1; then
        print_success "LaunchAgent loaded"
    else
        print_error "Failed to load LaunchAgent"
        exit 1
    fi
    
    # Verify it's loaded
    if launchctl print "$LAUNCH_DOMAIN"/com.user.calendarghostfix >/dev/null 2>&1; then
        print_success "LaunchAgent verified"
    else
        print_warning "LaunchAgent not visible (may need manual check)"
    fi
    
    # Trigger immediate run
    if launchctl kickstart -k "$LAUNCH_DOMAIN"/com.user.calendarghostfix >/dev/null 2>&1; then
        print_success "Initial run triggered"
    else
        print_warning "Could not trigger initial run"
    fi
    
    echo ""
    print_success "Setup complete!"
    echo ""
    echo "📋 Summary:"
    echo "   Script: ${CONFIG_DIR}/fix.sh"
    echo "   Logs:   ${CONFIG_DIR}/fix.log"
    echo "   Errors: ${CONFIG_DIR}/error.log"
    echo ""
    echo "⏱️  Runs every hour automatically"
    echo ""
    echo "📝 Management commands:"
    echo "   View status:  launchctl print ${LAUNCH_DOMAIN}/com.user.calendarghostfix"
    echo "   Trigger run:  launchctl kickstart -k ${LAUNCH_DOMAIN}/com.user.calendarghostfix"
    echo "   Stop service: launchctl bootout ${LAUNCH_DOMAIN}/com.user.calendarghostfix"
    echo "   Uninstall:    ./setup.sh uninstall"
}

# Main
if [[ "${1:-}" == "uninstall" ]]; then
    uninstall
else
    install
fi