#!/bin/bash
# Black-box tests for gaming-mode/gaming. Every external command is a PATH stub.

set -euo pipefail

[[ "$(uname -s)" == Linux ]] || { echo "SKIP: gaming is Linux-only (needs flock and systemd)"; exit 0; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GAMING_BIN="${GAMING_BIN:-$SCRIPT_DIR/gaming}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/gaming-mode-test.XXXXXX")
MOCK_BIN="$TEST_ROOT/bin"
T="$TEST_ROOT/work"
EVENTS="$T/events.log"
ACTIVE="$T/active"
FAIL_STOP="$T/fail-stop"
FAIL_START="$T/fail-start"
NOSUDO="$T/nosudo"
NOTIFY_LOG="$T/notify.log"
SETSID_LOG="$T/setsid.log"
STATE_DIR="$T/state"
PAUSE_FILE="$T/pause"
APPS_FILE="$T/apps"

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "$3 (expected '$2', got '$1')"; }
assert_has() { printf '%s\n' "$1" | grep -F -- "$2" >/dev/null || fail "$3"; }
assert_lacks() { if printf '%s\n' "$1" | grep -F -- "$2" >/dev/null; then fail "$3"; fi; }
assert_file_has() { grep -E -- "$2" "$1" >/dev/null 2>&1 || fail "$3"; }
assert_file_lacks() { if [[ -f "$1" ]] && grep -E -- "$2" "$1" >/dev/null; then fail "$3"; fi; }
assert_nonzero() { [[ "$1" != 0 ]] || fail "$2 (exit code was 0)"; }

mkdir -p "$MOCK_BIN"
export EVENTS ACTIVE FAIL_STOP FAIL_START NOSUDO NOTIFY_LOG SETSID_LOG MOCK_BIN HEARTBEAT_PAUSE_FILE="$PAUSE_FILE"

cat > "$MOCK_BIN/systemctl" <<'STUB'
#!/bin/bash
echo "systemctl $*" >> "$EVENTS"
args=("$@")
[[ "${args[0]:-}" == --user ]] && args=("${args[@]:1}")
verb="${args[0]:-}"
case "$verb" in
    is-active)
        unit="${args[*]: -1}"
        grep -qxF -- "$unit" "$ACTIVE" 2>/dev/null
        ;;
    stop)
        unit="${args[1]:-}"
        echo "stop-saw-pause=$([[ -f "$HEARTBEAT_PAUSE_FILE" ]] && echo y || echo n)" >> "$EVENTS"
        if grep -qxF -- "$unit" "$FAIL_STOP" 2>/dev/null; then exit 1; fi
        if [[ -f "$ACTIVE" ]]; then grep -vxF -- "$unit" "$ACTIVE" > "$ACTIVE.new" || true; mv "$ACTIVE.new" "$ACTIVE"; fi
        ;;
    start)
        unit="${args[1]:-}"
        if grep -qxF -- "$unit" "$FAIL_START" 2>/dev/null; then exit 1; fi
        echo "$unit" >> "$ACTIVE"
        ;;
    *) exit 0 ;;
esac
STUB
cat > "$MOCK_BIN/sudo" <<'STUB'
#!/bin/bash
echo "sudo $*" >> "$EVENTS"
[[ -f "$NOSUDO" ]] && exit 1
args=()
for a in "$@"; do
    [[ "$a" == -n ]] && continue
    [[ "$a" == /usr/bin/systemctl ]] && a="$MOCK_BIN/systemctl"
    args+=("$a")
done
exec "${args[@]}"
STUB
cat > "$MOCK_BIN/nvidia-smi" <<'STUB'
#!/bin/bash
echo 14336
STUB
cat > "$MOCK_BIN/notify-send" <<'STUB'
#!/bin/bash
echo "$*" >> "$NOTIFY_LOG"
STUB
cat > "$MOCK_BIN/setsid" <<'STUB'
#!/bin/bash
echo "$*" >> "$SETSID_LOG"
if { : >&9; } 2>/dev/null; then echo "fd9-open" >> "$SETSID_LOG"; fi
STUB
chmod +x "$MOCK_BIN"/*

export PATH="$MOCK_BIN:$PATH"
export GAMING_STATE_DIR="$STATE_DIR" GAMING_APPS_FILE="$APPS_FILE" GAMING_NO_WAIT=1
export XDG_RUNTIME_DIR="$T/run"

USER_UNITS=(bonsai.service)
SYS_UNITS=(docker.socket docker.service)
TIMERS=(system-update.timer toolsmith.timer logbook-sync.timer)
ALL_UNITS=("${USER_UNITS[@]}" "${SYS_UNITS[@]}" "${TIMERS[@]}")

reset() {
    rm -rf "$T"
    mkdir -p "$T/run" "$STATE_DIR"
    printf '%s\n' bonsai-cc-proxy.service "${ALL_UNITS[@]}" > "$ACTIVE"
    : > "$EVENTS"
    : > "$APPS_FILE"
}

# run_gaming <args...>: sets out and rc
out="" rc=0
run_gaming() {
    rc=0
    out=$(bash "$GAMING_BIN" "$@" 2>&1) || rc=$?
}
clear_events() { : > "$EVENTS"; }

# Units of start/stop calls in call order, restricted to the known units.
calls() {
    local verb="$1" u
    { grep -E "^systemctl (--user )?$verb " "$EVENTS" || true; } | awk '{print $NF}' | while read -r u; do
        for k in "${ALL_UNITS[@]}"; do if [[ "$u" == "$k" ]]; then echo "$u"; fi; done
    done
}
sorted() { sort | tr '\n' ' '; }
index_of() { # index_of <unit> in a newline list on stdin
    awk -v u="$1" '$0==u{print NR; exit}'
}

echo "== on: stops active units, records state, pause file first"
reset
before=$(date +%s)
run_gaming on
after=$(date +%s)
assert_eq "$rc" 0 'on must exit 0 when every stop succeeds'
assert_has "$out" 'Game mode on' 'on did not print "Game mode on"'
printf '%s\n' "$out" | grep -E 'VRAM free: 14(\.0)? GB' >/dev/null || fail 'on did not print VRAM free 14 GB from nvidia-smi 14336 MiB'
[[ -s "$NOTIFY_LOG" ]] || fail 'on did not call notify-send'
for u in "${USER_UNITS[@]}" "${TIMERS[@]}"; do
    assert_file_has "$EVENTS" "^systemctl --user stop $u\$" "$u not stopped via systemctl --user stop"
done
for u in "${SYS_UNITS[@]}"; do
    assert_file_has "$EVENTS" "^sudo -n /usr/bin/systemctl stop $u\$" "$u not stopped via sudo -n /usr/bin/systemctl stop"
    assert_file_lacks "$EVENTS" "^systemctl --user stop $u\$" "system unit $u stopped with --user"
done
assert_file_lacks "$EVENTS" '^sudo .*(bonsai|timer)' 'user unit stopped through sudo'
assert_file_lacks "$EVENTS" 'stop bonsai-cc-proxy' 'on stopped the proxy, so clients get a refused port instead of the game mode 503'
assert_eq "$(cat "$ACTIVE")" bonsai-cc-proxy.service 'after on only the proxy may stay active'
assert_file_lacks "$EVENTS" 'stop-saw-pause=n' 'a unit was stopped before the pause file existed'
assert_file_has "$EVENTS" 'stop-saw-pause=y' 'no stop observed (pause ordering untestable)'
[[ -f "$STATE_DIR/state" ]] || fail 'state file missing after on'
[[ ! -s "$SETSID_LOG" ]] || fail 'setsid called with GAMING_NO_WAIT=1 during on'

echo "== on: pause file contents"
[[ -f "$PAUSE_FILE" ]] || fail 'pause file missing after on'
since=$(grep -m1 '^since=' "$PAUSE_FILE" | cut -d= -f2)
[[ "$since" =~ ^[0-9]+$ ]] || fail "since is not an epoch: '$since'"
(( since >= before && since <= after )) || fail 'since is not the time of on'
assert_file_has "$PAUSE_FILE" '^owner=gaming$' 'pause file lacks owner=gaming'
assert_file_has "$PAUSE_FILE" '^max_age_hours=12$' 'pause file lacks max_age_hours=12'
for n in bonsai.service bonsai-cc-proxy.service bonsai-http bonsai-cc-proxy bonsai-no-crash system-update.service toolsmith.service logbook-sync.service; do
    assert_file_has "$PAUSE_FILE" "^pause=$n\$" "pause file lacks pause=$n"
done
assert_eq "$(grep -vE '^(since|owner|max_age_hours|pause)=' "$PAUSE_FILE" | grep -c . || true)" 0 'pause file has lines outside the key=value format'

echo "== off: reverse order, state and pause removed"
stops=$(calls stop)
assert_eq "$(printf '%s\n' "$stops" | grep -c .)" 6 'expected one stop per active unit'
clear_events
run_gaming off
assert_eq "$rc" 0 'off must exit 0'
assert_has "$out" 'Game mode off' 'off did not print "Game mode off"'
starts=$(calls start)
assert_eq "$(printf '%s\n' "$starts" | tr '\n' ' ')" "$(printf '%s\n' "$stops" | tac | tr '\n' ' ')" 'start order is not the reverse of stop order'
bi=$(printf '%s\n' "$starts" | index_of bonsai.service)
for t in "${TIMERS[@]}"; do
    ti=$(printf '%s\n' "$starts" | index_of "$t")
    (( ti < bi )) || fail "$t must start before bonsai.service"
done
for u in "${SYS_UNITS[@]}"; do
    assert_file_has "$EVENTS" "^sudo -n /usr/bin/systemctl start $u\$" "$u not started via sudo -n"
done
for u in "${USER_UNITS[@]}" "${TIMERS[@]}"; do
    assert_file_has "$EVENTS" "^systemctl --user start $u\$" "$u not started via systemctl --user start"
done
[[ ! -e "$STATE_DIR/state" ]] || fail 'state file survived off'
[[ ! -e "$PAUSE_FILE" ]] || fail 'pause file survived off'
[[ ! -s "$SETSID_LOG" ]] || fail 'setsid called with GAMING_NO_WAIT=1 during off'
assert_eq "$(sort "$ACTIVE" | tr '\n' ' ')" "$(printf '%s\n' bonsai-cc-proxy.service "${ALL_UNITS[@]}" | sort | tr '\n' ' ')" 'off did not restore the active set'

echo "== on twice keeps the first snapshot"
reset
run_gaming on
clear_events
snap=$(cksum < "$STATE_DIR/state")
run_gaming on
assert_eq "$rc" 0 'second on must exit 0'
assert_eq "$(calls stop | grep -c . || true)" 0 'second on made stop calls'
assert_eq "$(cksum < "$STATE_DIR/state")" "$snap" 'second on overwrote state'
assert_has "$out" 'Game mode on' 'second on did not print status'
run_gaming off
assert_eq "$(calls start | sorted)" "$(printf '%s\n' "${ALL_UNITS[@]}" | sorted)" 'off after double on lost the first snapshot'

echo "== units inactive before on are never started"
reset
printf '%s\n' bonsai.service docker.socket system-update.timer logbook-sync.timer > "$ACTIVE"
run_gaming on
assert_eq "$rc" 0 'on with partly inactive units must exit 0'
run_gaming off
assert_eq "$rc" 0 'off must exit 0'
assert_eq "$(calls start | sorted)" "$(printf '%s\n' bonsai.service docker.socket system-update.timer logbook-sync.timer | sorted)" 'off started a different set than was active'
assert_file_lacks "$EVENTS" 'start docker\.service' 'inactive docker.service was started'
assert_file_lacks "$EVENTS" 'start toolsmith\.timer' 'inactive toolsmith.timer was started'

echo "== off without on"
reset
run_gaming off
assert_eq "$rc" 0 'off without on must exit 0'
assert_has "$out" 'already off' 'off without on did not say already off'
assert_eq "$(calls start | grep -c . || true)" 0 'off without on started units'
assert_file_lacks "$EVENTS" ' start ' 'off without on called a start'
[[ ! -e "$STATE_DIR/state" ]] || fail 'off without on created state'

echo "== stop failure of the second unit"
reset
echo bonsai.service > "$FAIL_STOP"
run_gaming on
assert_nonzero "$rc" 'stop failure must give a non-zero exit'
line=$(printf '%s\n' "$out" | grep -F 'Not stopped:' || true)
[[ -n "$line" ]] || fail 'no "Not stopped:" in output'
assert_has "$line" 'bonsai.service' 'failed unit not named after Not stopped:'
assert_lacks "$line" 'docker' 'Not stopped lists a unit that stopped'
assert_lacks "$line" 'timer' 'Not stopped lists a timer that stopped'
assert_eq "$(calls stop | sorted)" "$(printf '%s\n' "${ALL_UNITS[@]}" | sorted)" 'a failure stopped the run early'
assert_eq "$(sort "$ACTIVE" | tr '\n' ' ')" 'bonsai-cc-proxy.service bonsai.service ' 'only the proxy and the failing unit may remain active'

echo "== sudo has no rule"
reset
: > "$NOSUDO"
run_gaming on
assert_nonzero "$rc" 'sudo failure must give a non-zero exit'
line=$(printf '%s\n' "$out" | grep -F 'Not stopped:' || true)
[[ -n "$line" ]] || fail 'no "Not stopped:" when sudo fails'
assert_has "$line" 'docker.socket' 'docker.socket not named'
assert_has "$line" 'docker.service' 'docker.service not named'
assert_lacks "$line" 'bonsai' 'user unit reported though stopped without sudo'
assert_lacks "$line" 'timer' 'timer reported though stopped without sudo'
assert_eq "$(sort "$ACTIVE" | tr '\n' ' ')" 'bonsai-cc-proxy.service docker.service docker.socket ' 'user units/timers must stop even without sudo'

echo "== start failure on off"
reset
run_gaming on
echo toolsmith.timer > "$FAIL_START"
clear_events
run_gaming off
assert_nonzero "$rc" 'start failure must give a non-zero exit'
line=$(printf '%s\n' "$out" | grep -F 'Not started:' || true)
[[ -n "$line" ]] || fail 'no "Not started:" in output'
assert_has "$line" 'toolsmith.timer' 'failed unit not named after Not started:'
assert_lacks "$line" 'bonsai' 'Not started lists a unit that started'
assert_eq "$(calls start | sorted)" "$(printf '%s\n' "${ALL_UNITS[@]}" | sorted)" 'start failure stopped the loop early'

echo "== app patterns"
reset
printf '# comment line\n\nsteam_app_*.scope\n  \nlutris-*\n' > "$APPS_FILE"
run_gaming on
assert_eq "$rc" 0 'on with app patterns must exit 0'
assert_file_has "$EVENTS" '^systemctl --user stop steam_app_\*\.scope$' 'pattern steam_app_* not passed literally to stop'
assert_file_has "$EVENTS" '^systemctl --user stop lutris-\*$' 'pattern lutris-* not stopped'
assert_file_lacks "$EVENTS" 'comment' 'comment line was treated as a pattern'
clear_events
run_gaming off
assert_file_lacks "$EVENTS" 'start (steam_app|lutris)' 'app pattern was started on off'
assert_file_lacks "$EVENTS" 'systemctl.* (steam_app|lutris)' 'app pattern touched on off'

echo "== status and toggle"
reset
run_gaming status
assert_eq "$rc" 0 'status exit code'
assert_has "$out" 'Game mode off' 'status when off'
run_gaming
assert_has "$out" 'Game mode on' 'bare gaming did not turn on'
[[ -f "$STATE_DIR/state" ]] || fail 'bare gaming did not create state'
run_gaming status
assert_has "$out" 'Game mode on since' 'status when on'
assert_has "$out" 'bonsai.service' 'status does not list stopped units'
assert_has "$out" 'docker.socket' 'status does not list stopped system units'
run_gaming
assert_has "$out" 'Game mode off' 'bare gaming did not turn off'
[[ ! -e "$STATE_DIR/state" ]] || fail 'bare gaming off left state'

echo "== run"
reset
rc=0
bash "$GAMING_BIN" run -- sh -c 'test -f "$GAMING_STATE_DIR/state" && test -f "$HEARTBEAT_PAUSE_FILE" && touch "$GAMING_STATE_DIR/../ran"; exit 0' >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 0 'run -- cmd must propagate exit 0'
[[ -f "$T/ran" ]] || fail 'command did not run with game mode on'
[[ ! -e "$STATE_DIR/state" ]] || fail 'run left game mode on'
assert_eq "$(calls start | sorted)" "$(printf '%s\n' "${ALL_UNITS[@]}" | sorted)" 'run did not start units back'
reset
run_gaming run -- false
assert_eq "$rc" 1 'run -- false must exit 1'
[[ ! -e "$STATE_DIR/state" ]] || fail 'run -- false left game mode on'
[[ ! -e "$PAUSE_FILE" ]] || fail 'run -- false left the pause file'
assert_eq "$(calls start | sorted)" "$(printf '%s\n' "${ALL_UNITS[@]}" | sorted)" 'off did not run after failing command'
reset
run_gaming run -- sh -c 'exit 7'
assert_eq "$rc" 7 'run did not propagate exit code 7'
[[ ! -e "$STATE_DIR/state" ]] || fail 'run -- exit 7 left game mode on'

echo "== run while already on"
reset
run_gaming on
clear_events
run_gaming run -- sh -c 'exit 3'
assert_eq "$rc" 3 'run while on did not propagate exit 3'
[[ -f "$STATE_DIR/state" ]] || fail 'run turned off game mode that was already on'
assert_eq "$(calls start | grep -c . || true)" 0 'run while on started units'
assert_eq "$(calls stop | grep -c . || true)" 0 'run while on stopped units again'
run_gaming off
assert_eq "$(calls start | sorted)" "$(printf '%s\n' "${ALL_UNITS[@]}" | sorted)" 'off after run-while-on lost the snapshot'

echo "== off: Bonsai health wait reports success and failure"
cat > "$MOCK_BIN/curl" <<'STUB'
#!/bin/bash
[[ ! -f "$CURL_FAIL" ]]
STUB
printf '#!/bin/bash\n' > "$MOCK_BIN/sleep"
chmod +x "$MOCK_BIN/curl" "$MOCK_BIN/sleep"
export CURL_FAIL="$T/curl-fail"
reset; : > "$NOTIFY_LOG"
run_gaming _wait-bonsai
assert_eq "$rc" 0 'health wait failed while /health answered'
assert_has "$out" 'Bonsai is back' 'health wait did not report Bonsai back'
touch "$CURL_FAIL"
GAMING_HEALTH_WAIT=1 run_gaming _wait-bonsai
assert_nonzero "$rc" 'health wait succeeded while /health never answered'
assert_has "$out" 'Bonsai did not answer' 'health wait did not report the failure'
assert_file_has "$NOTIFY_LOG" 'Bonsai did not answer' 'failure was not sent as a notification'
rm -f "$MOCK_BIN/curl" "$MOCK_BIN/sleep"

echo "== the background Bonsai wait does not hold the command lock"
reset; : > "$SETSID_LOG"
run_gaming on
GAMING_NO_WAIT=0 run_gaming off
assert_file_has "$SETSID_LOG" '_wait-bonsai' 'off did not start the Bonsai wait'
assert_file_lacks "$SETSID_LOG" 'fd9-open' 'the Bonsai wait inherited the lock on fd 9, so the next gaming on blocks for up to the health wait'

echo "== an inactive user service is neither recorded nor restarted"
reset
grep -vxF bonsai.service "$ACTIVE" > "$ACTIVE.new"; mv "$ACTIVE.new" "$ACTIVE"
run_gaming on
assert_file_lacks "$STATE_DIR/state" 'bonsai\.service' 'an inactive user service was recorded as stopped'
clear_events
run_gaming off
assert_lacks "$(calls start)" 'bonsai.service' 'off started a user service that was not running before on'

echo "== usage errors"
reset
run_gaming run
assert_eq "$rc" 2 'run without a command must exit 2'
assert_lacks "$(calls stop)" 'bonsai.service' 'run without a command must not stop anything'
run_gaming bogus
assert_eq "$rc" 2 'an unknown subcommand must exit 2'

echo 'PASS: gaming on/off/status/toggle/run, failures, pause file and app patterns'
