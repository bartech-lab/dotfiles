#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/launchd-heartbeat-edges.XXXXXX")
trap 'rm -rf "$TEST_ROOT"' EXIT
MOCK_BIN="$TEST_ROOT/bin"
CONF_DIR="$TEST_ROOT/home/.config/launchd-heartbeat"
JOB_DIR="$TEST_ROOT/jobs"
CALLS="$TEST_ROOT/calls.log"

fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$MOCK_BIN"
export HOME="$TEST_ROOT/home" JOB_STATUS_DIR="$JOB_DIR" CALLS
export HEARTBEAT_PAUSE_FILE="$TEST_ROOT/no-pause" HEARTBEAT_MAX_LOG_BYTES=1048576
export PATH="$MOCK_BIN:$PATH"
cat > "$MOCK_BIN/notify-send" <<'SH'
#!/bin/sh
echo "desktop $*" >> "$CALLS"
SH
cat > "$MOCK_BIN/osascript" <<'SH'
#!/bin/sh
echo "desktop $*" >> "$CALLS"
SH
chmod +x "$MOCK_BIN/notify-send" "$MOCK_BIN/osascript"

os() {
    printf '#!/bin/sh\necho %s\n' "$1" > "$MOCK_BIN/uname"
    chmod +x "$MOCK_BIN/uname"
}

reset() {
    rm -rf "$CONF_DIR" "$JOB_DIR" "$CALLS"
    mkdir -p "$CONF_DIR" "$JOB_DIR"
    printf '%s\n' "${@:-# none}" > "$CONF_DIR/monitored-labels.conf"
}

status() {
    local rc=0
    out=$(bash "$SCRIPT_DIR/heartbeat.sh" --status 2>&1) || rc=$?
    status_rc=$rc
}

os Linux
cat > "$MOCK_BIN/systemctl" <<'SH'
#!/bin/sh
exit 1
SH
chmod +x "$MOCK_BIN/systemctl"

reset
printf 'last_failure=1700000000\nreason=boom\n' > "$JOB_DIR/never.status"
status
[[ $status_rc -eq 2 && $out == *"FAIL never failed"*"reason=boom"* ]] || fail "a failure with no success is failed: rc=$status_rc $out"

reset
printf 'max_age_hours=24\n' > "$JOB_DIR/fresh.status"
status
[[ $status_rc -eq 2 && $out == *"FAIL fresh stale"*"never succeeded"* ]] || fail "max_age_hours with no success is stale: rc=$status_rc $out"

reset
printf 'last_success=soon\nmax_age_hours=24\n' > "$JOB_DIR/junk.status"
status
[[ $out == *"FAIL junk stale"*"never succeeded"* ]] || fail "a non-numeric last_success counts as none: $out"

reset
printf 'last_success=%s\nmax_age_hours=24\n' "$(date +%s)" > "$JOB_DIR/ok.status"
status
[[ $status_rc -eq 0 && $out == *"ok ok job last_success="* ]] || fail "a recent success is ok: rc=$status_rc $out"

cat > "$MOCK_BIN/systemctl" <<'SH'
#!/bin/sh
case "$*" in
    *LoadState*) echo loaded ;;
    *ActiveState*) echo inactive ;;
    *Result*) echo exit-code ;;
    *is-active*) echo active ;;
esac
SH
reset demo.service
status
[[ $status_rc -eq 2 && $out == *"FAIL demo.service failed"* ]] || fail "a unit whose last Result is not success is failed: rc=$status_rc $out"

reset
printf 'last_failure=1700000000\n' > "$JOB_DIR/bad.status"
cat > "$TEST_ROOT/ops" <<'SH'
#!/bin/sh
echo "ops $*" >> "$CALLS"
SH
chmod +x "$TEST_ROOT/ops"
OPS_BIN="$TEST_ROOT/ops" bash "$SCRIPT_DIR/heartbeat.sh" >/dev/null 2>&1 || true
grep -q '^ops notify heartbeat Failed or missing: bad (failed)' "$CALLS" || fail "problems go to ops notify: $(cat "$CALLS" 2>/dev/null)"
if grep -q '^desktop' "$CALLS"; then fail "a working ops notify must not also raise a desktop notification"; fi

os Darwin
reset com.example.job
for code in 1 '(never exited)'; do
    printf '#!/bin/sh\nprintf "\\tstate = not running\\n\\truns = 3\\n\\tlast exit code = %s\\n"\n' "$code" > "$MOCK_BIN/launchctl"
    chmod +x "$MOCK_BIN/launchctl"
    status
    if [[ $code == 1 ]]; then
        [[ $status_rc -eq 2 && $out == *"FAIL com.example.job failed"* ]] || fail "macOS: last exit code 1 is failed: rc=$status_rc $out"
    else
        [[ $status_rc -eq 0 && $out == *"ok com.example.job loaded"* ]] || fail "macOS: a job that never exited is loaded: rc=$status_rc $out"
    fi
done

os Linux
cat > "$MOCK_BIN/systemctl" <<'SH'
#!/bin/sh
case "$*" in
    *LoadState*) echo loaded ;;
    *ActiveState*) echo inactive ;;
    *Result*) echo exit-code ;;
esac
SH

reset
rc=0
out=$(bash "$SCRIPT_DIR/heartbeat.sh" --bogus 2>&1 >/dev/null) || rc=$?
[[ $rc -eq 2 && $out == *Usage*heartbeat.sh* ]] || fail "unknown option exits 2 with usage on stderr: rc=$rc $out"
rc=0
out=$(bash "$SCRIPT_DIR/heartbeat.sh" --bogus 2>/dev/null) || rc=$?
[[ $rc -eq 2 && -z $out ]] || fail "unknown option prints nothing on stdout: rc=$rc $out"

for size in 1001 1000; do
    reset
    head -c "$size" /dev/zero | tr '\0' x > "$CONF_DIR/heartbeat.log"
    head -c "$size" /dev/zero | tr '\0' y > "$CONF_DIR/error.log"
    HEARTBEAT_MAX_LOG_BYTES=1000 bash "$SCRIPT_DIR/heartbeat.sh" >/dev/null 2>&1 || true
    if [[ $size -eq 1001 ]]; then
        [[ -f $CONF_DIR/heartbeat.log.1 && $(wc -c < "$CONF_DIR/heartbeat.log.1" | tr -d ' ') -eq 1001 ]] || fail "heartbeat.log one byte over the limit is rotated"
        [[ -f $CONF_DIR/error.log.1 && $(wc -c < "$CONF_DIR/error.log.1" | tr -d ' ') -eq 1001 ]] || fail "error.log one byte over the limit is rotated"
    else
        [[ ! -e $CONF_DIR/heartbeat.log.1 ]] || fail "heartbeat.log exactly at the limit is not rotated"
        [[ ! -e $CONF_DIR/error.log.1 ]] || fail "error.log exactly at the limit is not rotated"
    fi
done

reset
now=$(date +%s)
printf 'last_success=%s\nmax_age_hours=1\n' "$((now - 5400))" > "$JOB_DIR/late.status"
printf 'last_success=%s\nmax_age_hours=1\n' "$((now - 1800))" > "$JOB_DIR/early.status"
status
[[ $status_rc -eq 2 && $out == *"FAIL late stale"* && $out == *"ok early"* && $out != *"FAIL early"* ]] || fail "90 minutes is stale for max_age_hours=1, 30 minutes is ok: rc=$status_rc $out"

reset down.service bonsai
printf 'bonsai-http false\nbonsai-h false\n' > "$CONF_DIR/probes.conf"
printf 'since=%s\nowner=me\nmax_age_hours=12\npause=bonsai-http\n' "$(date +%s)" > "$TEST_ROOT/pause"
rc=0
out=$(HEARTBEAT_PAUSE_FILE="$TEST_ROOT/pause" bash "$SCRIPT_DIR/heartbeat.sh" --status 2>&1) || rc=$?
[[ $rc -eq 2 ]] || fail "unpaused look-alike names keep the exit at 2: rc=$rc $out"
[[ $out == *"paused bonsai-http owner=me"* ]] || fail "bonsai-http is paused: $out"
printf '%s\n' "$out" | grep -Eq '^FAIL bonsai-h ' || fail "bonsai-h is not paused by pause=bonsai-http: $out"
printf '%s\n' "$out" | grep -Eq '^FAIL bonsai ' || fail "label bonsai is not paused by pause=bonsai-http: $out"
printf '%s\n' "$out" | grep -Eq '^(ok|FAIL) bonsai-http' && fail "paused bonsai-http is still reported: $out"
rm -f "$TEST_ROOT/pause"

cat > "$MOCK_BIN/systemctl" <<'SH'
#!/bin/sh
case "$*" in
    *LoadState*) echo not-found ;;
    *ActiveState*) echo active ;;
    *Result*) echo success ;;
    *is-active*) echo active ;;
esac
SH
reset ghost.service
status
[[ $status_rc -eq 2 && $out == *"FAIL ghost.service missing"* ]] || fail "LoadState not-found with ActiveState active is missing: rc=$status_rc $out"

cat > "$TEST_ROOT/ops" <<'SH'
#!/bin/sh
echo "ops $*" >> "$CALLS"
SH
reset
printf 'last_failure=1700000000\n' > "$JOB_DIR/bad.status"
OPS_BIN="$TEST_ROOT/ops" bash "$SCRIPT_DIR/heartbeat.sh" >/dev/null 2>&1 || true
[[ $(grep -c '^ops ' "$CALLS") -eq 1 ]] || fail "one run notifies once: $(cat "$CALLS" 2>/dev/null)"
grep -qxF 'ops notify heartbeat Failed or missing: bad (failed) --priority 4' "$CALLS" || fail "ops notify gets --priority 4: $(cat "$CALLS" 2>/dev/null)"

reset
printf 'last_failure=1700000000\n' > "$JOB_DIR/bad.status"
OPS_BIN="$TEST_ROOT/ops" bash "$SCRIPT_DIR/heartbeat.sh" --status >/dev/null 2>&1 || true
[[ ! -e $CALLS ]] || fail "--status calls neither ops nor the desktop notifier: $(cat "$CALLS")"

reset
printf 'last_failure=1700000000\n' > "$JOB_DIR/bad.status"
printf '#!/bin/sh\necho "ops $*" >> "$CALLS"\nexit 1\n' > "$TEST_ROOT/ops-fail"
chmod +x "$TEST_ROOT/ops-fail"
OPS_BIN="$TEST_ROOT/ops-fail" bash "$SCRIPT_DIR/heartbeat.sh" >/dev/null 2>&1 || true
grep -q '^ops notify' "$CALLS" && grep -q '^desktop' "$CALLS" || fail "a failing ops notify falls back to the desktop notifier: $(cat "$CALLS" 2>/dev/null)"

echo "PASS: launchd-heartbeat edge tests"
