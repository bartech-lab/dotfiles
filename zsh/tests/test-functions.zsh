#!/usr/bin/env zsh
emulate -R zsh
setopt err_return no_unset pipe_fail

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
REPO_ROOT=${0:A:h:h:h}

fail() { print -u2 -- "FAIL: $*"; exit 1 }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

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

source "$REPO_ROOT/zsh/functions/61-discord.zsh"

HOME="$TEST_ROOT/dhome"
mkdir -p "$HOME"
unset XDG_CONFIG_HOME XDG_DATA_HOME
DOTFILES_OS=macos
[[ $(_discord_config_dir) == "$HOME/Library/Application Support/discord" ]] || fail "macos config dir"
[[ $(_discord_backup_dir) == "$HOME/Library/OpenAsarPersist" ]] || fail "macos backup dir"
[[ $(_discord_asar_path) == /Applications/Discord.app/Contents/Resources/app.asar ]] || fail "macos asar path"

DOTFILES_OS=linux
[[ $(_discord_config_dir) == "$HOME/.config/discord" ]] || fail "linux config dir default"
[[ $(XDG_CONFIG_HOME=/x/cfg _discord_config_dir) == /x/cfg/discord ]] || fail "linux config dir honours XDG_CONFIG_HOME"
[[ $(_discord_backup_dir) == "$HOME/.local/share/OpenAsarPersist" ]] || fail "linux backup dir default"
[[ $(XDG_DATA_HOME=/x/data _discord_backup_dir) == /x/data/OpenAsarPersist ]] || fail "linux backup dir honours XDG_DATA_HOME"

if [[ ! -d /opt/discord && ! -d /usr/lib/discord ]]; then
  out=$(discord-openasar-status)
  [[ $out == *"Discord:       not installed"* ]] || fail "status without discord: $out"
  [[ $out == *"app.asar:      missing"* && $out == *"settings:      missing"* ]] || fail "status without files: $out"
  [[ $out == *"Backups:       none"* && $out == *"OpenAsar src:  not downloaded"* ]] || fail "status without backups: $out"

  app="$HOME/.local/share/discord"
  mkdir -p "$app/resources" "$HOME/.config/discord" "$HOME/.local/share/OpenAsarPersist/backups"
  [[ $(_discord_asar_path) == "$app/resources/app.asar" ]] || fail "linux asar path under the found app dir"
  head -c 99999 /dev/zero > "$app/resources/app.asar"
  print -r -- '{"openasar": {}}' > "$HOME/.config/discord/settings.json"
  out=$(discord-openasar-status)
  [[ $out == *"Discord:       found at $app"* ]] || fail "status finds the user app dir: $out"
  [[ $out == *"app.asar:      99999 bytes  (likely OpenAsar)"* ]] || fail "a small asar is OpenAsar: $out"
  [[ $out == *"settings:      OpenAsar configured"* ]] || fail "openasar settings: $out"
  [[ $out == *"Backups:       none"* ]] || fail "an empty backups dir is none: $out"

  head -c 100000 /dev/zero > "$app/resources/app.asar"
  print -r -- '{"other": 1}' > "$HOME/.config/discord/settings.json"
  print -r -- old > "$HOME/.local/share/OpenAsarPersist/backups/b-old"
  touch -t 202001010000 "$HOME/.local/share/OpenAsarPersist/backups/b-old"
  print -r -- new > "$HOME/.local/share/OpenAsarPersist/backups/a-new"
  print -r -- src > "$HOME/.local/share/OpenAsarPersist/openasar.app.asar"
  out=$(discord-openasar-status)
  [[ $out == *"(likely stock Discord)"* ]] || fail "a 100000-byte asar is stock: $out"
  [[ $out == *"settings:      no OpenAsar config"* ]] || fail "settings without openasar: $out"
  [[ $out == *"Backups:"*"b-old"*"a-new"* ]] || fail "backups list oldest first: $out"
  [[ $out == *"OpenAsar src:  "* && $out != *"not downloaded"* ]] || fail "downloaded OpenAsar source: $out"
  print -r -- '{not json' > "$HOME/.config/discord/settings.json"
  [[ $(discord-openasar-status) == *"settings:      no OpenAsar config"* ]] || fail "invalid settings json"
else
  print -- "SKIP: discord status checks, a system Discord is installed"
fi

print -- "PASS: zsh function tests"
