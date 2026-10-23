#!/usr/bin/env zsh
emulate -R zsh

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
REPO_ROOT=${0:A:h:h:h}

fail() { print -u2 -- "FAIL: $*"; exit 1 }

for t in ffmpeg ffprobe; do command -v $t >/dev/null || { print -- "SKIP: encode tests need $t"; exit 0 }; done
ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libx265 || { print -- "SKIP: encode tests need libx265"; exit 0 }

FAKEBIN="$TEST_ROOT/fakebin"
mkdir -p "$FAKEBIN"
for t in osascript notify-send; do
  print -rl -- '#!/bin/sh' 'exit 0' > "$FAKEBIN/$t"
  chmod +x "$FAKEBIN/$t"
done
export PATH="$FAKEBIN:$PATH"

case $(uname -s) in
  Darwin) export DOTFILES_OS=macos ;;
  *) export DOTFILES_OS=linux ;;
esac

source "$REPO_ROOT/zsh/functions/50-media.zsh"

ff() { ffmpeg -nostdin -v error -y "$@" }
probe() { ffprobe -v error "$@" }
vcodec() { probe -select_streams v:0 -show_entries stream=codec_name -of csv=p=0 "$1" }
acodec() { probe -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$1" }
vdim() { probe -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$1" }
vdur() { probe -show_entries format=duration -of csv=p=0 "$1" }
close_enough() { awk -v a="$1" -v b="$2" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d < 0.25) }' }
sum() { cksum < "$1" }

clip() { ff -f lavfi -i testsrc=size=320x180:rate=24 -f lavfi -i sine=frequency=440 -t 1 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$1" || fail "fixture $1" }

mk_fixture() {
  rm -rf "$1"
  mkdir -p "$1"
  clip "$1/a.mov"
  clip "$1/b.mp4"
}

check_pair() {
  local dir=$1 src=$2 dst=$3 ctx=$4
  [[ -f $dir/$dst ]] || fail "$dst missing in $dir $ctx"
  [[ $(vcodec "$dir/$dst") == hevc ]] || fail "$dst codec is $(vcodec "$dir/$dst") $ctx"
  close_enough "$(vdur "$1/$src")" "$(vdur "$dir/$dst")" || fail "$dst duration $(vdur "$1/$src") vs $(vdur "$dir/$dst") $ctx"
  [[ $(vdim "$1/$src") == $(vdim "$dir/$dst") ]] || fail "$dst dimensions $(vdim "$1/$src") vs $(vdim "$dir/$dst") $ctx"
}

W="$TEST_ROOT/w1"
mk_fixture "$W"
asum=$(sum "$W/a.mov")
bsum=$(sum "$W/b.mp4")
out=$(video-encode-cpu "$W" 2>&1); rc=$?
(( rc == 0 )) || fail "directory encode rc=$rc out=$out"
check_pair "$W" a.mov a.mp4 "rc=$rc out=$out"
check_pair "$W" b.mp4 b-h265.mp4 "rc=$rc out=$out"
[[ $(sum "$W/a.mov") == $asum ]] || fail "a.mov changed rc=$rc out=$out"
[[ $(sum "$W/b.mp4") == $bsum ]] || fail "b.mp4 changed rc=$rc out=$out"
[[ $(vcodec "$W/b.mp4") == h264 ]] || fail "b.mp4 no longer h264 rc=$rc out=$out"
got=$(cd "$W" && print -l -- *(N.) | sort | tr '\n' ' ')
[[ $got == "a.mov a.mp4 b-h265.mp4 b.mp4 " ]] || fail "unexpected file set: $got rc=$rc out=$out"
[[ -n $(acodec "$W/a.mp4") ]] || fail "a.mp4 lost its audio stream rc=$rc out=$out"

W="$TEST_ROOT/w2"
mk_fixture "$W"
out=$(cd "$W" && video-encode-cpu 2>&1); rc=$?
(( rc == 0 )) || fail "cwd encode rc=$rc out=$out"
check_pair "$W" a.mov a.mp4 "cwd mode rc=$rc out=$out"
check_pair "$W" b.mp4 b-h265.mp4 "cwd mode rc=$rc out=$out"

W="$TEST_ROOT/w3"
mk_fixture "$W"
asum=$(sum "$W/a.mov")
bsum=$(sum "$W/b.mp4")
out=$(video-encode-cpu "$W" --subdir 2>&1); rc=$?
(( rc == 0 )) || fail "subdir encode rc=$rc out=$out"
check_pair "$W" a.mov encoded/a.mp4 "subdir rc=$rc out=$out"
got=$(cd "$W" && print -l -- *(N.) | sort | tr '\n' ' ')
[[ $got == "a.mov b.mp4 " ]] || fail "subdir: files beside sources: $got rc=$rc out=$out"
[[ $(sum "$W/a.mov") == $asum && $(sum "$W/b.mp4") == $bsum ]] || fail "subdir: sources changed rc=$rc out=$out"

W="$TEST_ROOT/w4"
mkdir -p "$W"
clip "$W/my clip.mov"
out=$(video-encode-cpu "$W" 2>&1); rc=$?
(( rc == 0 )) || fail "space name rc=$rc out=$out"
check_pair "$W" "my clip.mov" "my clip.mp4" "rc=$rc out=$out"

W="$TEST_ROOT/w5"
mkdir -p "$W"
clip "$W/a.mov"
print -r -- "just text" > "$W/notes.txt"
out=$(video-encode-cpu "$W" 2>&1); rc=$?
[[ $(<"$W/notes.txt") == "just text" ]] || fail "notes.txt changed rc=$rc out=$out"
got=$(cd "$W" && print -l -- *(N.) | sort | tr '\n' ' ')
[[ $got == "a.mov a.mp4 notes.txt " ]] || fail "non-video not ignored: $got rc=$rc out=$out"

W="$TEST_ROOT/w6"
mk_fixture "$W"
asum=$(sum "$W/a.mov")
bsum=$(sum "$W/b.mp4")
out=$(video-encode-cpu "$W" 2>&1); rc=$?
(( rc == 0 )) || fail "first run rc=$rc out=$out"
out2=$(video-encode-cpu "$W" 2>&1); rc2=$?
[[ $(vcodec "$W/a.mp4") == hevc ]] || fail "after second run a.mp4 not hevc rc=$rc2 out=$out2"
[[ $(vcodec "$W/b-h265.mp4") == hevc ]] || fail "after second run b-h265.mp4 not hevc rc=$rc2 out=$out2"
[[ $(sum "$W/a.mov") == $asum && $(sum "$W/b.mp4") == $bsum ]] || fail "second run changed sources rc=$rc2 out=$out2"
got=$(cd "$W" && print -l -- *(N.) | sort | tr '\n' ' ')
[[ $got == "a.mov a.mp4 b-h265.mp4 b.mp4 " ]] || fail "a second run re-encoded its own output: $got out=$out2"

W="$TEST_ROOT/w8"
mkdir -p "$W"
clip "$W/a.mkv"
clip "$W/c.avi"
out=$(video-encode-cpu "$W" 2>&1); rc=$?
(( rc == 0 )) || fail "mkv/avi rc=$rc out=$out"
check_pair "$W" a.mkv a.mp4 "mkv rc=$rc out=$out"
check_pair "$W" c.avi c.mp4 "avi rc=$rc out=$out"

for mode in "" --subdir; do
  W="$TEST_ROOT/w9$mode"
  mkdir -p "$W"
  clip "$W/a.mov"
  clip "$W/a.mkv"
  out=$(video-encode-cpu "$W" $mode 2>&1); rc=$?
  (( rc == 0 )) || fail "collision $mode rc=$rc out=$out"
  dst=a.mp4; [[ -n $mode ]] && dst=encoded/a.mp4
  check_pair "$W" a.mkv $dst "collision $mode rc=$rc out=$out"
  [[ $out == *"a.mov"*"a.mp4"* ]] || fail "collision $mode: the skipped a.mov is not reported: $out"
done

W="$TEST_ROOT/w7"
mkdir -p "$W"
out=$(video-encode-cpu "$W/nope" 2>&1); rc=$?
(( rc != 0 )) || fail "missing path returned 0 out=$out"

W="$TEST_ROOT/w-keep"
mkdir -p "$W"
clip "$W/keep.mov"
print -r -- "not a video" > "$W/keep.mp4"
out=$(video-encode-cpu "$W" 2>&1); rc=$?
[[ $(<"$W/keep.mp4") == "not a video" ]] || fail "an existing keep.mp4 was overwritten rc=$rc out=$out"

print -- "PASS: zsh encode function tests"
