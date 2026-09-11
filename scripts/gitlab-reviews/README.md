# gitlab-reviews

Collects a GitLab reviewer's discussion openers into a per-reviewer ledger, so their
review decisions can be curated into durable guidance instead of being re-litigated.

Repository-agnostic. Run it from the checkout you want to collect for; ledgers and
verdicts are written there, not here.

## Use

```bash
cd ~/Projects/some-gitlab-repo
HR_USERS=alice,bob node ~/dotfiles/scripts/gitlab-reviews/harvestHumanReviews.mjs
HR_OUT=tools-local/human-reviews/<repo>-alice.json node ~/dotfiles/scripts/gitlab-reviews/reviewHumanReviews.mjs
```

One scan serves every reviewer in `HR_USERS`; each discussion is inspected once per
reviewer. A rerun preserves every recorded verdict and returns only comments that are
new, edited, or whose discussion changed.

## Config

Defaults live outside this repository, which is public and names no reviewer or
project. Write them to `~/.config/gitlab-reviews/config.json`, or point `HR_CONFIG`
elsewhere. Every key is optional; without one, the CLI names the variable it needs.

```json
{
  "repository": "some-gitlab-repo",
  "projectId": "1234567",
  "user": "alice",
  "userId": 42,
  "since": "2026-01-01",
  "ledgerDir": "tools-local/human-reviews"
}
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `HR_CONFIG` | `~/.config/gitlab-reviews/config.json` | Where the defaults above are read from |
| `HR_USERS` | `HR_USER`, else config `user` | Comma-separated reviewers, collected in one scan |
| `HR_REPO` | config `repository` | Key into the repository config |
| `HR_REPOS` | `tools-local/repos.json` | Repository config, read from the working directory |
| `HR_SINCE` | config `since`, else `1970-01-01` | Inclusive lower bound on comment creation |
| `HR_UNTIL` | start of the run | Inclusive upper bound |
| `HR_OUT` | `tools-local/human-reviews/<repo>-<user>.json` | Single-reviewer runs only |
| `HR_CONCURRENCY` | `4` | Concurrent merge request reads |

## Review commands

```bash
node .../reviewHumanReviews.mjs                      # open candidates
node .../reviewHumanReviews.mjs --short              # short candidates grouped
node .../reviewHumanReviews.mjs --status applied
node .../reviewHumanReviews.mjs --set <id> applied "reason"
```

`--short` groups the brief open candidates by normalised text. A group repeating several
times is a sign-off, not a finding: add a whole-comment pattern to
`processOnlyPatterns.json` rather than rejecting each one by hand. Do this before the
first curation pass on a new reviewer; every reviewer so far has needed it once.

## What it does and does not establish

It reads GitLab and writes only local files. Collecting a comment does not mean the
suggestion was correct, and thread resolution does not either. Verify every claim against
current source before recording it anywhere.

The API exposes currently available comments. It does not expose deleted comments or
earlier versions of an edited one, so coverage is complete only for what still exists.

A candidate carries `selfAuthored` when the reviewer also wrote the merge request. Such a
comment is a self-review note rather than a finding against another author; most are
closing notes.

## Tests

```bash
node --test ~/dotfiles/scripts/gitlab-reviews/humanReviews.test.mjs
```

## Requires

`glab`, authenticated. Node 18 or newer.
