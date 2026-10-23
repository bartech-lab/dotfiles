#!/usr/bin/env zsh
emulate -R zsh

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
REPO_ROOT=${0:A:h:h:h}

fail() { print -u2 -- "FAIL: $*"; exit 1 }

source "$REPO_ROOT/zsh/functions/40-dev.zsh"

src="$TEST_ROOT/src"
mkdir -p "$src/sub"
print -r -- alpha > "$src/a.txt"
print -r -- beta > "$src/sub/b.txt"

work="$TEST_ROOT/x"
mkdir -p "$work"
cd "$work"

out=$(extract) && fail "extract without an argument succeeded"
[[ $out == Usage:* ]] || fail "extract usage: $out"
out=$(extract missing.tar.gz) && fail "extract of a missing file succeeded"
[[ $out == *"File not found: missing.tar.gz"* ]] || fail "missing file message: $out"

check_tree() {
  [[ $(<"$1/a.txt") == alpha && $(<"$1/sub/b.txt") == beta ]] || fail "$2: extracted tree in $1"
}

tar -cf - -C "$src" a.txt sub > plain.tar
gzip -c plain.tar > "My Data.tar.gz"
cp "My Data.tar.gz" t.tgz
bzip2 -c plain.tar > t.tar.bz2
cp t.tar.bz2 t.tbz2
xz -c plain.tar > t.tar.xz
zstd -q -c plain.tar > t.tar.zst
for f in "My Data.tar.gz" t.tgz t.tar.bz2 t.tbz2 t.tar.xz t.tar.zst plain.tar; do
  rm -rf -- t plain
  extract "$f" >/dev/null || fail "extract $f failed"
done
check_tree "My Data" "tar.gz with a space"
check_tree plain ".tar"
for ext in tgz tar.bz2 tbz2 tar.xz tar.zst; do
  rm -rf t
  extract "t.$ext" >/dev/null
  check_tree t ".$ext"
done

rm -rf "My Data" "My Data-2" "My Data-3"
extract "My Data.tar.gz" >/dev/null
out=$(extract "My Data.tar.gz")
[[ $out == *"Extracting to: My Data-2/"* ]] || fail "second extract goes to -2: $out"
extract "My Data.tar.gz" >/dev/null
check_tree "My Data-3" "third extract goes to -3"

print -r -- single > "$TEST_ROOT/note"
gzip -c "$TEST_ROOT/note" > note.gz
bzip2 -c "$TEST_ROOT/note" > n2.bz2
xz -c "$TEST_ROOT/note" > n3.xz
extract note.gz >/dev/null && [[ $(<note/note) == single ]] || fail ".gz single file"
extract n2.bz2 >/dev/null && [[ $(<n2/n2) == single ]] || fail ".bz2 single file"
extract n3.xz >/dev/null && [[ $(<n3/n3) == single ]] || fail ".xz single file"

(cd "$src" && python3 -m zipfile -c "$work/z.zip" a.txt sub)
extract z.zip >/dev/null || fail "extract z.zip failed"
check_tree z ".zip"

mkdir -p sub
tar -cf - -C "$src" a.txt sub | gzip -c > sub/nested.tar.gz
extract sub/nested.tar.gz >/dev/null
check_tree sub/nested "archive in a subdirectory extracts beside it"

print -r -- notes > notes.txt
out=$(extract notes.txt 2>&1) && fail "extract of an unknown format succeeded"
[[ $out == *"Unknown archive format: notes.txt"* && $out != *mkdir* && $out != *Extracting* ]] || fail "unknown format message: $out"
[[ -f notes.txt ]] || fail "unknown format replaced the file"

print -r -- kept > kept
gzip -k kept
extract kept.gz >/dev/null || fail "extract beside its own uncompressed file failed"
[[ $(<kept) == kept && $(<kept-2/kept) == kept ]] || fail "a file named like the archive moves extraction to -2"

BIN="$TEST_ROOT/bin"
mkdir -p "$BIN"
for t in gzip tar mkdir basename; do ln -sf "$(command -v $t)" "$BIN/$t"; done
out=$(path=("$BIN"); extract t.tar.zst 2>&1) && fail "extract .tar.zst without zstd succeeded"
[[ $out == *"zstd not found"* ]] || fail "missing zstd message: $out"
[[ ! -e t-2 ]] || fail "missing zstd left an empty directory"
out=$(path=("$BIN"); extract z.zip 2>&1) && fail "extract .zip without unar succeeded"
[[ $out == *"unar not found"* ]] || fail "missing unar message: $out"
[[ ! -e z-2 ]] || fail "missing unar left an empty directory"

proj="$TEST_ROOT/proj"
mkdir -p "$proj"
cd "$proj"
out=$(archive 2>&1) && fail "archive of an empty directory succeeded"
[[ $out == *"Directory is empty"* ]] || fail "empty directory message: $out"
out=$(archive --bogus 2>&1) && fail "archive with an unknown option succeeded"
[[ $out == *"Unknown option: --bogus"* ]] || fail "unknown option message: $out"

mkdir -p src node_modules/pkg .git build
print -r -- code > src/main.js
print -r -- dep > node_modules/pkg/index.js
print -r -- obj > .git/HEAD
print -r -- out > build/out.js
print -r -- secret > .env
print -r -- secret > .env.local
print -r -- secret > .env.production
print -r -- noise > debug.log
print -r -- keep > README.md

out=$(archive --dry-run)
[[ $out == *"./src/main.js"* && $out == *"./README.md"* ]] || fail "dry run lists kept files: $out"
[[ $out != *node_modules* && $out != *".git/"* && $out != *build/* && $out != *".env"* && $out != *debug.log* ]] || fail "dry run lists excluded files: $out"
[[ $out == *"Would create: proj-"*".tar.zst"* ]] || fail "dry run names the default output: $out"
[[ -z $(print -l -- *.tar.*(N)) ]] || fail "dry run created an archive"

out=$(archive -n -gzip)
[[ $out == *"Would create: proj-"*".tar.gz"* ]] || fail "-n with -gzip names a .tar.gz: $out"

archive >/dev/null || fail "archive failed"
z=(proj-*.tar.zst(N))
(( ${#z} == 1 )) || fail "archive created one proj-*.tar.zst: ${z[*]}"
listing=$(zstd -dc "$z[1]" | tar -tf - | sort)
[[ $listing == *"./src/main.js"* && $listing == *"./README.md"* ]] || fail "archive keeps sources: $listing"
[[ $listing != *node_modules* && $listing != *".git/"* && $listing != *".env"* && $listing != *debug.log* && $listing != *build/* ]] || fail "archive excludes artifacts: $listing"

out=$(archive first second -n)
[[ $out == *"Would create: first-"* ]] || fail "the first name wins: $out"

archive named -gzip >/dev/null || fail "archive named -gzip failed"
g=(named-*.tar.gz(N))
(( ${#g} == 1 )) || fail "archive named -gzip created one named-*.tar.gz"
[[ $(gzip -dc "$g[1]" | tar -tf - | grep -c 'tar\.zst') -eq 0 ]] || fail "the gzip archive includes the earlier archive"

if command -v gtar >/dev/null || tar --version 2>/dev/null | grep -q "GNU tar"; then
  rm -f -- *.tar.*
  archive >/dev/null
  first=$(cksum < proj-*.tar.zst)
  rm -f -- *.tar.zst
  touch -t 202201010000 src/main.js README.md
  archive >/dev/null
  [[ $(cksum < proj-*.tar.zst) == "$first" ]] || fail "GNU tar archives of the same content differ"
  rm -f -- *.tar.zst
  mkdir order
  for f in zz mm aa; do print -r -- $f > order/$f; done
  archive >/dev/null
  [[ $(zstd -dc proj-*.tar.zst | tar -tf - | grep '^./order/.') == $'./order/aa\n./order/mm\n./order/zz' ]] || fail "GNU tar entries are sorted by name"
  rm -rf order
else
  print -- "SKIP: reproducibility check needs GNU tar"
fi

rm -f -- *.tar.*
print -r -- locked > locked.txt
chmod 000 locked.txt
out=$(archive 2>&1) && fail "archive succeeded when tar could not read a file"
[[ $out == *"Failed to create archive"* ]] || fail "tar failure message: $out"
[[ -z $(print -l -- *.tar.*(N)) ]] || fail "a failed tar left a partial archive"
rm -f locked.txt

print -rl -- '#!/bin/sh' 'exit 1' > "$BIN/zstd"
chmod +x "$BIN/zstd"
for t in date ls awk stat uname rm head wc grep; do ln -sf "$(command -v $t)" "$BIN/$t"; done
command -v gtar >/dev/null && ln -sf "$(command -v gtar)" "$BIN/gtar"
out=$(path=("$BIN"); archive 2>&1) && fail "archive succeeded when zstd failed"
[[ $out == *"Failed to create archive"* ]] || fail "zstd failure message: $out"
[[ -z $(print -l -- *.tar.*(N)) ]] || fail "a failed archive left a file"

print -- "PASS: zsh dev function tests"
