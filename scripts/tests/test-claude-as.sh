#!/usr/bin/env bash
# Tests for scripts/bin/claude-as. Uses a temporary HOME and a fake `claude`.
set -euo pipefail

script="$(cd "$(dirname "$0")/.." && pwd)/bin/claude-as"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
mkdir -p "$HOME/.claude/skills" "$HOME/.claude/projects" "$tmp/bin"
echo '{}' >"$HOME/.claude/settings.json"
echo '# rules' >"$HOME/.claude/CLAUDE.md"
echo 'secret' >"$HOME/.claude/.credentials.json"
echo '{}' >"$HOME/.claude/history.jsonl"
cat >"$tmp/bin/claude" <<'EOF'
#!/usr/bin/env bash
echo "dir=$CLAUDE_CONFIG_DIR args=$*"
EOF
chmod +x "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH"

fail() { echo "FAIL: $*" >&2; exit 1; }

out=$("$script" private -c --model opus)
[[ $out == "dir=$HOME/.claude-private args=-c --model opus" ]] || fail "exec: $out"

p="$HOME/.claude-private"
for e in settings.json CLAUDE.md skills; do
    [[ -L $p/$e && $(readlink "$p/$e") == "$HOME/.claude/$e" ]] || fail "$e not linked"
done
for e in .credentials.json history.jsonl projects hooks; do
    [[ ! -e $p/$e && ! -L $p/$e ]] || fail "$e must not be shared"
done

# A source that disappears loses its link; a new source gains one.
rm "$HOME/.claude/CLAUDE.md"
mkdir "$HOME/.claude/hooks"
"$script" private >/dev/null
[[ ! -L $p/CLAUDE.md ]] || fail "dangling link kept"
[[ -L $p/hooks ]] || fail "new entry not linked"

# A real file where a link belongs is kept and reported.
rm "$p/settings.json"
echo '{"x":1}' >"$p/settings.json"
err=$("$script" private 2>&1 >/dev/null)
[[ $err == *"local copy"* ]] || fail "no warning for local copy"
[[ $(cat "$p/settings.json") == '{"x":1}' ]] || fail "local copy overwritten"

"$script" 'Bad Name' >/dev/null 2>&1 && fail "invalid name accepted"
"$script" >/dev/null 2>&1 && fail "missing name accepted"
"$script" --help | grep -q 'Usage: claude-as' || fail "--help"

echo "PASS: claude-as"
