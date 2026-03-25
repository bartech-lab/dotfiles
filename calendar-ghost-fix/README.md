# Calendar Ghost Invite Fix

Manual, one-command repair for recurring ghost RSVP invites in macOS Calendar.

## Why manual mode

On this machine, `launchd` jobs (both user and root) are blocked from opening Calendar's database (`authorization denied`).
Manual runs from an interactive shell work reliably, so this setup is intentionally manual-only.

## Quick use

```bash
cd ~/dotfiles/calendar-ghost-fix
./run-now.sh
```
This command:
- `invitation_status=3` rows in `CalendarItem`
- repairs pending self-attendee rows for `b.kowalski@tidio.net`
- gracefully restarts Calendar
- resets Dock badge cache

## One-time cleanup old automation (recommended once per machine)

```bash
launchctl bootout gui/$(id -u)/com.user.calendarghostfix || true
rm -f ~/Library/LaunchAgents/com.user.calendarghostfix.plist

sudo launchctl bootout system/com.user.calendarghostfix.root || true
sudo rm -f /Library/LaunchDaemons/com.user.calendarghostfix.root.plist /usr/local/libexec/calendar-ghost-fix-root.sh

rm -f ~/.config/calendar-ghost-fix/fix.log \
      ~/.config/calendar-ghost-fix/error.log \
      ~/.config/calendar-ghost-fix/fix-root.log \
      ~/.config/calendar-ghost-fix/error-root.log \
      ~/.config/calendar-ghost-fix/launchd-test.out \
      ~/.config/calendar-ghost-fix/launchd-test.err
```

## Notes

- This only changes local Calendar DB state (does not modify Google Calendar server data).
- This is intentionally manual mode: one command when needed.
