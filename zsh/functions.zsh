# Dotfiles Function Loader
# This file sources all function files from the dotfiles repo

DOTFILES_DIR="$HOME/dotfiles"

# Source all .zsh files from functions directory
for func_file in "$DOTFILES_DIR/zsh/functions/"*.zsh(N); do
  source "$func_file" || print -u2 "⚠️  Failed to load $func_file"
done
