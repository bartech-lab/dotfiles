#!/usr/bin/env zsh
set -euo pipefail

TARGET_APP="${DISCORD_APP_PATH:-/Applications/Discord.app}"
TARGET="$TARGET_APP/Contents/Resources/app.asar"
SOURCE="${OPENASAR_SOURCE:-$HOME/Library/OpenAsarPersist/openasar.app.asar}"
LOG_DIR="${OPENASAR_LOG_DIR:-$HOME/Library/Logs/OpenAsarPersist}"
LOG_FILE="$LOG_DIR/reapply.log"
RETRY_COUNT="${OPENASAR_RETRY_COUNT:-18}"
RETRY_DELAY="${OPENASAR_RETRY_DELAY:-10}"

mkdir -p "$LOG_DIR"

timestamp() {
  /bin/date "+%Y-%m-%d %H:%M:%S"
}

log() {
  /usr/bin/printf "%s %s\n" "$(timestamp)" "$1" >> "$LOG_FILE"
}

copy_with_retry() {
  local attempt=1
  local copy_error=""

  while [ "$attempt" -le "$RETRY_COUNT" ]; do
    copy_error="$(/bin/cp "$SOURCE" "$TARGET" 2>&1)" && return 0
    log "copy attempt ${attempt}/${RETRY_COUNT} failed: $copy_error"

    if [ "$attempt" -lt "$RETRY_COUNT" ]; then
      /bin/sleep "$RETRY_DELAY"
    fi

    attempt=$((attempt + 1))
  done

  return 1
}

if [ ! -f "$SOURCE" ]; then
  log "source missing: $SOURCE"
  exit 1
fi

if [ ! -f "$TARGET" ]; then
  log "target missing: $TARGET"
  exit 0
fi

if [ ! -w "$TARGET" ]; then
  log "target not writable: $TARGET"
  exit 1
fi

source_sum="$(/usr/bin/shasum -a 256 "$SOURCE")"
source_hash="${source_sum%% *}"
target_sum="$(/usr/bin/shasum -a 256 "$TARGET")"
target_hash="${target_sum%% *}"

if [ "$source_hash" = "$target_hash" ]; then
  log "already current"
  exit 0
fi

if ! copy_with_retry; then
  log "failed to reapply openasar after ${RETRY_COUNT} attempts"
  exit 1
fi

new_sum="$(/usr/bin/shasum -a 256 "$TARGET")"
new_hash="${new_sum%% *}"

if [ "$new_hash" = "$source_hash" ]; then
  log "reapplied openasar"
  exit 0
fi

log "verification failed after copy"
exit 1
