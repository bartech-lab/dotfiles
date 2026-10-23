#!/usr/bin/env bash
set -euo pipefail

TEST_ROOT=$(mktemp -d)
trap 'chmod -R u+w "$TEST_ROOT" 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
TOOL="$REPO_ROOT/scripts/bin/filen-fix-window"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ $EUID -ne 0 ]] || { echo "SKIP: run as a normal user"; exit 0; }

mkdir -p "$TEST_ROOT/bin"
cat > "$TEST_ROOT/bin/sudo" <<EOF
#!/usr/bin/env bash
touch "$TEST_ROOT/sudo-called"
exit 97
EOF
chmod +x "$TEST_ROOT/bin/sudo"
export PATH="$TEST_ROOT/bin:$PATH"

build() {
  {
    head -c 2048 /dev/zero | tr '\0' 'a'
    printf '                if (this.driveWindow) {\n'
    printf '                    if (this.driveWindow.isMinimized()) {\n'
    printf '                        this.driveWindow.restore();\n'
    printf '                    }\n'
    printf '                    this.driveWindow.focus();\n'
    printf '                }\n'
    head -c 2048 /dev/zero | tr '\0' 'b'
  } > "$1"
}

export FILEN_ASAR="$TEST_ROOT/app.asar"

build "$FILEN_ASAR"
SIZE=$(wc -c < "$FILEN_ASAR" | tr -d ' ')
RC=0
"$TOOL" >/dev/null 2>&1 || RC=$?
[[ ! -e "$TEST_ROOT/sudo-called" ]] || fail "writable asar: sudo was called"
[[ $RC -eq 0 ]] || fail "writable asar: expected exit 0, got $RC"
grep -q 'this.showOrOpenDriveWindow();' "$FILEN_ASAR" || fail "writable asar: not patched"
[[ "$(wc -c < "$FILEN_ASAR" | tr -d ' ')" == "$SIZE" ]] || fail "writable asar: size changed"
RC=0
"$TOOL" --check >/dev/null 2>&1 || RC=$?
[[ $RC -eq 0 ]] || fail "patched --check: expected exit 0, got $RC"

build "$FILEN_ASAR"
chmod a-w "$FILEN_ASAR"
RC=0
"$TOOL" >/dev/null 2>&1 || RC=$?
[[ -e "$TEST_ROOT/sudo-called" ]] || fail "read-only asar: sudo was not called"
[[ $RC -eq 97 ]] || fail "read-only asar: expected the sudo stub's exit 97, got $RC"

chmod u+w "$FILEN_ASAR"
rm -f "$TEST_ROOT/sudo-called"

build "$FILEN_ASAR"
before=$(cksum < "$FILEN_ASAR")
RC=0
"$TOOL" --check >/dev/null 2>&1 || RC=$?
[[ $RC -eq 1 ]] || fail "unpatched --check: expected exit 1, got $RC"
[[ "$(cksum < "$FILEN_ASAR")" == "$before" ]] || fail "unpatched --check modified the asar"

{ build "$TEST_ROOT/one"; cat "$TEST_ROOT/one" "$TEST_ROOT/one"; } > "$FILEN_ASAR"
"$TOOL" >/dev/null 2>&1 || fail "two handlers: patch failed"
[[ "$(grep -c 'this.showOrOpenDriveWindow();' "$FILEN_ASAR")" -eq 2 ]] || fail "two handlers: both must be patched"
if grep -q 'this.driveWindow.focus();' "$FILEN_ASAR"; then fail "two handlers: an unpatched handler is left"; fi

head -c 4096 /dev/zero | tr '\0' 'c' > "$FILEN_ASAR"
before=$(cksum < "$FILEN_ASAR")
RC=0
"$TOOL" >/dev/null 2>&1 || RC=$?
[[ $RC -eq 2 ]] || fail "no handler block: expected exit 2, got $RC"
[[ "$(cksum < "$FILEN_ASAR")" == "$before" ]] || fail "no handler block: the asar was modified"

RC=0
FILEN_ASAR="$TEST_ROOT/missing.asar" "$TOOL" >/dev/null 2>&1 || RC=$?
[[ $RC -eq 2 ]] || fail "missing asar: expected exit 2, got $RC"

build "$FILEN_ASAR"
mkdir -p "$TEST_ROOT/norclone"
for t in bash python3 head tr env; do ln -sf "$(command -v "$t")" "$TEST_ROOT/norclone/$t"; done
err=$(PATH="$TEST_ROOT/norclone" "$TOOL" --check 2>&1 >/dev/null) || true
[[ $err == *"rclone missing"* ]] || fail "a missing rclone is warned about: $err"


build "$FILEN_ASAR"
printf '            this.showOrOpenDriveWindow();\n        }\n' >> "$FILEN_ASAR"
RC=0
"$TOOL" --check >/dev/null 2>&1 || RC=$?
[[ $RC -eq 1 ]] || fail "an existing showOrOpenDriveWindow call elsewhere: expected --check exit 1, got $RC"
"$TOOL" >/dev/null 2>&1 || fail "an existing showOrOpenDriveWindow call elsewhere: patch failed"
! grep -q 'this.driveWindow.focus();' "$FILEN_ASAR" || fail "an existing showOrOpenDriveWindow call elsewhere: handler left unpatched"
echo "PASS: filen-fix-window"
