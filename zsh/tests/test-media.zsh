#!/usr/bin/env zsh
emulate -R zsh

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
REPO_ROOT=${0:A:h:h:h}

fail() { print -u2 -- "FAIL: $*"; exit 1 }

for t in ffmpeg ffprobe; do command -v $t >/dev/null || { print -- "SKIP: media tests need $t"; exit 0 }; done

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
vdur() { probe -show_entries format=duration -of csv=p=0 "$1" }
close_enough() { awk -v a="$1" -v b="$2" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d < 0.25) }' }
sum() { cksum < "$1" }

h264_mov() { ff -f lavfi -i testsrc=size=640x360:rate=24 -f lavfi -i sine=frequency=440 -t 2 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$1" || fail "fixture $1" }
mpeg4_clip() { ff -f lavfi -i testsrc=size=320x180:rate=24 -t 2 -c:v mpeg4 -an "$1" || fail "fixture $1" }

W="$TEST_ROOT/w1"
mkdir -p "$W"
h264_mov "$W/clip.mov"
before=$(sum "$W/clip.mov")
out=$(video-remux "$W/clip.mov" 2>&1); rc=$?
(( rc == 0 )) || fail "single file remux rc=$rc out=$out"
[[ -f $W/clip.mp4 ]] || fail "clip.mp4 missing rc=$rc out=$out"
[[ $(vcodec "$W/clip.mp4") == h264 ]] || fail "clip.mp4 not readable h264 rc=$rc out=$out"
[[ $(sum "$W/clip.mov") == $before ]] || fail "clip.mov changed rc=$rc out=$out"
close_enough "$(vdur "$W/clip.mov")" "$(vdur "$W/clip.mp4")" || fail "clip duration differs rc=$rc out=$out"

W="$TEST_ROOT/w2"
mkdir -p "$W"
mpeg4_clip "$W/s.avi"
mpeg4_clip "$W/s.mkv"
for f in s.avi s.mkv; do
  rm -f "$W/s.mp4"
  out=$(video-remux "$W/$f" 2>&1); rc=$?
  (( rc == 0 )) || fail "$f remux rc=$rc out=$out"
  [[ -f $W/s.mp4 ]] || fail "$f produced no s.mp4 rc=$rc out=$out"
  [[ $(vcodec "$W/s.mp4") == mpeg4 ]] || fail "$f codec changed to $(vcodec "$W/s.mp4") rc=$rc out=$out"
  close_enough "$(vdur "$W/$f")" "$(vdur "$W/s.mp4")" || fail "$f duration $(vdur "$W/$f") vs $(vdur "$W/s.mp4") rc=$rc out=$out"
  fc_src=$(probe -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$W/$f")
  fc_dst=$(probe -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$W/s.mp4")
  [[ $fc_src == $fc_dst ]] || fail "$f frames $fc_src vs $fc_dst rc=$rc out=$out"
done

mk_dir_fixture() {
  rm -rf "$1"
  mkdir -p "$1"
  h264_mov "$1/a.mov"
  mpeg4_clip "$1/b.mkv"
  mpeg4_clip "$1/c.avi"
  mpeg4_clip "$1/d.mp4"
}

W="$TEST_ROOT/w3"
mk_dir_fixture "$W"
dsum=$(sum "$W/d.mp4")
out=$(video-remux "$W" 2>&1); rc=$?
(( rc == 0 )) || fail "directory remux rc=$rc out=$out"
for n in a b c; do
  [[ -f $W/$n.mp4 ]] || fail "$n.mp4 missing rc=$rc out=$out"
  [[ -n $(vcodec "$W/$n.mp4") ]] || fail "$n.mp4 unreadable rc=$rc out=$out"
done
[[ $(sum "$W/d.mp4") == $dsum ]] || fail "d.mp4 modified rc=$rc out=$out"
got=$(cd "$W" && print -l -- *.mp4(N) | sort | tr '\n' ' ')
[[ $got == "a.mp4 b.mp4 c.mp4 d.mp4 " ]] || fail "unexpected mp4 set: $got rc=$rc out=$out"
[[ ! -e $W/d.mp4.mp4 ]] || fail "d.mp4.mp4 created"
[[ -f $W/a.mov && -f $W/b.mkv && -f $W/c.avi ]] || fail "sources removed rc=$rc out=$out"

W="$TEST_ROOT/w4"
mk_dir_fixture "$W"
out=$(cd "$W" && video-remux 2>&1); rc=$?
(( rc == 0 )) || fail "cwd remux rc=$rc out=$out"
for n in a b c; do [[ -f $W/$n.mp4 ]] || fail "cwd mode: $n.mp4 missing rc=$rc out=$out"; done

W="$TEST_ROOT/w5"
mk_dir_fixture "$W"
out=$(video-remux "$W" --subdir 2>&1); rc=$?
(( rc == 0 )) || fail "subdir remux rc=$rc out=$out"
for n in a b c; do
  [[ -f $W/mp4/$n.mp4 ]] || fail "subdir: mp4/$n.mp4 missing rc=$rc out=$out"
  [[ ! -e $W/$n.mp4 ]] || fail "subdir: $n.mp4 created beside source rc=$rc out=$out"
done

W="$TEST_ROOT/w6"
mkdir -p "$W"
h264_mov "$W/my clip.mov"
out=$(video-remux "$W/my clip.mov" 2>&1); rc=$?
(( rc == 0 )) || fail "space name rc=$rc out=$out"
[[ -f "$W/my clip.mp4" ]] || fail "my clip.mp4 missing rc=$rc out=$out"
[[ -n $(vcodec "$W/my clip.mp4") ]] || fail "my clip.mp4 unreadable rc=$rc out=$out"

W="$TEST_ROOT/w7"
mkdir -p "$W"
h264_mov "$W/CLIP.MOV"
out=$(video-remux "$W/CLIP.MOV" 2>&1); rc=$?
(( rc == 0 )) || fail "upper-case extension rc=$rc out=$out"
[[ -f "$W/CLIP.mp4" ]] || fail "CLIP.mp4 missing rc=$rc out=$out"
[[ -n $(vcodec "$W/CLIP.mp4") ]] || fail "CLIP.mp4 unreadable rc=$rc out=$out"

if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q libvpx-vp9; then
  W="$TEST_ROOT/w8"
  mkdir -p "$W"
  ff -f lavfi -i testsrc=size=320x180:rate=24 -t 1 -c:v libvpx-vp9 -b:v 200k -an "$W/x.webm" || fail "fixture x.webm"
  out=$(video-remux "$W/x.webm" 2>&1); rc=$?
  (( rc == 0 )) || fail "webm remux rc=$rc out=$out"
  [[ -f $W/x.mp4 ]] || fail "x.mp4 missing rc=$rc out=$out"
  [[ -n $(vcodec "$W/x.mp4") ]] || fail "x.mp4 has no video stream rc=$rc out=$out"
else
  print -- "SKIP: libvpx-vp9 unavailable, webm case"
fi

W="$TEST_ROOT/w9"
mkdir -p "$W"
h264_mov "$W/twice.mov"
srcsum=$(sum "$W/twice.mov")
out=$(video-remux "$W/twice.mov" 2>&1); rc=$?
(( rc == 0 )) || fail "first run rc=$rc out=$out"
firstsum=$(sum "$W/twice.mp4")
out2=$(video-remux "$W/twice.mov" 2>&1); rc2=$?
[[ -n $(vcodec "$W/twice.mp4") ]] || fail "after second run, twice.mp4 not a valid video rc=$rc2 out=$out2"
[[ $(sum "$W/twice.mov") == $srcsum ]] || fail "second run changed source rc=$rc2 out=$out2"

W="$TEST_ROOT/w-keep"
mkdir -p "$W"
h264_mov "$W/keep.mov"
print -r -- "not a video" > "$W/keep.mp4"
mpeg4_clip "$W/UPPER.MOV"
out=$(video-remux "$W" 2>&1); rc=$?
[[ $(<"$W/keep.mp4") == "not a video" ]] || fail "an existing keep.mp4 was overwritten rc=$rc out=$out"
[[ $(vcodec "$W/UPPER.mp4") == mpeg4 ]] || fail "directory mode skips an upper-case .MOV rc=$rc out=$out"

if ffmpeg -hide_banner -encoders 2>/dev/null | grep -q ' libvpx '; then
  W="$TEST_ROOT/w-vp8"
  mkdir -p "$W"
  ff -f lavfi -i testsrc=size=320x180:rate=24 -t 1 -c:v libvpx -b:v 200k -an "$W/v8.webm" || fail "fixture v8.webm"
  out=$(video-remux "$W/v8.webm" 2>&1); rc=$?
  [[ $(vcodec "$W/v8.mp4") == h264 ]] || fail "a VP8 webm that mp4 cannot hold is converted to H.264 rc=$rc out=$out"
else
  print -- "SKIP: libvpx unavailable, VP8 webm fallback case"
fi

W="$TEST_ROOT/w10"
mkdir -p "$W"
out=$(video-remux "$W/nope" 2>&1); rc=$?
(( rc != 0 )) || fail "missing path returned 0 out=$out"

G="$TEST_ROOT/g"
mkdir -p "$G"
cd "$G"
ff -f lavfi -i testsrc=size=640x360:rate=24 -t 2 -c:v libx264 -pix_fmt yuv420p -an in.mp4 || fail "fixture in.mp4"

out=$(video-to-gif 2>&1); rc=$?
(( rc != 0 )) || fail "no-arg gif returned 0 out=$out"
[[ $out == *[Uu]sage* ]] || fail "no-arg gif lacks usage rc=$rc out=$out"

out=$(video-to-gif missing.mp4 2>&1); rc=$?
(( rc != 0 )) || fail "missing input gif returned 0 out=$out"
[[ ! -e missing.gif ]] || fail "missing input created missing.gif"

print -r -- keepme > exist.gif
gsum=$(sum exist.gif)
out=$(video-to-gif in.mp4 exist.gif 2>&1); rc=$?
(( rc != 0 )) || fail "existing output returned 0 out=$out"
[[ $(sum exist.gif) == $gsum ]] || fail "existing gif modified rc=$rc out=$out"

out=$(video-to-gif in.mp4 2>&1); rc=$?
(( rc == 0 )) || fail "default gif rc=$rc out=$out"
[[ -f in.gif ]] || fail "in.gif missing rc=$rc out=$out"
[[ $(head -c 4 in.gif) == GIF8 ]] || fail "in.gif not a GIF rc=$rc out=$out"
w=$(probe -select_streams v:0 -show_entries stream=width -of csv=p=0 in.gif)
[[ $w == 420 ]] || fail "default width $w rc=$rc out=$out"
frames_default=$(probe -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 in.gif)
video-to-gif in.mp4 f12.gif 12 >/dev/null 2>&1 || fail "explicit fps 12 gif failed"
frames_12=$(probe -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 f12.gif)
(( frames_default == frames_12 )) || fail "default fps matches an explicit 12: default $frames_default, 12 gives $frames_12"

out=$(video-to-gif in.mp4 w200.gif 12 200 2>&1); rc=$?
(( rc == 0 )) || fail "width 200 gif rc=$rc out=$out"
w=$(probe -select_streams v:0 -show_entries stream=width -of csv=p=0 w200.gif)
[[ $w == 200 ]] || fail "custom width $w rc=$rc out=$out"

out=$(video-to-gif in.mp4 f4.gif 4 2>&1); rc=$?
(( rc == 0 )) || fail "fps 4 gif rc=$rc out=$out"
frames_4=$(probe -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 f4.gif)
(( frames_4 > 0 && frames_4 < frames_default )) || fail "fps 4 frames=$frames_4 default frames=$frames_default rc=$rc out=$out"

print -- "PASS: zsh media function tests"
