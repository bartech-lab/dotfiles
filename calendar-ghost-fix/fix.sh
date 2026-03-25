#!/bin/bash

set -u

CONFIG_DIR="${HOME}/.config/calendar-ghost-fix"
LOG_FILE="${CONFIG_DIR}/fix.log"
ERROR_LOG="${CONFIG_DIR}/error.log"
CALENDAR_DB="${HOME}/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb"
USER_EMAIL="b.kowalski@tidio.net"
CURRENT_COCOA_TIME=$(( $(date '+%s') - 978307200 ))
LOCK_DIR="${CONFIG_DIR}/.lock"

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    echo "$(timestamp): $1" >> "$LOG_FILE"
}

log_error() {
    echo "$(timestamp): $1" >> "$ERROR_LOG"
}

if [[ ! -f "$CALENDAR_DB" ]]; then
    log_error "Calendar database not found at $CALENDAR_DB"
    exit 1
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    exit 0
fi

cleanup() {
    rmdir "$LOCK_DIR" 2>/dev/null || true
}

trap cleanup EXIT

BEFORE_INVITES=$(sqlite3 "$CALENDAR_DB" "SELECT COUNT(*) FROM CalendarItem WHERE invitation_status=3;" 2>/dev/null || echo "0")
BEFORE_SELF_PENDING=$(sqlite3 "$CALENDAR_DB" "SELECT COUNT(*) FROM Participant WHERE email='$USER_EMAIL' AND (status=0 OR pending_status=0);" 2>/dev/null || echo "0")

log_info "Run started - Found $BEFORE_INVITES events with invitation_status=3, $BEFORE_SELF_PENDING self-participants with pending state for $USER_EMAIL"

EVENTS_TO_FIX=$(sqlite3 "$CALENDAR_DB" "SELECT DISTINCT ci.summary || '|' || datetime(ci.start_date+978307200,'unixepoch','localtime') FROM CalendarItem ci JOIN Participant p ON p.owner_id=ci.ROWID WHERE p.email='$USER_EMAIL' AND (p.status=0 OR p.pending_status=0) AND ci.start_date > strftime('%s','now','-30 days')-978307200 ORDER BY ci.start_date DESC LIMIT 20;" 2>/dev/null)

run_fix_transaction() {
    sqlite3 "$CALENDAR_DB" <<EOF
PRAGMA busy_timeout=8000;
BEGIN IMMEDIATE;
DROP TABLE IF EXISTS tmp_fix_items;
CREATE TEMP TABLE tmp_fix_items AS SELECT ROWID FROM CalendarItem WHERE invitation_status=3;
UPDATE CalendarItem
SET invitation_status=0,
    last_modified=$CURRENT_COCOA_TIME
WHERE ROWID IN (SELECT ROWID FROM tmp_fix_items);
SELECT 'calendar_items=' || changes();

DROP TABLE IF EXISTS tmp_fix_owner_ids;
CREATE TEMP TABLE tmp_fix_owner_ids AS
SELECT DISTINCT owner_id
FROM Participant
WHERE email='$USER_EMAIL' AND (status=0 OR pending_status=0);

UPDATE Participant
SET status=1,
    pending_status=1
WHERE email='$USER_EMAIL' AND (status=0 OR pending_status=0);
SELECT 'participants=' || changes();

UPDATE CalendarItem
SET last_modified=$CURRENT_COCOA_TIME
WHERE ROWID IN (SELECT owner_id FROM tmp_fix_owner_ids);
SELECT 'calendar_touch=' || changes();
COMMIT;
EOF
}

FIX_RESULT=""
FIX_STATUS=1
for _ in 1 2 3 4 5; do
    FIX_RESULT=$(run_fix_transaction 2>/dev/null)
    FIX_STATUS=$?
    [[ $FIX_STATUS -eq 0 ]] && break
    sleep 2
done

if [[ $FIX_STATUS -ne 0 ]]; then
    log_error "Database update failed"
    exit 1
fi

FIXED_CALENDAR_ITEMS=0
FIXED_PARTICIPANTS=0
TOUCHED_ITEMS=0

while IFS= read -r line; do
    case "$line" in
        calendar_items=*) FIXED_CALENDAR_ITEMS=${line#calendar_items=} ;;
        participants=*) FIXED_PARTICIPANTS=${line#participants=} ;;
        calendar_touch=*) TOUCHED_ITEMS=${line#calendar_touch=} ;;
    esac
done <<< "$FIX_RESULT"
TOTAL_FIXED=$((FIXED_CALENDAR_ITEMS + FIXED_PARTICIPANTS))

if [[ "$FIXED_CALENDAR_ITEMS" -gt 0 ]]; then
    log_info "Fixed $FIXED_CALENDAR_ITEMS CalendarItem records"
fi

if [[ "$FIXED_PARTICIPANTS" -gt 0 ]]; then
    log_info "Fixed $FIXED_PARTICIPANTS Participant records for $USER_EMAIL"
    log_info "Touched $TOUCHED_ITEMS CalendarItem records to force UI refresh"
    if [[ -n "$EVENTS_TO_FIX" ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && log_info "Fixed participant for: $line"
        done <<< "$EVENTS_TO_FIX"
    fi
fi

if [[ "$TOTAL_FIXED" -eq 0 ]]; then
    log_info "No ghost invites found"
else
    log_info "Total fixed: $TOTAL_FIXED records"
fi

log_info "Run completed"
