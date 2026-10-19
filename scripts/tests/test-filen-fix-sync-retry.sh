#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT=$(mktemp -d)
trap 'chmod -R u+w "$TEST_ROOT" 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TOOL="$REPO_ROOT/scripts/bin/filen-fix-sync-retry"

fail() { echo "FAIL: $*" >&2; exit 1; }

if command -v sha256sum >/dev/null 2>&1; then
  hash_of() { sha256sum "$1" | cut -d' ' -f1; }
else
  hash_of() { shasum -a 256 "$1" | cut -d' ' -f1; }
fi

size_of() { wc -c < "$1" | tr -d ' '; }

# Runs the tool; sets RC, OUT, ERR.
run() {
  RC=0
  OUT=$("$TOOL" "$@" 2>"$TEST_ROOT/err") || RC=$?
  ERR=$(cat "$TEST_ROOT/err")
}

LINE='                this.worker.logger.log("error", "Not continueing sync cycle, got taskErrors or localTreeErrors", this.syncPair.localPath);'
LINE_LEN=${#LINE}

head -c 3001 /dev/urandom > "$TEST_ROOT/prefix"
head -c 2503 /dev/urandom > "$TEST_ROOT/suffix"
head -c 777 /dev/urandom > "$TEST_ROOT/middle"
PREFIX_LEN=$(size_of "$TEST_ROOT/prefix")
SUFFIX_LEN=$(size_of "$TEST_ROOT/suffix")

# Fixture: prefix + line + newline + suffix.
build_one() {
  { cat "$TEST_ROOT/prefix"; printf '%s\n' "$LINE"; cat "$TEST_ROOT/suffix"; } > "$1"
}
SUFFIX_LEN=$((SUFFIX_LEN + 1)) # the newline after the line belongs to the suffix region

export FILEN_ASAR="$TEST_ROOT/app.asar"

# F1: missing file.
rm -f "$FILEN_ASAR"
run
[[ $RC -eq 2 ]] || fail "missing file: expected exit 2, got $RC"
case "$ERR" in *"not found"*) ;; *) fail "missing file: stderr lacks 'not found': $ERR" ;; esac
run --check
[[ $RC -eq 2 ]] || fail "missing file --check: expected exit 2, got $RC"

# F2: --check on unpatched.
build_one "$FILEN_ASAR"
cp "$FILEN_ASAR" "$TEST_ROOT/orig"
H0=$(hash_of "$FILEN_ASAR")
run --check
[[ $RC -eq 1 ]] || fail "unpatched --check: expected exit 1, got $RC"
case "$OUT" in *unpatched*) ;; *) fail "unpatched --check: stdout lacks 'unpatched': $OUT" ;; esac
[[ "$(hash_of "$FILEN_ASAR")" == "$H0" ]] || fail "unpatched --check modified the file"

# F3: patch.
run
[[ $RC -eq 0 ]] || fail "patch: expected exit 0, got $RC ($ERR)"
case "$OUT" in *"patched OK"*) ;; *) fail "patch: stdout lacks 'patched OK': $OUT" ;; esac
[[ "$(size_of "$FILEN_ASAR")" == "$(size_of "$TEST_ROOT/orig")" ]] || fail "patch changed file size"
[[ "$(hash_of "$FILEN_ASAR")" != "$H0" ]] || fail "patch left file unchanged"
head -c "$PREFIX_LEN" "$FILEN_ASAR" > "$TEST_ROOT/got_prefix"
cmp -s "$TEST_ROOT/got_prefix" "$TEST_ROOT/prefix" || fail "bytes before patched region changed"
tail -c "$SUFFIX_LEN" "$FILEN_ASAR" > "$TEST_ROOT/got_suffix"
tail -c "$SUFFIX_LEN" "$TEST_ROOT/orig" > "$TEST_ROOT/want_suffix"
cmp -s "$TEST_ROOT/got_suffix" "$TEST_ROOT/want_suffix" || fail "bytes after patched region changed"
tail -c +"$((PREFIX_LEN + 1))" "$FILEN_ASAR" | head -c "$LINE_LEN" > "$TEST_ROOT/got_region"
printf '%s' "$LINE" > "$TEST_ROOT/want_region"
if cmp -s "$TEST_ROOT/got_region" "$TEST_ROOT/want_region"; then fail "patched region equals original line"; fi
if grep -qF 'Not continueing sync cycle, got taskErrors or localTreeErrors' "$FILEN_ASAR"; then
  fail "known line text still present after patch"
fi

# F5: --check after patch.
run --check
[[ $RC -eq 0 ]] || fail "patched --check: expected exit 0, got $RC"
case "$OUT" in *"already patched"*) ;; *) fail "patched --check: stdout lacks 'already patched': $OUT" ;; esac

# F4: idempotence.
H1=$(hash_of "$FILEN_ASAR")
run
[[ $RC -eq 0 ]] || fail "second run: expected exit 0, got $RC"
case "$OUT" in *"already patched"*) ;; *) fail "second run: stdout lacks 'already patched': $OUT" ;; esac
[[ "$(hash_of "$FILEN_ASAR")" == "$H1" ]] || fail "second run changed a patched file"
cp "$FILEN_ASAR" "$TEST_ROOT/patched"

# F6: zero and two occurrences.
{ cat "$TEST_ROOT/prefix"; printf 'unrelated\n'; cat "$TEST_ROOT/suffix"; } > "$FILEN_ASAR"
H=$(hash_of "$FILEN_ASAR")
for flag in "" "--check"; do
  # shellcheck disable=SC2086
  run $flag
  [[ $RC -eq 2 ]] || fail "zero occurrences ($flag): expected exit 2, got $RC"
  case "$OUT" in *"expected 1 unpatched block, found 0"*) ;; *) fail "zero occurrences ($flag): bad message: $OUT" ;; esac
  [[ "$(hash_of "$FILEN_ASAR")" == "$H" ]] || fail "zero occurrences ($flag): file modified"
done

{ cat "$TEST_ROOT/prefix"; printf '%s\n' "$LINE"; cat "$TEST_ROOT/middle"; printf '%s\n' "$LINE"; cat "$TEST_ROOT/suffix"; } > "$FILEN_ASAR"
H=$(hash_of "$FILEN_ASAR")
for flag in "" "--check"; do
  # shellcheck disable=SC2086
  run $flag
  [[ $RC -eq 2 ]] || fail "two occurrences ($flag): expected exit 2, got $RC"
  case "$OUT" in *"expected 1 unpatched block, found 2"*) ;; *) fail "two occurrences ($flag): bad message: $OUT" ;; esac
  [[ "$(hash_of "$FILEN_ASAR")" == "$H" ]] || fail "two occurrences ($flag): file modified"
done

# F7: one byte different (correct spelling) counts as zero occurrences.
NEAR=${LINE/continueing/continuing}
[[ "$NEAR" != "$LINE" ]] || fail "test bug: near-miss equals line"
{ cat "$TEST_ROOT/prefix"; printf '%s\n' "$NEAR"; cat "$TEST_ROOT/suffix"; } > "$FILEN_ASAR"
H=$(hash_of "$FILEN_ASAR")
for flag in "" "--check"; do
  # shellcheck disable=SC2086
  run $flag
  [[ $RC -eq 2 ]] || fail "near-miss line ($flag): expected exit 2, got $RC"
  case "$OUT" in *"found 0"*) ;; *) fail "near-miss line ($flag): bad message: $OUT" ;; esac
  [[ "$(hash_of "$FILEN_ASAR")" == "$H" ]] || fail "near-miss line ($flag): file modified"
done

# F8: read-only fixture with --check must not call sudo.
STUBS="$TEST_ROOT/stubs"
mkdir -p "$STUBS"
cat > "$STUBS/sudo" <<SH
#!/bin/sh
echo called >> "$TEST_ROOT/sudo-called"
exit 99
SH
chmod +x "$STUBS/sudo"
OLD_PATH=$PATH
export PATH="$STUBS:$PATH"

build_one "$FILEN_ASAR"
chmod 444 "$FILEN_ASAR"
H=$(hash_of "$FILEN_ASAR")
run --check
[[ $RC -eq 1 ]] || fail "read-only unpatched --check: expected exit 1, got $RC ($ERR)"
case "$OUT" in *unpatched*) ;; *) fail "read-only unpatched --check: bad message: $OUT" ;; esac
[[ "$(hash_of "$FILEN_ASAR")" == "$H" ]] || fail "read-only --check modified file"
chmod 644 "$FILEN_ASAR"

cp "$TEST_ROOT/patched" "$FILEN_ASAR"
chmod 444 "$FILEN_ASAR"
run --check
[[ $RC -eq 0 ]] || fail "read-only patched --check: expected exit 0, got $RC ($ERR)"
case "$OUT" in *"already patched"*) ;; *) fail "read-only patched --check: bad message: $OUT" ;; esac
chmod 644 "$FILEN_ASAR"

[[ ! -e "$TEST_ROOT/sudo-called" ]] || fail "--check on read-only file called sudo"
export PATH="$OLD_PATH"

echo "PASS: filen-fix-sync-retry"
