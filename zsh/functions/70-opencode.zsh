# OpenCode Functions

oco() {
  if ! command -v opencode >/dev/null; then
    echo "OpenCode not installed. Run: curl -fsSL https://opencode.ai/install | bash" >&2
    return 1
  fi
  opencode "$@"
}

# Cleanup orphaned opencode processes (safe with multiple terminals)
# Only removes exact `opencode` processes reparented to launchd (PPID 1)
# and no longer attached to any terminal (tty == "??")
opencode-clean() {
  echo "Scanning orphaned opencode processes..."

  local -a candidates surviving
  local pid ppid tty command

  while read -r pid ppid tty command; do
    [[ -z "$pid" ]] && continue
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    [[ "$ppid" == "1" ]] || continue
    [[ "$tty" == "??" ]] || continue
    [[ "$command" == "opencode" ]] || continue
    candidates+=("$pid")
  done < <(ps -axo pid=,ppid=,tty=,comm=)

  if (( ${#candidates[@]} == 0 )); then
    echo "No orphaned opencode processes detected"
    return 0
  fi

  echo "Found ${#candidates[@]} orphaned process(es): ${candidates[*]}"

  for pid in "${candidates[@]}"; do
    echo "Sending TERM to PID $pid"
    kill -TERM "$pid" 2>/dev/null || true
  done

  sleep 1

  for pid in "${candidates[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      surviving+=("$pid")
    fi
  done

  if (( ${#surviving[@]} > 0 )); then
    echo "Escalating to KILL for: ${surviving[*]}"
    for pid in "${surviving[@]}"; do
      kill -KILL "$pid" 2>/dev/null || true
    done
    sleep 0.5
  fi

  local -a remaining
  for pid in "${candidates[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      remaining+=("$pid")
    fi
  done

  if (( ${#remaining[@]} == 0 )); then
    echo "Cleaned ${#candidates[@]} orphaned opencode process(es)"
    return 0
  fi

  echo "Failed to clean: ${remaining[*]}"
  return 1
}

alias ocfix='opencode-clean'
