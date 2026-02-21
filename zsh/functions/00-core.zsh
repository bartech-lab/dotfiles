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
autoload -Uz _zinit
(( ${+_comps} )) && _comps[zinit]=_zinit

# Load Powerlevel10k theme (if not already loaded)
if ! command -v p10k &>/dev/null; then
  zinit ice depth=1; zinit light romkatv/powerlevel10k
fi

# Load completions
zinit ice blockf; zinit light zsh-users/zsh-completions

# Load autosuggestions
zinit light zsh-users/zsh-autosuggestions

# Note: Syntax highlighting is loaded LAST in ~/.zshrc after this file
# to ensure all aliases and functions are defined first
