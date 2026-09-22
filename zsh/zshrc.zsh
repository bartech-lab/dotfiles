# --- Platform Detection (must be first) ---
case "$(uname -s)" in
  Darwin) export DOTFILES_OS=macos ;;
  Linux)  export DOTFILES_OS=linux ;;
  *)      export DOTFILES_OS=unknown ;;
esac

# Restore interactive colors when the persistent Mac terminal inherits NO_COLOR.
if [[ "$DOTFILES_OS" == macos && "${TERM_PROGRAM:-}" == WezTerm && -o interactive ]]; then
  unset NO_COLOR
fi

# Show the prompt only after shell initialization finishes.
# An early prompt can invite Ctrl+C before functions and plugins finish loading.
typeset -g POWERLEVEL9K_INSTANT_PROMPT=off

# --- Homebrew (macOS only) ---
if [[ "$DOTFILES_OS" == macos && -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
_zst_mark brew

# ====== Performance Critical Section ======
{
  # ====== Zsh Options ======
  setopt INC_APPEND_HISTORY EXTENDED_HISTORY HIST_IGNORE_SPACE NONOMATCH
  unsetopt SHARE_HISTORY
  ZSH_DISABLE_COMPFIX=true

  # ====== Path Configuration ======
  typeset -U PATH path  # Prevent duplicate entries
  path=(
    "$HOME/dotfiles/scripts/bin"
    "$HOME/.local/bin"
  )

  # npm global bin (fnm default alias, version-agnostic)
  path+=("$HOME/.local/share/fnm/aliases/default/bin")

  # macOS-specific paths (Homebrew)
  if [[ "$DOTFILES_OS" == macos ]]; then
    path=(
      "/opt/homebrew/opt/mozjpeg/bin"
      "/opt/homebrew/bin"
      "/opt/homebrew/sbin"
      "/opt/homebrew/opt/openssl@3/bin"
      $path
    )
  fi

  # ====== Java Configuration (macOS only) ======
  if [[ "$DOTFILES_OS" == macos ]] && java_home=$(/usr/libexec/java_home 2>/dev/null); then
    export JAVA_HOME=$java_home
    path=("$JAVA_HOME/bin" $path)
  fi
  _zst_mark java

  # Add system paths
  path+=(
    /usr/local/bin
    /usr/bin
    /bin
    /usr/sbin
    /sbin
  )

  # Shims shadow real binaries, so they must win over Homebrew and /usr/bin.
  # `typeset -U path` keeps this first copy and drops the duplicate below.
  # Child processes normally inherit this order. install.sh also links the shim
  # into ~/.local/bin for agents that rebuild PATH. See docs/functions.md.
  path=("$HOME/dotfiles/scripts/shims" $path)
  export PATH

  # ====== Environment Variables ======
  export BUN_INSTALL="$HOME/.bun"
  export EDITOR="nvim"
  export VISUAL="nvim"
  export HISTFILE=~/.zsh_history
  export HISTSIZE=100000
  export SAVEHIST=100000

  # macOS-specific environment
  if [[ "$DOTFILES_OS" == macos ]]; then
    export PKG_CONFIG_PATH="/opt/homebrew/opt/blaze/share/pkgconfig:$PKG_CONFIG_PATH"
    export HOMEBREW_CASK_OPTS="--no-quarantine"
    export HOMEBREW_NO_ENV_HINTS=1
  fi

  # Linux-specific environment (NVIDIA Wayland)
  if [[ "$DOTFILES_OS" == linux ]]; then
    export LIBVA_DRIVER_NAME=nvidia
    export __GL_GSYNC_ALLOWED=1
    export __GL_VRR_ALLOWED=1
    export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
    export MOZ_ENABLE_WAYLAND=1
  fi
}

# ====== Zinit Plugin Manager ======
export ZINIT_HOME="$HOME/.zinit"

# ====== Powerlevel10k Configuration ======
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# ====== Completion Optimization ======
zstyle ':completion:*' accept-exact '*(N)'
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path ~/.zsh/cache

# fnm (Fast Node Manager), loaded lazily. Running `fnm env` at startup
# occasionally stalled the prompt for ~6 s. The default Node is already on
# PATH (npm global bin above), so the fnm binary first runs on the first `fnm`
# call or the first cd into a directory with a Node version file.
# install.sh installs fnm on Linux with its curl installer, into FNM_DIR.
[[ -x "$HOME/.local/share/fnm/fnm" ]] && path+=("$HOME/.local/share/fnm")
if command -v fnm &>/dev/null; then
  _fnm_lazy_init() {
    unfunction fnm
    add-zsh-hook -d chpwd _fnm_lazy_chpwd
    eval "$(command fnm env --use-on-cd --log-level quiet)"
  }
  fnm() { _fnm_lazy_init; fnm "$@"; }
  _fnm_lazy_chpwd() {
    [[ -f .node-version || -f .nvmrc || -f package.json ]] || return 0
    _fnm_lazy_init
    _fnm_autoload_hook
  }
  autoload -U add-zsh-hook
  add-zsh-hook chpwd _fnm_lazy_chpwd
fi
_zst_mark fnm

# Clean up PATH - remove unwanted paths inherited from parent environment
path=(${path:#${HOME}/.rvm/bin})
export PATH
