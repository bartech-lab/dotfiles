#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TOOL=(bash "$REPO_ROOT/git-auto-pull/pull.sh")
export HOME="$TEST_ROOT/home"
UP="$TEST_ROOT/up.git"
DEV="$TEST_ROOT/dev"

fail() { echo "FAIL: $*" >&2; exit 1; }

g() { git -c user.name=t -c user.email=t@example.invalid "$@"; }

publish() {
    printf '%s\n' "$1" > "$DEV/f"
    g -C "$DEV" commit -qam "$1"
    g -C "$DEV" push -q origin main
}

mkdir -p "$HOME/Projects"
git init -q --bare -b main "$UP"
g clone -q "$UP" "$DEV" 2>/dev/null
printf 'v1\n' > "$DEV/f"
g -C "$DEV" add f
g -C "$DEV" commit -qm v1
g -C "$DEV" push -q origin main

# main checked out in the primary worktree: fast-forwarded.
g clone -q "$UP" "$HOME/Projects/onmain"
publish v2
"${TOOL[@]}" || true
[[ "$(cat "$HOME/Projects/onmain/f")" == v2 ]] || fail "checked-out main not fast-forwarded"

# main not checked out anywhere: the branch ref moves, the worktree stays.
g clone -q "$UP" "$HOME/Projects/onfeature"
g -C "$HOME/Projects/onfeature" switch -q -c feature
publish v3
"${TOOL[@]}" || true
[[ "$(git -C "$HOME/Projects/onfeature" rev-parse main)" == "$(git -C "$DEV" rev-parse HEAD)" ]] || fail "idle main ref not updated"
[[ "$(cat "$HOME/Projects/onfeature/f")" == v2 ]] || fail "feature worktree changed"

# main checked out in a linked worktree: the ref must not move under it.
g -C "$HOME/Projects/onfeature" worktree add -q "$TEST_ROOT/linked" main
before=$(git -C "$TEST_ROOT/linked" rev-parse HEAD)
publish v4
"${TOOL[@]}" || true
[[ "$(git -C "$TEST_ROOT/linked" rev-parse HEAD)" == "$before" ]] || fail "main moved under a linked worktree"
[[ -z "$(git -C "$TEST_ROOT/linked" status --porcelain)" ]] || fail "linked worktree shows changes it did not make"
grep -q "checked out in another worktree" "$HOME/.config/git-auto-pull/error.log" || fail "skip not logged"

echo ok
