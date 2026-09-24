#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TOOL="$REPO_ROOT/scripts/bin/git-local-patch"
UP="$TEST_ROOT/up.git"
LOCAL="$TEST_ROOT/local"
DEV="$TEST_ROOT/dev"

fail() { echo "FAIL: $*" >&2; exit 1; }

g() { git -c user.name=t -c user.email=t@example.invalid "$@"; }

git init -q --bare -b main "$UP"
g clone -q "$UP" "$DEV" 2>/dev/null
printf 'title\none\ntwo\nthree\nfour\nfive\nsix\nseven\n' > "$DEV/doc.md"
g -C "$DEV" add doc.md
g -C "$DEV" commit -qm init
g -C "$DEV" push -q origin main
g clone -q "$UP" "$LOCAL"

# Local-only edit, recorded by the tool.
sed -i.orig 's/^two$/two (local)/' "$LOCAL/doc.md" && rm "$LOCAL/doc.md.orig"
(cd "$LOCAL" && "$TOOL" add doc.md) >/dev/null
[[ -z "$(git -C "$LOCAL" status --porcelain)" ]] || fail "status not clean after add"
grep -qx 'two (local)' "$LOCAL/doc.md" || fail "edit lost after add"
git -C "$LOCAL" diff --cached --quiet || fail "add staged something"

# Upstream change on other lines: ff-only pull succeeds, edit reapplied.
sed -i.orig 's/^seven$/seven (upstream)/' "$DEV/doc.md" && rm "$DEV/doc.md.orig"
g -C "$DEV" commit -qam up1
g -C "$DEV" push -q origin main
git -C "$LOCAL" pull -q --ff-only || fail "ff pull 1 failed"
grep -qx 'seven (upstream)' "$LOCAL/doc.md" || fail "upstream change missing"
grep -qx 'two (local)' "$LOCAL/doc.md" || fail "edit not reapplied after pull"
[[ -z "$(git -C "$LOCAL" status --porcelain)" ]] || fail "status not clean after pull 1"

# Upstream rewrites the patched line: pull still succeeds, file is plain upstream, logged.
sed -i.orig 's/^two$/two (upstream)/' "$DEV/doc.md" && rm "$DEV/doc.md.orig"
g -C "$DEV" commit -qam up2
g -C "$DEV" push -q origin main
git -C "$LOCAL" pull -q --ff-only || fail "ff pull 2 failed"
grep -qx 'two (upstream)' "$LOCAL/doc.md" || fail "conflicting upstream change missing"
[[ -z "$(git -C "$LOCAL" status --porcelain)" ]] || fail "status not clean after pull 2"
grep -q 'doc.md: local patch no longer applies' "$LOCAL/.git/info/local-patches.log" || fail "failure not logged"
(cd "$LOCAL" && "$TOOL" list) | grep -q 'NOT APPLIED' || fail "list did not report stale patch"

# Re-record, then remove: edits stay and become visible.
sed -i.orig 's/^two (upstream)$/two (local again)/' "$LOCAL/doc.md" && rm "$LOCAL/doc.md.orig"
(cd "$LOCAL" && "$TOOL" add doc.md) >/dev/null
(cd "$LOCAL" && "$TOOL" list) | grep -q $'doc.md\tapplied' || fail "list did not report applied"
(cd "$LOCAL" && "$TOOL" remove doc.md) >/dev/null
git -C "$LOCAL" status --porcelain | grep -q '^ M doc.md' || fail "edit not visible after remove"

# Refusals.
(cd "$LOCAL" && "$TOOL" add missing.md) 2>/dev/null && fail "accepted untracked file"
git -C "$LOCAL" checkout -q -- doc.md
(cd "$LOCAL" && "$TOOL" add doc.md) 2>/dev/null && fail "accepted file without edits"

echo "ok"
