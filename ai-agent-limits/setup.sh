#!/bin/bash

# ai-agent-limits Setup Script
# Installs a memory-capped systemd user slice for AI agent CLI sessions plus
# the ai-agent-scope launcher. Linux only; cgroup v2 has no macOS equivalent.
# Safe to re-run.

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC_DIR="$DOTFILES_DIR/ai-agent-limits"

if [[ "$(uname -s)" != "Linux" ]]; then
    echo "ai-agent-limits is Linux-only (cgroup v2); nothing to do on $(uname -s)."
    exit 0
fi

if ! command -v systemd-run >/dev/null 2>&1; then
    echo "Error: systemd-run not found; this host cannot enforce the slice." >&2
    exit 1
fi

echo "Setting up ai-agent-limits (systemd user slice)..."

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"

# Atomic replace: a running bash keeps reading the old inode safely.
cp "$SRC_DIR/ai-agent-scope" "$HOME/.local/bin/ai-agent-scope.tmp"
chmod +x "$HOME/.local/bin/ai-agent-scope.tmp"
mv -f "$HOME/.local/bin/ai-agent-scope.tmp" "$HOME/.local/bin/ai-agent-scope"

cp "$SRC_DIR/ai-agents.slice" "$HOME/.config/systemd/user/ai-agents.slice"
systemctl --user daemon-reload

high=$(systemctl --user show ai-agents.slice -p MemoryHigh --value)
max=$(systemctl --user show ai-agents.slice -p MemoryMax --value)

if [[ "$max" == "infinity" || -z "$max" ]]; then
    echo "Warning: MemoryMax did not apply; check the slice unit." >&2
    exit 1
fi

echo "Slice loaded: MemoryHigh=$high MemoryMax=$max"
echo ""
echo "Setup complete."
echo "The claude/codex shell functions in zsh/functions/41-ai-agents.zsh route"
echo "through ai-agent-scope. Restart existing agent sessions to pick up the cap."
echo "Verify: ai-agent-mem"
