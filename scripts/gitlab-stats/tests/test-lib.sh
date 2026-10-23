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

source "$ROOT_DIR/lib/api.sh"

FAKE="$TMP_DIR/fake"
mkdir -p "$FAKE/bin"
cat > "$FAKE/bin/glab" <<'GLAB'
#!/usr/bin/env bash
dir="$(dirname "$0")/.."
echo "$*" >> "$dir/calls"
if [[ "$*" == *"projects/:id"* ]]; then
  exit 1
fi
if [[ "${2:-}" == graphql ]]; then
  n=$(( $(cat "$dir/gql" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$dir/gql"
  if [[ -f "$dir/page-$n.json" ]]; then cat "$dir/page-$n.json"; exit 0; fi
  echo "boom"; exit 1
fi
n=$(( $(cat "$dir/rest" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$dir/rest"
if (( n <= ${FAKE_FAILS:-0} )); then echo "fail $n"; exit 1; fi
echo '{"ok":true}'
GLAB
chmod +x "$FAKE/bin/glab"
export PATH="$FAKE/bin:$PATH"
reset_fake() { rm -f "$FAKE"/calls "$FAKE"/gql "$FAKE"/rest "$FAKE"/page-*.json; }

[[ "$(urlencode_project org/sub/repo)" == "org%2Fsub%2Frepo" ]] || fail "urlencode_project"

repo="$TMP_DIR/repo"
git init -q "$repo"
for pair in "git@gitlab.com:org/sub/repo.git|org/sub/repo" "https://gitlab.com/org/repo.git|org/repo" "ssh://git@gitlab.com/org/repo2.git|org/repo2"; do
  git -C "$repo" remote remove origin 2>/dev/null || true
  git -C "$repo" remote add origin "${pair%%|*}"
  [[ "$(cd "$repo" && detect_project)" == "${pair##*|}" ]] || fail "detect_project for ${pair%%|*}"
done
git -C "$repo" remote set-url origin git@github.com:o/r.git
if out=$(cd "$repo" && detect_project 2>&1); then fail "a github remote was accepted"; fi
[[ "$out" == *"not hosted on gitlab.com"* ]] || fail "github remote message: $out"

reset_fake
echo '{"data":{"project":{"mergeRequests":{"nodes":[{"iid":"1"}],"pageInfo":{"hasNextPage":true,"endCursor":"c1"}}}}}' > "$FAKE/page-1.json"
echo '{"data":{"project":{"mergeRequests":{"nodes":[{"iid":"2"}],"pageInfo":{"hasNextPage":false,"endCursor":"c2"}}}}}' > "$FAKE/page-2.json"
[[ "$(fetch_all_mrs org/repo 2026-01-01 2026-01-31 main | jq -c '[.[].iid]')" == '["1","2"]' ]] || fail "pagination joins pages"
[[ "$(grep -c 'after: "c1"' "$FAKE/calls")" -eq 1 ]] || fail "second page asks after the first cursor"
[[ "$(grep -c 'after: null' "$FAKE/calls")" -eq 1 ]] || fail "first page starts with a null cursor"

reset_fake
echo '{"data":{"project":{"mergeRequests":{"nodes":[{"iid":"1"}],"pageInfo":{"hasNextPage":true,"endCursor":null}}}}}' > "$FAKE/page-1.json"
echo '{"data":{"project":{"mergeRequests":{"nodes":[{"iid":"1"}],"pageInfo":{"hasNextPage":true,"endCursor":null}}}}}' > "$FAKE/page-2.json"
out=$(fetch_all_mrs org/repo 2026-01-01 2026-01-31 main 2>&1) && fail "a next page without a cursor was accepted"
[[ "$out" == *"without a cursor"* ]] || fail "cursorless page message: $out"
[[ "$(cat "$FAKE/gql")" -eq 1 ]] || fail "a next page without a cursor is requested again"

reset_fake
echo '{"errors":[{"message":"bad field"}]}' > "$FAKE/page-1.json"
out=$(fetch_all_mrs org/repo 2026-01-01 2026-01-31 main 2>&1) && fail "graphql errors were accepted"
[[ "$out" == *"GraphQL error for project 'org/repo': bad field"* ]] || fail "graphql error message: $out"
reset_fake
echo '{"data":{"project":null}}' > "$FAKE/page-1.json"
out=$(fetch_all_mrs org/repo 2026-01-01 2026-01-31 main 2>&1) && fail "a missing project was accepted"
[[ "$out" == *"was not found or is not accessible"* ]] || fail "missing project message: $out"
reset_fake
out=$(fetch_all_mrs org/repo 2026-01-01 2026-01-31 main 2>&1) && fail "a failed request was accepted"
[[ "$out" == *"GraphQL request failed"* ]] || fail "request failure message: $out"

export GITLAB_STATS_RETRY_DELAY=0
reset_fake
[[ "$(FAKE_FAILS=3 api_get_with_retries projects/1/x 2)" == '{"ok":true}' ]] || fail "fourth attempt succeeds"
[[ "$(cat "$FAKE/rest")" -eq 4 ]] || fail "four attempts"
[[ "$(tail -1 "$FAKE/calls")" == *"-F per_page=100 -F page=2"* ]] || fail "page parameters"
reset_fake
if err=$(FAKE_FAILS=9 api_get_with_retries projects/1/x 2>&1 >/dev/null); then fail "four failures were accepted"; fi
[[ "$err" == "fail 4" ]] || fail "the last failure is reported: $err"

echo "PASS: gitlab-stats lib tests"
