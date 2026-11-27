# Sourced from ~/.zshenv so every zsh invocation gets it, including
# non-interactive agent shells that never read .zshrc.
#
# Wraps git to switch back to the default branch after a finished push.
# See docs/functions.md. Disable for one command: GIT_AUTOSWITCH_OFF=1 git push
if [[ -x "$HOME/dotfiles/scripts/bin/git-autoswitch" ]]; then
  git() { "$HOME/dotfiles/scripts/bin/git-autoswitch" "$@" }
fi

# Commands run over ssh and by agent tools read only ~/.zshenv, so they missed ~/.local/bin (claude,
# ops tools) and, on macOS, Homebrew. Append them; interactive shells reorder PATH in .zshrc anyway.
typeset -U path
[[ -d "$HOME/.local/bin" ]] && path+=("$HOME/.local/bin")
[[ -d /opt/homebrew/bin ]] && path+=(/opt/homebrew/bin)
