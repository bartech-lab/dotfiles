#!/usr/bin/env zsh
emulate -R zsh

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
REPO_ROOT=${0:A:h:h:h}
ZSH_BIN=$(command -v zsh)

fail() { print -u2 -- "FAIL: $*"; exit 1 }

FAKEBIN="$TEST_ROOT/fakebin"
mkdir -p "$FAKEBIN"
STORE="$TEST_ROOT/store"
WRITES="$TEST_ROOT/writes"
mkdir -p "$STORE"
: > "$WRITES"
print -rl -- '#!/bin/sh' 'case "$1" in -currentHost) shift ;; esac' \
  'if [ "$1" = read ]; then f="$STORE/$2 $3"; [ -f "$f" ] || exit 1; cat "$f"; exit 0; fi' \
  'if [ "$1" = write ]; then printf "%s\0" "$2" "$3" "$4" "$5" >> "$WRITES"; exit 0; fi' \
  'exit 1' > "$FAKEBIN/defaults"
print -rl -- '#!/bin/sh' 'exec "$@"' > "$FAKEBIN/sudo"
print -rl -- '#!/bin/sh' 'exit 0' > "$FAKEBIN/killall"
print -rl -- '#!/bin/sh' 'exit 0' > "$FAKEBIN/nvram"
print -rl -- '#!/bin/sh' 'echo today' > "$FAKEBIN/date"
chmod +x "$FAKEBIN"/*
export STORE WRITES
path=("$FAKEBIN" /usr/bin /bin)
for t in defaults sudo killall nvram; do
  [[ $(whence -p $t) == "$FAKEBIN/$t" ]] || fail "stub $t is not first on PATH"
done

export DOTFILES_OS=macos
source "$REPO_ROOT/zsh/functions/60-macos.zsh"

tricky="/Users/x/Bob's \"shots\" \$HOME \`id\`"
print -rn -- "$tricky" > "$STORE/com.apple.screencapture location"
print -rn -- "png" > "$STORE/com.apple.screencapture type"
print -rn -- "1" > "$STORE/com.apple.dock autohide"

macos-defaults-export > "$TEST_ROOT/restore.zsh" || fail "export failed"
"$ZSH_BIN" -n "$TEST_ROOT/restore.zsh" || fail "exported script does not parse"
out=$(HOME=/nohome "$ZSH_BIN" "$TEST_ROOT/restore.zsh" 2>&1) || fail "exported script failed: $out"

got=$(tr '\0' '\n' < "$WRITES" | paste -d'|' - - - -)
[[ $got == *"com.apple.screencapture|location|-string|$tricky"* ]] || fail "string value did not round-trip: $got"
[[ $got == *"com.apple.screencapture|type|-string|png"* ]] || fail "plain string value: $got"
[[ $got == *"com.apple.dock|autohide|-bool|1"* ]] || fail "bool value: $got"
[[ $got != *"tilesize"* ]] || fail "an unset key was exported: $got"

print -- "PASS: macos tests"
