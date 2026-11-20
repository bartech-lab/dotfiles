#!/bin/bash
# gaming-gpu-log marks the GPU busy only while one process holds a large share
# of graphics memory, so the heartbeat counts idle time, not total game-mode time.
set -u
HERE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT=$(mktemp -d)
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/bin"
fail() { echo "FAIL: $*"; exit 1; }

# $1: per-process memory lines (MiB) the stub reports for --query-compute-apps.
run_logger() {
    cat > "$ROOT/bin/nvidia-smi" <<STUB
#!/bin/bash
case "\$*" in
    *query-compute-apps=used_memory*) printf '%s\n' $1 ;;
    *query-compute-apps*) ;;
    *) echo '15000, 16303' ;;
esac
STUB
    chmod +x "$ROOT/bin/nvidia-smi"
    rm -f "$ROOT/busy"
    PATH="$ROOT/bin:$PATH" GAMING_GPU_LOG_DIR="$ROOT/log" GAMING_GPU_LOG_INTERVAL=0.2 \
        GAMING_GPU_BUSY_FILE="$ROOT/busy" timeout 1 "$HERE/gaming-gpu-log"
}

echo "== desktop only: small processes do not mark busy"
run_logger "121 158 900"
[[ ! -e "$ROOT/busy" ]] || fail 'processes under the threshold marked the GPU busy'

echo "== one large process marks busy with the current epoch"
before=$(date +%s)
run_logger "121 13400"
[[ -f "$ROOT/busy" ]] || fail 'a 13400 MiB process did not mark the GPU busy'
mark=$(cat "$ROOT/busy")
[[ "$mark" =~ ^[0-9]+$ ]] && (( mark >= before && mark <= $(date +%s) )) || fail "busy mark '$mark' is not the current epoch"

echo "== no answer from nvidia-smi does not mark busy"
run_logger ""
[[ ! -e "$ROOT/busy" ]] || fail 'an empty nvidia-smi answer marked the GPU busy'

echo "PASS: gaming-gpu-log busy mark"
