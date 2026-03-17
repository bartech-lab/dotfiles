# Discord OpenAsar (Manual Setup)

This is an opt-in setup for keeping OpenAsar persistent across Discord updates on macOS.

It is intentionally **not** part of `install.sh`.

## What it installs

- LaunchAgent: `~/Library/LaunchAgents/dev.openasar.reapply.plist`
- Reapply script: `~/dotfiles/discord/openasar/reapply-openasar.sh`
- Theme CSS source: `~/dotfiles/discord/openasar/aggressive-minimal.css`
- OpenAsar binary cache: `~/Library/OpenAsarPersist/openasar.app.asar`
- Backup of stock asar: `~/Library/OpenAsarPersist/discord-stock.app.asar.backup`

## Setup

```bash
~/dotfiles/scripts/bin/setup-discord-openasar
```

Optional flags:

```bash
# Re-download latest OpenAsar nightly
~/dotfiles/scripts/bin/setup-discord-openasar --refresh-openasar

# Use Discord PTB or Canary app path
~/dotfiles/scripts/bin/setup-discord-openasar --app "/Applications/Discord PTB.app"

# Skip syncing custom CSS into OpenAsar settings.json
~/dotfiles/scripts/bin/setup-discord-openasar --no-theme
```

## Commands

- Run setup via shell function: `discord-openasar-setup`
- Check LaunchAgent status: `discord-openasar-status`

## Notes

- This flow repatches `app.asar` after updates; it does not modify your dotfiles installer.
- OpenAsar custom CSS is synced into the channel-specific Discord settings file when available.
- If Discord is in a different location, pass `--app`.
- LaunchAgent is update-driven via `WatchPaths` with a 24h fallback interval (`StartInterval=86400`).
- `RunAtLoad` is intentionally disabled.
