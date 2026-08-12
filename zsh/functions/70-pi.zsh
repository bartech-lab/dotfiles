# pi Coding Agent Functions

# Rebuild pi's global AGENTS.md from ~/.claude/rules/*.md.
# Run after editing any rule file, then use /reload inside pi.
pi-agents() {
  local script="$HOME/.pi/agent/bin/build-agents-md.sh"
  if [[ ! -x "$script" ]]; then
    echo "pi AGENTS.md builder not found at $script" >&2
    return 1
  fi
  "$script"
}

# Cleanup orphaned pi processes (safe with multiple terminals)
# pi runs under node, so `comm` is "node" and cannot identify it. Matching is
# done on the argument list, which always contains the package path.
# Only removes processes reparented to launchd (PPID 1) and no longer attached
# to any terminal (tty == "??").
pi-clean() {
  echo "Scanning orphaned pi processes..."

  local -a candidates surviving remaining
  local pid ppid tty args

  while read -r pid ppid tty args; do
    [[ -z "$pid" ]] && continue
    [[ "$pid" =~ ^[0-9]+$ ]] || continue
    [[ "$ppid" == "1" ]] || continue
    [[ "$tty" == "??" ]] || continue
    [[ "$args" == *pi-coding-agent* ]] || continue
    candidates+=("$pid")
  done < <(ps -axo pid=,ppid=,tty=,args=)

  if (( ${#candidates[@]} == 0 )); then
    echo "No orphaned pi processes detected"
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

  for pid in "${candidates[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      remaining+=("$pid")
    fi
  done

  if (( ${#remaining[@]} == 0 )); then
    echo "Cleaned ${#candidates[@]} orphaned pi process(es)"
    return 0
  fi

  echo "Failed to clean: ${remaining[*]}"
  return 1
}

alias pifix='pi-clean'
