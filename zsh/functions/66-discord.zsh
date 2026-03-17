# Discord utilities

discord-openasar-setup() {
  "$HOME/dotfiles/scripts/bin/setup-discord-openasar" "$@"
}

discord-openasar-status() {
  launchctl print "gui/$(id -u)/dev.openasar.reapply" 2>/dev/null || echo "LaunchAgent not loaded"
}
