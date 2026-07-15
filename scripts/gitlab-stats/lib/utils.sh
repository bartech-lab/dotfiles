#!/usr/bin/env bash

is_macos() {
  [[ "$(uname)" == "Darwin" ]]
}

has_command() {
  command -v "$1" &>/dev/null
}

get_date_n_days_ago() {
  local days="${1:-30}"
  if is_macos; then
    date -v-"${days}"d +%Y-%m-%d
  else
    date -d "$days days ago" +%Y-%m-%d
  fi
}

get_today() {
  date +%Y-%m-%d
}

get_months_between() {
  local since="$1" until="$2"
  if is_macos; then
    local year month end_year end_month
    year="${since:0:4}"
    month="${since:5:2}"
    end_year="${until:0:4}"
    end_month="${until:5:2}"
    while [[ "$((10#$year * 100 + 10#$month))" -le "$((10#$end_year * 100 + 10#$end_month))" ]]; do
      printf "%s-%02d\n" "$year" "$((10#$month))"
      month=$((10#$month + 1))
      if [[ "$month" -gt 12 ]]; then
        month=1
        year=$((year + 1))
      fi
      month=$(printf "%02d" "$month")
    done
  else
    local current="${since:0:7}-01"
    local end="${until:0:7}-01"
    while [[ "$current" < "$end" ]] || [[ "$current" == "$end" ]]; do
      date -d "$current" +%Y-%m
      current=$(date -d "$current +1 month" +%Y-%m-%d)
    done
  fi
}

compute_hash() {
  local str="$1"
  if is_macos; then
    printf '%s' "$str" | md5
  elif has_command md5sum; then
    printf '%s' "$str" | md5sum | cut -d' ' -f1
  else
    printf '%s' "$str" | shasum -a 256 | cut -d' ' -f1 | head -c 32
  fi
}

make_cache_key() {
  local project="$1" branch="$2" since="$3" until="$4" variant="${5:-base-v2}"
  compute_hash "${project}|${branch}|${since}|${until}|${variant}"
}

get_cache_dir() {
  local dir="${CACHE_DIR:-/tmp}"
  mkdir -p "$dir" 2>/dev/null || true
  echo "$dir"
}
