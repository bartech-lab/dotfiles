#!/usr/bin/env zsh
set -euo pipefail

DISCORD_APP="${DISCORD_APP_PATH:-/Applications/Discord.app}"
DISCORD_ASAR="$DISCORD_APP/Contents/Resources/app.asar"
BUILD_INFO="$DISCORD_APP/Contents/Resources/build_info.json"
SETTINGS_JSON="$HOME/Library/Application Support/discord/settings.json"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/dotfiles}"

OPENASAR_URL="https://github.com/GooseMod/OpenAsar/releases/download/nightly/app.asar"
GITHUB_API="https://api.github.com/repos/GooseMod/OpenAsar/releases/tags/nightly"

PERSIST_DIR="$HOME/Library/OpenAsarPersist"
BACKUP_DIR="$PERSIST_DIR/backups"
LOG_DIR="$HOME/Library/Logs/OpenAsarPersist"
OPENASAR_FILE="$PERSIST_DIR/openasar.app.asar"
THEME_CSS="$DOTFILES_DIR/discord/openasar/aggressive-minimal.css"
EXTERNAL_THEME_URL="https://d3sox.me/complementary-discord-theme/complementary.theme.css"

SMOKE_TIMEOUT=6
FORCE=false
SKIP_SMOKE=false
YES=false
while (( $# > 0 )); do
  case "$1" in
    --force) FORCE=true; shift ;;
    --skip-smoke) SKIP_SMOKE=true; shift ;;
    --yes|-y) YES=true; shift ;;
    --help|-h)
      cat <<'HELP'
Usage: apply-openasar.sh [options]

Options:
  --yes, -y       Skip confirmation prompts
  --force         Apply even if Discord appears newer than OpenAsar nightly
  --skip-smoke    Skip the post-apply smoke test (not recommended)
  --help, -h      Show this help

After applying, Discord is launched for a 6-second smoke test.
If it crashes, the previous state is automatically restored.
HELP
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

log()  { echo "  $*"; }
err()  { echo "  ERROR: $*" >&2; }
fatal(){ echo "FATAL: $*" >&2; exit 1; }

if ! command -v jq &>/dev/null; then
  fatal "jq is required. Install it with: brew install jq"
fi

if [ ! -d "$DISCORD_APP" ]; then
  fatal "Discord not found at $DISCORD_APP"
fi

if [ ! -f "$THEME_CSS" ]; then
  fatal "Theme CSS not found at $THEME_CSS"
fi

if pgrep -f "Discord.app/Contents/MacOS/Discord" &>/dev/null; then
  fatal "Discord is running. Quit Discord first (Cmd+Q) and try again."
fi

DISCORD_VERSION="$(jq -r '.version // "unknown"' "$BUILD_INFO" 2>/dev/null)" || true
: "${DISCORD_VERSION:=unknown}"

echo "===== OpenAsar Apply ====="
echo ""
echo "  Discord:   $DISCORD_VERSION ($DISCORD_APP)"
echo "  Theme:     $THEME_CSS"
echo "  Backups:   $BACKUP_DIR"
echo ""

echo "Checking OpenAsar nightly release date..."
NIGHTLY_DATE="$(curl -sf "$GITHUB_API" | jq -r '.assets[0].updated_at // .published_at // empty' 2>/dev/null)" || true

if [ -n "$NIGHTLY_DATE" ]; then
  NIGHTLY_EPOCH="$(date -jf "%Y-%m-%dT%H:%M:%SZ" "$NIGHTLY_DATE" "+%s" 2>/dev/null)" || true
  DISCORD_MTIME="$(stat -f %m "$DISCORD_APP" 2>/dev/null)" || true

  if [ -n "$NIGHTLY_EPOCH" ] && [ -n "$DISCORD_MTIME" ] && [ "$DISCORD_MTIME" -gt "$NIGHTLY_EPOCH" ]; then
    echo ""
    echo "  WARNING: Discord appears newer than the OpenAsar nightly build."
    echo "  Discord bundle modified: $(date -r "$DISCORD_MTIME" '+%Y-%m-%d %H:%M:%S')"
    echo "  OpenAsar nightly:       $(date -r "$NIGHTLY_EPOCH" '+%Y-%m-%d %H:%M:%S')"
    echo ""
    if [ "$FORCE" = false ]; then
      if [ "$YES" = false ]; then
        echo -n "  Apply anyway? This may break Discord. [Y/n] "
        read -r REPLY
        [[ "$REPLY" = "" || "$REPLY" =~ ^[Yy]$ ]] || fatal "Aborted."
      fi
    else
      echo "  --force: applying despite version mismatch."
    fi
  else
    echo "  OpenAsar nightly: $(date -r "$NIGHTLY_EPOCH" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "$NIGHTLY_DATE")"
  fi
else
  echo "  Could not determine nightly release date (GitHub API issue?)."
  if [ "$FORCE" = false ] && [ "$YES" = false ]; then
    echo -n "  Apply anyway? [Y/n] "
    read -r REPLY
    [[ "$REPLY" = "" || "$REPLY" =~ ^[Yy]$ ]] || fatal "Aborted."
  fi
fi

mkdir -p "$PERSIST_DIR" "$BACKUP_DIR" "$LOG_DIR"

echo ""
echo "Downloading OpenAsar nightly..."
curl -fL "$OPENASAR_URL" -o "$OPENASAR_FILE" || fatal "Failed to download OpenAsar nightly."

DOWNLOADSIZE=$(stat -f%z "$OPENASAR_FILE" 2>/dev/null || echo 0)
if [ "$DOWNLOADSIZE" -lt 10000 ]; then
  fatal "Downloaded file is too small ($DOWNLOADSIZE bytes). Corrupt download?"
fi
echo "  Downloaded: $(du -h "$OPENASAR_FILE" | cut -f1)"

echo ""
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_FILE="$BACKUP_DIR/discord-stock-${DISCORD_VERSION}-${TIMESTAMP}.asar.backup"

echo "Backing up current app.asar..."
cp "$DISCORD_ASAR" "$BACKUP_FILE"
echo "  Saved: $BACKUP_FILE"

echo ""
echo "Applying OpenAsar..."
cp "$OPENASAR_FILE" "$DISCORD_ASAR"
echo "  Done."

echo ""
echo "Updating settings.json..."
mkdir -p "$(dirname "$SETTINGS_JSON")"
THEME_CONTENT="$(<"$THEME_CSS")"
python3 - "$SETTINGS_JSON" "$EXTERNAL_THEME_URL" "$THEME_CONTENT" <<'PY'
import json, sys
from pathlib import Path

settings_path = Path(sys.argv[1])
external_theme_url = sys.argv[2]
theme_css = sys.argv[3]

if external_theme_url:
    combined_css = f'@import url({external_theme_url});\n\n{theme_css}'
else:
    combined_css = theme_css

settings = {}
if settings_path.exists():
    settings = json.loads(settings_path.read_text())

settings['openasar'] = {
    'setup': True,
    'autoupdate': False,
    'quickstart': True,
    'noTyping': True,
    'css': combined_css.strip()
}

settings_path.write_text(json.dumps(settings, indent=2) + '\n')
print('  Done.')
PY

if [ "$SKIP_SMOKE" = true ]; then
  echo ""
  echo "Smoke test skipped (--skip-smoke)."
  echo "Launch Discord manually to verify it works."
  exit 0
fi

echo ""
echo "Smoke test: launching Discord for ${SMOKE_TIMEOUT} seconds..."
STDERR_LOG="$LOG_DIR/smoke-test-${TIMESTAMP}.log"
"$DISCORD_APP/Contents/MacOS/Discord" 2>"$STDERR_LOG" &
SMOKE_PID=$!
sleep "$SMOKE_TIMEOUT"

CRASHED=false
if ! kill -0 "$SMOKE_PID" 2>/dev/null; then
  CRASHED=true
else
  kill "$SMOKE_PID" 2>/dev/null || true
  wait "$SMOKE_PID" 2>/dev/null || true
fi

if [ "$CRASHED" = true ]; then
  echo ""
  echo "  DETECTED CRASH during smoke test!"
  echo ""
  echo "  Auto-recovering previous state..."

  cp "$BACKUP_FILE" "$DISCORD_ASAR"
  echo "  Restored: $BACKUP_FILE"

  MODULES_DIR="$HOME/Library/Application Support/discord/${DISCORD_VERSION}/modules"
  if [ -d "$MODULES_DIR" ]; then
    rm -rf "$MODULES_DIR"
    echo "  Nuked modules: $MODULES_DIR"
  fi

  python3 - "$SETTINGS_JSON" <<'PY'
import json
from pathlib import Path
settings_path = Path(sys.argv[1])
if settings_path.exists():
    settings = json.loads(settings_path.read_text())
    settings.pop('openasar', None)
    settings_path.write_text(json.dumps(settings, indent=2) + '\n')
PY

  echo ""
  echo "  Launching stock Discord to re-download modules..."
  "$DISCORD_APP/Contents/MacOS/Discord" 2>/dev/null &
  disown

  echo ""
  echo "  OpenAsar removed. Discord launched stock."
  echo "  Check stderr log: $STDERR_LOG"
  exit 1
fi

echo "  Smoke test passed."

echo ""
echo "===== Done ====="
echo "  Discord:     $DISCORD_VERSION"
echo "  Backup:      $BACKUP_FILE"
echo "  Recover:     discord-openasar-recover"
