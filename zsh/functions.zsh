# Dotfiles Function Loader
# Sources shell config, then functions, then syntax highlighting (must be last)

DOTFILES_DIR="$HOME/dotfiles"

# 1. Load shell config (env vars, paths, p10k instant prompt)
if [[ -f "$DOTFILES_DIR/zsh/zshrc.zsh" ]]; then
  source "$DOTFILES_DIR/zsh/zshrc.zsh"
fi

# 2. Source all function files (00-core.zsh sets up zinit)
for func_file in "$DOTFILES_DIR/zsh/functions/"*.zsh(N); do
  source "$func_file" || print -u2 "⚠️  Failed to load $func_file"
done

# 3. Syntax highlighting (MUST be last - after all aliases/functions defined)
# zinit is available after 00-core.zsh loads
if (( ${+commands[zinit]} )) || [[ -f "$ZINIT_HOME/bin/zinit.zsh" ]]; then
  zinit light zsh-users/zsh-syntax-highlighting
fi
