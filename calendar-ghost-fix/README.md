# Calendar Ghost Invite Fix

Automatically fixes recurring ghost RSVP invites in macOS Calendar that keep reappearing even after accepting them in Google Calendar.

## Problem

Calendar events (especially recurring ones) show as "needs response" in macOS Calendar even though:
- They appear accepted in Google Calendar web interface
- You've already accepted them multiple times
- They keep coming back after each sync

This happens because Google CalDAV sync reports incorrect RSVP state for some events, and macOS Calendar keeps resetting them to "needs response".

## Solution

This fix monitors your Calendar database every hour and automatically resets ghost invites back to accepted state. It also includes retry and locking logic so runs are reliable even while Calendar is syncing.

## Setup

```bash
cd ~/dotfiles/calendar-ghost-fix
./setup.sh
```

This will:
- Install the fix script to `~/.config/calendar-ghost-fix/`
- Create a LaunchAgent that runs every hour
- Trigger an immediate fix run

## How It Works

On each run, the script:
1. Checks Calendar database for events with `invitation_status=3` (needs response)
2. Resets them to `invitation_status=0` (accepted)
3. Fixes the self-attendee `status` and `pending_status` to accepted
4. Refreshes the Calendar app UI if changes were made
5. Logs all activity

## Logs

- **Fix log**: `~/.config/calendar-ghost-fix/fix.log`
- **Error log**: `~/.config/calendar-ghost-fix/error.log`

View recent activity:
```bash
tail -f ~/.config/calendar-ghost-fix/fix.log
```

## Management

```bash
# Check service status
launchctl print gui/$(id -u)/com.user.calendarghostfix

# Trigger immediate run
launchctl kickstart -k gui/$(id -u)/com.user.calendarghostfix

# Stop service (temporarily)
launchctl bootout gui/$(id -u)/com.user.calendarghostfix

# Start service again
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.calendarghostfix.plist
```

## Uninstall

```bash
cd ~/dotfiles/calendar-ghost-fix
./setup.sh uninstall
```

This will:
- Stop the LaunchAgent
- Remove the plist file
- Optionally remove config directory and logs

## Technical Details

- **Interval**: Runs every hour (3600 seconds)
- **Database**: `~/Library/Group Containers/group.com.apple.calendar/Calendar.sqlitedb`
- **Process type**: Background (low resource usage)
- **Safe**: Only modifies local database, doesn't touch Google Calendar
- **UI refresh**: Relaunches Calendar only when it actually repairs rows

## When to Use

Use this if you:
- Have recurring meetings that keep showing as "needs response"
- Already confirmed they're accepted in Google Calendar
- Don't want to remove and re-add your Google account (especially with MDM)
- Need a permanent workaround while waiting for a Google fix

## Notes

- This is a workaround, not a root cause fix
- The root cause is Google CalDAV reporting incorrect RSVP state
- You may still see ghost invites briefly until the next hourly run
- All fixes are logged so you can verify it's working
