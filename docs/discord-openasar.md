# Discord OpenAsar (Manual)

Opt-in OpenAsar for Discord. On macOS you apply it by hand. On Linux an optional watcher reapplies it after each update (see "Linux: automatic reapply").

Intentionally **not** part of `install.sh`.

## What it is

- **`apply-openasar.sh`** — Downloads latest OpenAsar nightly, backs up current stock asar, applies OpenAsar + theme CSS, runs a 6-second smoke test, and auto-recovers if Discord crashes.
- **`recover-discord.sh`** — Restores stock Discord from a timestamped backup, removes OpenAsar config, nukes modules to trigger fresh downloads.
- **`aggressive-minimal.css`** — Compact sidebar/guildbar, hidden nitro/shop noise, tighter message spacing.

On macOS there is no launchd agent and no automatic reapply. You control when OpenAsar gets applied.

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
4. Back up current stock asar to `~/Library/OpenAsarPersist/backups/` (on Linux `~/.local/share/OpenAsarPersist/backups/`); an asar that already holds OpenAsar is not backed up
5. Apply OpenAsar + theme CSS + settings
6. Launch Discord for 6 seconds as a smoke test
7. If Discord crashes, automatically restore the backup, nuke modules, and launch stock Discord

### Recover from a broken state

```bash
discord-openasar-recover --launch
```

Picks the latest backup that does not hold OpenAsar, restores it, removes OpenAsar config, and launches Discord to re-download modules.

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

On Linux the scripts look for Discord in `/opt/discord`, `/usr/lib/discord`, `~/.local/share/discord`, then the newest `~/.config/discord/app-*` directory, where the Arch `discord` launcher installs it. Discord replaces that directory on each update, which removes OpenAsar.

## Linux: automatic reapply

On Linux an opt-in systemd watcher reapplies OpenAsar after every Discord update. Install it once:

```bash
~/dotfiles/discord/openasar/linux/setup.sh
```

- `openasar-patch.path` watches `~/.config/discord/installer.db` and runs `openasar-patch` when it changes.
- `openasar-patch` patches every `app-*/resources/app.asar` that is not OpenAsar yet, from the cached `~/.local/share/OpenAsarPersist/openasar.app.asar`. It downloads only when the cache is missing.
- `openasar-patch --refresh` downloads the latest nightly into the cache and repatches.
- The theme CSS stays in `settings.json` under `openasar.css`; the watcher does not touch it.

When Discord does not start, run `discord-check`. It prints one `ok` or `FAIL` line per check and exits non-zero on any failure:

- the `~/.config/discord/Discord` link points at the newest `app-*` directory (a stale link means a half-finished update);
- `discord_desktop_core` exists for that version;
- OpenAsar is applied;
- a monitor is connected. Without one, every Electron app hangs at startup on Wayland, stock Discord included.
