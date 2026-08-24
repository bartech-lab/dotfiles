#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTOSWITCH_LOG="$TEST_ROOT/git-autoswitch.log"

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_HOME="$TEST_ROOT/home"
REMOTE="$TEST_ROOT/remote.git"
WORKTREE="$TEST_ROOT/worktree"

mkdir -p "$TEST_HOME/.local/bin"
ln -s "$REPO_ROOT/scripts/bin/git-autoswitch" "$TEST_HOME/.local/bin/git"

/usr/bin/git init --bare -b develop "$REMOTE" >/dev/null
/usr/bin/git init -b develop "$WORKTREE" >/dev/null
/usr/bin/git -C "$WORKTREE" config user.name "Git Autoswitch Test"
/usr/bin/git -C "$WORKTREE" config user.email "git-autoswitch@example.invalid"
/usr/bin/git -C "$WORKTREE" commit --allow-empty -m "Initial commit" >/dev/null
/usr/bin/git -C "$WORKTREE" remote add origin "$REMOTE"
/usr/bin/git -C "$WORKTREE" push -u origin develop >/dev/null
/usr/bin/git -C "$WORKTREE" switch -c feature/test >/dev/null
/usr/bin/git -C "$WORKTREE" commit --allow-empty -m "Feature commit" >/dev/null

PATH="$TEST_HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin" \
    /bin/bash -c 'cd "$1" && git push -u origin feature/test' _ "$WORKTREE" >/dev/null

branch=$(/usr/bin/git -C "$WORKTREE" branch --show-current)
if [[ "$branch" != "develop" ]]; then
    echo "Expected develop after push, got: $branch" >&2
    exit 1
fi

/usr/bin/git -C "$WORKTREE" switch -c feature/via-c >/dev/null
/usr/bin/git -C "$WORKTREE" commit --allow-empty -m "Via C commit" >/dev/null

# Agents invoke pushes as `git -C <repo> push` from another directory.
cd "$TEST_ROOT"
PATH="$TEST_HOME/.local/bin:/opt/homebrew/bin:/usr/bin:/bin" \
    /bin/bash -c 'git -C "$1" push origin feature/via-c' _ "$WORKTREE" >/dev/null

branch=$(/usr/bin/git -C "$WORKTREE" branch --show-current)
if [[ "$branch" != "develop" ]]; then
    echo "Expected develop after -C push, got: $branch" >&2
    exit 1
fi

echo "git-autoswitch test passed"
