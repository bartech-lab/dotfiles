# Calendar Ghost Invite Fix

Manual, one-command repair for recurring ghost RSVP invites in macOS Calendar.

## Why manual mode

On this machine, `launchd` jobs (both user and root) are blocked from opening Calendar's database (`authorization denied`).
Manual runs from an interactive shell work reliably, so this setup is intentionally manual-only.

## Configuration

The script needs the Calendar account address to repair. It is never stored in
this repository. Export it from `~/.zshenv`, which is untracked:

```bash
export CALFIX_USER_EMAIL='you@example.com'
```

Pass `--email ADDR` to override it for one run.

## Quick use

```bash
cd ~/dotfiles/calendar-ghost-fix
./run-now.sh
```
This command:
- `invitation_status=3` rows in `CalendarItem`
- repairs pending self-attendee rows for the configured address
- gracefully restarts Calendar in the background

Optional Dock badge reset:

```bash
./run-now.sh --reset-dock
```

## Notes

- This only changes local Calendar DB state (does not modify Google Calendar server data).
- This is intentionally manual mode: one command when needed.
