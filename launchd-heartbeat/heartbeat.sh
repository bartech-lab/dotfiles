#!/bin/bash

# Service Heartbeat Script
# Writes lightweight status snapshots every hour

set -u

usage() {
    cat <<'EOF'
Usage: heartbeat.sh [--help] [--status]

Check configured background services, probes and job records, and log their
current status. A changed set of problems raises one desktop notification.

  --status  print one line per check and exit 2 when any check has a problem;
            never notifies
EOF
}

STATUS_MODE=0
case "${1:-}" in
    '') ;;
    --status) STATUS_MODE=1 ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        printf 'Error: unknown option: %s\n' "$1" >&2
        usage >&2
        exit 2
        ;;
esac

CONFIG_DIR="$HOME/.config/launchd-heartbeat"
LABELS_FILE="$CONFIG_DIR/monitored-labels.conf"
PROBES_FILE="$CONFIG_DIR/probes.conf"
JOBS_DIR="${JOB_STATUS_DIR:-$HOME/.local/state/jobs}"
LOG_FILE="$CONFIG_DIR/heartbeat.log"
ERROR_LOG="$CONFIG_DIR/error.log"
PROBE_TIMEOUT="${HEARTBEAT_PROBE_TIMEOUT:-20}"
MAX_LOG_BYTES="${HEARTBEAT_MAX_LOG_BYTES:-1048576}"
PAUSE_FILE="${HEARTBEAT_PAUSE_FILE:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/heartbeat-pause}"
BOOT_GRACE="${HEARTBEAT_BOOT_GRACE:-300}"
UPTIME_FILE="${HEARTBEAT_UPTIME_FILE:-/proc/uptime}"

if ! mkdir -p "$CONFIG_DIR"; then
    printf 'Error: unable to create log directory: %s\n' "$CONFIG_DIR" >&2
    exit 1
fi

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    echo "$(timestamp): $1" >> "$LOG_FILE"
}

log_error() {
    echo "$(timestamp): $1" >> "$ERROR_LOG"
}

rotate_log() {
    local file="$1" size
    [[ -f "$file" ]] || return 0
    size=$(wc -c < "$file" 2>/dev/null | tr -d ' ')
    [[ -n "$size" ]] || return 0
    if (( size > MAX_LOG_BYTES )); then
        mv -f "$file" "$file.1"
    fi
}

run_probe() {
    local command="$1" pid watcher rc
    bash -c "$command" >/dev/null 2>&1 </dev/null &
    pid=$!
    ( sleep "$PROBE_TIMEOUT"; pkill -9 -P "$pid"; kill -9 "$pid" ) >/dev/null 2>&1 &
    watcher=$!
    wait "$pid" 2>/dev/null
    rc=$?
    pkill -P "$watcher" >/dev/null 2>&1
    kill "$watcher" >/dev/null 2>&1
    wait "$watcher" 2>/dev/null
    return "$rc"
}

# Prints "failed <reason>", "stale <age>" or "ok" for one job record.
check_job_record() {
    local file="$1" key value now
    local last_success='' last_failure='' reason='' max_age_hours=''
    while IFS='=' read -r key value; do
        case "$key" in
            last_success) last_success="$value" ;;
            last_failure) last_failure="$value" ;;
            reason) reason="$value" ;;
            max_age_hours) max_age_hours="$value" ;;
        esac
    done < "$file"
    [[ "$last_success" =~ ^[0-9]+$ ]] || last_success=''
    [[ "$last_failure" =~ ^[0-9]+$ ]] || last_failure=''
    [[ "$max_age_hours" =~ ^[0-9]+$ ]] || max_age_hours=''

    if [[ -n "$last_failure" ]] && { [[ -z "$last_success" ]] || (( last_failure > last_success )); }; then
        echo "failed reason=${reason:-unknown}"
        return
    fi
    if [[ -n "$max_age_hours" ]]; then
        now=$(date +%s)
        if [[ -z "$last_success" ]]; then
            echo "stale never succeeded, max_age_hours=$max_age_hours"
            return
        fi
        if (( now - last_success > max_age_hours * 3600 )); then
            echo "stale last_success_age_hours=$(( (now - last_success) / 3600 )) max_age_hours=$max_age_hours"
            return
        fi
    fi
    echo "ok last_success=${last_success:-none}"
}

problem_labels=""
problem_count=0

# A pause file (written by `gaming on`) names checks to skip while their
# service is stopped on purpose. A pause older than max_age_hours is a problem.
paused_names=" "
pause_since=""
pause_owner="unknown"
pause_max_age=""
if [[ -f "$PAUSE_FILE" ]]; then
    while IFS='=' read -r key value; do
        case "$key" in
            since) pause_since="$value" ;;
            owner) pause_owner="$value" ;;
            max_age_hours) pause_max_age="$value" ;;
            pause) paused_names+="$value " ;;
        esac
    done < "$PAUSE_FILE"
fi

is_paused() {
    [[ "$paused_names" == *" $1 "* ]]
}

record_paused() {
    log_info "Label=$1 status=paused owner=$pause_owner"
    (( STATUS_MODE )) && printf 'paused %s owner=%s\n' "$1" "$pause_owner"
    return 0
}

record_ok() {
    local name="$1" detail="$2"
    log_info "Label=$name status=ok $detail"
    (( STATUS_MODE )) && printf 'ok %s %s\n' "$name" "$detail"
    return 0
}

record_problem() {
    local name="$1" status="$2" detail="$3"
    log_error "Label=$name status=$status $detail"
    (( STATUS_MODE )) && printf 'FAIL %s %s %s\n' "$name" "$status" "$detail"
    problem_labels="${problem_labels}${problem_labels:+, }$name ($status)"
    problem_count=$((problem_count + 1))
    return 0
}

# Platform-aware service check
if [[ "$(uname -s)" == Darwin ]]; then
    check_service() {
        local info exit_code
        if ! info=$(launchctl print "gui/$(id -u)/$1" 2>/dev/null); then
            echo "missing"
            return
        fi
        exit_code=$(sed -n 's/^[[:space:]]*last exit code = //p' <<< "$info" | head -n 1)
        if [[ -n "$exit_code" && "$exit_code" != "0" && "$exit_code" != "(never exited)" ]]; then
            echo "failed"
            return
        fi
        echo "loaded"
    }
    notify() {
        osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
    }
    get_service_details() {
        local info
        info=$(launchctl print "gui/$(id -u)/$1" 2>/dev/null)
        local state="unknown" runs="unknown" last_exit="unknown"
        while IFS= read -r line; do
            case "$line" in
                *"last exit code = "*) last_exit="${line##*last exit code = }" ;;
                *"state = "*) [[ $state == unknown ]] && state="${line##*state = }" ;;
                *"runs = "*)  runs="${line##*runs = }" ;;
            esac
        done <<< "$info"
        echo "state=$state runs=$runs last_exit=$last_exit"
    }
else
    check_service() {
        local service="$1" timer_name="${1%.service}.timer"
        local load_state active_state result timer_state

        load_state=$(systemctl --user show "$service" --property=LoadState --value 2>/dev/null || true)
        active_state=$(systemctl --user show "$service" --property=ActiveState --value 2>/dev/null || true)
        result=$(systemctl --user show "$service" --property=Result --value 2>/dev/null || true)

        if [[ -z "$load_state" || "$load_state" == "not-found" ]]; then
            echo "missing"
            return
        fi

        if [[ "$active_state" == "failed" || ( -n "$result" && "$result" != "success" ) ]]; then
            echo "failed"
            return
        fi

        if [[ "$active_state" == "active" ]]; then
            echo "active"
            return
        fi

        timer_state=$(systemctl --user is-active "$timer_name" 2>/dev/null || true)
        if [[ "$timer_state" == "active" && "$result" == "success" ]]; then
            echo "active"
            return
        fi

        echo "missing"
    }
    notify() {
        notify-send "$1" "$2" >/dev/null 2>&1 || true
    }
    get_service_details() {
        local service="$1" timer_name="${1%.service}.timer"
        local load_state active_state result timer_state

        load_state=$(systemctl --user show "$service" --property=LoadState --value 2>/dev/null || true)
        active_state=$(systemctl --user show "$service" --property=ActiveState --value 2>/dev/null || true)
        result=$(systemctl --user show "$service" --property=Result --value 2>/dev/null || true)
        timer_state=$(systemctl --user is-active "$timer_name" 2>/dev/null || true)

        if [[ -z "$load_state" || "$load_state" == "not-found" ]]; then
            active_state="unknown"
            result="unknown"
        fi

        [[ -z "$active_state" ]] && active_state="unknown"
        [[ -z "$result" ]] && result="unknown"
        [[ -z "$timer_state" ]] && timer_state="unknown"
        echo "state=$active_state result=$result timer=$timer_state"
    }
fi

if [[ ! -f "$LABELS_FILE" ]]; then
    log_error "Labels file not found at $LABELS_FILE"
    exit 1
fi

rotate_log "$LOG_FILE"
rotate_log "$ERROR_LOG"

# Prints whole seconds since boot, or nothing when unknown.
uptime_seconds() {
    local boot value
    if [[ "$(uname -s)" == Darwin ]]; then
        boot=$(sysctl -n kern.boottime 2>/dev/null | sed -n 's/^{ sec = \([0-9]*\),.*/\1/p')
        [[ "$boot" =~ ^[0-9]+$ ]] && echo $(( $(date +%s) - boot ))
    else
        read -r value _ < "$UPTIME_FILE" 2>/dev/null || return 0
        value="${value%%.*}"
        [[ "$value" =~ ^[0-9]+$ ]] && echo "$value"
    fi
    return 0
}

# A catch-up run right after boot or login sees services that have not started yet.
if (( ! STATUS_MODE )) && [[ "$BOOT_GRACE" =~ ^[0-9]+$ ]] && (( BOOT_GRACE > 0 )); then
    uptime=$(uptime_seconds)
    if [[ -n "$uptime" ]] && (( uptime < BOOT_GRACE )); then
        log_info "Run skipped: uptime=${uptime}s inside boot grace ${BOOT_GRACE}s"
        exit 0
    fi
fi

monitored=0
loaded=0

log_info "Run started"

while IFS= read -r label; do
    [[ -z "$label" ]] && continue
    [[ "$label" =~ ^[[:space:]]*# ]] && continue

    if is_paused "$label"; then
        record_paused "$label"
        continue
    fi
    monitored=$((monitored + 1))
    status=$(check_service "$label")
    details=$(get_service_details "$label")

    if [[ "$status" == "loaded" || "$status" == "active" ]]; then
        loaded=$((loaded + 1))
        log_info "Label=$label status=$status $details"
        (( STATUS_MODE )) && printf 'ok %s %s %s\n' "$label" "$status" "$details"
    else
        record_problem "$label" "$status" "$details"
    fi
done < "$LABELS_FILE"

if [[ -f "$PROBES_FILE" ]]; then
    while read -r name command; do
        [[ -z "$name" || "$name" == \#* ]] && continue
        if is_paused "$name"; then
            record_paused "$name"
            continue
        fi
        monitored=$((monitored + 1))
        if run_probe "$command"; then
            loaded=$((loaded + 1))
            record_ok "$name" "probe"
        else
            record_problem "$name" "failed" "probe exit=$?"
        fi
    done < "$PROBES_FILE"
fi

if [[ -d "$JOBS_DIR" ]]; then
    for record in "$JOBS_DIR"/*.status; do
        [[ -f "$record" ]] || continue
        job=$(basename "$record" .status)
        monitored=$((monitored + 1))
        result=$(check_job_record "$record")
        case "$result" in
            ok*)
                loaded=$((loaded + 1))
                record_ok "$job" "job ${result#ok }"
                ;;
            *)
                record_problem "$job" "${result%% *}" "job ${result#* }"
                ;;
        esac
    done
fi

if [[ -f "$PAUSE_FILE" ]]; then
    monitored=$((monitored + 1))
    if [[ "$pause_since" =~ ^[0-9]+$ && "$pause_max_age" =~ ^[0-9]+$ ]] \
        && (( $(date +%s) - pause_since > pause_max_age * 3600 )); then
        record_problem "pause-$pause_owner" "stale" "paused_hours=$(( ($(date +%s) - pause_since) / 3600 )) max_age_hours=$pause_max_age (run: $pause_owner off)"
    else
        loaded=$((loaded + 1))
        record_ok "pause-$pause_owner" "since=${pause_since:-unknown}"
    fi
fi

log_info "Run finished monitored=$monitored loaded=$loaded"

if (( STATUS_MODE )); then
    (( problem_count > 0 )) && exit 2
    exit 0
fi

# A log file nobody reads is not a monitor. Surface every problem once.
NOTIFIED_FILE="$CONFIG_DIR/last-notified"
previous_problems=$(cat "$NOTIFIED_FILE" 2>/dev/null || true)
if [[ "$problem_labels" != "$previous_problems" ]]; then
    if [[ -n "$problem_labels" ]]; then
        "${OPS_BIN:-$HOME/.agents/ops/bin/ops}" notify "heartbeat" "Failed or missing: $problem_labels" --priority 4 >/dev/null 2>&1 \
            || notify "launchd heartbeat" "Failed or missing: $problem_labels"
    fi
    printf '%s' "$problem_labels" > "$NOTIFIED_FILE"
fi
