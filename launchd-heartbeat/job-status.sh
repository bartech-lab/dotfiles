#!/bin/bash

set -u

usage() {
    cat <<'EOF'
Usage: job-status.sh start <job>
       job-status.sh ok <job> [--max-age HOURS]
       job-status.sh fail <job> <reason> [--max-age HOURS]

Record a scheduled job's health in $JOB_STATUS_DIR/<job>.status
(default ~/.local/state/jobs). The heartbeat reports a job as failed when its
last failure is newer than its last success, and as stale when its last
success is older than max_age_hours.
EOF
}

case "${1:-}" in
    -h|--help) usage; exit 0 ;;
    start|ok|fail) ;;
    *) usage >&2; exit 2 ;;
esac

command="$1"
job="${2:-}"
if [[ ! "$job" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'Error: invalid job name: %s\n' "$job" >&2
    exit 2
fi
shift 2

new_reason=''
if [[ "$command" == fail ]]; then
    if (( $# < 1 )); then
        usage >&2
        exit 2
    fi
    new_reason="${1//$'\n'/ }"
    new_reason="${new_reason//$'\r'/ }"
    shift
fi

new_max_age=''
if [[ "${1:-}" == --max-age ]]; then
    if [[ ! "${2:-}" =~ ^[0-9]+$ ]]; then
        printf 'Error: --max-age needs a whole number of hours\n' >&2
        exit 2
    fi
    new_max_age="$2"
    shift 2
fi
if (( $# > 0 )); then
    usage >&2
    exit 2
fi

dir="${JOB_STATUS_DIR:-$HOME/.local/state/jobs}"
mkdir -p "$dir" || exit 1
file="$dir/$job.status"

last_attempt='' last_success='' last_failure='' reason='' max_age_hours=''
if [[ -f "$file" ]]; then
    while IFS='=' read -r key value; do
        case "$key" in
            last_attempt) last_attempt="$value" ;;
            last_success) last_success="$value" ;;
            last_failure) last_failure="$value" ;;
            reason) reason="$value" ;;
            max_age_hours) max_age_hours="$value" ;;
        esac
    done < "$file"
fi

now=$(date +%s)
last_attempt="$now"
case "$command" in
    ok) last_success="$now" ;;
    fail) last_failure="$now"; reason="$new_reason" ;;
esac
[[ -n "$new_max_age" ]] && max_age_hours="$new_max_age"

tmp=$(mktemp "$dir/.$job.XXXXXX") || exit 1
{
    printf 'last_attempt=%s\n' "$last_attempt"
    [[ -n "$last_success" ]] && printf 'last_success=%s\n' "$last_success"
    [[ -n "$last_failure" ]] && printf 'last_failure=%s\n' "$last_failure"
    [[ -n "$reason" ]] && printf 'reason=%s\n' "$reason"
    [[ -n "$max_age_hours" ]] && printf 'max_age_hours=%s\n' "$max_age_hours"
} > "$tmp"
mv -f "$tmp" "$file"
