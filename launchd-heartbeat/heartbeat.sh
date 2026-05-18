#!/bin/bash

# Service Heartbeat Script
# Writes lightweight status snapshots every hour

set -u

CONFIG_DIR="$HOME/.config/launchd-heartbeat"
LABELS_FILE="$CONFIG_DIR/monitored-labels.conf"
LOG_FILE="$CONFIG_DIR/heartbeat.log"
ERROR_LOG="$CONFIG_DIR/error.log"

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
        launchctl print "gui/$(id -u)/$1" 2>/dev/null && echo "loaded" || echo "missing"
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
        systemctl --user is-active "$1" 2>/dev/null || echo "missing"
    }
    get_service_details() {
        local state runs
        state=$(systemctl --user is-active "$1" 2>/dev/null || echo "unknown")
        runs="N/A"
        echo "state=$state runs=$runs"
    }
fi

if [[ ! -f "$LABELS_FILE" ]]; then
    log_error "Labels file not found at $LABELS_FILE"
    exit 1
fi

monitored=0
loaded=0

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
        log_error "Label=$label status=missing"
    fi
done < "$LABELS_FILE"

log_info "Run finished monitored=$monitored loaded=$loaded"
