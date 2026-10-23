#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TEST_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gitlab-stats-lib.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

source "$ROOT_DIR/lib/utils.sh"
source "$ROOT_DIR/lib/cache.sh"
source "$ROOT_DIR/lib/format.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

months=$(get_months_between 2025-11-20 2026-02-03 | tr '\n' ' ')
[[ "$months" == "2025-11 2025-12 2026-01 2026-02 " ]] || fail "months across a year end: $months"
[[ "$(get_months_between 2026-03-31 2026-03-01)" == "2026-03" ]] || fail "same month is listed once"
[[ -z "$(get_months_between 2026-04-01 2026-03-31)" ]] || fail "an end before the start lists nothing"

[[ "$(make_cache_key p b 2026-01-01 2026-02-01)" != "$(make_cache_key p b 2026-01-01 2026-02-02)" ]] || fail "cache key ignores until"
[[ "$(make_cache_key p b s u)" == "$(make_cache_key p b s u base-v2)" ]] || fail "cache key default variant is base-v2"
[[ "$(make_cache_key p b s u)" != "$(make_cache_key p b s u other)" ]] || fail "cache key ignores variant"

cache="$TMP_DIR/sub/dir/c.json"
cache_write "$cache" '[1,2]' || fail "cache_write into a new directory"
[[ "$(cache_read "$cache")" == "[1,2]" ]] || fail "cache round trip"
compgen -G "$TMP_DIR/sub/dir/c.json.tmp.*" >/dev/null && fail "cache_write left a temp file"
cache_valid "$cache" || fail "a fresh array cache is valid"
cache_write "$cache" '{"a":1}'
cache_valid "$cache" && fail "a non-array cache is invalid"
cache_write "$cache" '[1]'
CACHE_TTL=0 cache_valid "$cache" && fail "an expired cache is invalid"
touch -t 203001010000 "$cache"
cache_valid "$cache" && fail "a cache dated in the future is invalid"
cache_valid "$TMP_DIR/missing.json" && fail "a missing cache is invalid"
[[ -z "$(cache_read "$TMP_DIR/missing.json")" ]] || fail "reading a missing cache prints nothing"
cache_clear "$cache"
[[ ! -e "$cache" ]] || fail "cache_clear removes the file"

rows='[{"name":"Al, Jr.","n":2}]'
[[ "$(FORMAT=csv format_results "$rows" '[.name, .n]' 'Name|Count')" == $'Name,Count\n"Al, Jr.",2' ]] || fail "csv quotes a comma and uses comma headers"
table=$(FORMAT=table format_results "$rows" '[.name, .n]' 'Name|Count')
[[ "$(head -1 <<< "$table" | tr -s ' ')" == "Name Count" ]] || fail "table header"
[[ "$table" == *"Al, Jr."*"2"* ]] || fail "table row"
[[ -z "$(format_results '[]' '[.name]' 'Name')" ]] || fail "no rows print nothing"
[[ "$(FORMAT=json format_results "$rows" '[.name]' 'Name' | jq -c .)" == '[{"name":"Al, Jr.","n":2}]' ]] || fail "json passes rows through"

echo "PASS: gitlab-stats lib tests"
