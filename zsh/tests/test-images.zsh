#!/usr/bin/env zsh
emulate -R zsh

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
REPO_ROOT=${0:A:h:h:h}

fail() { print -u2 -- "FAIL: $*"; exit 1 }

for t in ffmpeg ffprobe cjpeg pngquant oxipng; do command -v $t >/dev/null || { print -- "SKIP: image tests need $t"; exit 0 }; done

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
dims() { probe -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$1" }
sum() { cksum < "$1" }

mk_jpg() { ff -f lavfi -i testsrc=size=320x200 -frames:v 1 -q:v 2 "$1" || fail "fixture $1" }
mk_opaque() { ff -f lavfi -i testsrc=size=320x200 -frames:v 1 "$1" || fail "fixture $1" }
mk_alpha() { ff -f lavfi -i "testsrc=size=320x200,format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(lt(X,160),255,0)'" -frames:v 1 "$1" || fail "fixture $1" }

W="$TEST_ROOT/w1"
mkdir -p "$W"
mk_jpg "$W/photo.jpg"
before=$(sum "$W/photo.jpg")
out=$(optimize-images "$W/photo.jpg" 2>&1); rc=$?
(( rc == 0 )) || fail "single jpeg rc=$rc out=$out"
[[ -f $W/photo-opt.jpg ]] || fail "photo-opt.jpg missing rc=$rc out=$out"
[[ $(sum "$W/photo.jpg") == $before ]] || fail "photo.jpg changed rc=$rc out=$out"
[[ $(vcodec "$W/photo-opt.jpg") == mjpeg ]] || fail "photo-opt.jpg not mjpeg rc=$rc out=$out"
[[ $(dims "$W/photo-opt.jpg") == $(dims "$W/photo.jpg") ]] || fail "dimensions differ $(dims "$W/photo-opt.jpg") vs $(dims "$W/photo.jpg") rc=$rc out=$out"

W="$TEST_ROOT/w2"
mkdir -p "$W"
mk_jpg "$W/name.jpeg"
out=$(optimize-images "$W/name.jpeg" 2>&1); rc=$?
(( rc == 0 )) || fail "jpeg ext rc=$rc out=$out"
[[ -f $W/name-opt.jpeg ]] || fail "name-opt.jpeg missing rc=$rc out=$out"
[[ ! -e $W/name-opt.jpg ]] || fail "name-opt.jpg created for a .jpeg source rc=$rc out=$out"

W="$TEST_ROOT/w3"
mkdir -p "$W"
mk_jpg "$W/photo.jpg"
out=$(optimize-images "$W/photo.jpg" 2>&1); rc=$?
(( rc == 0 )) || fail "run 1 rc=$rc out=$out"
first=$(sum "$W/photo-opt.jpg")
out=$(optimize-images "$W/photo.jpg" 2>&1); rc=$?
(( rc == 0 )) || fail "run 2 rc=$rc out=$out"
[[ -f $W/photo-opt2.jpg ]] || fail "photo-opt2.jpg missing rc=$rc out=$out"
[[ $(sum "$W/photo-opt.jpg") == $first ]] || fail "photo-opt.jpg changed on run 2 rc=$rc out=$out"
out=$(optimize-images "$W/photo.jpg" 2>&1); rc=$?
(( rc == 0 )) || fail "run 3 rc=$rc out=$out"
[[ -f $W/photo-opt3.jpg ]] || fail "photo-opt3.jpg missing rc=$rc out=$out"
[[ $(sum "$W/photo-opt.jpg") == $first ]] || fail "photo-opt.jpg changed on run 3 rc=$rc out=$out"

W="$TEST_ROOT/w5"
mkdir -p "$W"
mk_alpha "$W/alpha.png"
mk_opaque "$W/opaque.png"
sa=$(sum "$W/alpha.png")
so=$(sum "$W/opaque.png")
out=$(optimize-images "$W" 2>&1); rc=$?
(( rc == 0 )) || fail "default png rc=$rc out=$out"
[[ $(sum "$W/alpha.png") == $sa ]] || fail "alpha.png changed rc=$rc out=$out"
[[ $(sum "$W/opaque.png") == $so ]] || fail "opaque.png changed rc=$rc out=$out"
[[ ! -e $W/optimized ]] || fail "optimized/ directory created rc=$rc out=$out"
got=$(cd "$W" && print -l -- alpha*(N) | grep -v '^alpha\.png$')
[[ -n $got ]] || fail "no output for alpha.png rc=$rc out=$out"
got=$(cd "$W" && print -l -- opaque*(N) | grep -v '^opaque\.png$')
[[ -n $got ]] || fail "no output for opaque.png rc=$rc out=$out"
[[ $(vcodec "$W/alpha-opt.png") == png && ! -e $W/alpha.jpg ]] || fail "docs: a transparent PNG stays PNG as name-opt.png: $(ls "$W")"
ff -i "$W/alpha.png" -f rawvideo -pix_fmt rgba "$TEST_ROOT/alpha-src.raw" && ff -i "$W/alpha-opt.png" -f rawvideo -pix_fmt rgba "$TEST_ROOT/alpha-out.raw" || fail "alpha decode"
python3 -c '
import sys
a, b = open(sys.argv[1], "rb").read(), open(sys.argv[2], "rb").read()
sys.exit(0 if len(a) == len(b) and a[3::4] == b[3::4] and 0 in a[3::4] else 1)' "$TEST_ROOT/alpha-src.raw" "$TEST_ROOT/alpha-out.raw" || fail "default mode kept the alpha channel of alpha.png"
[[ $(vcodec "$W/opaque-opt.png") == png && ! -e $W/opaque.jpg ]] || fail "docs: an opaque PNG becomes name-opt.png: $(ls "$W")"

W="$TEST_ROOT/w6"
mkdir -p "$W"
mk_jpg "$W/a.jpg"
mk_opaque "$W/b.png"
print -r -- "plain notes" > "$W/notes.txt"
out=$(optimize-images "$W" 2>&1); rc=$?
(( rc == 0 )) || fail "directory rc=$rc out=$out"
[[ -f $W/a-opt.jpg ]] || fail "a-opt.jpg missing rc=$rc out=$out"
got=$(cd "$W" && print -l -- b*(N) | grep -v '^b\.png$')
[[ -n $got ]] || fail "no output for b.png rc=$rc out=$out"
[[ $(<"$W/notes.txt") == "plain notes" ]] || fail "notes.txt changed rc=$rc out=$out"
got=$(cd "$W" && print -l -- notes*(N) | grep -v '^notes\.txt$')
[[ -z $got ]] || fail "output created for notes.txt: $got rc=$rc out=$out"
[[ ! -e $W/optimized ]] || fail "optimized/ directory created rc=$rc out=$out"

mk_jpg "$W/c.jpeg"
out=$(optimize-images "$W" 2>&1); rc=$?
[[ -f $W/c-opt.jpeg ]] || fail "directory mode skips .jpeg sources: $(ls "$W") out=$out"
[[ -z $(print -l -- "$W"/*-opt-opt*(N) "$W"/*-opt2-opt*(N)) ]] || fail "an earlier -opt output was optimized again: $(ls "$W")"
psnr=$(ffmpeg -nostdin -i "$W/a.jpg" -i "$W/a-opt.jpg" -lavfi psnr -f null - 2>&1 | sed -n 's/.*average:\([0-9.]*\).*/\1/p')
awk -v p="$psnr" 'BEGIN { exit !(p > 30) }' || fail "an optimized JPEG keeps quality 85 (PSNR $psnr dB)"

W="$TEST_ROOT/w7"
mkdir -p "$W"
mk_jpg "$W/cwd.jpg"
out=$(cd "$W" && optimize-images 2>&1); rc=$?
(( rc == 0 )) || fail "cwd rc=$rc out=$out"
[[ -f $W/cwd-opt.jpg ]] || fail "cwd mode: cwd-opt.jpg missing rc=$rc out=$out"

W="$TEST_ROOT/w8"
mkdir -p "$W"
mk_jpg "$W/my photo.jpg"
out=$(optimize-images "$W/my photo.jpg" 2>&1); rc=$?
(( rc == 0 )) || fail "space name rc=$rc out=$out"
[[ -f "$W/my photo-opt.jpg" ]] || fail "my photo-opt.jpg missing rc=$rc out=$out"
[[ $(vcodec "$W/my photo-opt.jpg") == mjpeg ]] || fail "my photo-opt.jpg unreadable rc=$rc out=$out"

W="$TEST_ROOT/w10"
mkdir -p "$W"
out=$(optimize-images "$W/nope" 2>&1); rc=$?
(( rc != 0 )) || fail "missing path returned 0 out=$out"

visible_same() {
  ff -i "$1" -f rawvideo -pix_fmt rgba "$TEST_ROOT/a.raw" && ff -i "$2" -f rawvideo -pix_fmt rgba "$TEST_ROOT/b.raw" || return 1
  python3 -c '
import sys
a, b = open(sys.argv[1], "rb").read(), open(sys.argv[2], "rb").read()
same = len(a) == len(b) and all(a[i + 3] == b[i + 3] and (a[i + 3] == 0 or a[i:i + 3] == b[i:i + 3]) for i in range(0, len(a), 4))
sys.exit(0 if same else 1)' "$TEST_ROOT/a.raw" "$TEST_ROOT/b.raw"
}

W="$TEST_ROOT/w-lossless"
mkdir -p "$W"
mk_alpha "$W/alpha.png"
mk_opaque "$W/opaque.png"
out=$(optimize-images "$W" --lossless 2>&1); rc=$?
(( rc == 0 )) || fail "lossless run rc=$rc out=$out"
[[ -f $W/alpha-opt.png && -f $W/opaque-opt.png ]] || fail "lossless outputs are name-opt.png: $(ls "$W") out=$out"
[[ -z $(print -l -- "$W"/*.jpg(N)) ]] || fail "lossless mode made a JPEG: $(ls "$W")"
visible_same "$W/alpha.png" "$W/alpha-opt.png" || fail "lossless changed alpha or a visible pixel of alpha.png"
visible_same "$W/opaque.png" "$W/opaque-opt.png" || fail "lossless changed a pixel of opaque.png"

print -- "PASS: zsh image function tests"
