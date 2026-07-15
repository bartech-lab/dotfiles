#!/usr/bin/env bash

CACHE_TTL="${CACHE_TTL:-3600}"

cache_valid() {
  local cache_file="$1"
  [[ -z "$cache_file" ]] && return 1
  [[ -f "$cache_file" ]] || return 1

  local file_time now_time
  if is_macos; then
    file_time=$(stat -f "%m" "$cache_file" 2>/dev/null || echo 0)
  else
    file_time=$(stat -c "%Y" "$cache_file" 2>/dev/null || echo 0)
  fi
  now_time=$(date +%s)

  (( now_time >= file_time && now_time - file_time < CACHE_TTL )) || return 1
  jq -e 'type == "array"' "$cache_file" >/dev/null 2>&1
}

cache_read() {
  local cache_file="$1"
  if [[ -f "$cache_file" ]]; then
    cat "$cache_file"
  fi
}

cache_write() {
  local cache_file="$1" data="$2"
  local cache_dir tmp_file
  cache_dir="$(dirname "$cache_file")"
  mkdir -p "$cache_dir" 2>/dev/null || return 1
  tmp_file="${cache_file}.tmp.$$"
  if ! printf '%s\n' "$data" > "$tmp_file"; then
    rm -f "$tmp_file"
    return 1
  fi
  mv -f "$tmp_file" "$cache_file"
}

cache_clear() {
  local cache_file="$1"
  rm -f "$cache_file"
}
