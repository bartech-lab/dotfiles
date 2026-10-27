#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT_PATH="${BREW_AUTOUPDATE_SCRIPT:-$SCRIPT_DIR/autoupdate.sh}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/brew-autoupdate-test.XXXXXX")
FAKE_BREW="$TEST_ROOT/brew"
CALLS="$TEST_ROOT/calls"
STATUS_CALLS="$TEST_ROOT/status-calls"

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

cat > "$FAKE_BREW" <<SH
#!/bin/sh
echo "\$*" >> "$CALLS"
echo "brew output for \$1"
[ "\$1" = "\${FAKE_BREW_FAIL:-}" ] && exit 3
exit 0
SH
chmod +x "$FAKE_BREW"

new_home() {
    TEST_HOME="$TEST_ROOT/home-$1"
    LOG="$TEST_HOME/Library/Logs/brew-autoupdate/brew-autoupdate.log"
    mkdir -p "$TEST_HOME"
    : > "$CALLS"
    : > "$STATUS_CALLS"
}

add_job_status() {
    mkdir -p "$TEST_HOME/.local/bin"
    cat > "$TEST_HOME/.local/bin/job-status" <<SH
#!/bin/sh
printf '%s|' "\$@" >> "$STATUS_CALLS"
echo >> "$STATUS_CALLS"
SH
    chmod +x "$TEST_HOME/.local/bin/job-status"
}

run_update() {
    local rc=0
    OUT=$(HOME="$TEST_HOME" BREW_BIN="${1:-$FAKE_BREW}" FAKE_BREW_FAIL="${FAIL_STEP:-}" sh "$SCRIPT_PATH") || rc=$?
    RC=$rc
}

# A clean run upgrades formulae only, in order, and records success.
new_home ok
add_job_status
FAIL_STEP='' run_update
assert_eq 0 "$RC" "a clean run exits 0"
assert_eq $'update\nupgrade --formula\ncleanup' "$(cat "$CALLS")" "brew is called for update, formula upgrade and cleanup only"
assert_eq "ok|brew-autoupdate|--max-age|60|" "$(cat "$STATUS_CALLS")" "success is recorded with a 60 hour max age"
assert_eq "" "$OUT" "brew output goes to the log, not stdout"
grep -q '^brew output for upgrade$' "$LOG" || fail "brew output is in the log"
grep -q '^=== done ' "$LOG" || fail "the log ends with a done line"

# A failing update stops before any upgrade and records the exit code.
new_home update-fails
add_job_status
FAIL_STEP=update run_update
assert_eq 3 "$RC" "the brew exit code is the job exit code"
assert_eq "update" "$(cat "$CALLS")" "nothing runs after a failed update"
assert_eq "fail|brew-autoupdate|exit 3, see $LOG|--max-age|60|" "$(cat "$STATUS_CALLS")" "failure is recorded with the exit code and log path"
if grep -q '^=== done ' "$LOG"; then fail "a failed run writes no done line"; fi

# A failing upgrade skips cleanup.
new_home upgrade-fails
add_job_status
FAIL_STEP=upgrade run_update
assert_eq 3 "$RC" "a failed upgrade fails the job"
assert_eq $'update\nupgrade --formula' "$(cat "$CALLS")" "cleanup does not run after a failed upgrade"

# Without job-status the exit code is unchanged.
new_home no-status
FAIL_STEP=cleanup run_update
assert_eq 3 "$RC" "a failure still fails the job without job-status"
new_home no-status-ok
FAIL_STEP='' run_update
assert_eq 0 "$RC" "a clean run still exits 0 without job-status"

# Without brew the job does nothing and succeeds.
new_home no-brew
add_job_status
FAIL_STEP='' run_update "$TEST_ROOT/missing-brew"
assert_eq 0 "$RC" "a missing brew exits 0"
[[ ! -e "$TEST_HOME/Library/Logs/brew-autoupdate" ]] || fail "a missing brew creates no log"
assert_eq "" "$(cat "$STATUS_CALLS")" "a missing brew records nothing"

# The log rotates only above 1 MiB.
new_home rotate
mkdir -p "$(dirname "$LOG")"
head -c 1048577 /dev/zero | tr '\0' 'a' > "$LOG"
FAIL_STEP='' run_update
[[ -f "$LOG.1" ]] || fail "a log over 1 MiB is rotated"
assert_eq 1048577 "$(wc -c < "$LOG.1" | tr -d ' ')" "the rotated log is kept whole"
grep -q '^=== done ' "$LOG" || fail "the run writes a fresh log"
(( $(wc -c < "$LOG") < 1048576 )) || fail "the fresh log does not carry the rotated content"

new_home no-rotate
mkdir -p "$(dirname "$LOG")"
head -c 1048576 /dev/zero | tr '\0' 'a' > "$LOG"
FAIL_STEP='' run_update
[[ ! -e "$LOG.1" ]] || fail "a log of exactly 1 MiB is not rotated"

echo "brew-autoupdate tests passed"
