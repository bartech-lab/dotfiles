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
- gracefully restarts Calendar in the background

Optional Dock badge reset:

```bash
./run-now.sh --reset-dock
```

## Notes

- This only changes local Calendar DB state (does not modify Google Calendar server data).
- This is intentionally manual mode: one command when needed.
