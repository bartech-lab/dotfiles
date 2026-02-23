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

# Cleanup orphaned opencode processes (safe with multiple terminals)
opencode-clean() {
  echo "Scanning opencode processes..."

  local found=0
  local killed=0

  while read -r pid ppid tty cmd; do
    found=1

    # Keep anything attached to a terminal
    if [[ "$tty" != "?" ]]; then
      continue
    fi

    # Only kill if orphaned (adopted by launchd / PID 1)
    if [[ "$ppid" -eq 1 ]]; then
      echo "Cleaning orphan PID $pid"
      kill -TERM "$pid" 2>/dev/null
      sleep 0.5
      kill -KILL "$pid" 2>/dev/null
      ((killed++))
    fi

  done < <(ps -axo pid,ppid,tty,command | grep '[o]pencode')

  [[ $found -eq 0 ]] && echo "No opencode processes found"
  [[ $killed -eq 0 ]] && echo "No orphan processes detected"
  [[ $killed -gt 0 ]] && echo "Cleaned $killed orphan processes"
}

# Alias for quick access
alias ocfix='opencode-clean'
