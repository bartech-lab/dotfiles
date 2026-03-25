#!/bin/bash

set -euo pipefail

CALENDAR_DB="${HOME}/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb"
USER_EMAIL="b.kowalski@tidio.net"

if [[ ! -f "$CALENDAR_DB" ]]; then
    echo "Calendar database not found: $CALENDAR_DB"
    exit 1
fi

COUNT_SQL="
SELECT
  (SELECT COUNT(*) FROM CalendarItem WHERE invitation_status=3),
  (SELECT COUNT(*) FROM Participant WHERE lower(email)=lower('$USER_EMAIL') AND (status<>1 OR pending_status<>1));
"

read -r BEFORE_INVITES BEFORE_PENDING < <(
    sqlite3 -noheader -separator ' ' "$CALENDAR_DB" "$COUNT_SQL"
)

echo "Before: invitation_status=3=${BEFORE_INVITES}, pending_self=${BEFORE_PENDING}"

COCOA_NOW=$(( $(date '+%s') - 978307200 ))

sqlite3 -cmd ".timeout 30000" "$CALENDAR_DB" <<EOF
BEGIN IMMEDIATE;

DROP TABLE IF EXISTS tmp_fix_items;
CREATE TEMP TABLE tmp_fix_items AS
SELECT ROWID FROM CalendarItem WHERE invitation_status=3;

UPDATE CalendarItem
SET invitation_status=0,
    last_modified=$COCOA_NOW
WHERE ROWID IN (SELECT ROWID FROM tmp_fix_items);

DROP TABLE IF EXISTS tmp_fix_owner_ids;
CREATE TEMP TABLE tmp_fix_owner_ids AS
SELECT DISTINCT owner_id
FROM Participant
WHERE lower(email)=lower('$USER_EMAIL')
  AND (status<>1 OR pending_status<>1);

UPDATE Participant
SET status=1,
    pending_status=1,
    last_modified=$COCOA_NOW
WHERE lower(email)=lower('$USER_EMAIL')
  AND (status<>1 OR pending_status<>1);

UPDATE CalendarItem
SET self_attendee_id = (
    SELECT p2.ROWID
    FROM Participant p2
    WHERE p2.owner_id = CalendarItem.ROWID
      AND lower(p2.email)=lower('$USER_EMAIL')
    ORDER BY (p2.status=1 AND p2.pending_status=1) DESC, p2.ROWID DESC
    LIMIT 1
),
last_modified=$COCOA_NOW
WHERE ROWID IN (SELECT owner_id FROM tmp_fix_owner_ids)
  AND EXISTS (
      SELECT 1 FROM Participant p3
      WHERE p3.owner_id = CalendarItem.ROWID
        AND lower(p3.email)=lower('$USER_EMAIL')
  );

COMMIT;
EOF

read -r AFTER_INVITES AFTER_PENDING < <(
    sqlite3 -noheader -separator ' ' "$CALENDAR_DB" "$COUNT_SQL"
)

echo "After:  invitation_status=3=${AFTER_INVITES}, pending_self=${AFTER_PENDING}"

# Refresh Calendar UI state after DB repair
osascript -e 'tell application "Calendar" to quit' >/dev/null 2>&1 || true

for _ in 1 2 3 4 5; do
    if ! pgrep -x Calendar >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

open -a Calendar >/dev/null 2>&1 || true
sleep 5
killall Dock >/dev/null 2>&1 || true

echo "UI refresh: Calendar restarted, Dock badge cache reset"
