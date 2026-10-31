#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TOOL="$REPO_ROOT/scripts/bin/pclaude"

fail() { echo "FAIL: $*" >&2; exit 1; }

export HOME="$TEST_ROOT/home"
BIN="$TEST_ROOT/bin"
mkdir -p "$HOME/.claude" "$BIN"
cat > "$BIN/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${CLAUDE_CONFIG_DIR:-unset}" "$@" > "$HOME/claude-call"
SH
chmod +x "$BIN/claude"
export PATH="$BIN:$PATH"
export CLAUDE_CONFIG_DIR=/elsewhere

P="$HOME/.claude-private"
echo '{}' > "$HOME/.claude/settings.json"

EXISTING="$HOME/existing-project"
EXISTING_WORK="$HOME/existing-work-project"
MISSING_PRIVATE="$TEST_ROOT/never-created-private"
MISSING_WORK="$TEST_ROOT/never-created-work"
mkdir -p "$EXISTING" "$EXISTING_WORK"

python3 - "$HOME/.claude.json" "$EXISTING_WORK" "$MISSING_WORK" <<'PY'
import json, sys
work = {
    "oauthAccount": {"emailAddress": "work@example.invalid"},
    "userID": "work-user",
    "projects": {
        sys.argv[2]: {"allowedTools": ["Read"]},
        sys.argv[3]: {"allowedTools": ["Bash"]},
    },
}
json.dump(work, open(sys.argv[1], "w"))
PY

mkdir -p "$P"
python3 - "$P/.claude.json" "$EXISTING" "$MISSING_PRIVATE" <<'PY'
import json, sys
priv = {
    "oauthAccount": {"emailAddress": "me@example.invalid"},
    "userID": "private-user",
    "projects": {
        sys.argv[2]: {"lastCost": 7, "hasTrustDialogAccepted": True},
        sys.argv[3]: {"lastCost": 5},
    },
}
json.dump(priv, open(sys.argv[1], "w"))
PY

[[ -d $EXISTING && ! -e $MISSING_PRIVATE && ! -e $MISSING_WORK ]] || fail "fixture directories are wrong"

"$TOOL" 2>"$TEST_ROOT/err" || fail "pclaude exited non-zero: $(cat "$TEST_ROOT/err")"

check() {
    python3 - "$P/.claude.json" "$EXISTING" "$MISSING_PRIVATE" "$MISSING_WORK" "$EXISTING_WORK" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
existing, missing_private, missing_work, existing_work = sys.argv[2:6]
p = d["projects"]
assert missing_private not in p, "private-only entry with a missing directory survived: %r" % (p,)
assert existing in p, "private-only entry with an existing directory was pruned: %r" % (p,)
assert p[existing].get("lastCost") == 7 and p[existing].get("hasTrustDialogAccepted") is True, p[existing]
assert missing_work in p, "work entry with a missing directory was pruned: %r" % (p,)
assert p[missing_work].get("allowedTools") == ["Bash"], p[missing_work]
assert existing_work in p and p[existing_work].get("allowedTools") == ["Read"], p
assert set(p) == {existing, missing_work, existing_work}, sorted(p)
assert d["userID"] == "private-user"
PY
}

check || fail "first launch: prune result is wrong"

"$TOOL" 2>"$TEST_ROOT/err" || fail "second launch exited non-zero: $(cat "$TEST_ROOT/err")"
check || fail "second launch: prune result is not stable"

echo "ok"
