#!/bin/bash
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
INFOLOG="$CONF/pull.log"
LIMIT=5242880

fail() { echo "FAIL: $*" >&2; exit 1; }

g() { git -c user.name=t -c user.email=t@example.invalid "$@"; }

publish() {
    printf '%s\n' "$1" > "$DEV/f"
    g -C "$DEV" commit -qam "$1"
    g -C "$DEV" push -q origin main
}

fsize() { wc -c < "$1" | tr -d ' '; }

mkfile() { head -c "$1" /dev/zero | tr '\0' 'x' > "$2"; }

run_tool() {
    set +e
    "${TOOL[@]}" >/dev/null 2>&1
    RC=$?
    set -e
}

mkdir -p "$HOME/Projects" "$CONF"
git init -q --bare -b main "$UP"
g clone -q "$UP" "$DEV" 2>/dev/null
printf 'v1\n' > "$DEV/f"
g -C "$DEV" add f
g -C "$DEV" commit -qm v1
g -C "$DEV" push -q origin main

g clone -q "$UP" "$HOME/Projects/ok"
printf '%s\n' "$HOME/Projects/ok:main" > "$CONF/repos.conf"

# Test 1: a branchless config line fails the run but valid repos still update.
publish v2
mkdir -p "$HOME/Projects/nobranch" "$HOME/Projects/nobranch2"
cat > "$CONF/repos.conf" <<CONF
$HOME/Projects/ok:main
$HOME/Projects/nobranch
$HOME/Projects/nobranch2:
CONF
run_tool
[[ "$RC" -eq 1 ]] || fail "branchless config lines must exit 1, got $RC"
[[ "$(cat "$HOME/Projects/ok/f")" == v2 ]] || fail "valid repo was not fast-forwarded next to a branchless line"
grep -q "Missing configured branch for $HOME/Projects/nobranch$" "$ERRLOG" || fail "no 'Missing configured branch' line for path without colon: $(cat "$ERRLOG" 2>/dev/null)"
grep -q "Missing configured branch for $HOME/Projects/nobranch2$" "$ERRLOG" || fail "no 'Missing configured branch' line for path with empty branch: $(cat "$ERRLOG" 2>/dev/null)"
echo "ok: branchless config line exits 1 and valid repo still updates"

# Test 2: a log over the limit is rotated, exact size preserved in .1.
printf '%s\n' "$HOME/Projects/ok:main" > "$CONF/repos.conf"
rm -f "$CONF"/*.log "$CONF"/*.log.1
mkfile $((LIMIT + 1)) "$INFOLOG"
publish v3
run_tool
[[ -f "$INFOLOG.1" ]] || fail "pull.log of $((LIMIT + 1)) bytes was not rotated to pull.log.1"
[[ "$(fsize "$INFOLOG.1")" -eq $((LIMIT + 1)) ]] || fail "pull.log.1 size is $(fsize "$INFOLOG.1"), expected $((LIMIT + 1))"
[[ ! -f "$INFOLOG" || "$(fsize "$INFOLOG")" -lt 100000 ]] || fail "new pull.log is not small: $(fsize "$INFOLOG")"
echo "ok: pull.log of limit+1 bytes rotates"

# Test 3: a log of exactly the limit is not rotated.
rm -f "$CONF"/*.log "$CONF"/*.log.1
mkfile "$LIMIT" "$INFOLOG"
publish v4
run_tool
[[ ! -e "$INFOLOG.1" ]] || fail "pull.log of exactly $LIMIT bytes was rotated"
[[ "$(fsize "$INFOLOG")" -gt "$LIMIT" ]] || fail "pull.log of exactly $LIMIT bytes did not grow: $(fsize "$INFOLOG")"
echo "ok: pull.log of exactly the limit is not rotated"

# Test 4: rotation replaces an older .1 and also applies to error.log.
rm -f "$CONF"/*.log "$CONF"/*.log.1
printf 'old\n' > "$ERRLOG.1"
mkfile $((LIMIT + 1)) "$ERRLOG"
run_tool
[[ -f "$ERRLOG.1" ]] || fail "error.log over the limit was not rotated"
[[ "$(fsize "$ERRLOG.1")" -eq $((LIMIT + 1)) ]] || fail "error.log.1 size is $(fsize "$ERRLOG.1"), the older .1 was not replaced"
echo "ok: error.log over the limit rotates and replaces the older .1"

# Test 5: ~/dotfiles is scheduled without a repos.conf entry.
rm -f "$CONF/repos.conf" "$CONF"/*.log "$CONF"/*.log.1
rm -rf "$HOME/Projects/ok"
g clone -q "$UP" "$HOME/dotfiles"
publish v5
new=$(git -C "$DEV" rev-parse HEAD)
[[ "$(git -C "$HOME/dotfiles" rev-parse HEAD)" != "$new" ]] || fail "setup: dotfiles clone is already current"
run_tool
[[ "$(git -C "$HOME/dotfiles" rev-parse HEAD)" == "$new" ]] || fail "\$HOME/dotfiles was not fast-forwarded without a config entry (rc=$RC): $(cat "$ERRLOG" 2>/dev/null)"
echo "ok: ~/dotfiles is auto-scheduled and fast-forwarded"

echo "PASS: git-auto-pull edge tests"
