# Discord OpenAsar (Manual)

Opt-in manual OpenAsar application for Discord on macOS. No automation — you run it when you want it.

Intentionally **not** part of `install.sh`.

## What it is

- **`apply-openasar.sh`** — Downloads latest OpenAsar nightly, backs up current stock asar, applies OpenAsar + theme CSS, runs a 6-second smoke test, and auto-recovers if Discord crashes.
- **`recover-discord.sh`** — Restores stock Discord from a timestamped backup, removes OpenAsar config, nukes modules to trigger fresh downloads.
- **`aggressive-minimal.css`** — Compact sidebar/guildbar, hidden nitro/shop noise, tighter message spacing.

No launchd agent. No automatic reapply. No WatchPaths. You control when OpenAsar gets applied.

## Commands

```bash
discord-openasar-apply           # apply OpenAsar with smoke test
discord-openasar-apply --force   # skip version mismatch warning
discord-openasar-apply --yes     # skip confirmation prompts
discord-openasar-apply --skip-smoke  # skip smoke test (not recommended)

discord-openasar-recover         # restore latest backup
discord-openasar-recover --launch  # restore + launch Discord

discord-openasar-status          # show current state
```

## Workflow

### Apply OpenAsar

```bash
discord-openasar-apply
```

The script will:
1. Compare Discord version date with OpenAsar nightly build date
2. Warn if Discord is newer (use `--force` to proceed anyway)
3. Download latest nightly
4. Back up current stock asar to `~/Library/OpenAsarPersist/backups/`
5. Apply OpenAsar + theme CSS + settings
6. Launch Discord for 6 seconds as a smoke test
7. If Discord crashes, automatically restore the backup, nuke modules, and launch stock Discord

### Recover from a broken state

```bash
discord-openasar-recover --launch
```

Picks the latest backup, restores it, removes OpenAsar config, and launches Discord to re-download modules.

### After a Discord update

Discord updates itself (via the new updater) and overwrites `app.asar`. After updating, re-run:

```bash
discord-openasar-apply
```

If the new Discord version broke OpenAsar nightly, the smoke test catches it and auto-recovers.

## Files

| Path | Purpose |
|------|---------|
| `~/dotfiles/discord/openasar/apply-openasar.sh` | Apply script |
| `~/dotfiles/discord/openasar/recover-discord.sh` | Recovery script |
| `~/dotfiles/discord/openasar/aggressive-minimal.css` | Theme CSS |
| `~/dotfiles/zsh/functions/61-discord.zsh` | Shell wrappers |
| `~/Library/OpenAsarPersist/` | Cached nightly + backups |
| `~/Library/Logs/OpenAsarPersist/` | Smoke test logs |

## Theme

The CSS applies a compact layout and hides annoying elements (nitro shop, gift/sticker/gif buttons, activity panel, profile effects). Edit `aggressive-minimal.css` to tweak.
