#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="${GIT_AUTO_PULL_SCRIPT:-$SCRIPT_DIR/pull.sh}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/git-auto-pull-test.XXXXXX")
TEST_HOME="$TEST_ROOT/home"
TEST_GIT_CONFIG="$TEST_ROOT/gitconfig"
REMOTE="$TEST_ROOT/remote.git"
SEED="$TEST_ROOT/seed"
AUTO_REPO="$TEST_HOME/Projects/auto-repo"
LOG_DIR="$TEST_HOME/.config/git-auto-pull"
LOG_FILE="$LOG_DIR/pull.log"
ERROR_LOG="$LOG_DIR/error.log"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_eq() {
    local expected="$1" actual="$2" message="$3"
    [[ "$expected" == "$actual" ]] || fail "$message (expected '$expected', got '$actual')"
}

assert_contains() {
    local file="$1" text="$2" message="$3"
    grep -F -- "$text" "$file" >/dev/null || fail "$message"
}

assert_not_contains() {
    local file="$1" text="$2" message="$3"
    if grep -F -- "$text" "$file" >/dev/null; then
        fail "$message"
    fi
}

commit_file() {
    local repo="$1" file="$2" content="$3" message="$4"
    printf '%s\n' "$content" > "$repo/$file"
    git -C "$repo" add "$file"
    git -C "$repo" -c user.name='Git Auto-Pull Test' -c user.email='git-auto-pull-test@example.com' commit -m "$message" >/dev/null
}

run_pull() {
    HOME="$TEST_HOME" bash "$SCRIPT_PATH"
}

mkdir -p "$TEST_HOME/Projects" "$LOG_DIR"
: > "$TEST_GIT_CONFIG"
export GIT_CONFIG_GLOBAL="$TEST_GIT_CONFIG"
: > "$LOG_FILE"
: > "$ERROR_LOG"

git -c init.defaultBranch=main init --bare "$REMOTE" >/dev/null
git -c init.defaultBranch=main init "$SEED" >/dev/null
git -C "$SEED" checkout -b develop >/dev/null 2>&1
commit_file "$SEED" README.md initial initial
git -C "$SEED" remote add origin "$REMOTE"
git -C "$SEED" push -u origin develop >/dev/null 2>&1
git --git-dir="$REMOTE" symbolic-ref HEAD refs/heads/develop
git clone --quiet "$REMOTE" "$AUTO_REPO"
git -C "$AUTO_REPO" checkout -b feature/work >/dev/null 2>&1

commit_file "$SEED" README.md develop-update develop-update
git -C "$SEED" push origin develop >/dev/null 2>&1

run_pull

assert_eq feature/work "$(git -C "$AUTO_REPO" symbolic-ref --quiet --short HEAD)" \
    'auto-pull changed the checked-out feature branch'
assert_eq "$(git --git-dir="$REMOTE" rev-parse refs/heads/develop)" \
    "$(git -C "$AUTO_REPO" rev-parse refs/heads/develop)" \
    'auto-pull did not update the remote default branch'
assert_contains "$LOG_FILE" "$AUTO_REPO (develop)" \
    'auto-pull did not log the default-branch update'
assert_not_contains "$LOG_FILE" "$AUTO_REPO (feature/work)" \
    'auto-pull incorrectly processed the checked-out feature branch'

git -C "$SEED" checkout -b feature/override develop >/dev/null 2>&1
git -C "$SEED" push -u origin feature/override >/dev/null 2>&1
git -C "$AUTO_REPO" fetch --quiet origin feature/override
git -C "$AUTO_REPO" branch feature/override origin/feature/override >/dev/null 2>&1
git -C "$AUTO_REPO" checkout develop >/dev/null 2>&1
commit_file "$SEED" override.txt override-update override-update
git -C "$SEED" push origin feature/override >/dev/null 2>&1
printf '%s\n' "$AUTO_REPO:feature/override" > "$TEST_HOME/.config/git-auto-pull/repos.conf"

run_pull

assert_eq "$(git --git-dir="$REMOTE" rev-parse refs/heads/feature/override)" \
    "$(git -C "$AUTO_REPO" rev-parse refs/heads/feature/override)" \
    'explicit config override was not updated'
assert_eq 1 "$(grep -c -F "Updated $AUTO_REPO (feature/override)" "$LOG_FILE")" \
    'configured repository was processed more than once'

git -C "$SEED" checkout -b main develop >/dev/null 2>&1
commit_file "$SEED" main.txt main-update main-update
git -C "$SEED" push -u origin main >/dev/null 2>&1
git -C "$SEED" show-ref --verify --quiet refs/heads/main || fail 'test fixture failed to create seed main branch'
git --git-dir="$REMOTE" show-ref --verify --quiet refs/heads/main || fail 'test fixture failed to push remote main branch'
git --git-dir="$REMOTE" symbolic-ref HEAD refs/heads/main
: > "$TEST_HOME/.config/git-auto-pull/repos.conf"

run_pull

assert_eq "$(git --git-dir="$REMOTE" rev-parse refs/heads/main)" \
    "$(git -C "$AUTO_REPO" rev-parse refs/heads/main)" \
    'auto-pull did not follow a changed remote default branch'
assert_contains "$LOG_FILE" "Created local branch main for $AUTO_REPO" \
    'auto-pull did not log the changed default branch'

EXTERNAL_REPO="$TEST_HOME/external-repo"
git clone --quiet "$REMOTE" "$EXTERNAL_REPO"
git -C "$EXTERNAL_REPO" fetch --quiet origin develop
git -C "$EXTERNAL_REPO" branch develop origin/develop >/dev/null 2>&1
git -C "$SEED" checkout develop >/dev/null 2>&1
commit_file "$SEED" external.txt external-update external-update
git -C "$SEED" push origin develop >/dev/null 2>&1
printf '%s\n' "$EXTERNAL_REPO:develop" > "$TEST_HOME/.config/git-auto-pull/repos.conf"

run_pull

assert_eq "$(git --git-dir="$REMOTE" rev-parse refs/heads/develop)" \
    "$(git -C "$EXTERNAL_REPO" rev-parse refs/heads/develop)" \
    'configured repository outside auto-discovery was not updated'
assert_contains "$LOG_FILE" "Updated $EXTERNAL_REPO (develop)" \
    'configured external repository update was not logged'
: > "$TEST_HOME/.config/git-auto-pull/repos.conf"

DIVERGED_REPO="$TEST_HOME/Projects/diverged-repo"
git clone --quiet "$REMOTE" "$DIVERGED_REPO"
commit_file "$DIVERGED_REPO" local-only.txt local-only local-only
git -C "$SEED" checkout main >/dev/null 2>&1
commit_file "$SEED" remote-only.txt remote-only remote-only
git -C "$SEED" push origin main >/dev/null 2>&1

run_pull

assert_not_contains "$LOG_FILE" "Updated $DIVERGED_REPO (main)" \
    'diverged default branch was reported as updated'
assert_contains "$ERROR_LOG" "Skipped diverged branch for $DIVERGED_REPO (main)" \
    'diverged default branch was not skipped'

BROKEN_REMOTE="$TEST_ROOT/broken.git"
BROKEN_REPO="$TEST_HOME/Projects/broken-repo"
git -c init.defaultBranch=main init --bare "$BROKEN_REMOTE" >/dev/null
git clone --quiet "$REMOTE" "$BROKEN_REPO"
git -C "$BROKEN_REPO" remote set-url origin "$BROKEN_REMOTE"
git -C "$BROKEN_REPO" push --quiet origin refs/remotes/origin/develop:refs/heads/develop
printf '%s\n' "$(git --git-dir="$BROKEN_REMOTE" rev-parse refs/heads/develop)" > "$BROKEN_REMOTE/HEAD"

run_pull

assert_contains "$ERROR_LOG" "Remote did not advertise a default branch for $BROKEN_REPO" \
    'missing remote HEAD was not reported'

echo 'PASS: git-auto-pull default-branch and override integration tests'
