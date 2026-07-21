#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TEST_DIR/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gitlab-stats-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

ln -s "$TEST_DIR/fake-glab" "$TMP_DIR/glab"
export PATH="$TMP_DIR:$PATH"
export GLAB_LOG="$TMP_DIR/glab.log"
export GITLAB_STATS_RETRY_DELAY=0

source "$ROOT_DIR/lib/utils.sh"
source "$ROOT_DIR/lib/format.sh"
source "$ROOT_DIR/lib/api.sh"
source "$ROOT_DIR/stats/comments.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected output to contain: $needle"
}

query=$(build_query tidio/js/frontend/operators-apps 2026-07-01 2026-07-15 develop)
[[ "$query" != *"discussions"* ]] || fail "GraphQL query still requests discussions"

base_mrs='[
  {"iid":"101","author":{"name":"Alice","username":"alice","bot":false},"mergeUser":{"name":"Alice","username":"alice","bot":false},"mergedAt":"2026-07-10T12:00:00Z","diffStatsSummary":{"additions":5,"deletions":3}},
  {"iid":"102","author":{"name":"Alice","username":"alice","bot":false},"mergeUser":{"name":"Alice","username":"alice","bot":false},"mergedAt":"2026-07-11T12:00:00Z","diffStatsSummary":{"additions":8,"deletions":2}}
]'

discussion_data=$(fetch_discussion_data tidio/js/frontend/operators-apps "$base_mrs") || fail "discussion fetch failed"
enriched=$(merge_discussion_data "$base_mrs" "$discussion_data") || fail "discussion merge failed"

[[ "$(jq '[.[] | .discussions | length] | add' <<< "$discussion_data")" -eq 4 ]] || fail "pagination/discussion count mismatch"
[[ "$(jq '[.[] | .discussions.nodes[] | .notes.nodes[0].author.username] | map(select(. == "alice")) | length' <<< "$enriched")" -eq 2 ]] || fail "resolved/first-note normalization mismatch"
[[ "$(jq '[.[] | .discussions.nodes[] | .notes.nodes[0].author.username] | map(select(. == "bot")) | length' <<< "$enriched")" -eq 2 ]] || fail "standalone/bot normalization mismatch"

author_calls=$(rg -c '^/users/' "$GLAB_LOG" || true)
[[ "$author_calls" -eq 2 ]] || fail "expected one lookup per unique author, got $author_calls"
discussion_pages=$(rg -c '/merge_requests/.*/discussions' "$GLAB_LOG" || true)
[[ "$discussion_pages" -eq 3 ]] || fail "expected paginated discussion calls, got $discussion_pages"

MR_DATA="$enriched" TOP_N=0 EXCLUDE_BOTS=true FORMAT=json
comments_output=$(stat_comments)
comments_json=$(sed -n '/^\[/,$p' <<< "$comments_output")
[[ "$(jq -r '.[0].username' <<< "$comments_json")" == alice ]] || fail "comments output author mismatch"
[[ "$(jq -r '.[0].count' <<< "$comments_json")" -eq 2 ]] || fail "comments output count mismatch"

export GLAB_MODE=retry-discussion
export GLAB_RETRY_FILE="$TMP_DIR/retry.count"
retry_data=$(fetch_discussion_data tidio/js/frontend/operators-apps '[{"iid":"102"}]') || fail "retry fetch failed"
[[ "$(<"$GLAB_RETRY_FILE")" -eq 4 ]] || fail "expected three retries before success"
unset GLAB_MODE GLAB_RETRY_FILE

if GLAB_MODE=fail-author fetch_discussion_data tidio/js/frontend/operators-apps '[{"iid":"102"}]' >"$TMP_DIR/fail.out" 2>"$TMP_DIR/fail.err"; then
  fail "author failure did not fail closed"
fi
assert_contains "$(<"$TMP_DIR/fail.err")" "MR IIDs 102"
assert_contains "$(<"$TMP_DIR/fail.err")" "GET /users/2"

export CACHE_DIR="$TMP_DIR/cache"
first_output=$(bash "$ROOT_DIR/gitlab-stats" --project tidio/js/frontend/operators-apps --since 2026-07-01 --until 2026-07-15 --stats comments --format json --no-cache 2>"$TMP_DIR/cli-first.err") || fail "CLI comments run failed"
assert_contains "$first_output" "Reviewer | Review threads started"
before_lines=$(wc -l < "$GLAB_LOG")
all_output=$(bash "$ROOT_DIR/gitlab-stats" --project tidio/js/frontend/operators-apps --since 2026-07-01 --until 2026-07-15 --stats all --format json 2>"$TMP_DIR/cli-cache.err") || fail "CLI all cached run failed"
assert_contains "$all_output" "Reviewer | Review threads started"
after_lines=$(wc -l < "$GLAB_LOG")
[[ "$before_lines" -eq "$after_lines" ]] || fail "cached all run made API calls"

echo "PASS: gitlab-stats REST discussion tests"
