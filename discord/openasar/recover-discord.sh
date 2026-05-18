#!/usr/bin/env zsh
set -euo pipefail

# Platform detection
case "$(uname -s)" in
  Darwin) OS=macos ;;
  Linux)  OS=linux ;;
  *)      echo "Unsupported OS"; exit 1 ;;
esac

# Platform-specific paths
if [[ "$OS" == macos ]]; then
  DISCORD_APP="${DISCORD_APP_PATH:-/Applications/Discord.app}"
  DISCORD_ASAR="$DISCORD_APP/Contents/Resources/app.asar"
  BUILD_INFO="$DISCORD_APP/Contents/Resources/build_info.json"
  SETTINGS_JSON="$HOME/Library/Application Support/discord/settings.json"
  PERSIST_DIR="$HOME/Library/OpenAsarPersist"
  BACKUP_DIR="$PERSIST_DIR/backups"
  DISCORD_BIN="$DISCORD_APP/Contents/MacOS/Discord"
  PGREP_PATTERN="Discord.app/Contents/MacOS/Discord"
else
  for d in "/opt/discord" "/usr/lib/discord" "$HOME/.local/share/discord"; do
    [[ -d "$d" ]] && { DISCORD_APP="$d"; break; }
  done
  DISCORD_ASAR="$DISCORD_APP/resources/app.asar"
  BUILD_INFO="$DISCORD_APP/resources/build_info.json"
  SETTINGS_JSON="${XDG_CONFIG_HOME:-$HOME/.config}/discord/settings.json"
  PERSIST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/OpenAsarPersist"
  BACKUP_DIR="$PERSIST_DIR/backups"
  DISCORD_BIN="$(command -v discord 2>/dev/null || echo "/usr/bin/discord")"
  PGREP_PATTERN="discord"
fi

LAUNCH=false
RESTORE_FILE=""
while (( $# > 0 )); do
  case "$1" in
    --launch) LAUNCH=true; shift ;;
    --help|-h)
      cat <<'HELP'
Usage: recover-discord.sh [--launch] [backup-file]

Restores Discord's stock app.asar from a backup and removes OpenAsar.

If no backup file is specified, the latest backup is used.
Use --launch to also start Discord after recovery.

Examples:
  recover-discord.sh                          restore latest backup
  recover-discord.sh --launch                 restore + launch Discord
  recover-discord.sh path/to/backup.asar      restore specific backup
HELP
      exit 0
      ;;
    *)
      if [ -f "$1" ]; then
        RESTORE_FILE="$1"
        shift
      else
        echo "Unknown option or file not found: $1" >&2
        exit 1
      fi
      ;;
  esac
done

log()  { echo "  $*"; }
fatal(){ echo "FATAL: $*" >&2; exit 1; }

if [ ! -d "$DISCORD_APP" ]; then
  fatal "Discord not found at $DISCORD_APP"
fi

if pgrep -f "$PGREP_PATTERN" &>/dev/null; then
  echo "Discord is running. Quitting..."
  pkill -f "$PGREP_PATTERN" 2>/dev/null || true
  sleep 2
fi

echo "===== Discord Recovery ====="
echo ""

if [ -n "$RESTORE_FILE" ]; then
  if [ ! -f "$RESTORE_FILE" ]; then
    fatal "Backup not found: $RESTORE_FILE"
  fi
  log "Using specified backup: $RESTORE_FILE"
else
  if [ ! -d "$BACKUP_DIR" ] || [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
    fatal "No backups found in $BACKUP_DIR"
  fi

  echo "  Available backups:"
  ls -1tr "$BACKUP_DIR" | while read -r f; do
    size=$(du -h "$BACKUP_DIR/$f" | cut -f1)
    printf "    %s  %s\n" "$size" "$f"
  done
  echo ""

  RESTORE_FILE="$(ls -t "$BACKUP_DIR"/*.asar.backup 2>/dev/null | head -1)"
  if [ -z "$RESTORE_FILE" ]; then
    fatal "No .asar.backup files found in $BACKUP_DIR"
  fi
  log "Using latest backup: $(basename "$RESTORE_FILE")"
fi

if [ ! -f "$RESTORE_FILE" ]; then
  fatal "Backup file missing: $RESTORE_FILE"
fi

BACKUP_SIZE=$(stat -f%z "$RESTORE_FILE" 2>/dev/null || echo 0)
if [ "$BACKUP_SIZE" -lt 10000 ]; then
  fatal "Backup file is too small ($BACKUP_SIZE bytes). It may be an OpenAsar file, not stock Discord."
fi

echo ""
log "Restoring stock app.asar (${BACKUP_SIZE} bytes)..."
cp "$RESTORE_FILE" "$DISCORD_ASAR"
log "Done."

DISCORD_VERSION="$(jq -r '.version // "0.0.0"' "$BUILD_INFO" 2>/dev/null)" || true
: "${DISCORD_VERSION:=0.0.0}"

MODULES_DIR="$HOME/Library/Application Support/discord/${DISCORD_VERSION}/modules"
if [ -d "$MODULES_DIR" ]; then
  echo ""
  log "Nuking modules directory to force fresh download..."
  rm -rf "$MODULES_DIR"
  log "Done: $MODULES_DIR"
fi

echo ""
log "Removing OpenAsar from settings.json..."
if [ -f "$SETTINGS_JSON" ]; then
  python3 - "$SETTINGS_JSON" <<'PY'
import json, sys
from pathlib import Path
settings_path = Path(sys.argv[1])
settings = json.loads(settings_path.read_text())
settings.pop('openasar', None)
settings_path.write_text(json.dumps(settings, indent=2) + '\n')
PY
  log "Done."
else
  log "No settings.json found, skipping."
fi

echo ""
echo "===== Recovery Complete ====="
echo "  Restored:  $(basename "$RESTORE_FILE")"
echo "  Discord:   $DISCORD_VERSION"
echo "  OpenAsar:  removed"
echo ""

if [ "$LAUNCH" = true ]; then
  log "Launching Discord to re-download modules..."
  "$DISCORD_BIN" 2>/dev/null &
  disown
  echo "  Discord started. The splash screen will show module download progress."
else
  echo "  Run with --launch or open Discord manually to re-download modules."
fi
