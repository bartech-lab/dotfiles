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
  (cd ~/.config/opencode && rm -f bun.lock && bun install --silent 2>/dev/null)
  ocx oc -p omo
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

# Cleanup detached opencode processes (safe with multiple terminals)
# Only removes processes not attached to any terminal (tty == "?")
opencode-clean() {
  echo "Scanning opencode processes..."

  local killed=0

  while read -r pid ppid tty; do
    # Skip empty lines
    [[ -z "$pid" ]] && continue

    # Validate PID is numeric
    [[ "$pid" =~ ^[0-9]+$ ]] || continue

    # Keep anything attached to a terminal
    [[ "$tty" != "?" ]] && continue

    # Kill detached processes
    echo "Cleaning detached PID $pid"
    kill -TERM "$pid" 2>/dev/null
    sleep 0.5
    kill -KILL "$pid" 2>/dev/null
    ((killed++))

  done < <(ps -axo pid,ppid,tty,command | grep '[o]pencode' | awk '{print $1, $2, $3}')

  [[ $killed -eq 0 ]] && echo "No detached processes detected"
  [[ $killed -gt 0 ]] && echo "Cleaned $killed detached processes"
}

# Alias for quick access
alias ocfix='opencode-clean'
