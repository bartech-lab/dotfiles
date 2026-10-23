#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTOSWITCH_LOG="$TEST_ROOT/git-autoswitch.log"

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TEST_HOME="$TEST_ROOT/home"
mkdir -p "$TEST_HOME/.local/bin"
ln -s "$REPO_ROOT/scripts/bin/git-autoswitch" "$TEST_HOME/.local/bin/git"

REAL=/usr/bin/git
WT=""
OUT=""
ERR=""
STATUS=0

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

mk_case() {
    local name=$1 first=$2
    local dir="$TEST_ROOT/$name"
    mkdir -p "$dir"
    WT="$dir/worktree"
    OUT="$dir/out"
    ERR="$dir/err"
    "$REAL" init --bare -b "$first" "$dir/remote.git" >/dev/null
    "$REAL" init -b "$first" "$WT" >/dev/null
    "$REAL" -C "$WT" config user.name "Git Autoswitch Test"
    "$REAL" -C "$WT" config user.email "git-autoswitch@example.invalid"
    "$REAL" -C "$WT" commit --allow-empty -m "Initial commit" >/dev/null
    "$REAL" -C "$WT" remote add origin "$dir/remote.git"
    "$REAL" -C "$WT" push origin "$first" >/dev/null 2>&1
}

remote_branch() {
    "$REAL" -C "$WT" push origin "$1:refs/heads/$2" >/dev/null 2>&1
}

start_feature() {
    "$REAL" -C "$WT" switch -c feature/x >/dev/null 2>&1
    "$REAL" -C "$WT" commit --allow-empty -m "Feature commit" >/dev/null
}

wrapped() {
    STATUS=0
    PATH="$TEST_HOME/.local/bin:$PATH" git -C "$WT" "$@" >"$OUT" 2>"$ERR" || STATUS=$?
}

current() {
    "$REAL" -C "$WT" rev-parse --abbrev-ref HEAD
}

expect_branch() {
    local want=$1 label=$2 got
    got=$(current)
    [[ "$got" == "$want" ]] || fail "$label: expected branch $want, got $got"
}

expect_status_zero() {
    [[ "$STATUS" -eq 0 ]] || fail "$1: expected exit 0, got $STATUS"
}

expect_no_switch_message() {
    if grep -q "switching back" "$OUT" "$ERR"; then
        fail "$1: unexpected switching message"
    fi
}

expect_stderr_contains() {
    grep -q -- "$2" "$ERR" || fail "$1: stderr lacks '$2': $(cat "$ERR")"
}

mk_case c1 develop
start_feature
wrapped push -fn origin feature/x
expect_status_zero "case 1"
expect_branch feature/x "case 1"
expect_no_switch_message "case 1"

mk_case c2 develop
"$REAL" -C "$WT" remote add broken "$TEST_ROOT/c2/does-not-exist.git"
start_feature
real_status=0
"$REAL" -C "$WT" push broken feature/x >/dev/null 2>&1 || real_status=$?
[[ "$real_status" -ne 0 ]] || fail "case 2: setup push unexpectedly succeeded"
wrapped push broken feature/x
[[ "$STATUS" -ne 0 ]] || fail "case 2: expected non-zero exit"
[[ "$STATUS" -eq "$real_status" ]] || fail "case 2: expected exit $real_status, got $STATUS"
expect_branch feature/x "case 2"
expect_no_switch_message "case 2"

mk_case c2b develop
start_feature
"$REAL" -C "$WT" push origin feature/x >/dev/null 2>&1
"$REAL" -C "$WT" switch develop >/dev/null 2>&1
"$REAL" -C "$WT" switch -c feature/y >/dev/null 2>&1
"$REAL" -C "$WT" commit --allow-empty -m "Other" >/dev/null
real_status=0
"$REAL" -C "$WT" push origin feature/y:refs/heads/feature/x >/dev/null 2>&1 || real_status=$?
[[ "$real_status" -ne 0 ]] || fail "case 2b: setup push unexpectedly succeeded"
wrapped push origin feature/y:refs/heads/feature/x
[[ "$STATUS" -eq "$real_status" ]] || fail "case 2b: expected exit $real_status, got $STATUS"
expect_branch feature/y "case 2b"
expect_no_switch_message "case 2b"

mk_case c3 develop
remote_branch develop main
"$REAL" -C "$WT" remote set-head origin main >/dev/null
start_feature
wrapped push origin feature/x
expect_status_zero "case 3"
expect_branch main "case 3"

mk_case c4a master
remote_branch master main
start_feature
wrapped push origin feature/x
expect_status_zero "case 4a"
expect_branch master "case 4a"

mk_case c4b develop
remote_branch develop main
start_feature
wrapped push origin feature/x
expect_status_zero "case 4b"
expect_branch develop "case 4b"

mk_case c5 trunk
start_feature
wrapped push origin feature/x
expect_status_zero "case 5"
expect_branch feature/x "case 5"
expect_stderr_contains "case 5" "no origin/HEAD"

mk_case c6 develop
wrapped push origin develop
expect_status_zero "case 6"
expect_branch develop "case 6"
expect_no_switch_message "case 6"

mk_case c7 develop
start_feature
echo scratch >"$WT/untracked.txt"
wrapped push origin feature/x
expect_status_zero "case 7"
expect_branch develop "case 7"

mk_case c8a develop
echo base >"$WT/tracked.txt"
"$REAL" -C "$WT" add tracked.txt
"$REAL" -C "$WT" commit -m "Add tracked" >/dev/null
"$REAL" -C "$WT" push origin develop >/dev/null 2>&1
start_feature
echo changed >"$WT/tracked.txt"
wrapped push origin feature/x
expect_status_zero "case 8a"
expect_branch feature/x "case 8a"
expect_stderr_contains "case 8a" "staying on"

mk_case c8b develop
echo base >"$WT/tracked.txt"
"$REAL" -C "$WT" add tracked.txt
"$REAL" -C "$WT" commit -m "Add tracked" >/dev/null
"$REAL" -C "$WT" push origin develop >/dev/null 2>&1
start_feature
echo changed >"$WT/tracked.txt"
"$REAL" -C "$WT" add tracked.txt
wrapped push origin feature/x
expect_status_zero "case 8b"
expect_branch feature/x "case 8b"
expect_stderr_contains "case 8b" "staying on"

mk_case c9 develop
start_feature
wrapped status --short
expect_status_zero "case 9"
expect_branch feature/x "case 9"

mk_case c10 develop
start_feature
"$REAL" -C "$WT" switch --detach feature/x >/dev/null 2>&1
wrapped push origin HEAD:refs/heads/feature/x
expect_status_zero "case 10"
expect_branch HEAD "case 10"

echo "PASS: git-autoswitch edge tests"
