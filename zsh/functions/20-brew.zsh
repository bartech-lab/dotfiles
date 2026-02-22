# Brew Functions
# Homebrew helper functions

brewup() {
  echo "→ brew update";         brew update
  echo "→ brew upgrade";        brew upgrade
  echo "→ brew upgrade --cask"; brew upgrade --cask
  echo "→ brew bundle";         brew bundle --file="$HOME/dotfiles/Brewfile"
  echo "→ brew cleanup";        brew cleanup
}
