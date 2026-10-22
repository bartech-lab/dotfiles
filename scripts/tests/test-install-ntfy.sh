#!/bin/bash
# Offline tests for scripts/install-ntfy.sh against a fake release served from file://.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/install-ntfy.sh"
ROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-install-ntfy.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

case "$(uname -s)/$(uname -m)" in
    Linux/x86_64) asset="ntfy_9.9.9_linux_amd64" ;;
    Linux/aarch64|Linux/arm64) asset="ntfy_9.9.9_linux_arm64" ;;
    Darwin/*) asset="ntfy_9.9.9_darwin_all" ;;
esac

make_release() {
    local version=$1 body=$2
    rm -rf "$ROOT/release" && mkdir -p "$ROOT/release/v9.9.9/$asset"
    printf '#!/bin/sh\necho "ntfy version %s (fake)"\n' "$version" > "$ROOT/release/v9.9.9/$asset/ntfy"
    printf '%s\n' "$body" >> "$ROOT/release/v9.9.9/$asset/ntfy"
    chmod +x "$ROOT/release/v9.9.9/$asset/ntfy"
    tar -czf "$ROOT/release/v9.9.9/$asset.tar.gz" -C "$ROOT/release/v9.9.9" "$asset"
    (cd "$ROOT/release/v9.9.9" && { command -v sha256sum >/dev/null && sha256sum "$asset.tar.gz" || shasum -a 256 "$asset.tar.gz"; } > checksums.txt)
}

run() { NTFY_VERSION=9.9.9 NTFY_BASE_URL="file://$ROOT/release" NTFY_DEST_DIR="$ROOT/bin" "$SCRIPT" "$@"; }

make_release 9.9.9 "# first"
run >/dev/null || fail "a valid release did not install"
"$ROOT/bin/ntfy" --version | grep -q "ntfy version 9.9.9" || fail "installed binary is not the release binary"

out=$(run) || fail "rerun failed"
[[ "$out" == *"already installed"* ]] || fail "same version was downloaded again"

rm -f "$ROOT/bin/ntfy"
make_release 9.9.9 "# tampered"
sed -i.orig 's/^[0-9a-f]\{8\}/00000000/' "$ROOT/release/v9.9.9/checksums.txt"
if run >/dev/null 2>&1; then fail "a checksum mismatch was installed"; fi
[[ ! -e "$ROOT/bin/ntfy" ]] || fail "a checksum mismatch left a binary behind"

make_release 9.9.9 "# fine"
out=$(run --dry-run)
[[ "$out" == *"Would install"* && ! -e "$ROOT/bin/ntfy" ]] || fail "--dry-run changed something"

mkdir -p "$ROOT/bin" && printf '#!/bin/sh\nexit 1\n' > "$ROOT/bin/ntfy" && chmod +x "$ROOT/bin/ntfy"
run >/dev/null 2>&1 || fail "an installed binary whose --version fails stopped the reinstall"
"$ROOT/bin/ntfy" --version | grep -q "ntfy version 9.9.9" || fail "a broken installed binary was not replaced"

run --bogus >/dev/null 2>&1 && fail "an unknown option was accepted"
echo "PASS: install-ntfy installs a verified release, skips a current one, refuses a bad checksum, replaces a broken one"
