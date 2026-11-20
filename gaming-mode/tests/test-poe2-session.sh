#!/bin/bash
[[ "$(uname -s)" == Linux ]] || { echo SKIP; exit 0; }
# Black-box tests for gaming-mode/poe2-session. Every external command is a PATH stub.
# The tool directory comes from GAMELOG_TOOL_DIR (default: the parent of tests/).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL_DIR="${GAMELOG_TOOL_DIR:-$SCRIPT_DIR}"
LAUNCHER="$TOOL_DIR/poe2-session"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/poe2-session-test.XXXXXX")
BIN="$TEST_ROOT/bin"
T="$TEST_ROOT/work"
FAILS=0

cleanup() {
  if [[ -f "$T/pids" ]]; then
    while read -r p; do kill -KILL "$p" 2>/dev/null; done < "$T/pids"
  fi
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; FAILS=$((FAILS + 1)); }
check_eq() { [[ "$1" == "$2" ]] || fail "$3 (expected '$2', got '$1')"; }

mkdir -p "$BIN" "$T"
export EVENTS="$T/events" PIDS="$T/pids" RELEASE="$T/release" STARTED="$T/started" COUNTER="$T/qcount"
export POE2_SESSION_LOCK="$T/poe2.lock" XDG_RUNTIME_DIR="$T/run"
export POE2_GAMING="$BIN/gaming" POE2_GAMELOG="$BIN/gamelog"
export PREV_MODE=autohide QDBUS_MODE=ok GAMING_MODE=ok
export PATH="$BIN:$PATH"
mkdir -p "$XDG_RUNTIME_DIR"

cat > "$BIN/qdbus6" <<'STUB'
#!/bin/bash
args="$*"
echo "qdbus6 ${args//$'\n'/ }" >> "$EVENTS"
n=$(cat "$COUNTER" 2>/dev/null || echo 0)
echo $((n + 1)) > "$COUNTER"
case "$QDBUS_MODE" in
  fail) exit 1 ;;
  empty) exit 0 ;;
esac
if [[ "$n" == 0 ]]; then echo "$PREV_MODE"; else echo dodgewindows; fi
STUB
cat > "$BIN/gaming" <<'STUB'
#!/bin/bash
echo "gaming $*" >> "$EVENTS"
echo "${GAMELOG_REPORT_COPY-unset}" > "$EVENTS.copy"
echo $$ >> "$PIDS"
case "$GAMING_MODE" in
  fail) exit 3 ;;
  hold) touch "$STARTED"; while [[ ! -e "$RELEASE" ]]; do sleep 0.1; done ;;
  term) sleep 3 & echo $! >> "$PIDS"; touch "$STARTED"; wait ;;
  bg) sleep 30 </dev/null >/dev/null 2>&1 & echo $! >> "$PIDS" ;;
esac
exit 0
STUB
cat > "$BIN/gamelog" <<'STUB'
#!/bin/bash
exit 0
STUB
printf '#!/bin/bash\nexit 0\n' > "$BIN/ops"
printf '#!/bin/bash\necho "notify-send $*" >> "$EVENTS"\n' > "$BIN/notify-send"
chmod +x "$BIN"/*

# reset_state: new lock file, empty event log, default stub modes.
reset_state() {
  rm -f "$EVENTS" "$COUNTER" "$RELEASE" "$STARTED" "$POE2_SESSION_LOCK"
  : > "$EVENTS"
  PREV_MODE=autohide QDBUS_MODE=ok GAMING_MODE=ok
  export PREV_MODE QDBUS_MODE GAMING_MODE
}

# summary: one token per event: SWITCH, RESTORE:<mode>, GAMING:<args>, QDBUS?.
summary() {
  local prev="$1" line out=""
  while IFS= read -r line; do
    case "$line" in
      qdbus6*dodgewindows*) out+="SWITCH " ;;
      qdbus6*"$prev"*) out+="RESTORE:$prev " ;;
      qdbus6*) out+="QDBUS? " ;;
      gaming*) out+="GAMING:${line#gaming } " ;;
    esac
  done < "$EVENTS"
  echo "${out% }"
}

wait_for_file() { # file, tries of 0.1 s
  local i
  for ((i = 0; i < $2; i++)); do [[ -e "$1" ]] && return 0; sleep 0.1; done
  return 1
}

EXPECT_OK() { echo "SWITCH GAMING:run -- $POE2_GAMELOG record --launch RESTORE:$1"; }

# --- 1. normal run, two different previous modes
for prev in autohide none; do
  reset_state
  PREV_MODE=$prev; export PREV_MODE
  timeout 20 "$LAUNCHER" >/dev/null 2>&1
  rc=$?
  check_eq "$rc" 0 "normal run exit code ($prev)"
  check_eq "$(summary "$prev")" "$(EXPECT_OK "$prev")" "normal run order ($prev)"
  first=$(head -n 1 "$EVENTS")
  [[ "$first" == "qdbus6 org.kde.plasmashell /PlasmaShell evaluateScript "* ]] || fail "qdbus6 arguments: $first"
  last=$(tail -n 1 "$EVENTS")
  [[ "$last" != *dodgewindows* ]] || fail "restore call still targets dodgewindows ($prev)"
done

# --- 2. gaming exits non-zero: panel still restored
reset_state
GAMING_MODE=fail; export GAMING_MODE
timeout 20 "$LAUNCHER" >/dev/null 2>&1
check_eq "$(summary autohide)" "$(EXPECT_OK autohide)" "restore after failing gaming"

# --- 3. SIGTERM while gaming runs: panel restored once the child returns
reset_state
GAMING_MODE=term; export GAMING_MODE
"$LAUNCHER" >/dev/null 2>&1 &
lp=$!
if wait_for_file "$STARTED" 50; then
  kill -TERM "$lp" 2>/dev/null
  for ((i = 0; i < 80; i++)); do kill -0 "$lp" 2>/dev/null || break; sleep 0.1; done
  if kill -0 "$lp" 2>/dev/null; then fail "launcher still alive 8 s after SIGTERM"; kill -KILL "$lp" 2>/dev/null; fi
  wait "$lp" 2>/dev/null
  check_eq "$(summary autohide)" "$(EXPECT_OK autohide)" "restore after SIGTERM"
else
  fail "gaming stub never started in SIGTERM test"
  kill -KILL "$lp" 2>/dev/null
fi

# --- 4. second launch while the first runs past the wait; 5. lock released afterwards
reset_state
GAMING_MODE=hold; export GAMING_MODE
"$LAUNCHER" >/dev/null 2>&1 &
lp=$!
if wait_for_file "$STARTED" 50; then
  t0=$SECONDS
  POE2_SESSION_WAIT=1 timeout 10 "$LAUNCHER" >/dev/null 2>&1
  rc=$?
  check_eq "$rc" 0 "second launch exit code"
  (( SECONDS - t0 <= 3 )) || fail "second launch took $((SECONDS - t0)) s"
  check_eq "$(grep -c '^gaming' "$EVENTS")" 1 "second launch must not start gaming"
  check_eq "$(grep -c '^qdbus6' "$EVENTS")" 1 "second launch must not touch the panel"
  grep -qi '^notify-send.*already running' "$EVENTS" || fail "second launch gave no 'already running' notice"
else
  fail "first launcher never reached gaming in lock test"
fi
touch "$RELEASE"
wait "$lp" 2>/dev/null
check_eq "$(summary autohide)" "$(EXPECT_OK autohide)" "first run unaffected by second launch"
GAMING_MODE=ok; export GAMING_MODE
: > "$EVENTS"; rm -f "$COUNTER"
timeout 20 "$LAUNCHER" >/dev/null 2>&1
check_eq "$(summary autohide)" "$(EXPECT_OK autohide)" "run after the lock was released"

# --- 4b. a click while the last session is still closing waits for it, then starts the game
reset_state
GAMING_MODE=hold; export GAMING_MODE
"$LAUNCHER" >/dev/null 2>&1 &
lp=$!
if wait_for_file "$STARTED" 50; then
  rm -f "$STARTED"
  GAMING_MODE=ok POE2_SESSION_WAIT=10 timeout 20 "$LAUNCHER" >/dev/null 2>&1 &
  sp=$!
  sleep 1
  touch "$RELEASE"
  wait "$lp" 2>/dev/null
  wait "$sp" 2>/dev/null
  check_eq "$(grep -c '^gaming' "$EVENTS")" 2 "click during shutdown must start the game once the old session ends"
  ! grep -q '^notify-send' "$EVENTS" || fail "click during shutdown showed a notice"
else
  fail "first launcher never reached gaming in wait test"
  touch "$RELEASE"
fi
wait "$lp" 2>/dev/null

# --- 6. lock not inherited by a background child of gaming
reset_state
GAMING_MODE="bg"; export GAMING_MODE
timeout 20 "$LAUNCHER" >/dev/null 2>&1
: > "$EVENTS"; rm -f "$COUNTER"
GAMING_MODE=ok; export GAMING_MODE
out=$(timeout 10 "$LAUNCHER" 2>&1)
check_eq "$(summary autohide)" "$(EXPECT_OK autohide)" "launch while an orphan sleep from the last run lives"
[[ "$out" != *already* ]] || fail "reported already running because of an inherited lock: $out"

# --- 7. qdbus6 failing or silent
for mode in fail empty; do
  reset_state
  QDBUS_MODE=$mode; export QDBUS_MODE
  timeout 20 "$LAUNCHER" >/dev/null 2>&1
  check_eq "$(grep -c '^gaming' "$EVENTS")" 1 "gaming still runs with qdbus6 $mode"
  bad=$(grep '^qdbus6' "$EVENTS" | grep -vc dodgewindows)
  check_eq "$bad" 0 "no restore call with an unknown mode (qdbus6 $mode)"
done

# --- the recorder is told where to put a copy of the latest report
check_eq "$(cat "$EVENTS.copy")" "$HOME/Downloads/poe2-session-report.html" "report copy path handed to the recorder"

if (( FAILS > 0 )); then echo "$FAILS check(s) failed" >&2; exit 1; fi
echo "poe2-session: all checks passed"
