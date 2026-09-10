#!/bin/bash

# Service Heartbeat Script
# Writes lightweight status snapshots every hour

set -u

usage() {
    cat <<'EOF'
Usage: heartbeat.sh [--help]

Check configured background services and log their current status.
EOF
}

case "${1:-}" in
    '') ;;
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
LOG_FILE="$CONFIG_DIR/heartbeat.log"
ERROR_LOG="$CONFIG_DIR/error.log"

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

# Platform-aware service check
if [[ "$(uname -s)" == Darwin ]]; then
    check_service() {
        launchctl print "gui/$(id -u)/$1" >/dev/null 2>&1 && echo "loaded" || echo "missing"
    }
    notify() {
        osascript -e "display notification \"$2\" with title \"$1\"" >/dev/null 2>&1 || true
    }
    get_service_details() {
        local info
        info=$(launchctl print "gui/$(id -u)/$1" 2>/dev/null)
        local state="unknown" runs="unknown"
        while IFS= read -r line; do
            case "$line" in
                *"state = "*) state="${line##*state = }" ;;
                *"runs = "*)  runs="${line##*runs = }" ;;
            esac
        done <<< "$info"
        echo "state=$state runs=$runs"
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

monitored=0
loaded=0
problem_labels=""

log_info "Run started"

while IFS= read -r label; do
    [[ -z "$label" ]] && continue
    [[ "$label" =~ ^[[:space:]]*# ]] && continue

    monitored=$((monitored + 1))
    status=$(check_service "$label")
    
    if [[ "$status" == "loaded" || "$status" == "active" ]]; then
        loaded=$((loaded + 1))
        details=$(get_service_details "$label")
        log_info "Label=$label status=$status $details"
    else
        details=$(get_service_details "$label")
        log_error "Label=$label status=$status $details"
        if [[ "$status" == "failed" || "$status" == "missing" ]]; then
            problem_labels="${problem_labels}${problem_labels:+, }$label ($status)"
        fi
    fi
done < "$LABELS_FILE"

log_info "Run finished monitored=$monitored loaded=$loaded"

# A log file nobody reads is not a monitor. Surface unloaded services.
if [[ -n "$problem_labels" ]]; then
    notify "launchd heartbeat" "Failed or missing: $problem_labels"
fi
