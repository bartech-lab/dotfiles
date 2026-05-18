# Brew Functions
# Homebrew helper functions
[[ "$DOTFILES_OS" == linux ]] && return 0

brewup() {
  echo "→ brew update";         brew update
  echo "→ brew upgrade";        brew upgrade
  echo "→ brew upgrade --cask"; brew upgrade --cask
  echo "→ brew cleanup";        brew cleanup
}
