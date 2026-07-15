# gitlab-stats

CLI tool to answer "who merged/approved/commented most" and other GitLab MR stats for a project and date range.

## Quick start

```bash
cd ~/Projects/some-gitlab-repo
gitlab-stats                         # defaults: last 30 days, develop, merged-by
gitlab-stats --stats all --top 5     # sprint retro — all stats, top 5
gitlab-stats --since 2026-04-01      # since April, all defaults
gitlab-stats --project tidio/js/frontend/operators-apps --stats mr-authors --top 0
```

## Prerequisites

- `glab` CLI — authenticated and logged in (`glab auth status`)
- `jq` — JSON processor
- Network access to `gitlab.com` (VPN if required)
- A GitLab repo as current directory (or `--project`)

## Options

| Flag | Default | Description |
|---|---|---|
| `--since DATE` | 30 days ago | Start date `YYYY-MM-DD` |
| `--until DATE` | today | End date `YYYY-MM-DD` |
| `--target-branch BR` | develop | Target branch (e.g. `main`) |
| `--project PROJECT` | `GITLAB_STATS_PROJECT` or auto-detect | GitLab project path, e.g. `org/group/repo` |
| `--stats LIST` | merged-by | Comma-separated stats or `all` (see below) |
| `--format FORMAT` | table | Output: `table`, `json`, `csv` |
| `--top N` | 10 | Show top N entries (`0` = all) |
| `--exclude-bots BOOL` | true | Filter out bot users |
| `--buckets LIST` | `0,50,200,500,999999` | Size bucket thresholds |
| `--by-author BOOL` | true | Throughput breakdown by author |
| `--no-cache` | — | Skip cache, fetch fresh data |
| `--help` | — | Show help |

## Stats

| Stat | Counts |
|---|---|
| `merged-by` | Who clicked the merge button |
| `mr-authors` | Whose MRs got merged |
| `approvals` | Who approved (non-bot users) |
| `comments` | Thread starters — first note of each discussion |
| `size-distribution` | MR line-change buckets (S/M/L/XL) per author |
| `throughput` | MRs merged per month, by author |

## Examples

```bash
# Sprint retro: all stats, top 10
gitlab-stats --stats all --top 10

# Since April, approvals + comments leaderboard
gitlab-stats --since 2026-04-01 --stats approvals,comments --top 5

# Export throughput for a spreadsheet
gitlab-stats --since 2026-04-01 --stats throughput --format csv > throughput.csv

# Custom size buckets
gitlab-stats --stats size-distribution --buckets "0,20,100,300,999999"

# Overall throughput without author breakdown
gitlab-stats --stats throughput --by-author false

# JSON output for scripting
gitlab-stats --since 2026-04-01 --stats all --format json > stats.json
```

## Caching

**Every run that fetches data caches the full MR payload.** The cache contains
the raw API response — nodes with author, merger, approvals, discussions,
diffStats, and dates — not pre-computed stat results. This means:

```bash
# The first run fetches everything and caches it (this is the slow part):
gitlab-stats --since 2026-04-01 --stats merged-by

# After that, run any combination of stats, formats, or --top values
# against the SAME date range — zero API calls, instant results:
gitlab-stats --since 2026-04-01 --stats approvals,comments
gitlab-stats --since 2026-04-01 --stats throughput --format csv > throughput.csv
gitlab-stats --since 2026-04-01 --stats all --top 20 --format json > stats.json
```

Each stat is just a jq filter over the same cached MR list. You only pay the
API cost once per `(project, branch, since, until, cache version)` combination.

**Cache details:**
- Base MR data is stored in `/tmp/gitlab-stats-base-<hash>.json`.
- REST-enriched discussion data is stored separately in `/tmp/gitlab-stats-discussions-<hash>.json`.
- Cache keys include `project|target_branch|since|until|cache version`, so old GraphQL discussion caches cannot be reused.
- TTL: 1 hour. Use `--no-cache` to force a fresh fetch before expiry

## Notes

- **Comments stat**: Counts all discussion thread starters (resolved included).
  Discussion data is fetched through GitLab's REST Discussions API, with full
  pagination, bounded concurrency, retries, and authoritative user bot flags.
  `comments` and `all` are slower because they make additional REST requests;
  author, merger, approval, size, and throughput stats keep the fast GraphQL path.

- **People stats**: Keyed on `username` (stable), displayed as `name`. Bot
  filtering (`--exclude-bots true`) checks the `bot` field from the API.

- **API performance**: For large date ranges (months), GraphQL fetches up to
  100 MRs per page. REST discussions fetch up to 100 discussions per page with
  four concurrent MR requests and retries transient failures.

- **Discussion failures**: Discussion and author lookups fail closed. If any
  lookup remains unsuccessful after retries, the affected MR IID and endpoint
  are reported, no partial statistics are printed, and no incomplete discussion
  cache is written.

- **Project selection**: `--project` works from any directory. You can also set
  `GITLAB_STATS_PROJECT` for repeated use; without either, the script detects a
  GitLab project from the current directory's remote.

## Structure

```
~/dotfiles/scripts/gitlab-stats/
├── gitlab-stats       # CLI entry point
├── README.md          # this file
├── lib/
│   ├── utils.sh       # OS detection, date math, hashing
│   ├── format.sh      # table / json / csv formatters
│   ├── cache.sh       # cache read/write/TTL
│   └── api.sh         # GraphQL MR metadata and REST discussion enrichment
└── stats/
    ├── merged-by.sh
    ├── mr-authors.sh
    ├── approvals.sh
    ├── comments.sh
    ├── size-distribution.sh
    └── throughput.sh
```
