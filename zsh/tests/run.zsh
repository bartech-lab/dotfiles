#!/usr/bin/env zsh
emulate -R zsh

TESTS_DIR=${0:A:h}
LIMIT=${TEST_TIMEOUT:-300}

command -v timeout >/dev/null || { print -u2 -- "run.zsh needs timeout (coreutils)"; exit 2 }

typeset -a tests failed
if (( $# )); then
  for t in "$@"; do tests+=("$TESTS_DIR/${${t:t}%.zsh}.zsh"); done
else
  tests=("$TESTS_DIR"/test-*.zsh)
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for t in $tests; do
  [[ -f $t ]] || { print -u2 -- "no such test: $t"; failed+=(${t:t}); continue }
  start=$SECONDS
  (cd "$WORK" && timeout --kill-after=10 $LIMIT zsh "$t")
  rc=$?
  if (( rc == 124 || rc == 137 )); then
    print -u2 -- "TIMEOUT after ${LIMIT}s: ${t:t}"
    failed+=(${t:t})
  elif (( rc )); then
    print -u2 -- "FAIL (exit $rc): ${t:t}"
    failed+=(${t:t})
  else
    print -- "ok ${t:t} ($(( SECONDS - start ))s)"
  fi
done

(( ${#failed} )) && { print -u2 -- "failed: ${failed[*]}"; exit 1 }
exit 0
