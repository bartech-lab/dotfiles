# Core Zsh Configuration
# Zsh plugins and syntax highlighting (load first)
# NOTE: This replaces the plugin loading in ~/.zshrc

# Initialize zinit (if not already done)
if [[ -z "$ZINIT_HOME" ]]; then
  export ZINIT_HOME="$HOME/.zinit"
fi

# Ensure zinit is installed
if [[ ! -f "$ZINIT_HOME/bin/zinit.zsh" ]]; then
    print -P "%F{33}▓▒░ %F{220}Installing %F{33}ZDHARMA-CONTINUUM%F{220} Initiative Plugin Manager (%F{33}zinit%F{220})…%f"
    command mkdir -p "$ZINIT_HOME" && command chmod g-rwX "$ZINIT_HOME"
    command git clone https://github.com/zdharma-continuum/zinit "$ZINIT_HOME/bin" && \
        print -P "%F{33}▓▒░ %F{34}Installation successful.%f%b" || \
        print -P "%F{160}▓▒░ The clone has failed.%f%b"
fi

# Source zinit
source "$ZINIT_HOME/bin/zinit.zsh"
_zst_mark zinit
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# Load Powerlevel10k theme (if not already loaded)
if ! command -v p10k &>/dev/null; then
  zinit ice depth=1; zinit light romkatv/powerlevel10k
fi
_zst_mark p10k

# Load completions
zinit ice blockf; zinit light zsh-users/zsh-completions
_zst_mark completions

# Homebrew exports FPATH, so nested shells can inherit duplicate directories.
# Keep the first occurrence to preserve lookup order and stable cache counts.
typeset -U fpath

# Initialize completion after plugins add their completion directories.
# A full compinit rescans fpath and rewrites the dump on every shell start,
# which cost ~600 ms of the ~750 ms startup on macOS.  Rescan at most once a
# day and reuse the cached dump otherwise.
autoload -Uz compinit
ZSH_COMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump"
if [[ -n ${ZSH_COMPDUMP}(#qN.mh-24) ]]; then
  compinit -C -d "$ZSH_COMPDUMP"
else
  compinit -d "$ZSH_COMPDUMP"
fi
# Compile the dump so later shells load bytecode instead of parsing 57 KB.
if [[ ! -s ${ZSH_COMPDUMP}.zwc || ${ZSH_COMPDUMP} -nt ${ZSH_COMPDUMP}.zwc ]]; then
  zcompile -R -- "${ZSH_COMPDUMP}.zwc" "$ZSH_COMPDUMP" 2>/dev/null
fi
zinit cdreplay -q
# bun ships a script that calls compdef, so it must run after compinit.
[[ -s "$BUN_INSTALL/_bun" ]] && source "$BUN_INSTALL/_bun"
_zst_mark compinit

# Load autosuggestions
zinit light zsh-users/zsh-autosuggestions
_zst_mark autosuggest

# Note: Syntax highlighting is loaded LAST in ~/.zshrc after this file
# to ensure all aliases and functions are defined first
