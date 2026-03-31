# --- Powerlevel10k Instant Prompt (must stay first) ---
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# --- Homebrew (Apple Silicon) ---
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# ====== Performance Critical Section ======
{
  # ====== Zsh Options ======
  setopt INC_APPEND_HISTORY EXTENDED_HISTORY HIST_IGNORE_SPACE NONOMATCH
  unsetopt SHARE_HISTORY
  ZSH_DISABLE_COMPFIX=true

  # ====== Path Configuration ======
  typeset -U PATH path  # Prevent duplicate entries
  path=(
    "$HOME/.cargo/bin"
    "/opt/homebrew/opt/mozjpeg/bin"
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "$HOME/.local/bin"
    "/opt/homebrew/opt/openssl@3/bin"
    "$HOME/.opencode/bin"
    "$BUN_INSTALL/bin"
  )

  # ====== Java Configuration (before system paths) ======
  if java_home=$(/usr/libexec/java_home 2>/dev/null); then
    export JAVA_HOME=$java_home
    path=("$JAVA_HOME/bin" $path)
  fi

  # Add system paths
  path+=(
    /usr/local/bin
    /usr/bin
    /bin
    /usr/sbin
    /sbin
  )
  export PATH

  # ====== Environment Variables ======
  export BUN_INSTALL="$HOME/.bun"
  export EDITOR="nvim"
  export VISUAL="nvim"
  export HISTFILE=~/.zsh_history
  export HISTSIZE=100000
  export SAVEHIST=100000
  export PKG_CONFIG_PATH="/opt/homebrew/opt/blaze/share/pkgconfig:$PKG_CONFIG_PATH"
  # Use system clang from Xcode Command Line Tools
  # Uncomment and install llvm via brew if Homebrew clang is needed:
  # brew install llvm
  # export CC="/opt/homebrew/opt/llvm/bin/clang"
  # export CXX="/opt/homebrew/opt/llvm/bin/clang++"
  export HOMEBREW_CASK_OPTS="--no-quarantine"
  export HOMEBREW_NO_ENV_HINTS=1
}

# ====== Zinit Plugin Manager ======
export ZINIT_HOME="$HOME/.zinit"

# ====== Powerlevel10k Configuration ======
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

# ====== Completion Optimization ======
zstyle ':completion:*' accept-exact '*(N)'
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path ~/.zsh/cache

# bun completions
[ -s "$BUN_INSTALL/_bun" ] && source "$BUN_INSTALL/_bun"

# fnm (Fast Node Manager)
if command -v fnm &>/dev/null; then
  eval "$(fnm env --use-on-cd --log-level quiet)"
fi

# Clean up PATH - remove unwanted paths inherited from parent environment
path=(${path:#${HOME}/.rvm/bin})
export PATH
