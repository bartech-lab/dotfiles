# Dotfiles Function Loader
# Sources shell config, then functions, then syntax highlighting (must be last)

DOTFILES_DIR="$HOME/dotfiles"

# --- Startup timing log (temporary) ---
# Diagnoses intermittent multi-second starts after hours of idle. Appends one
# line per interactive shell to ~/.cache/zsh-startup.log: seconds since the
# shell process started at each stage, up to the first usable prompt.
# Remove this block and the _zst_mark calls once the cause is fixed.
zmodload zsh/datetime
typeset -F SECONDS
typeset -ga _zst_marks
_zst_mark() {
  local v
  printf -v v '%.3f' $SECONDS
  _zst_marks+=("$1=$v")
}
_zst_precmd() {
  _zst_mark precmd
  precmd_functions=(${precmd_functions:#_zst_precmd})
}
_zst_line_init() {
  local ts
  _zst_mark prompt
  strftime -s ts '%Y-%m-%dT%H:%M:%S' $EPOCHSECONDS
  add-zle-hook-widget -d line-init _zst_line_init
  print -r -- "$ts os=$DOTFILES_OS pid=$$ term=${TERM_PROGRAM:-?} pwd=${PWD/#$HOME/~} gitstatusd=${GITSTATUS_DAEMON_PID_POWERLEVEL9K:-none} ${_zst_marks[*]}" >>| ~/.cache/zsh-startup.log
  unset _zst_marks
  typeset -gi SECONDS
}
_zst_mark loader

# 1. Load shell config (env vars, paths, prompt settings)
if [[ -f "$DOTFILES_DIR/zsh/zshrc.zsh" ]]; then
  source "$DOTFILES_DIR/zsh/zshrc.zsh"
fi
_zst_mark zshrc

# 2. Source all function files (00-core.zsh sets up zinit)
for func_file in "$DOTFILES_DIR/zsh/functions/"*.zsh(N); do
  # Skip macOS-only functions on Linux
  if [[ "$DOTFILES_OS" == linux && "$func_file" == *"/60-macos.zsh" ]]; then
    continue
  fi
  source "$func_file" || print -u2 "⚠️  Failed to load $func_file"
done
_zst_mark functions

# 3. Syntax highlighting (MUST be last - after all aliases/functions defined)
# zinit is available after 00-core.zsh loads
if (( ${+commands[zinit]} )) || [[ -f "$ZINIT_HOME/bin/zinit.zsh" ]]; then
  zinit light zsh-users/zsh-syntax-highlighting
fi
_zst_mark highlighting

# First precmd runs p10k init, which starts gitstatusd; line-init is the
# moment the prompt accepts input with plugins active.
precmd_functions=(_zst_precmd $precmd_functions)
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-init _zst_line_init
