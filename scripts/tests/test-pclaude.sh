#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TOOL="$REPO_ROOT/scripts/bin/pclaude"

fail() { echo "FAIL: $*" >&2; exit 1; }

export HOME="$TEST_ROOT/home"
BIN="$TEST_ROOT/bin"
mkdir -p "$HOME/.claude/skills" "$HOME/.claude/projects" "$BIN"
cat > "$BIN/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "${CLAUDE_CONFIG_DIR:-unset}" "$@" > "$HOME/claude-call"
SH
chmod +x "$BIN/claude"
export PATH="$BIN:$PATH"
export CLAUDE_CONFIG_DIR=/elsewhere

B="$HOME/.claude"
P="$HOME/.claude-private"
echo '{}' > "$B/settings.json"
echo '{"work":"token"}' > "$B/.credentials.json"
echo '{}' > "$B/policy-limits.json"
echo '{}' > "$B/remote-settings.json"
echo 'x' > "$B/.last-cleanup"
echo 'x' > "$B/.last-update-result.json"
cat > "$HOME/.claude.json" <<'JSON'
{
  "oauthAccount": {"emailAddress": "work@example.invalid"},
  "userID": "work-user",
  "mcpServers": {"exa": {"type": "http"}},
  "autoUpdates": false,
  "projects": {
    "/a": {"hasTrustDialogAccepted": true, "mcpServers": {"x": {}}, "lastCost": 9},
    "/b": {"allowedTools": ["Bash"]}
  }
}
JSON

# A private-only file that existed before must survive.
mkdir -p "$P"
cat > "$P/.claude.json" <<'JSON'
{
  "oauthAccount": {"emailAddress": "me@example.invalid"},
  "userID": "private-user",
  "mcpServers": {"stale": {}},
  "projects": {"/b": {"lastCost": 1, "disabledMcpServers": ["old"]}}
}
JSON
echo '{"private":"token"}' > "$P/.credentials.json"
ln -s "$B/gone" "$P/gone"
ln -s "$B/.last-cleanup" "$P/.last-cleanup"

"$TOOL" -c --model x

call=(); while IFS= read -r l; do call+=("$l"); done < "$HOME/claude-call"
[[ ${call[0]} == "$P" ]] || fail "CLAUDE_CONFIG_DIR is ${call[0]}, want $P"
[[ "${call[*]:1}" == "-c --model x" ]] || fail "args not passed through: ${call[*]:1}"

for e in settings.json skills projects; do
    [[ -L $P/$e && $(readlink "$P/$e") == "$B/$e" ]] || fail "$e is not linked to $B/$e"
done
for e in policy-limits.json remote-settings.json .last-cleanup .last-update-result.json; do
    [[ ! -e $P/$e ]] || fail "$e must not be shared"
done
[[ ! -L $P/.credentials.json ]] || fail ".credentials.json is a link"
grep -q private "$P/.credentials.json" || fail "private login was overwritten"
[[ ! -L $P/gone ]] || fail "broken link was kept"

python3 - "$P/.claude.json" <<'PY' || fail "private .claude.json merge is wrong"
import json, sys
d = json.load(open(sys.argv[1]))
assert d["oauthAccount"]["emailAddress"] == "me@example.invalid", d["oauthAccount"]
assert d["userID"] == "private-user"
assert d["mcpServers"] == {"exa": {"type": "http"}}, d["mcpServers"]
assert d["autoUpdates"] is False
assert d["projects"]["/a"] == {"hasTrustDialogAccepted": True, "mcpServers": {"x": {}}}, d["projects"]["/a"]
assert d["projects"]["/b"] == {"lastCost": 1, "allowedTools": ["Bash"]}, d["projects"]["/b"]
PY
[[ $(stat -c %a "$P/.claude.json" 2>/dev/null || stat -f %Lp "$P/.claude.json") == 600 ]] \
    || fail ".claude.json is not mode 600"

# A state file Claude Code replaced by rename stays local without a warning.
echo 'y' > "$P/.last-update-result.json"
"$TOOL" 2>"$TEST_ROOT/err"
! grep -q "last-update-result" "$TEST_ROOT/err" || fail "warned about a per-account state file"
grep -q y "$P/.last-update-result.json" || fail "per-account state file was touched"

# A real file where a link belongs is left alone.
rm "$P/settings.json"
echo '{"local":1}' > "$P/settings.json"
"$TOOL" 2>"$TEST_ROOT/err"
grep -q local "$P/settings.json" || fail "local copy was overwritten"
grep -q "local copy" "$TEST_ROOT/err" || fail "no warning for local copy"

# Before the first /login, the work login must not be shared.
rm "$P/.credentials.json"
"$TOOL" 2>/dev/null
[[ ! -e $P/.credentials.json && ! -L $P/.credentials.json ]] || fail "work login is shared"

# A new entry in ~/.claude is picked up on the next launch.
mkdir "$B/agents"
"$TOOL" 2>/dev/null
[[ -L $P/agents ]] || fail "new entry agents was not linked"

# mcp subcommands write the default config.
"$TOOL" mcp add foo
call=(); while IFS= read -r l; do call+=("$l"); done < "$HOME/claude-call"
[[ ${call[0]} == unset ]] || fail "mcp ran with CLAUDE_CONFIG_DIR=${call[0]}"

echo "ok"
