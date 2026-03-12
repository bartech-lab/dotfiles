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

# ============================================================================
# ECC (Everything Claude Code) Profile
# Full ECC profile with auto-update and preserved settings
# ============================================================================

# Check if ECC updates are available
ecc-check-update() {
  local ecc_dir="$HOME/ecc"
  local current_hash remote_hash

  cd "$ecc_dir" 2>/dev/null || return 1

  # Fetch latest info silently
  git fetch origin main --quiet 2>/dev/null || return 1

  current_hash=$(git rev-parse HEAD)
  remote_hash=$(git rev-parse origin/main)

  if [ "$current_hash" != "$remote_hash" ]; then
    echo "update-available"
    return 0
  fi

  return 1
}

# Update ECC to latest version
ecc-update() {
  local update_script="$HOME/.config/opencode/profiles/ecc/update-ecc.sh"

  if [ -f "$update_script" ]; then
    "$update_script"
  else
    echo "Error: Update script not found at $update_script"
    return 1
  fi
}

# Launch ECC profile with auto-update
ecc() {
  # Check for updates first
  if ecc-check-update 2>/dev/null | grep -q "update-available"; then
    echo "🔄 ECC update available!"
    echo ""
    read -q "REPLY?Update ECC now? [Y/n] "
    echo ""
    if [[ ! "$REPLY" =~ ^[Nn]$ ]]; then
      ecc-update
    fi
  fi

  # Launch ECC profile
  ocx oc -p ecc
}

# Quick access to update without launching
ecc-upgrade() {
  ecc-update
}

# Show ECC status
ecc-status() {
  local ecc_dir="$HOME/ecc"

  echo "ECC Profile Status"
  echo "=================="
  echo ""

  if [ -d "$ecc_dir/.git" ]; then
    cd "$ecc_dir"
    echo "Repository: $ecc_dir"
    echo "Current commit: $(git rev-parse --short HEAD)"
    echo "Branch: $(git branch --show-current)"

    git fetch origin main --quiet 2>/dev/null
    local current_hash=$(git rev-parse HEAD)
    local remote_hash=$(git rev-parse origin/main)

    if [ "$current_hash" != "$remote_hash" ]; then
      echo "Status: ⚠️  Update available"
      echo "Run 'ecc-update' to update"
    else
      echo "Status: ✓ Up to date"
    fi
  else
    echo "Error: ECC repository not found at $ecc_dir"
    return 1
  fi
}

# Clean up ECC backup files
ecc-clean() {
  local backup_dir="$HOME/.config/opencode/profiles/ecc/.backup"

  if [ -d "$backup_dir" ]; then
    local count=$(find "$backup_dir" -name "*.backup.*" | wc -l)
    if [ "$count" -gt 0 ]; then
      find "$backup_dir" -name "*.backup.*" -delete
      echo "Cleaned $count backup files"
    else
      echo "No backup files to clean"
    fi
  fi
}
