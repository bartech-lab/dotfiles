#!/bin/bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEARTBEAT_SCRIPT="${HEARTBEAT_BIN:-${HEARTBEAT_SCRIPT:-$SCRIPT_DIR/heartbeat.sh}}"
JOB_STATUS_SCRIPT="${JOB_STATUS_SCRIPT:-$SCRIPT_DIR/job-status.sh}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/launchd-heartbeat-health.XXXXXX")
TEST_HOME="$TEST_ROOT/home"
MOCK_BIN="$TEST_ROOT/bin"
CONF_DIR="$TEST_HOME/.config/launchd-heartbeat"
LOG_FILE="$CONF_DIR/heartbeat.log"
ERROR_LOG="$CONF_DIR/error.log"
LAST_NOTIFIED="$CONF_DIR/last-notified"
PROBES="$CONF_DIR/probes.conf"
NOTIFY_LOG="$TEST_ROOT/notifications.log"
JOB_DIR="$TEST_ROOT/jobs"

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
    if [[ -f "$file" ]] && grep -F -- "$text" "$file" >/dev/null; then
        fail "$message"
    fi
}

assert_eq() {
    [[ "$1" == "$2" ]] || fail "$3 (expected '$2', got '$1')"
}

assert_line() {
    printf '%s\n' "$1" | grep -E -- "$2" >/dev/null || fail "$3"
}

assert_no_line() {
    if printf '%s\n' "$1" | grep -E -- "$2" >/dev/null; then
        fail "$3"
    fi
}

notify_count() {
    if [[ -f "$NOTIFY_LOG" ]]; then wc -l < "$NOTIFY_LOG" | tr -d ' '; else echo 0; fi
}

record_value() {
    grep -m1 "^$2=" "$JOB_DIR/$1.status" | cut -d= -f2-
}

write_record() {
    local job="$1"
    shift
    printf '%s\n' "$@" > "$JOB_DIR/$job.status"
}

reset() {
    rm -rf "$CONF_DIR" "$JOB_DIR" "$NOTIFY_LOG"
    mkdir -p "$CONF_DIR" "$JOB_DIR"
    printf '# no services\n' > "$CONF_DIR/monitored-labels.conf"
    : > "$PROBES"
}

heartbeat() {
    bash "$HEARTBEAT_SCRIPT" "$@"
}

mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/uname" <<'EOF'
#!/bin/sh
echo Linux
EOF
cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/bin/bash
exit 1
EOF
cat > "$MOCK_BIN/notify-send" <<'EOF'
#!/bin/bash

printf '%s\n' "$*" >> "$NOTIFY_LOG"
EOF
chmod +x "$MOCK_BIN/uname" "$MOCK_BIN/systemctl" "$MOCK_BIN/notify-send"

export NOTIFY_LOG JOB_STATUS_DIR="$JOB_DIR"
export HOME="$TEST_HOME"
export PATH="$MOCK_BIN:$PATH"
export HEARTBEAT_MAX_LOG_BYTES=1048576
unset HEARTBEAT_PROBE_TIMEOUT
PAUSE_FILE="$TEST_ROOT/pause"
export HEARTBEAT_PAUSE_FILE="$TEST_ROOT/no-such-pause-file"

help_output=$(heartbeat --help)
[[ "$help_output" == *'Usage: heartbeat.sh'* ]] || fail '--help did not print usage'

echo "== probes"
reset
cat > "$PROBES" <<'EOF'
# commented-probe false

good-probe true
args-probe test 1 -eq 1
pipe-probe echo hi | grep -q hi
bonsai-http false
EOF
heartbeat
assert_contains "$LOG_FILE" 'good-probe' 'healthy probe not logged to heartbeat.log'
assert_contains "$LOG_FILE" 'args-probe' 'probe with arguments not run as a command'
assert_contains "$LOG_FILE" 'pipe-probe' 'probe with a pipe not run through bash -c'
assert_contains "$ERROR_LOG" 'bonsai-http' 'failed probe not logged to error.log'
assert_not_contains "$ERROR_LOG" 'good-probe' 'healthy probe logged as a problem'
assert_not_contains "$LOG_FILE" 'commented-probe' 'commented probe was run'
assert_not_contains "$ERROR_LOG" 'commented-probe' 'commented probe was run'
assert_contains "$NOTIFY_LOG" 'launchd heartbeat Failed or missing: bonsai-http (failed)' \
    'notification did not name the failed probe'
assert_eq "$(notify_count)" 1 'one problem run must send one notification'
assert_not_contains "$NOTIFY_LOG" 'good-probe' 'notification included a healthy probe'

echo "== notify only on change"
heartbeat
assert_eq "$(notify_count)" 1 'identical second run notified again'
printf 'second-probe false\n' >> "$PROBES"
heartbeat
assert_eq "$(notify_count)" 2 'changed problem set did not notify'
assert_contains "$NOTIFY_LOG" 'second-probe (failed)' 'changed notification missed the new item'
: > "$PROBES"
heartbeat
assert_eq "$(notify_count)" 2 'recovery sent a notification'
[[ ! -s "$LAST_NOTIFIED" ]] || fail 'last-notified was not emptied on recovery'
printf 'bonsai-http false\n' > "$PROBES"
heartbeat
assert_eq "$(notify_count)" 3 'same problem after recovery did not notify again'

echo "== --status"
reset
printf 'bad-probe false\nfine-probe true\n' > "$PROBES"
rc=0
out=$(heartbeat --status) || rc=$?
assert_eq "$rc" 2 '--status with a problem must exit 2'
assert_line "$out" '^FAIL .*bad-probe' '--status missing FAIL line for bad-probe'
assert_line "$out" '^ok .*fine-probe' '--status missing ok line for fine-probe'
assert_no_line "$out" '^ok .*bad-probe' '--status reported bad-probe as ok'
assert_eq "$(notify_count)" 0 '--status called notify-send'
[[ ! -s "$LAST_NOTIFIED" ]] || fail '--status wrote last-notified'
heartbeat
before=$(cat "$LAST_NOTIFIED")
printf 'other-probe false\n' >> "$PROBES"
rc=0
heartbeat --status > /dev/null || rc=$?
assert_eq "$rc" 2 '--status exit code with changed problem set'
assert_eq "$(cat "$LAST_NOTIFIED")" "$before" '--status changed last-notified'
assert_eq "$(notify_count)" 1 '--status notified on a changed problem set'
printf 'fine-probe true\n' > "$PROBES"
rc=0
out=$(heartbeat --status) || rc=$?
assert_eq "$rc" 0 '--status with no problem must exit 0'
assert_line "$out" '^ok .*fine-probe' '--status missing ok line when healthy'

echo "== probe timeout"
reset
printf 'slow-probe sleep 30\n' > "$PROBES"
SECONDS=0
HEARTBEAT_PROBE_TIMEOUT=1 heartbeat
(( SECONDS < 10 )) || fail "run took ${SECONDS}s with a 1s probe timeout"
assert_contains "$ERROR_LOG" 'slow-probe' 'timed-out probe not counted as failed'
assert_contains "$NOTIFY_LOG" 'slow-probe (failed)' 'timed-out probe not in notification'

echo "== job records"
reset
now=$(date +%s)
write_record recovered "last_failure=$((now - 500))" "last_success=$((now - 100))" "max_age_hours=24"
write_record newfail "last_success=$((now - 100))" "last_failure=$((now - 10))" 'reason=exit 3 key=value'
write_record onlyfail "last_failure=$((now - 10))"
write_record staleshort "last_success=$((now - 3 * 3600))" "max_age_hours=2"
write_record stalelong "last_success=$((now - 3 * 3600))" "max_age_hours=5"
write_record nosuccess "last_attempt=$((now - 10))" "max_age_hours=1"
write_record noage "last_success=$((now - 400 * 3600))"
write_record failwins "last_success=$((now - 9 * 3600))" "last_failure=$((now - 5))" "max_age_hours=1"
rc=0
out=$(heartbeat --status) || rc=$?
assert_eq "$rc" 2 'job problems must make --status exit 2'
assert_line "$out" '^ok .*recovered' 'last_failure older than last_success must be healthy'
assert_line "$out" '^FAIL .*newfail' 'last_failure newer than last_success must fail'
assert_line "$out" '^FAIL .*onlyfail' 'last_failure with no last_success must fail'
assert_line "$out" '^FAIL .*staleshort' 'success older than max_age_hours must be stale'
assert_line "$out" '^ok .*stalelong' 'stale check must use the record own max_age_hours'
assert_line "$out" '^FAIL .*nosuccess' 'max_age_hours with no last_success must be stale'
assert_line "$out" '^ok .*noage' 'a job without max_age_hours is never stale'
assert_line "$out" '^FAIL .*failwins.*failed' 'failed must win over stale'
heartbeat
assert_contains "$NOTIFY_LOG" 'staleshort (stale)' 'notification missing stale label'
assert_contains "$NOTIFY_LOG" 'newfail (failed)' 'notification missing failed label'
assert_contains "$NOTIFY_LOG" 'failwins (failed)' 'notification showed the wrong status for failwins'
assert_not_contains "$NOTIFY_LOG" 'recovered' 'notification included a recovered job'
assert_not_contains "$NOTIFY_LOG" 'stalelong' 'notification included a fresh job'
assert_contains "$ERROR_LOG" 'exit 3 key=value' 'error.log line for a failed job lacks the reason'
assert_contains "$LOG_FILE" 'recovered' 'healthy job not logged to heartbeat.log'

echo "== log rotation"
reset
pad=$(printf 'x%.0s' {1..300})
printf 'OLDHB %s\n' "$pad" > "$LOG_FILE"
printf 'OLDERR %s\n' "$pad" > "$ERROR_LOG"
printf 'STALE1\n' > "$LOG_FILE.1"
printf 'good-probe true\nbad-probe false\n' > "$PROBES"
HEARTBEAT_MAX_LOG_BYTES=100 heartbeat
assert_contains "$LOG_FILE.1" 'OLDHB' 'oversized heartbeat.log not moved to .1'
assert_not_contains "$LOG_FILE.1" 'STALE1' 'older heartbeat.log.1 not overwritten'
assert_not_contains "$LOG_FILE" 'OLDHB' 'heartbeat.log kept old content after rotation'
assert_contains "$LOG_FILE" 'good-probe' 'fresh heartbeat.log not written after rotation'
assert_contains "$ERROR_LOG.1" 'OLDERR' 'oversized error.log not moved to .1'
assert_not_contains "$ERROR_LOG" 'OLDERR' 'error.log kept old content after rotation'
assert_contains "$ERROR_LOG" 'bad-probe' 'fresh error.log not written after rotation'
reset
printf 'KEEP\n' > "$LOG_FILE"
heartbeat
assert_contains "$LOG_FILE" 'KEEP' 'small heartbeat.log was rotated'
[[ ! -e "$LOG_FILE.1" ]] || fail 'small heartbeat.log produced a .1 file'

echo "== job-status.sh"
reset
before=$(date +%s)
bash "$JOB_STATUS_SCRIPT" start alpha
after=$(date +%s)
attempt=$(record_value alpha last_attempt)
(( attempt >= before && attempt <= after )) || fail 'start did not set last_attempt to now'
[[ -z "$(record_value alpha last_success)" ]] || fail 'start set last_success'
bash "$JOB_STATUS_SCRIPT" ok alpha --max-age 6
assert_eq "$(record_value alpha max_age_hours)" 6 'ok --max-age not stored'
success=$(record_value alpha last_success)
assert_eq "$(record_value alpha last_attempt)" "$success" 'ok must set last_attempt and last_success together'
(( success >= before )) || fail 'ok did not set last_success to now'
bash "$JOB_STATUS_SCRIPT" fail alpha $'first line\nsecond a=b'
assert_eq "$(record_value alpha reason)" 'first line second a=b' 'reason with newline and = not stored on one line'
assert_eq "$(grep -c '^reason=' "$JOB_DIR/alpha.status")" 1 'reason must occupy exactly one line'
assert_eq "$(wc -l < "$JOB_DIR/alpha.status" | tr -d ' ')" \
    "$(grep -c '=' "$JOB_DIR/alpha.status")" 'every record line must be key=value'
assert_eq "$(record_value alpha max_age_hours)" 6 'fail dropped max_age_hours'
assert_eq "$(record_value alpha last_success)" "$success" 'fail dropped last_success'
[[ -n "$(record_value alpha last_failure)" ]] || fail 'fail did not set last_failure'
bash "$JOB_STATUS_SCRIPT" ok alpha
assert_eq "$(record_value alpha max_age_hours)" 6 'ok without the flag dropped max_age_hours'
[[ -n "$(record_value alpha last_failure)" ]] || fail 'ok dropped last_failure'
bash "$JOB_STATUS_SCRIPT" fail alpha reason2 --max-age 9
assert_eq "$(record_value alpha max_age_hours)" 9 'fail --max-age not stored'
assert_eq "$(record_value alpha reason)" reason2 'second fail did not replace reason'
rc=0
bash "$JOB_STATUS_SCRIPT" ok '../x' || rc=$?
assert_eq "$rc" 2 'invalid job name must exit 2'
[[ ! -e "$TEST_ROOT/x.status" && ! -e "$JOB_DIR/../x.status" ]] || fail 'invalid job name wrote a file'
assert_eq "$(find "$JOB_DIR" -type f | wc -l | tr -d ' ')" 1 'invalid job name changed the job directory'
rc=0
bash "$JOB_STATUS_SCRIPT" explode alpha || rc=$?
assert_eq "$rc" 2 'unknown command must exit 2'

echo "== job-status then heartbeat"
reset
rm -rf "$JOB_DIR"
bash "$JOB_STATUS_SCRIPT" fail harvest 'VPN off: GitLab 404'
rc=0
out=$(heartbeat --status) || rc=$?
assert_eq "$rc" 2 'job marked fail must make --status exit 2'
assert_line "$out" '^FAIL .*harvest' 'failed job not reported by heartbeat'
heartbeat
assert_contains "$NOTIFY_LOG" 'harvest (failed)' 'failed job missing from notification'
assert_contains "$ERROR_LOG" 'VPN off: GitLab 404' 'failed job reason missing from error.log'
now=$(date +%s)
write_record harvest "last_failure=$((now - 60))" "last_success=$((now - 5))" 'reason=VPN off: GitLab 404'
rc=0
heartbeat --status > /dev/null || rc=$?
assert_eq "$rc" 0 'job with a newer success must be healthy'
heartbeat
assert_eq "$(notify_count)" 1 'recovery sent a notification'
[[ ! -s "$LAST_NOTIFIED" ]] || fail 'last-notified not emptied after job recovery'

echo "== pause file"
write_pause() {
    local since="$1" maxage="$2" owner="$3"
    shift 3
    { printf 'since=%s\nowner=%s\nmax_age_hours=%s\n' "$since" "$owner" "$maxage"
      local n; for n in "$@"; do printf 'pause=%s\n' "$n"; done; } > "$PAUSE_FILE"
}
now=$(date +%s)
hb() { HEARTBEAT_PAUSE_FILE="$PAUSE_FILE" heartbeat "$@"; }

reset
rm -f "$PAUSE_FILE"
printf 'down.service\n' > "$CONF_DIR/monitored-labels.conf"
printf 'p-paused false\np-live false\np-fine true\n' > "$PROBES"
rc=0
out=$(hb --status) || rc=$?
assert_eq "$rc" 2 'no pause file: failing checks must exit 2'
assert_no_line "$out" 'pause-' 'no pause file but a pause- line was printed'
assert_line "$out" '^FAIL .*p-paused' 'no pause file: p-paused must FAIL'
assert_line "$out" '^FAIL .*down\.service' 'no pause file: unavailable label must FAIL (harness sanity)'

write_pause "$((now - 60))" 12 gaming p-paused down.service
rc=0
out=$(hb --status) || rc=$?
assert_eq "$rc" 2 'unpaused probe p-live must still make --status exit 2'
assert_line "$out" '^paused p-paused owner=gaming' 'paused probe lacks paused line'
assert_line "$out" '^paused down\.service owner=gaming' 'paused label lacks paused line'
assert_no_line "$out" '^(ok|FAIL) .*p-paused' 'paused probe still reported ok/FAIL'
assert_no_line "$out" '^(ok|FAIL) .*down\.service' 'paused label still reported ok/FAIL'
assert_line "$out" '^FAIL .*p-live' 'probe not in pause= must still FAIL'
assert_line "$out" '^ok .*p-fine' 'unpaused healthy probe must be ok'
assert_line "$out" '^ok .*pause-gaming' 'fresh pause must report ok pause-gaming'
assert_no_line "$out" 'stale' 'fresh pause reported stale'

printf 'p-live false\n' > "$PROBES"
write_pause "$((now - 60))" 12 gaming p-paused down.service p-live
rc=0
out=$(hb --status) || rc=$?
assert_eq "$rc" 0 'everything paused and fresh must exit 0'
assert_line "$out" '^paused p-live owner=gaming' 'second pause= entry not honoured'
assert_no_line "$out" '^FAIL' 'paused-only run printed FAIL'
rm -f "$ERROR_LOG" "$LOG_FILE"
hb
assert_eq "$(notify_count)" 0 'paused checks must not notify'
assert_not_contains "$ERROR_LOG" 'p-live' 'paused probe was run and logged as failing'
assert_not_contains "$ERROR_LOG" 'down.service' 'paused label was checked and logged as a problem'

echo "== stale pause"
reset
printf 'p-paused false\n' > "$PROBES"
write_pause "$((now - 13 * 3600))" 12 gaming p-paused
rc=0
out=$(hb --status) || rc=$?
assert_eq "$rc" 2 'stale pause must make --status exit 2'
assert_line "$out" '^FAIL .*pause-gaming.*stale' 'stale pause must print FAIL pause-gaming stale'
assert_line "$out" '^paused p-paused owner=gaming' 'stale pause must still pause its checks'
hb
assert_contains "$NOTIFY_LOG" 'pause-gaming (stale)' 'stale pause not in notification'
assert_eq "$(notify_count)" 1 'stale pause must notify once'
write_pause "$((now - 11 * 3600))" 12 gaming p-paused
rc=0
out=$(hb --status) || rc=$?
assert_eq "$rc" 0 'pause younger than max_age_hours must be healthy'
assert_line "$out" '^ok .*pause-gaming' 'pause 11h old with 12h limit must be ok'
write_pause "$((now - 3 * 3600))" 2 other p-paused
rc=0
out=$(hb --status) || rc=$?
assert_eq "$rc" 2 'pause uses its own max_age_hours'
assert_line "$out" '^FAIL .*pause-other.*stale' 'owner name must appear in pause-<owner>'

echo 'PASS: launchd-heartbeat probes, job records, status, rotation and pause'
