# OpenCode Functions
# Functions and helpers for OpenCode profiles

# Default profile - Clean OpenCode (no plugins)
# Use this for vanilla OpenCode experience
opencode() {
  ocx oc -p default
}

# Oh-My-OpenCode profile (with Sisyphus agent, background tasks, etc.)
# Updates via npm, config preserved in profile directory
omo() {
  (cd ~/.config/opencode && bun update oh-my-opencode --silent 2>/dev/null)
  ocx oc -p omo
}

# OpenAgentsControl profile (pattern-aware agents, approval-based execution)
# Auto-updates on every use, checks GitHub for latest release
oac() {
  ocx-auto-update oac 2>/dev/null
  ocx oc -p oac
}

# List all available profiles
ocp() {
  ocx profile list
}

# Quick function to open any profile
ocx-profile() {
  if [ -z "$1" ]; then
    echo "Usage: ocx-profile <profile-name>"
    echo "Available profiles:"
    ocx profile list
  else
    ocx oc -p "$1"
  fi
}
