#!/usr/bin/env zsh
emulate -R zsh

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
REPO_ROOT=${0:A:h:h:h}

fail() { print -u2 -- "FAIL: $*"; exit 1 }

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

source "$REPO_ROOT/zsh/functions/40-dev.zsh"

typeset -i N=0
out="" rc=0

new_repo() {
  N=$((N + 1))
  r="$TEST_ROOT/repo$N"
  mkdir -p "$r"
  git -C "$r" init -q
  print -- "# readme" > "$r/README.md"
  print -- "MIT" > "$r/LICENSE"
  print -- "print(1)" > "$r/main.py"
  git -C "$r" add -A
  git -C "$r" commit -qm x
}

commit_all() {
  git -C "$r" add -A -f
  git -C "$r" commit -qm y
}

add_file() {
  mkdir -p "$r/${1:h}"
  print -- "data" > "$r/$1"
}

run() {
  out=$(cd "$r" && repo-check "$@" 2>&1)
  rc=$?
}

expect_error() {
  local name=$1
  run
  (( rc != 0 )) || fail "$name: expected non-zero, rc=$rc out=$out"
}

new_repo
run
(( rc == 0 )) || fail "clean repo: rc=$rc out=$out"
[[ $out != *❌* ]] || fail "clean repo prints error line: rc=$rc out=$out"
run --strict
(( rc == 0 )) || fail "clean repo strict: rc=$rc out=$out"

new_repo
add_file .env
commit_all
run
(( rc != 0 )) || fail "committed root .env: rc=$rc out=$out"
[[ -n ${(M)${(f)out}:#*❌*.env*} ]] || fail "committed root .env is an error line: rc=$rc out=$out"

new_repo
print -- ".env" > "$r/.gitignore"
commit_all
print -- "S=1" > "$r/.env"
run
(( rc == 0 )) || fail "ignored .env: rc=$rc out=$out"
[[ $out != *❌* ]] || fail "ignored .env prints error: rc=$rc out=$out"
[[ -z ${(M)${(f)out}:#*⚠️*.env*} ]] || fail "ignored .env prints a warning: rc=$rc out=$out"

for f in server.pem tls.key; do
  new_repo
  add_file $f
  commit_all
  expect_error "secret $f"
done

new_repo
add_file certs/sub/a.pem
commit_all
expect_error "nested pem"

new_repo
dd if=/dev/zero of="$r/big.bin" bs=1 count=0 seek=$((101*1024*1024)) 2>/dev/null
commit_all
expect_error "101MB file"

new_repo
dd if=/dev/zero of="$r/mid.bin" bs=1 count=0 seek=$((50*1024*1024)) 2>/dev/null
commit_all
run
(( rc == 0 )) || fail "50MB file: rc=$rc out=$out"

new_repo
print -- "changed" >> "$r/README.md"
run
(( rc == 0 )) || fail "uncommitted change: rc=$rc out=$out"
[[ $out == *⚠️* ]] || fail "uncommitted change prints warning: rc=$rc out=$out"
run --strict
(( rc != 0 )) || fail "uncommitted change strict: rc=$rc out=$out"

new_repo
print -- "x" > "$r/new.txt"
run
(( rc == 0 )) || fail "untracked file: rc=$rc out=$out"
run --strict
(( rc != 0 )) || fail "untracked file strict: rc=$rc out=$out"

new_repo
git -C "$r" rm -qf README.md
git -C "$r" commit -qm y
run
(( rc == 0 )) || fail "no README: rc=$rc out=$out"
run --strict
(( rc != 0 )) || fail "no README strict: rc=$rc out=$out"

new_repo
git -C "$r" rm -qf LICENSE
git -C "$r" commit -qm y
run
(( rc == 0 )) || fail "no LICENSE: rc=$rc out=$out"
run --strict
(( rc != 0 )) || fail "no LICENSE strict: rc=$rc out=$out"

for f in node_modules/x/index.js vendor/x.php .venv/pyvenv.cfg venv/pyvenv.cfg __pycache__/m.pyc .sisyphus/state.json .DS_Store; do
  new_repo
  add_file $f
  commit_all
  expect_error "tracked $f"
done

print -- "PASS: repo-check tests"
