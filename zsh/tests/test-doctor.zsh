#!/usr/bin/env zsh
emulate -R zsh

TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT
REPO_ROOT=${0:A:h:h:h}
[[ -f $REPO_ROOT/zsh/functions/40-dev.zsh ]] || REPO_ROOT=$PWD

fail() { print -u2 -- "FAIL: $*"; exit 1 }

typeset -i N=0 ERR=0 WARN=0
out="" rc=0 h="" log=""
BIN=$TEST_ROOT/bin
REAL=$TEST_ROOT/real
mkdir -p "$BIN" "$REAL"

make_real() { print -r -- "#!/bin/sh
exec '$2' \"\$@\"" > "$REAL/$1"; chmod +x "$REAL/$1" }

for t in zsh git uname grep egrep sed awk ls cat readlink ln rm mkdir dirname basename env head tail cut tr sort uniq wc date id stat which tee cp mv touch chmod find xargs sleep test expr printf echo true false; do
  p=$(PATH=/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin whence -p $t) && make_real $t "$p"
done

make_stub() {
  local name=$1 body=$2
  print -r -- "#!/bin/sh" > "$BIN/$name"
  print -r -- "$body" >> "$BIN/$name"
  chmod +x "$BIN/$name"
}

for t in brew pacman sudo xcode-select lsmod systemctl pgrep; do
  make_stub $t 'echo "'$t' $*" >> "$STUBLOG"
case " $* " in *" install "*|*" -S "*) [ -n "$STUB_FAIL_INSTALL" ] && exit 1;; esac
exit 0'
done
make_stub sw_vers 'echo "sw_vers $*" >> "$STUBLOG"; echo 14.0'
for t in zstd gtar ffmpeg cjpeg parallel eza rg dust btm duf; do
  make_stub $t 'exit 0'
done

new_home() {
  N=$((N + 1))
  h=$TEST_ROOT/home$N
  log=$TEST_ROOT/log$N
  mkdir -p "$h/.config"
  : > "$log"
  ln -s "$REPO_ROOT/zsh/functions.zsh" "$h/.config/zsh-dotfiles-loader.zsh"
  print -- 'source ~/.config/zsh-dotfiles-loader.zsh' > "$h/.zshrc"
}

run() {
  out=$(HOME=$h STUBLOG=$log PATH=$BIN:$REAL DOTFILES_DIR=$REPO_ROOT \
    DOTFILES_OS=${OS:-macos} STUB_FAIL_INSTALL=$FAIL zsh -c \
    'source "$DOTFILES_DIR/zsh/functions/40-dev.zsh"; dotfiles-doctor "$@"' _ "$@" 2>&1)
  rc=$?
}

counts() {
  ERR=0 WARN=0
  [[ $out =~ '([0-9]+) error\(s\), ([0-9]+) warning\(s\)' ]] && { ERR=$match[1]; WARN=$match[2] }
  [[ $out =~ '([0-9]+) warning\(s\) - safe' ]] && WARN=$match[1]
}

assert_sandboxed() {
  local line
  while IFS= read -r line; do
    case $line in
      brew\ *|pacman\ *|sudo\ pacman\ *|xcode-select\ *|sw_vers*|lsmod*|systemctl\ *|pgrep\ *) ;;
      *) fail "$1: unexpected command logged: $line" ;;
    esac
  done < "$log"
}

expect_has() { [[ $out == *$2* ]] || fail "$1: missing '$2' in: $out" }
expect_lacks() { [[ $out != *$2* ]] || fail "$1: unexpected '$2' in: $out" }

# 1. help and unknown option
new_home
for opt in --help -h; do
  run $opt
  (( rc == 0 )) || fail "$opt: rc=$rc"
  [[ $out == "Usage: dotfiles-doctor [--fix]"* ]] || fail "$opt: usage not first: $out"
  expect_lacks "$opt" "Dotfiles Setup"
done
[[ ! -s $log ]] || fail "help ran tools: $(<$log)"
run --bogus
(( rc == 1 )) || fail "unknown option: rc=$rc"
expect_has "unknown option" "❌ Unknown option: --bogus"
expect_lacks "unknown option" "Dotfiles Setup"
[[ ! -s $log ]] || fail "unknown option ran tools: $(<$log)"

# 2. loader states
new_home
run
expect_has "loader ok" "✅ Loader symlinked correctly"
counts; typeset -i base_err=$ERR base_warn=$WARN
(( base_err == 0 )) || fail "baseline has $base_err errors: $out"
(( rc == 0 )) || fail "baseline rc=$rc"

new_home
rm "$h/.config/zsh-dotfiles-loader.zsh"
ln -s "$TEST_ROOT/elsewhere.zsh" "$h/.config/zsh-dotfiles-loader.zsh"
run
expect_has "loader elsewhere" "Loader symlink points elsewhere"
expect_has "loader elsewhere" "Expected: $REPO_ROOT/zsh/functions.zsh"
expect_has "loader elsewhere" "Actual: $TEST_ROOT/elsewhere.zsh"
counts
(( ERR == base_err && WARN == base_warn + 1 )) || fail "elsewhere counts $ERR/$WARN vs $base_err/$base_warn"
[[ $(readlink "$h/.config/zsh-dotfiles-loader.zsh") == $TEST_ROOT/elsewhere.zsh ]] || fail "repointed without --fix"
run --fix
[[ $(readlink "$h/.config/zsh-dotfiles-loader.zsh") == $REPO_ROOT/zsh/functions.zsh ]] || fail "--fix did not repoint"
assert_sandboxed "loader fix"

new_home
rm "$h/.config/zsh-dotfiles-loader.zsh"
print -- "# real file" > "$h/.config/zsh-dotfiles-loader.zsh"
run --fix
expect_has "loader regular" "Loader exists but is not a symlink"
[[ ! -L $h/.config/zsh-dotfiles-loader.zsh && $(<$h/.config/zsh-dotfiles-loader.zsh) == "# real file" ]] || fail "regular loader modified"
counts
(( ERR == base_err && WARN == base_warn + 1 )) || fail "regular counts $ERR/$WARN"

new_home
rm "$h/.config/zsh-dotfiles-loader.zsh"
run
expect_has "loader missing" "Loader not found"
counts
(( ERR == base_err + 1 && WARN == base_warn )) || fail "missing counts $ERR/$WARN"
(( rc == 1 )) || fail "missing loader rc=$rc"
expect_has "loader missing" "${ERR} error(s), ${WARN} warning(s)"
expect_has "loader missing" "dotfiles-doctor --fix"
run --fix
expect_lacks "loader missing --fix" "Run 'dotfiles-doctor --fix'"
assert_sandboxed "loader missing fix"

# 3. .zshrc states
new_home
run
expect_has "zshrc ok" "Sourced in ~/.zshrc"

new_home
print -- '# nothing here' > "$h/.zshrc"
run
counts
(( ERR == base_err + 1 && WARN == base_warn )) || fail "zshrc missing-source counts $ERR/$WARN"
(( rc == 1 )) || fail "zshrc missing-source rc=$rc"
[[ $(<$h/.zshrc) == "# nothing here" ]] || fail "zshrc modified without --fix"
run --fix
[[ $(grep -c 'zsh-dotfiles-loader.zsh' "$h/.zshrc") == 1 ]] || fail "--fix append count: $(<$h/.zshrc)"
[[ $(tail -n 1 "$h/.zshrc") == 'source ~/.config/zsh-dotfiles-loader.zsh' ]] || fail "wrong appended line: $(<$h/.zshrc)"
[[ $(grep -c '^source ' "$h/.zshrc") == 1 ]] || fail "appended more than one source line: $(<$h/.zshrc)"
cp "$h/.zshrc" "$TEST_ROOT/zshrc.after1"
run --fix
cmp -s "$h/.zshrc" "$TEST_ROOT/zshrc.after1" || fail "second --fix changed .zshrc: $(<$h/.zshrc)"
counts
(( ERR == base_err )) || fail "errors after fix: $ERR"
assert_sandboxed "zshrc fix"

new_home
rm "$h/.zshrc"
run
expect_has "zshrc absent" "~/.zshrc not found"
counts
(( ERR == base_err && WARN == base_warn + 1 )) || fail "zshrc absent counts $ERR/$WARN"

# 4. summary and exit code
new_home
run
counts
(( ERR == 0 && WARN > 0 && rc == 0 )) || fail "warnings-only: $ERR/$WARN rc=$rc"
expect_has "warnings-only" "${WARN} warning(s) - safe to proceed"
expect_lacks "warnings-only" "error(s)"

new_home
rm "$h/.config/zsh-dotfiles-loader.zsh"
run
expect_lacks "error summary" "safe to proceed"
expect_lacks "error summary" "All systems operational"

# 5. --fix installs through the platform package manager
new_home
rm "$BIN/zstd"
OS=macos run --fix
expect_has "brew fix" "Installing zstd"
grep -qx 'brew install zstd' "$log" || fail "brew install not logged: $(<$log)"
! grep -q pacman "$log" || fail "pacman used on macos"
assert_sandboxed "brew fix"

new_home
OS=macos run
expect_has "no --fix" "❌ zstd"
! grep -q 'install' "$log" || fail "installed without --fix: $(<$log)"

new_home
OS=linux run --fix
grep -qx 'sudo pacman -S --needed --noconfirm zstd' "$log" || fail "pacman install not logged: $(<$log)"
! grep -q '^brew install' "$log" || fail "brew install on linux"
assert_sandboxed "pacman fix"

new_home
rm "$BIN/gtar"
FAIL=1 OS=macos run --fix
expect_has "install failure" "Failed to install zstd"
expect_has "install failure" "Failed to install gnu-tar"
expect_has "install failure" "Dotfiles Setup"
grep -qx 'brew install gnu-tar' "$log" || fail "run stopped after failed install: $(<$log)"
counts
(( rc == 1 && ERR >= 2 )) || fail "failed install: rc=$rc errors=$ERR"
assert_sandboxed "failed install"

new_home
FAIL=1 OS=linux run --fix
expect_has "pacman failure" "Failed to install zstd"
expect_has "pacman failure" "Dotfiles Setup"
assert_sandboxed "pacman failure"

print -- "PASS test-doctor"
