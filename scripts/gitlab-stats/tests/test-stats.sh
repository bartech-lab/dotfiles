#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$TEST_DIR/.." && pwd)"

source "$ROOT_DIR/lib/utils.sh"
source "$ROOT_DIR/lib/format.sh"
source "$ROOT_DIR/stats/approvals.sh"
source "$ROOT_DIR/stats/merged-by.sh"
source "$ROOT_DIR/stats/mr-authors.sh"
source "$ROOT_DIR/stats/size-distribution.sh"
source "$ROOT_DIR/stats/throughput.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

body() {
  sed -n '3,$p'
}

MR_DATA=$(cat <<'JSON'
[
  {"iid":"1","author":{"name":"Alice","username":"zara","bot":false},"mergeUser":{"name":"Bob","username":"bob","bot":false},
   "approvedBy":{"nodes":[{"name":"Carol","username":"carol","bot":false},{"name":"Bot One","username":"bot1","bot":true}]},
   "mergedAt":"2026-01-15T10:00:00Z","diffStatsSummary":{"additions":30,"deletions":10}},
  {"iid":"2","author":{"name":"Alice","username":"zara","bot":false},"mergeUser":{"name":"Bob","username":"bob","bot":false},
   "approvedBy":{"nodes":[{"name":"Carol","username":"carol","bot":false}]},
   "mergedAt":"2026-02-03T10:00:00Z","diffStatsSummary":{"additions":40,"deletions":10}},
  {"iid":"3","author":{"name":"Renovate","username":"renovate","bot":true},"mergeUser":{"name":"Renovate","username":"renovate","bot":true},
   "approvedBy":{"nodes":[]},"mergedAt":"2026-02-10T10:00:00Z","diffStatsSummary":{"additions":600,"deletions":0}},
  {"iid":"4","author":{"name":"Bob","username":"bob","bot":false},"mergeUser":null,"approvedBy":null,
   "mergedAt":"2026-02-20T10:00:00Z","diffStatsSummary":null}
]
JSON
)
FORMAT=csv SINCE=2026-01-01 UNTIL=2026-02-28
export MR_DATA FORMAT SINCE UNTIL

[[ "$(stat_mr_authors | body)" == $'Author,MRs merged\n"Alice","2"\n"Bob","1"' ]] || fail "authors without bots"
[[ "$(EXCLUDE_BOTS=false stat_mr_authors | body)" == $'Author,MRs merged\n"Alice","2"\n"Bob","1"\n"Renovate","1"' ]] || fail "authors with bots"
[[ "$(TOP_N=1 stat_mr_authors | body)" == $'Author,MRs merged\n"Alice","2"' ]] || fail "TOP_N limits rows"
[[ "$(TOP_N=0 EXCLUDE_BOTS=false stat_mr_authors | body | wc -l | tr -d ' ')" == 4 ]] || fail "TOP_N=0 keeps every row"

[[ "$(stat_merged_by | body)" == $'Name,Count\n"Bob","2"' ]] || fail "merged-by skips bots and missing merge users"
[[ "$(EXCLUDE_BOTS=false stat_merged_by | body)" == $'Name,Count\n"Bob","2"\n"Renovate","1"' ]] || fail "merged-by with bots has no row for a missing merge user"
[[ "$(stat_approvals | body)" == $'Approver,Approvals granted\n"Carol","2"' ]] || fail "approvals skip bots and null lists"
[[ "$(EXCLUDE_BOTS=false stat_approvals | body)" == $'Approver,Approvals granted\n"Carol","2"\n"Bot One","1"' ]] || fail "approvals with bots"

[[ "$(stat_size_distribution | body)" == $'Author,MR count,S,M,L,XL\n"Alice","2","1","1","0","0"' ]] || fail "size buckets: 40 is S, 50 is M"
[[ "$(EXCLUDE_BOTS=false stat_size_distribution | body | sed -n 3p)" == '"Renovate","1","0","0","0","1"' ]] || fail "600 changes are XL"
[[ "$(BUCKETS=0,45,999999 stat_size_distribution | body)" == $'Author,MR count,S,M\n"Alice","2","1","1"' ]] || fail "custom buckets"

SIZE_DATA='[
  {"author":{"name":"Ann","username":"ann","bot":false},"diffStatsSummary":{"additions":200,"deletions":0}},
  {"author":{"name":"Ann","username":"ann","bot":false},"diffStatsSummary":{"additions":1000000,"deletions":0}},
  {"author":{"name":"Ben","username":"ben","bot":false},"diffStatsSummary":{"additions":1,"deletions":0}}
]'
[[ "$(MR_DATA=$SIZE_DATA stat_size_distribution | body | sed -n 2p)" == '"Ann","2","0","0","1","1"' ]] || fail "200 is L only and 1000000 is still XL"
[[ "$(MR_DATA=$SIZE_DATA TOP_N=1 stat_size_distribution | body | wc -l | tr -d ' ')" == 2 ]] || fail "TOP_N limits size rows"
[[ "$(MR_DATA=$SIZE_DATA BUCKETS=0,10,20,30,40,999999 stat_size_distribution | body | head -1)" == 'Author,MR count,S,M,L,XL,B4' ]] || fail "a fifth bucket is labelled B4"

[[ "$(stat_throughput | body)" == $'Author,2026-01,2026-02,Total\n"Alice","1","1","2"\n"Bob","0","1","1"' ]] || fail "throughput per author with empty months"
[[ "$(BY_AUTHOR=false stat_throughput | body)" == $'"Month","Count"\n"2026-01","1"\n"2026-02","2"' ]] || fail "overall throughput without bots"

OPEN_DATA=$(jq -c '. + [{"iid":"5","author":{"name":"Alice","username":"zara","bot":false},"mergedAt":null}]' <<< "$MR_DATA")
[[ "$(MR_DATA=$OPEN_DATA stat_throughput | body)" == $'Author,2026-01,2026-02,Total\n"Alice","1","1","2"\n"Bob","0","1","1"' ]] || fail "an unmerged MR is skipped, not fatal"
[[ "$(TOP_N=1 stat_throughput | body)" == $'Author,2026-01,2026-02,Total\n"Alice","1","1","2"' ]] || fail "TOP_N limits throughput rows"
[[ "$(UNTIL=2026-03-31 BY_AUTHOR=false stat_throughput | body)" == $'"Month","Count"\n"2026-01","1"\n"2026-02","2"\n"2026-03","0"' ]] || fail "overall throughput lists an empty month as 0"

echo "PASS: gitlab-stats stat tests"
