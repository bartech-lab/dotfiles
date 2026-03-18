#!/bin/bash

# LaunchAgent Heartbeat Script
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

uid="$(id -u)"

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
    info=""

    if info=$(launchctl print "gui/$uid/$label" 2>/dev/null); then
        loaded=$((loaded + 1))
        state="unknown"
        runs="unknown"

        while IFS= read -r line; do
            case "$line" in
                *"state = "*)
                    state="${line##*state = }"
                    ;;
                *"runs = "*)
                    runs="${line##*runs = }"
                    ;;
            esac
        done <<< "$info"

        log_info "Label=$label status=loaded state=$state runs=$runs"
    else
        log_error "Label=$label status=missing"
    fi
done < "$LABELS_FILE"

log_info "Run finished monitored=$monitored loaded=$loaded"
