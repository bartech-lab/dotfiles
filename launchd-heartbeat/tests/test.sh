#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/launchd-heartbeat-test.XXXXXX")
TEST_HOME="$TEST_ROOT/home"
MOCK_BIN="$TEST_ROOT/bin"
LOG_DIR="$TEST_HOME/.config/launchd-heartbeat"
LOG_FILE="$LOG_DIR/heartbeat.log"
ERROR_LOG="$LOG_DIR/error.log"
NOTIFY_LOG="$TEST_ROOT/notifications.log"
CALL_LOG="$TEST_ROOT/systemctl-calls.log"

cleanup() {
    rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() {
    echo "FAIL: $*" >&2
    exit 1
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

mkdir -p "$MOCK_BIN" "$LOG_DIR"

cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/bin/bash

set -euo pipefail

printf '%s\n' "$*" >> "$CALL_LOG"

if [[ "${1:-}" != --user ]]; then
    exit 2
fi
shift

case "${1:-}" in
    show)
        service="$2"
        property="${3#--property=}"
        case "$service:$property" in
            healthy.service:LoadState|failed.service:LoadState|active.service:LoadState)
                echo loaded
                ;;
            missing.service:LoadState)
                echo not-found
                ;;
            healthy.service:ActiveState)
                echo inactive
                ;;
            failed.service:ActiveState)
                echo failed
                ;;
            active.service:ActiveState)
                echo active
                ;;
            missing.service:ActiveState)
                echo inactive
                ;;
            healthy.service:Result|active.service:Result)
                echo success
                ;;
            failed.service:Result)
                echo exit-code
                ;;
            missing.service:Result)
                echo success
                ;;
            *)
                exit 1
                ;;
        esac
        ;;
    is-active)
        case "$2" in
            healthy.timer|failed.timer)
                echo active
                ;;
            active.timer|missing.timer)
                echo inactive
                exit 3
                ;;
            *)
                echo unknown
                exit 3
                ;;
        esac
        ;;
    *)
        exit 2
        ;;
esac
EOF
chmod +x "$MOCK_BIN/systemctl"

cat > "$MOCK_BIN/notify-send" <<'EOF'
#!/bin/bash

printf '%s\n' "$*" >> "$NOTIFY_LOG"
EOF
chmod +x "$MOCK_BIN/notify-send"

export CALL_LOG NOTIFY_LOG
export HOME="$TEST_HOME"
export PATH="$MOCK_BIN:$PATH"

help_output=$(bash "$SCRIPT_DIR/heartbeat.sh" --help)
[[ "$help_output" == *'Usage: heartbeat.sh [--help]'* ]] || fail '--help did not print usage'

cat > "$LOG_DIR/monitored-labels.conf" <<'EOF'
# A successful idle oneshot with an active timer is healthy.
healthy.service
failed.service
missing.service
active.service
EOF

bash "$SCRIPT_DIR/heartbeat.sh"

assert_contains "$LOG_FILE" \
    'Label=healthy.service status=active state=inactive result=success timer=active' \
    'successful idle oneshot with an active timer was not healthy'
assert_contains "$ERROR_LOG" \
    'Label=failed.service status=failed state=failed result=exit-code timer=active' \
    'failed oneshot was masked by its active timer'
assert_contains "$ERROR_LOG" \
    'Label=missing.service status=missing state=unknown result=unknown timer=inactive' \
    'missing service was not distinguished from a failed service'
assert_contains "$LOG_FILE" \
    'Label=active.service status=active state=active result=success timer=inactive' \
    'active service was not reported as healthy'
assert_contains "$LOG_FILE" 'Run finished monitored=4 loaded=2' \
    'heartbeat summary did not count healthy services'
assert_contains "$NOTIFY_LOG" 'launchd heartbeat Failed or missing: failed.service (failed), missing.service (missing)' \
    'notification did not include failed and missing services'
assert_not_contains "$NOTIFY_LOG" 'healthy.service' \
    'notification included a healthy service'

failed_result_line=$(grep -n -- 'show failed.service --property=Result' "$CALL_LOG" | head -n 1 | cut -d: -f1)
timer_line=$(grep -n -- 'is-active failed.timer' "$CALL_LOG" | head -n 1 | cut -d: -f1)
[[ "$failed_result_line" -lt "$timer_line" ]] || fail 'failed service Result was checked after its timer'

echo 'PASS: launchd-heartbeat service-state and timer checks'
