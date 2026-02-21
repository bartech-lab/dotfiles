# Brew Functions
# Homebrew helper functions

brewup() {
  echo "→ brew update";         brew update
  echo "→ brew upgrade";        brew upgrade
  echo "→ brew upgrade --cask"; brew upgrade --cask
  echo "→ brew cleanup";        brew cleanup
}
