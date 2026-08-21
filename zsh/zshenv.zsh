# Sourced from ~/.zshenv so every zsh invocation gets it, including
# non-interactive agent shells that never read .zshrc.
#
# Wraps git to switch back to the default branch after a finished push.
# See docs/functions.md. Disable for one command: GIT_AUTOSWITCH_OFF=1 git push
if [[ -x "$HOME/dotfiles/scripts/bin/git-autoswitch" ]]; then
  git() { "$HOME/dotfiles/scripts/bin/git-autoswitch" "$@" }
fi
