#!/usr/bin/env bash
# dotfiles-test must answer --help and reject unknown arguments without running any suite.
set -uo pipefail
bin="$(dirname "$(readlink -f "$0")")/../bin/dotfiles-test"
fail() { echo "FAIL: $*" >&2; exit 1; }

for opt in --help -h; do
  out=$(timeout 5 bash "$bin" "$opt" 2>&1); rc=$?
  ((rc == 0)) || fail "$opt exited $rc"
  [[ $out == Usage:* ]] || fail "$opt printed: ${out:0:200}"
  [[ $out != *"suites passed"* ]] || fail "$opt ran the suites"
done

out=$(timeout 5 bash "$bin" --bogus 2>&1); rc=$?
((rc == 2)) || fail "--bogus exited $rc"
[[ $out == *"unknown argument: --bogus"* ]] || fail "--bogus printed: ${out:0:200}"

echo "PASS test-dotfiles-test-args"
