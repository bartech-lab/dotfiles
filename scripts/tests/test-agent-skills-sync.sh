#!/bin/bash
# Black-box tests for scripts/agent-skills-sync.sh. Every case uses a fake HOME under TEST_ROOT.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SYNC_BIN="${SKILLS_SYNC_BIN:-$SCRIPT_DIR/agent-skills-sync.sh}"
TEST_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/agent-skills-sync-test.XXXXXX")
MARKER=".agent-skills-sync"
CASE_N=0

cleanup() { rm -rf "$TEST_ROOT"; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [[ "$1" == "$2" ]] || fail "$3 (expected '$2', got '$1')"; }
assert_has() { printf '%s\n' "$1" | grep -F -- "$2" >/dev/null || fail "$3"; }
assert_lacks() { if printf '%s\n' "$1" | grep -F -- "$2" >/dev/null; then fail "$3"; fi; }
assert_exists() { [[ -e "$1" ]] || fail "$2 (missing $1)"; }
assert_missing() { [[ ! -e "$1" ]] || fail "$2 (unexpected $1)"; }

# new_home: sets HOME_DIR to a fresh fake home inside TEST_ROOT.
new_home() {
    CASE_N=$((CASE_N + 1))
    HOME_DIR="$TEST_ROOT/case$CASE_N/home"
    mkdir -p "$HOME_DIR"
    case "$HOME_DIR" in "$TEST_ROOT"/*) ;; *) fail "fake home escaped TEST_ROOT" ;; esac
    SYNCED="$HOME_DIR/.claude/skills/synced"
    TARGET="$HOME_DIR/.agents/skills"
    CODEX="$HOME_DIR/.codex/skills"
    mkdir -p "$TARGET"
}

# mk_skill <bundle> <name> [file content]: a skill dir with SKILL.md and a body file.
mk_skill() {
    mkdir -p "$SYNCED/$1/$2"
    echo "skill $2" > "$SYNCED/$1/$2/SKILL.md"
    echo "${3:-body}" > "$SYNCED/$1/$2/body.txt"
}

# set_mtime <bundle> <YYYYMMDDhhmm>: call after the bundle contents are final.
set_mtime() { touch -t "$2" "$SYNCED/$1"; }

# run_sync [args...]: sets OUT, ERR, RC.
run_sync() {
    local rc=0
    HOME="$HOME_DIR" bash "$SKILLS_SYNC_BIN" "$@" >"$HOME_DIR/out.txt" 2>"$HOME_DIR/err.txt" || rc=$?
    RC=$rc
    OUT=$(cat "$HOME_DIR/out.txt")
    ERR=$(cat "$HOME_DIR/err.txt")
}

snapshot() { [[ -d "$1" ]] && (cd "$1" && find . | LC_ALL=C sort) || echo "<none>"; }

assert_no_writes() {
    assert_eq "$(snapshot "$TARGET")" "." "$1: target root not empty"
    assert_missing "$HOME_DIR/.codex" "$1: .codex was created"
}

case_missing_synced_dir() {
    new_home
    run_sync
    assert_eq "$RC" 2 "missing synced dir exit"
    [[ -n "$ERR" ]] || fail "missing synced dir: no stderr message"
    assert_no_writes "missing synced dir"
}

case_no_bundle_dir() {
    new_home
    mkdir -p "$SYNCED"
    echo x > "$SYNCED/plain-file"
    run_sync
    assert_eq "$RC" 2 "no bundle exit"
    [[ -n "$ERR" ]] || fail "no bundle: no stderr message"
    assert_no_writes "no bundle"
}

case_no_skills_in_newest_bundle() {
    new_home
    mk_skill old alpha
    mkdir -p "$SYNCED/new/not-a-skill"
    echo x > "$SYNCED/new/not-a-skill/readme.txt"
    echo x > "$SYNCED/new/loose.txt"
    set_mtime old 202001010000
    set_mtime new 202101010000
    run_sync
    assert_eq "$RC" 2 "no skills exit"
    [[ -n "$ERR" ]] || fail "no skills: no stderr message"
    assert_no_writes "no skills"
}

case_missing_target_root_is_created() {
    new_home
    rmdir "$TARGET"
    mk_skill b1 alpha
    run_sync
    assert_eq "$RC" 0 "missing target root exit"
    assert_exists "$TARGET/alpha/SKILL.md" "missing target root: skill not mirrored"
}

case_newest_bundle_by_mtime_not_name() {
    new_home
    mk_skill aaa-old-by-time firstskill
    mk_skill mmm-new-by-time newskill
    mk_skill zzz-old-by-time lastskill
    set_mtime aaa-old-by-time 202001010000
    set_mtime mmm-new-by-time 202101010000
    set_mtime zzz-old-by-time 202001010000
    run_sync
    assert_eq "$RC" 0 "mtime selection exit"
    assert_exists "$TARGET/newskill/SKILL.md" "newest bundle skill mirrored"
    assert_missing "$TARGET/firstskill" "first-by-name older bundle must not be mirrored"
    assert_missing "$TARGET/lastskill" "last-by-name older bundle must not be mirrored"
}

case_ignores_non_skill_entries() {
    new_home
    mk_skill b real
    mkdir -p "$SYNCED/b/no-skill-md"
    echo x > "$SYNCED/b/no-skill-md/other.txt"
    echo x > "$SYNCED/b/plain-file"
    set_mtime b 202101010000
    run_sync
    assert_eq "$RC" 0 "ignore non-skills exit"
    assert_exists "$TARGET/real/SKILL.md" "real skill mirrored"
    assert_missing "$TARGET/no-skill-md" "dir without SKILL.md mirrored"
    assert_missing "$TARGET/plain-file" "plain file mirrored"
    assert_has "$OUT" "done: 1 skill(s) mirrored to" "done count"
}

case_full_run_mirrors_with_marker_and_nested() {
    new_home
    mk_skill b alpha
    mk_skill b beta
    mkdir -p "$SYNCED/b/alpha/sub/deep"
    echo nested > "$SYNCED/b/alpha/sub/deep/n.txt"
    set_mtime b 202101010000
    run_sync
    assert_eq "$RC" 0 "full run exit"
    for s in alpha beta; do
        assert_exists "$TARGET/$s/SKILL.md" "$s SKILL.md"
        assert_exists "$TARGET/$s/$MARKER" "$s marker"
    done
    assert_eq "$(cat "$TARGET/alpha/sub/deep/n.txt")" nested "nested file copied"
    assert_has "$OUT" "mirroring alpha -> $TARGET/alpha" "mirroring line alpha"
    assert_has "$OUT" "mirroring beta -> $TARGET/beta" "mirroring line beta"
    assert_has "$OUT" "done: 2 skill(s) mirrored to $TARGET" "done line"
    assert_has "$OUT" "note:" "note line"
}

case_dry_run_writes_nothing() {
    new_home
    mk_skill b alpha
    mk_skill b beta
    set_mtime b 202101010000
    mkdir -p "$TARGET/alpha"
    echo hand > "$TARGET/alpha/mine.txt"
    mkdir -p "$TARGET/stale"
    touch "$TARGET/stale/$MARKER"
    mkdir -p "$CODEX/legacy"
    touch "$CODEX/legacy/$MARKER"
    local before_t before_c
    before_t=$(snapshot "$TARGET")
    before_c=$(snapshot "$CODEX")
    run_sync --dry-run
    assert_eq "$RC" 0 "dry-run exit"
    assert_has "$OUT" "bundle: $SYNCED/b" "dry-run bundle line"
    assert_has "$OUT" "would mirror alpha -> $TARGET/alpha" "dry-run alpha line"
    assert_has "$OUT" "would mirror beta -> $TARGET/beta" "dry-run beta line"
    assert_eq "$(snapshot "$TARGET")" "$before_t" "dry-run changed target"
    assert_eq "$(snapshot "$CODEX")" "$before_c" "dry-run changed codex"
    assert_missing "$TARGET/alpha/$MARKER" "dry-run wrote marker"
    assert_missing "$TARGET/beta" "dry-run created beta"
}

case_dry_run_with_name_lists_only_that_skill() {
    new_home
    mk_skill b alpha
    mk_skill b beta
    set_mtime b 202101010000
    run_sync --dry-run beta
    assert_eq "$RC" 0 "dry-run name exit"
    assert_has "$OUT" "would mirror beta -> $TARGET/beta" "beta planned"
    assert_lacks "$OUT" "would mirror alpha" "alpha must not be planned"
    assert_eq "$(snapshot "$TARGET")" "." "dry-run wrote into target root"
}

case_replaced_wholesale() {
    new_home
    mk_skill b alpha
    set_mtime b 202101010000
    run_sync
    assert_eq "$RC" 0 "first sync exit"
    echo extra > "$SYNCED/b/alpha/extra.txt"
    mkdir -p "$SYNCED/b/alpha/dir"
    echo x > "$SYNCED/b/alpha/dir/x.txt"
    run_sync
    assert_exists "$TARGET/alpha/extra.txt" "new file copied"
    assert_exists "$TARGET/alpha/dir/x.txt" "new nested file copied"
    rm -rf "$SYNCED/b/alpha/extra.txt" "$SYNCED/b/alpha/dir"
    echo changed > "$SYNCED/b/alpha/body.txt"
    run_sync
    assert_eq "$RC" 0 "resync exit"
    assert_missing "$TARGET/alpha/extra.txt" "removed source file survived"
    assert_missing "$TARGET/alpha/dir" "removed source dir survived"
    assert_eq "$(cat "$TARGET/alpha/body.txt")" changed "content updated"
    assert_exists "$TARGET/alpha/$MARKER" "marker after resync"
}

case_stray_file_in_marked_target_removed() {
    new_home
    mk_skill b alpha
    set_mtime b 202101010000
    mkdir -p "$TARGET/alpha"
    touch "$TARGET/alpha/$MARKER"
    echo stray > "$TARGET/alpha/stray.txt"
    run_sync
    assert_eq "$RC" 0 "marked target resync exit"
    assert_missing "$TARGET/alpha/stray.txt" "stray file survived wholesale replace"
    assert_exists "$TARGET/alpha/SKILL.md" "skill copied over marked target"
}

case_unmarked_target_is_protected() {
    new_home
    mk_skill b alpha
    mk_skill b beta
    set_mtime b 202101010000
    mkdir -p "$TARGET/alpha"
    echo hand > "$TARGET/alpha/SKILL.md"
    echo keep > "$TARGET/alpha/mine.txt"
    run_sync
    assert_eq "$RC" 0 "protected run exit"
    assert_has "$ERR" "skipping alpha: $TARGET/alpha is not a mirrored skill" "skip message on stderr"
    assert_eq "$(cat "$TARGET/alpha/SKILL.md")" hand "hand-made SKILL.md overwritten"
    assert_eq "$(cat "$TARGET/alpha/mine.txt")" keep "hand-made file lost"
    assert_missing "$TARGET/alpha/$MARKER" "marker added to hand-made skill"
    assert_exists "$TARGET/beta/$MARKER" "other skill still mirrored"
    assert_has "$OUT" "done: 2 skill(s) mirrored to $TARGET" "skipped skill counted"
    assert_lacks "$OUT" "skipping alpha" "skip message must not be on stdout"
}

case_full_run_prunes_stale_marked_only() {
    new_home
    mk_skill b alpha
    set_mtime b 202101010000
    mkdir -p "$TARGET/stale-marked" "$TARGET/hand-made"
    touch "$TARGET/stale-marked/$MARKER"
    echo x > "$TARGET/stale-marked/SKILL.md"
    echo x > "$TARGET/hand-made/SKILL.md"
    run_sync
    assert_eq "$RC" 0 "prune run exit"
    assert_missing "$TARGET/stale-marked" "stale marked mirror kept"
    assert_exists "$TARGET/hand-made/SKILL.md" "unmarked dir pruned"
    assert_exists "$TARGET/alpha/$MARKER" "current skill mirrored"
    assert_has "$OUT" "removing stale mirror" "prune message"
}

case_full_run_removes_legacy_codex_marked_only() {
    new_home
    mk_skill b alpha
    set_mtime b 202101010000
    mkdir -p "$CODEX/alpha" "$CODEX/other" "$CODEX/hand-made"
    touch "$CODEX/alpha/$MARKER" "$CODEX/other/$MARKER"
    echo x > "$CODEX/hand-made/SKILL.md"
    run_sync
    assert_eq "$RC" 0 "legacy run exit"
    assert_missing "$CODEX/alpha" "marked codex dir (name in bundle) kept"
    assert_missing "$CODEX/other" "marked codex dir (name not in bundle) kept"
    assert_exists "$CODEX/hand-made/SKILL.md" "unmarked codex dir deleted"
    assert_has "$OUT" "removing legacy Codex mirror" "legacy message"
}

case_named_run_mirrors_only_named_and_prunes_nothing() {
    new_home
    mk_skill b alpha "new-alpha"
    mk_skill b beta "new-beta"
    set_mtime b 202101010000
    mkdir -p "$TARGET/alpha" "$TARGET/beta" "$TARGET/stale" "$CODEX/legacy"
    touch "$TARGET/alpha/$MARKER" "$TARGET/beta/$MARKER" "$TARGET/stale/$MARKER" "$CODEX/legacy/$MARKER"
    echo old > "$TARGET/beta/body.txt"
    run_sync alpha
    assert_eq "$RC" 0 "named run exit"
    assert_eq "$(cat "$TARGET/alpha/body.txt")" new-alpha "named skill mirrored"
    assert_eq "$(cat "$TARGET/beta/body.txt")" old "unnamed skill touched"
    assert_exists "$TARGET/stale/$MARKER" "named run pruned stale agents mirror"
    assert_exists "$CODEX/legacy/$MARKER" "named run removed legacy codex mirror"
    assert_has "$OUT" "done: 1 skill(s) mirrored to $TARGET" "named done count"
}

case_unknown_name_rejected() {
    new_home
    mk_skill b alpha
    mkdir -p "$SYNCED/b/no-skill-md"
    set_mtime b 202101010000
    run_sync alpha ghost
    assert_eq "$RC" 2 "unknown name exit"
    assert_has "$ERR" "skill not in bundle: ghost" "unknown name message"
    assert_no_writes "unknown name"
    run_sync no-skill-md
    assert_eq "$RC" 2 "dir without SKILL.md as name exit"
    assert_has "$ERR" "skill not in bundle: no-skill-md" "non-skill name message"
    assert_no_writes "non-skill name"
}

case_name_checked_against_newest_bundle_only() {
    new_home
    mk_skill old-bundle oldonly
    mk_skill new-bundle alpha
    set_mtime old-bundle 202001010000
    set_mtime new-bundle 202101010000
    run_sync oldonly
    assert_eq "$RC" 2 "name from older bundle exit"
    assert_has "$ERR" "skill not in bundle: oldonly" "older bundle name message"
    assert_no_writes "older bundle name"
}

main() {
    [[ -f "$SKILLS_SYNC_BIN" ]] || fail "script not found: $SKILLS_SYNC_BIN"
    local c
    for c in \
        case_missing_synced_dir \
        case_no_bundle_dir \
        case_no_skills_in_newest_bundle \
        case_missing_target_root_is_created \
        case_newest_bundle_by_mtime_not_name \
        case_ignores_non_skill_entries \
        case_full_run_mirrors_with_marker_and_nested \
        case_dry_run_writes_nothing \
        case_dry_run_with_name_lists_only_that_skill \
        case_replaced_wholesale \
        case_stray_file_in_marked_target_removed \
        case_unmarked_target_is_protected \
        case_full_run_prunes_stale_marked_only \
        case_full_run_removes_legacy_codex_marked_only \
        case_named_run_mirrors_only_named_and_prunes_nothing \
        case_unknown_name_rejected \
        case_name_checked_against_newest_bundle_only; do
        "$c"
        echo "ok: $c"
    done
    echo "All agent-skills-sync tests passed"
}

main "$@"
