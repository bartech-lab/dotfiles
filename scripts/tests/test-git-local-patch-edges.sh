#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TOOL="$REPO_ROOT/scripts/bin/git-local-patch"
N=0

fail() { echo "FAIL: $*" >&2; exit 1; }

new_repo() {
  N=$((N + 1))
  R="$TEST_ROOT/repo$N"
  git init -q -b main "$R"
  git -C "$R" config user.name t
  git -C "$R" config user.email t@example.invalid
  printf 'title\none\ntwo\nthree\nfour\n' > "$R/doc.md"
  printf 'x\ny\n' > "$R/run.sh"
  chmod 755 "$R/run.sh"
  printf '\x00\x01\xff' > "$R/blob.bin"
  git -C "$R" add .
  git -C "$R" commit -qm init
}

tool() { (cd "$R" && "$TOOL" "$@"); }

attrs() { cat "$R/.git/info/attributes" 2>/dev/null || true; }

edit_two() { sed -i.orig 's/^two$/two (local)/' "$R/doc.md" && rm "$R/doc.md.orig"; }

new_repo
edit_two
git -C "$R" add doc.md
before=$(attrs)
status=0
out=$(tool add doc.md 2>&1) || status=$?
[[ $status -ne 0 ]] || fail "1: add accepted staged changes"
grep -q 'has staged changes' <<<"$out" || fail "1: message missing: $out"
[[ ! -e "$R/.git/info/local-patches/doc.md.patch" ]] || fail "1: patch created"
[[ "$(attrs)" == "$before" ]] || fail "1: attributes changed"

new_repo
printf '\x00\x01\xfe' > "$R/blob.bin"
status=0
out=$(tool add blob.bin 2>&1) || status=$?
[[ $status -ne 0 ]] || fail "2: add accepted binary file"
grep -q 'does not round-trip' <<<"$out" || fail "2: message missing: $out"
[[ ! -e "$R/.git/info/local-patches/blob.bin.patch" ]] || fail "2: patch left behind"
! attrs | grep -q 'blob.bin' || fail "2: attributes mention binary file"

new_repo
edit_two
tool add doc.md >/dev/null
tool add doc.md >/dev/null
[[ "$(attrs | grep -c 'doc.md filter=localpatch')" -eq 1 ]] || fail "3: attributes line not unique"

new_repo
edit_two
git -C "$R" update-index --skip-worktree doc.md
git -C "$R" ls-files -v doc.md | grep -q '^S ' || fail "4: precondition skip-worktree not set"
tool add doc.md >/dev/null
git -C "$R" ls-files -v doc.md | grep -q '^[Sh] ' && fail "4: still skip-worktree after add"
git -C "$R" ls-files -v doc.md | grep -q '^H ' || fail "4: unexpected flag after add"

new_repo
edit_two
tool add doc.md >/dev/null
[[ -f "$R/.git/info/local-patches/doc.md.patch" ]] || fail "5: precondition patch missing"
tool remove doc.md | grep -q 'released: doc.md' || fail "5: release message missing"
[[ ! -e "$R/.git/info/local-patches/doc.md.patch" ]] || fail "5: patch not deleted"
! attrs | grep -q 'doc.md' || fail "5: attributes line not removed"
grep -qx 'two (local)' "$R/doc.md" || fail "5: edit lost"
git -C "$R" status --porcelain | grep -q '^ M doc.md' || fail "5: file not shown as modified"

new_repo
edit_two
tool add doc.md >/dev/null
tool list | grep -q $'^doc.md\tapplied$' || fail "6: list did not report applied"
printf 'extra\n' >> "$R/doc.md"
listed=$(tool list)
grep -q $'^doc.md\tapplied, plus unrecorded edits' <<<"$listed" || fail "6: unrecorded edits not reported: $listed"
! grep -q $'^doc.md\tapplied$' <<<"$listed" || fail "6: still plain applied"

new_repo
edit_two
tool add doc.md >/dev/null
g() { git -C "$R" -c user.name=t -c user.email=t@example.invalid "$@"; }
base=$(git -C "$R" rev-parse HEAD)
LOG="$R/.git/info/local-patches.log"
: > "$LOG"
git -C "$R" checkout -q -b upstream
git -C "$R" show "$base:doc.md" | sed 's/^two$/two (upstream)/' > "$R/doc.md"
g commit -qam upstream-rewrite
git -C "$R" checkout -q "$base"
lines_old=$(wc -l < "$LOG")
git -C "$R" checkout -q upstream
lines_new=$(wc -l < "$LOG")
: > "$LOG"
listed=$(tool list)
grep -q 'NOT APPLIED' <<<"$listed" || fail "7: precondition: list did not report stale patch: $listed"
[[ "$(wc -l < "$LOG")" -eq 0 ]] || fail "7: list wrote to the log"
(( lines_new == lines_old + 1 )) || fail "7: a checkout whose patch no longer applies logs one line: before=$lines_old after=$lines_new"

new_repo
printf 'x\ny\nz\n' > "$R/run.sh"
tool add run.sh >/dev/null || fail "8: add refused executable file"
[[ -f "$R/.git/info/local-patches/run.sh.patch" ]] || fail "8: patch missing"
git -C "$R" ls-files -s run.sh | grep -q '^100755 ' || fail "8: mode changed in index"
[[ -z "$(git -C "$R" status --porcelain)" ]] || fail "8: status not clean after add"

new_repo
status=0
tool frobnicate >/dev/null 2>&1 || status=$?
[[ $status -eq 2 ]] || fail "9: unknown subcommand status $status"

new_repo
status=0
out=$(tool add 2>&1) || status=$?
[[ $status -ne 0 ]] || fail "10: add without files succeeded"
grep -q 'no files given' <<<"$out" || fail "10: message missing: $out"

echo "PASS: git-local-patch edge tests"
