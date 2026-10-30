#!/usr/bin/env zsh
emulate -R zsh

TEST_ROOT=$(mktemp -d)
trap '/bin/rm -rf "$TEST_ROOT"' EXIT
REPO_ROOT=${0:A:h:h:h}

fail() { print -u2 -- "FAIL: $*"; exit 1 }

FAKEBIN="$TEST_ROOT/fakebin"
STUBS="$TEST_ROOT/stubs"
CALLS="$TEST_ROOT/calls"
mkdir -p "$FAKEBIN" "$STUBS"
: > "$CALLS"

print -rl -- '#!/bin/sh' 'printf "sudo %s\n" "$*" >> "$CALLS"' 'exec "$@"' > "$STUBS/sudo"
print -rl -- '#!/bin/sh' 'printf "pacman %s\n" "$*" >> "$CALLS"' \
  'if [ "$1" = -Qdtq ] && [ -n "$ORPHANS" ]; then printf "%s\n" "$ORPHANS"; fi' \
  'exit "${PACMAN_RC:-0}"' > "$STUBS/pacman"
print -rl -- '#!/bin/sh' 'printf "yay %s\n" "$*" >> "$CALLS"' 'exit "${YAY_RC:-0}"' > "$STUBS/yay"
print -rl -- '#!/bin/sh' 'printf "paccache %s\n" "$*" >> "$CALLS"' 'exit "${PACCACHE_RC:-0}"' > "$STUBS/paccache"
chmod +x "$STUBS"/*
export CALLS

path=("$FAKEBIN")

with() {
  local t
  for t in sudo pacman yay paccache; do /bin/rm -f "$FAKEBIN/$t"; done
  for t in "$@"; do /bin/cp "$STUBS/$t" "$FAKEBIN/$t"; done
  rehash
  for t in "$@"; do
    [[ $(whence -p $t) == "$FAKEBIN/$t" ]] || fail "stub $t is not first on PATH"
  done
  for t in yay paccache; do
    (( ${@[(Ie)$t]} )) || [[ -z $(whence -p $t) ]] || fail "$t should not resolve"
  done
  PACMAN_RC=0 YAY_RC=0 PACCACHE_RC=0 ORPHANS=
  export PACMAN_RC YAY_RC PACCACHE_RC ORPHANS
  : > "$CALLS"
}

calls_are() {
  local want=${(pj:\n:)@}
  [[ $(<"$CALLS") == "$want" ]] || fail "$CASE: unexpected calls:"$'\n'"$(<"$CALLS")"$'\n'"expected:"$'\n'"$want"
}

has() { [[ $out == *"$1"* ]] || fail "$CASE: output lacks '$1': $out" }
hasnt() { [[ $out != *"$1"* ]] || fail "$CASE: output has '$1': $out" }

export DOTFILES_OS=linux
source "$REPO_ROOT/zsh/functions/21-pacman.zsh"

CASE="pacup full success"
with sudo pacman yay
out=$(pacup 2>&1); rc=$?
(( rc == 0 )) || fail "$CASE: rc=$rc"
has "✓ System updated"
calls_are "sudo pacman -Syu" "pacman -Syu" "yay -Sua --noconfirm"

CASE="pacup pacman fails with 3"
with sudo pacman yay
PACMAN_RC=3
out=$(pacup 2>&1); rc=$?
(( rc == 3 )) || fail "$CASE: rc=$rc, want 3"
hasnt "✓ System updated"
calls_are "sudo pacman -Syu" "pacman -Syu"

CASE="pacup yay fails after pacman succeeded"
with sudo pacman yay
YAY_RC=5
out=$(pacup 2>&1); rc=$?
(( rc != 0 )) || fail "$CASE: rc=0"
hasnt "✓ System updated"
calls_are "sudo pacman -Syu" "pacman -Syu" "yay -Sua --noconfirm"

CASE="pacup without yay"
with sudo pacman
out=$(pacup 2>&1); rc=$?
(( rc == 0 )) || fail "$CASE: rc=$rc"
has "✓ System updated"
calls_are "sudo pacman -Syu" "pacman -Syu"

CASE="pacclean success"
with sudo paccache
out=$(pacclean 2>&1); rc=$?
(( rc == 0 )) || fail "$CASE: rc=$rc"
has "✓ Cache cleaned"
calls_are "sudo paccache -rk2" "paccache -rk2"

CASE="pacclean paccache fails"
with sudo paccache
PACCACHE_RC=4
out=$(pacclean 2>&1); rc=$?
(( rc != 0 )) || fail "$CASE: rc=0"
hasnt "✓ Cache cleaned"
calls_are "sudo paccache -rk2" "paccache -rk2"

CASE="pacclean without paccache"
with sudo
out=$(pacclean 2>&1); rc=$?
(( rc != 0 )) || fail "$CASE: rc=0"
has "pacman-contrib"
hasnt "✓ Cache cleaned"
calls_are

CASE="pacorphans none"
with sudo pacman
out=$(pacorphans 2>&1)
has "✓ No orphaned packages found"
hasnt "pacman -Rns"
calls_are "pacman -Qdtq"

CASE="pacorphans lists orphans"
with sudo pacman
ORPHANS=$'orphan-one\norphan-two'
out=$(pacorphans 2>&1)
has "orphan-one"
has "orphan-two"
has "pacman -Rns"
hasnt "✓ No orphaned packages found"
calls_are "pacman -Qdtq"

print -- "PASS: pacman tests"
