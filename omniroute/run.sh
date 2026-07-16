#!/bin/sh
# omniroute launcher — used by both launchd (macOS) and systemd --user (Linux).
# Resolves node without shell profiles (supervisors provide a minimal PATH),
# then execs node directly so the supervisor tracks the real server PID and
# SIGTERM reaches it (npm's shell intermediary breaks signal forwarding —
# see https://github.com/npm/rfcs/issues/829).
set -eu

APP_DIR="$HOME/omniroute"
cd "$APP_DIR"

if [ -x /usr/bin/node ]; then
  # Linux: system node (pacman)
  NODE=/usr/bin/node
else
  # macOS: newest fnm-managed node
  NODE=$(ls -d "$HOME/.local/share/fnm/node-versions"/*/installation/bin/node 2>/dev/null | sort -V | tail -1)
fi

if [ -z "${NODE:-}" ] || [ ! -x "$NODE" ]; then
  echo "omniroute: no node binary found" >&2
  exit 1
fi

export NODE_ENV=production
export PATH="$(dirname "$NODE"):$PATH"

# run-next.mjs runs Next in-process (no child spawn), so exec'ing node here
# means launchd/systemd supervise the actual server.
exec "$NODE" scripts/dev/run-next.mjs start
