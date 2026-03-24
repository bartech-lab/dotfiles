#!/bin/bash

# Calendar Ghost Invite Fix Script
# Automatically fixes recurring ghost RSVP issues in macOS Calendar
# Runs every hour via LaunchAgent

set -u

CONFIG_DIR="${HOME}/.config/calendar-ghost-fix"
LOG_FILE="${CONFIG_DIR}/fix.log"
ERROR_LOG="${CONFIG_DIR}/error.log"
CALENDAR_DB="${HOME}/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb"
USER_EMAIL="b.kowalski@tidio.net"

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    echo "$(timestamp): $1" >> "$LOG_FILE"
}

log_error() {
    echo "$(timestamp): $1" >> "$ERROR_LOG"
}

# Check if database exists
if [[ ! -f "$CALENDAR_DB" ]]; then
    log_error "Calendar database not found at $CALENDAR_DB"
    exit 1
fi

# Count problematic events before fix (CalendarItem level)
BEFORE_COUNT=$(sqlite3 "$CALENDAR_DB" "SELECT COUNT(*) FROM CalendarItem WHERE invitation_status=3;" 2>/dev/null || echo "0")

# Count participants with pending status for the user
PENDING_PARTICIPANTS=$(sqlite3 "$CALENDAR_DB" "SELECT COUNT(*) FROM Participant WHERE email='$USER_EMAIL' AND status=0;" 2>/dev/null || echo "0")

log_info "Run started - Found $BEFORE_COUNT events with invitation_status=3, $PENDING_PARTICIPANTS participants with status=0 for $USER_EMAIL"

TOTAL_FIXED=0

# Fix 1: CalendarItem invitation_status
if [[ "$BEFORE_COUNT" -gt 0 ]]; then
    # Get Cocoa timestamp for last_modified update
    CURRENT_COCOA_TIME=$(echo "$(date '+%s') - 978307200" | bc)
    
    sqlite3 "$CALENDAR_DB" <<EOF 2>/dev/null
BEGIN;
UPDATE CalendarItem SET invitation_status=0 WHERE invitation_status=3;
UPDATE CalendarItem SET last_modified = $CURRENT_COCOA_TIME WHERE invitation_status=0 AND last_modified < $CURRENT_COCOA_TIME - 3600;
COMMIT;
EOF
    
    if [[ $? -eq 0 ]]; then
        AFTER_COUNT=$(sqlite3 "$CALENDAR_DB" "SELECT COUNT(*) FROM CalendarItem WHERE invitation_status=3;" 2>/dev/null || echo "0")
        FIXED_COUNT=$((BEFORE_COUNT - AFTER_COUNT))
        TOTAL_FIXED=$((TOTAL_FIXED + FIXED_COUNT))
        log_info "Fixed $FIXED_COUNT CalendarItem records and updated timestamps"
    else
        log_error "Failed to fix CalendarItem records"
    fi
fi

# Fix 2: Participant status for the user (this is what causes grayed out UI)
if [[ "$PENDING_PARTICIPANTS" -gt 0 ]]; then
    # Get list of events that will be fixed and their IDs
    EVENTS_TO_FIX=$(sqlite3 "$CALENDAR_DB" "SELECT DISTINCT ci.summary, datetime(ci.start_date+978307200,'unixepoch','localtime') FROM CalendarItem ci JOIN Participant p ON ci.ROWID=p.owner_id WHERE p.email='$USER_EMAIL' AND p.status=0 AND ci.start_date > strftime('%s','now','-30 days')-978307200 ORDER BY ci.start_date DESC LIMIT 20;" 2>/dev/null)
    
    # Get Cocoa timestamp for last_modified update
    CURRENT_COCOA_TIME=$(echo "$(date '+%s') - 978307200" | bc)
    
    sqlite3 "$CALENDAR_DB" <<EOF 2>/dev/null
BEGIN;
UPDATE Participant 
SET status=1, pending_status=1 
WHERE email='$USER_EMAIL' AND status=0;
COMMIT;
EOF
    
    if [[ $? -eq 0 ]]; then
        AFTER_PENDING=$(sqlite3 "$CALENDAR_DB" "SELECT COUNT(*) FROM Participant WHERE email='$USER_EMAIL' AND status=0;" 2>/dev/null || echo "0")
        FIXED_PARTICIPANTS=$((PENDING_PARTICIPANTS - AFTER_PENDING))
        TOTAL_FIXED=$((TOTAL_FIXED + FIXED_PARTICIPANTS))
        log_info "Fixed $FIXED_PARTICIPANTS Participant records for $USER_EMAIL"
        
        # Update last_modified on affected CalendarItems to force UI refresh
        sqlite3 "$CALENDAR_DB" <<EOF 2>/dev/null
BEGIN;
UPDATE CalendarItem 
SET last_modified = $CURRENT_COCOA_TIME 
WHERE ROWID IN (
    SELECT DISTINCT owner_id 
    FROM Participant 
    WHERE email='$USER_EMAIL' AND status=1
) AND last_modified < $CURRENT_COCOA_TIME - 3600;
COMMIT;
EOF
        
        if [[ $? -eq 0 ]]; then
            log_info "Updated last_modified timestamps to force UI refresh"
        fi
        
        # Log the specific events fixed
        if [[ -n "$EVENTS_TO_FIX" ]]; then
            echo "$EVENTS_TO_FIX" | while read -r line; do
                [[ -n "$line" ]] && log_info "Fixed participant for: $line"
            done
        fi
    else
        log_error "Failed to fix Participant records"
    fi
fi

if [[ $TOTAL_FIXED -eq 0 ]]; then
    log_info "No ghost invites found"
else
    log_info "Total fixed: $TOTAL_FIXED records"
fi

log_info "Run completed"