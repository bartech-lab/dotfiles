#!/bin/bash
# Install the ntfy client/server binary to ~/.local/bin, pinned and checksum-verified.

set -euo pipefail

NTFY_VERSION="${NTFY_VERSION:-2.32.0}"
BASE_URL="${NTFY_BASE_URL:-https://github.com/binwiederhier/ntfy/releases/download}"
DEST_DIR="${NTFY_DEST_DIR:-$HOME/.local/bin}"
DRY_RUN=false

usage() {
    cat <<EOF
Usage: install-ntfy.sh [--dry-run] [--help]

Download ntfy $NTFY_VERSION from its GitHub release, verify it against the
release's checksums.txt, and install it to $DEST_DIR/ntfy. Skips the download
when that version is already installed. A checksum mismatch installs nothing.
Override the version with NTFY_VERSION.
EOF
}

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        -h|--help) usage; exit 0 ;;
        *) printf 'Error: unknown option: %s\n' "$arg" >&2; usage >&2; exit 2 ;;
    esac
done

case "$(uname -s)/$(uname -m)" in
    Linux/x86_64) asset="ntfy_${NTFY_VERSION}_linux_amd64" ;;
    Linux/aarch64|Linux/arm64) asset="ntfy_${NTFY_VERSION}_linux_arm64" ;;
    Darwin/*) asset="ntfy_${NTFY_VERSION}_darwin_all" ;;
    *) printf 'Error: unsupported platform: %s/%s\n' "$(uname -s)" "$(uname -m)" >&2; exit 1 ;;
esac

target="$DEST_DIR/ntfy"
if [[ -x "$target" ]]; then
    installed=$("$target" --version 2>/dev/null | sed -n 's/^ntfy version \([0-9.]*\).*/\1/p' | head -n 1) || installed=""
    if [[ "$installed" == "$NTFY_VERSION" ]]; then
        echo "✓ ntfy $NTFY_VERSION already installed at $target"
        exit 0
    fi
fi

if [[ "$DRY_RUN" == true ]]; then
    echo "  → Would install ntfy $NTFY_VERSION ($asset) to $target"
    exit 0
fi

sha256() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1"; else shasum -a 256 "$1"; fi | cut -d' ' -f1
}

work=$(mktemp -d "${TMPDIR:-/tmp}/install-ntfy.XXXXXX")
trap 'rm -rf "$work"' EXIT

curl -fsSL -o "$work/$asset.tar.gz" "$BASE_URL/v$NTFY_VERSION/$asset.tar.gz"
curl -fsSL -o "$work/checksums.txt" "$BASE_URL/v$NTFY_VERSION/checksums.txt"

expected=$(awk -v name="$asset.tar.gz" '$2 == name || $2 == "*" name { print $1 }' "$work/checksums.txt")
if [[ -z "$expected" ]]; then
    printf 'Error: %s.tar.gz is not listed in checksums.txt\n' "$asset" >&2
    exit 1
fi
actual=$(sha256 "$work/$asset.tar.gz")
if [[ "$actual" != "$expected" ]]; then
    printf 'Error: checksum mismatch for %s.tar.gz (expected %s, got %s); nothing installed\n' "$asset" "$expected" "$actual" >&2
    exit 1
fi

tar -xzf "$work/$asset.tar.gz" -C "$work"
mkdir -p "$DEST_DIR"
install -m 755 "$work/$asset/ntfy" "$target.tmp"
mv "$target.tmp" "$target"
echo "✓ ntfy $NTFY_VERSION installed at $target"
