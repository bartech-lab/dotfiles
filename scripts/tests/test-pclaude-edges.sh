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

B="$HOME/.claude"
P="$HOME/.claude-private"

mode() {
    if [[ $(uname) == Darwin ]]; then stat -f %Lp "$1"; else stat -c %a "$1"; fi
}

launch() { "$TOOL" 2>"$TEST_ROOT/err" || fail "pclaude exited non-zero: $(cat "$TEST_ROOT/err")"; }

jsonget() {
    python3 - "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for k in sys.argv[2].split("/"):
    if k == "":
        continue
    if not isinstance(d, dict) or k not in d:
        print("MISSING")
        sys.exit(0)
    d = d[k]
print(json.dumps(d))
PY
}

write_base() {
    python3 - "$HOME/.claude.json" "$1" <<'PY'
import json, sys
open(sys.argv[1], "w").write(sys.argv[2])
PY
}

mkdir -p "$B/sessions" "$B/jobs" "$B/skills"
echo '{}' > "$B/settings.json"
echo 'h' > "$B/history.jsonl"
echo 'n' > "$B/notes.txt"
echo '{}' > "$B/old.json"

mkdir -p "$P"
chmod 755 "$P"
ln -s "$B/old.json" "$P/old.json"
echo '{}' > "$TEST_ROOT/elsewhere.json"
ln -s "$TEST_ROOT/elsewhere.json" "$P/elsewhere.json"
ln -s "$B/missing-target" "$P/dangling"
echo '{"oauthAccount":{"emailAddress":"me@example.invalid"},"userID":"private-user"}' > "$P/.claude.json"
chmod 644 "$P/.claude.json"

write_base '{
  "oauthAccount": {"emailAddress": "work@example.invalid"},
  "userID": "work-user",
  "mcpServers": {"exa": {"type": "http"}},
  "codeReviewLastEffort": "high",
  "diffSidebarOpen": true,
  "projects": {
    "/a": {"allowedTools": ["Bash"], "hasTrustDialogAccepted": true},
    "/b": {"allowedTools": ["Read"], "lastCost": 3}
  }
}'

launch

[[ $(readlink "$P/skills") == "$B/skills" ]] || fail "directory skills not linked"

[[ ! -e $P/sessions && ! -L $P/sessions ]] || fail "sessions was linked"
[[ ! -e $P/jobs && ! -L $P/jobs ]] || fail "jobs was linked"

[[ -L $P/history.jsonl ]] || fail "history.jsonl is not a symlink"
[[ $(readlink "$P/history.jsonl") == "$B/history.jsonl" ]] || fail "history.jsonl points to $(readlink "$P/history.jsonl")"
[[ ! -e $P/notes.txt && ! -L $P/notes.txt ]] || fail "notes.txt was linked"

[[ $(mode "$P") == 700 ]] || fail "profile dir mode is $(mode "$P"), want 700"

[[ ! -L $P/old.json ]] || fail "stale link into unshared base file was kept"
[[ -L $P/elsewhere.json ]] || fail "link pointing outside ~/.claude was removed"
[[ $(readlink "$P/elsewhere.json") == "$TEST_ROOT/elsewhere.json" ]] || fail "outside link was retargeted"
[[ ! -L $P/dangling ]] || fail "dangling link was kept"

[[ $(jsonget "$P/.claude.json" oauthAccount/emailAddress) == '"me@example.invalid"' ]] || fail "oauthAccount in profile changed"
[[ $(jsonget "$P/.claude.json" userID) == '"private-user"' ]] || fail "userID in profile changed"
[[ $(jsonget "$P/.claude.json" codeReviewLastEffort) == '"high"' ]] || fail "codeReviewLastEffort not copied"
[[ $(jsonget "$P/.claude.json" diffSidebarOpen) == true ]] || fail "diffSidebarOpen not copied"
[[ $(jsonget "$P/.claude.json" mcpServers/exa/type) == '"http"' ]] || fail "mcpServers not copied"
python3 - "$P/.claude.json" <<'PY' || fail "project keys not copied as expected"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["projects"]["/a"]["allowedTools"] == ["Bash"], d["projects"]
assert d["projects"]["/b"]["allowedTools"] == ["Read"], d["projects"]
assert "lastCost" not in d["projects"]["/b"], d["projects"]
PY
[[ $(mode "$P/.claude.json") == 600 ]] || fail ".claude.json mode is $(mode "$P/.claude.json"), want 600"

write_base '{
  "oauthAccount": {"emailAddress": "work@example.invalid"},
  "userID": "work-user",
  "mcpServers": {"exa": {"type": "http"}},
  "diffSidebarOpen": true,
  "projects": {
    "/a": {"hasTrustDialogAccepted": true},
    "/b": {"allowedTools": ["Read"], "lastCost": 3}
  }
}'
launch
[[ $(jsonget "$P/.claude.json" codeReviewLastEffort) == MISSING ]] || fail "removed codeReviewLastEffort stayed in profile"
python3 - "$P/.claude.json" <<'PY' || fail "per-project allowedTools removal wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert "allowedTools" not in d["projects"]["/a"], d["projects"]["/a"]
assert d["projects"]["/a"]["hasTrustDialogAccepted"] is True
assert d["projects"]["/b"]["allowedTools"] == ["Read"]
PY
[[ $(jsonget "$P/.claude.json" mcpServers/exa/type) == '"http"' ]] || fail "unrelated mcpServers lost"

write_base '{
  "oauthAccount": {"emailAddress": "work@example.invalid"},
  "userID": "work-user",
  "diffSidebarOpen": true,
  "projects": {
    "/a": {"hasTrustDialogAccepted": true},
    "/b": {"allowedTools": ["Read"]}
  }
}'
chmod 644 "$P/.claude.json"
launch
[[ $(jsonget "$P/.claude.json" mcpServers) == MISSING ]] || fail "removed mcpServers stayed in profile"
[[ $(jsonget "$P/.claude.json" oauthAccount/emailAddress) == '"me@example.invalid"' ]] || fail "oauthAccount changed on later launch"
[[ $(jsonget "$P/.claude.json" userID) == '"private-user"' ]] || fail "userID changed on later launch"
[[ $(mode "$P/.claude.json") == 600 ]] || fail ".claude.json mode after change is $(mode "$P/.claude.json"), want 600"

rm -rf "$P"
launch
[[ $(jsonget "$P/.claude.json" oauthAccount) == MISSING ]] || fail "oauthAccount copied into fresh profile"
[[ $(jsonget "$P/.claude.json" userID) == MISSING ]] || fail "userID copied into fresh profile"
[[ $(mode "$P") == 700 ]] || fail "fresh profile dir mode is $(mode "$P"), want 700"

mkdir -p "$B/.hidden-dir"
launch
[[ -L "$P/.hidden-dir" && $(readlink "$P/.hidden-dir") == "$B/.hidden-dir" ]] || fail "hidden directory was not shared"

rm -f "$HOME/.claude.json" "$HOME/claude-call"
launch
[[ $(head -n 1 "$HOME/claude-call") == "$P" ]] || fail "pclaude did not start claude without ~/.claude.json"

echo "PASS: pclaude edge tests"
