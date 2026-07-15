# Brew Functions
# Homebrew helper functions
[[ "$DOTFILES_OS" == linux ]] && return 0

brewup() {
  echo "→ brew update"
  brew update || return

  echo "→ brew upgrade --formula"
  brew upgrade --formula || return

  echo "→ brew upgrade --cask"
  brew upgrade --cask || return
}

brewupgrade() {
  if (( $# == 0 )); then
    echo "usage: brewupgrade <formula> [formula ...]" >&2
    return 2
  fi

  brew upgrade --formula "$@"
}

brewcaskupgrade() {
  if (( $# == 0 )); then
    echo "usage: brewcaskupgrade <cask> [cask ...]" >&2
    return 2
  fi

  brew upgrade --cask "$@"
}
