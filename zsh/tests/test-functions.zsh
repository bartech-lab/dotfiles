#!/usr/bin/env zsh
emulate -R zsh
setopt err_return no_unset pipe_fail

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
REPO_ROOT=${0:A:h:h:h}

fail() { print -u2 -- "FAIL: $*"; exit 1 }

BIN="$TEST_ROOT/bin"
mkdir -p "$BIN"
for opener in open xdg-open; do
  print -rl -- '#!/bin/sh' "echo \"$opener \$*\" >> \"$TEST_ROOT/opened\"" > "$BIN/$opener"
  chmod +x "$BIN/$opener"
done
path=("$BIN" $path)

source "$REPO_ROOT/zsh/functions/30-git.zsh"

repo="$TEST_ROOT/repo"
git init -q "$repo"
cd "$repo"

out=$(git-open 2>&1) && fail "git-open without origin succeeded"
[[ $out == "No origin remote" ]] || fail "no origin message: $out"

opened() {
  rm -f "$TEST_ROOT/opened"
  git remote remove origin 2>/dev/null || true
  git remote add origin "$1"
  DOTFILES_OS=$2 git-open >/dev/null 2>&1 || true
  for _ in {1..50}; do [[ -s $TEST_ROOT/opened ]] && break; sleep 0.1; done
  cat "$TEST_ROOT/opened"
}

[[ $(opened git@github.com:o/r.git macos) == "open https://github.com/o/r" ]] || fail "ssh remote on macos"
[[ $(opened git@gitlab.com:g/sub/r.git linux) == "xdg-open https://gitlab.com/g/sub/r" ]] || fail "ssh remote with a subgroup on linux"
[[ $(opened https://github.com/o/r.git macos) == "open https://github.com/o/r" ]] || fail "https remote drops .git"
[[ $(opened https://github.com/o/r macos) == "open https://github.com/o/r" ]] || fail "https remote without .git"
[[ $(opened git@ssh.dev.azure.com:v3/org/proj/repo macos) == "open https://dev.azure.com/org/proj/_git/repo" ]] || fail "azure ssh remote on macos"
[[ $(opened git@ssh.dev.azure.com:v3/org/proj/repo linux) == "xdg-open https://dev.azure.com/org/proj/_git/repo" ]] || fail "azure ssh remote on linux"

cd "$TEST_ROOT"
source "$REPO_ROOT/zsh/functions/42-tfg.zsh"

HOME="$TEST_ROOT/home"
work="$HOME/volunteer/tokens-for-good"
mkdir -p "$work/app/src" "$HOME/volunteer/bin"

out=$(tfg --help) || fail "tfg --help failed"
[[ $out == Usage:* ]] || fail "tfg --help prints usage"
for bad in "1 2" abc 0 -1 "--codex x"; do
  tfg ${(z)bad} 2>/dev/null && fail "tfg $bad succeeded"
  (( $? == 2 )) || fail "tfg $bad exits 2"
done

print -rl -- '#!/bin/sh' "echo \"\$TFG_API_KEY|\$*\" > \"$TEST_ROOT/ran\"" > "$HOME/volunteer/bin/tfg-run"
chmod +x "$HOME/volunteer/bin/tfg-run"
out=$(TFG_API_KEY=k tfg 2>&1) && fail "tfg without mcp-server.js succeeded"
[[ $out == *"is not set up."* ]] || fail "missing mcp-server.js message: $out"
touch "$work/app/src/mcp-server.js"
chmod -x "$HOME/volunteer/bin/tfg-run"
out=$(TFG_API_KEY=k tfg 2>&1) && fail "tfg with a non-executable tfg-run succeeded"
[[ $out == *"is not set up."* ]] || fail "non-executable tfg-run message: $out"
chmod +x "$HOME/volunteer/bin/tfg-run"

out=$(path=("$BIN"); TFG_API_KEY=k tfg 2>&1) && fail "tfg without claude succeeded"
[[ $out == *"claude is not installed"* ]] || fail "missing agent message: $out"
for agent in claude codex; do
  print -rl -- '#!/bin/sh' > "$BIN/$agent"
  chmod +x "$BIN/$agent"
done
rehash

out=$(unset TFG_API_KEY; tfg </dev/null 2>&1) && fail "tfg without a key and a terminal succeeded"
[[ $out == *"Run in a terminal"* ]] || fail "no terminal message: $out"
[[ ! -e $HOME/.zshenv ]] || fail "tfg without a key wrote ~/.zshenv"

(typeset +x TFG_API_KEY=k1; tfg) || fail "tfg with a key failed"
[[ $(<"$TEST_ROOT/ran") == "k1|" ]] || fail "an unexported key is exported to tfg-run with no arguments"
TFG_API_KEY=k2 tfg 3 || fail "tfg 3 failed"
[[ $(<"$TEST_ROOT/ran") == "k2|3" ]] || fail "count is passed through"
TFG_API_KEY=k3 tfg --codex 12 || fail "tfg --codex 12 failed"
[[ $(<"$TEST_ROOT/ran") == "k3|--codex 12" ]] || fail "codex flag and count are passed through"

print -- "PASS: zsh function tests"
