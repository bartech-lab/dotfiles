#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT=$(mktemp -d)
pids=()
cleanup() { for p in "${pids[@]}"; do kill "$p" 2>/dev/null || true; done; rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
eval "$(sed -n '/^agents_running() {/,/^}/p' "$REPO_ROOT/ai-caffeine/ai-caffeine")"

fail() { echo "FAIL: $*" >&2; exit 1; }

ln -s "$(command -v sleep)" "$TEST_ROOT/aicfake"
export PROCESSES=aicfake

agents_running && fail "detected an agent with none running"

( exec -a "aicfake app-server daemon" "$TEST_ROOT/aicfake" 30 ) & pids+=($!)
sleep 0.5
if ! pgrep -x aicfake >/dev/null; then
    echo "skip: this platform names a symlinked process after its target"
    exit 0
fi
agents_running && fail "an app-server daemon counted as an agent session"

( exec -a "aicfake --cd /work" "$TEST_ROOT/aicfake" 30 ) & pids+=($!)
sleep 0.5
agents_running || fail "a real agent session beside the daemon was missed"

echo ok
