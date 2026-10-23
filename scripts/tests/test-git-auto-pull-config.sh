#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TOOL=(bash "$REPO_ROOT/git-auto-pull/pull.sh")
export HOME="$TEST_ROOT/home"
UP="$TEST_ROOT/up.git"
DEV="$TEST_ROOT/dev"
CONF="$HOME/.config/git-auto-pull"
ERRLOG="$CONF/error.log"

fail() { echo "FAIL: $*" >&2; exit 1; }

g() { git -c user.name=t -c user.email=t@example.invalid "$@"; }

mkdir -p "$HOME/Projects" "$HOME/elsewhere" "$CONF"
git init -q --bare -b main "$UP"
g clone -q "$UP" "$DEV" 2>/dev/null
printf 'v1\n' > "$DEV/f"
g -C "$DEV" add f
g -C "$DEV" commit -qm v1
g -C "$DEV" push -q origin main

g clone -q "$UP" "$HOME/elsewhere/repo"
printf 'v2\n' > "$DEV/f"
g -C "$DEV" commit -qam v2
g -C "$DEV" push -q origin main

cat > "$CONF/repos.conf" <<'CONF'
# ~/missing/repo:main
   # ~/also-missing:main
~/elsewhere/repo/ : main
~/elsewhere/repo:main
CONF
"${TOOL[@]}" >/dev/null 2>&1 || true
[[ "$(cat "$HOME/elsewhere/repo/f")" == v2 ]] || fail "a ~ path with a trailing slash in repos.conf is pulled"
if grep -q "missing" "$ERRLOG" 2>/dev/null; then fail "a commented repos.conf line was read: $(cat "$ERRLOG")"; fi
grep -q "Duplicate repository configuration ignored for $HOME/elsewhere/repo$" "$ERRLOG" || fail "the same repo with and without a trailing slash is one entry: $(cat "$ERRLOG" 2>/dev/null)"

rm -f "$ERRLOG" "$CONF/repos.conf"
for n in a b; do
    g clone -q "$UP" "$HOME/Projects/$n"
    git -C "$HOME/Projects/$n" remote set-url origin "https://user$n@unreachable.invalid/x/$n.git"
done
"${TOOL[@]}" >/dev/null 2>&1 || true
[[ "$(grep -c "Skipped all unreachable.invalid repositories" "$ERRLOG")" -eq 1 ]] || fail "https remotes with different users share one host probe: $(cat "$ERRLOG")"

echo "PASS: git-auto-pull config tests"
