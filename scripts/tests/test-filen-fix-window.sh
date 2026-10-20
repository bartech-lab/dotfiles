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

echo "PASS: filen-fix-window"
