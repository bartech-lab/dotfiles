# Modern CLI Aliases
# Requires: brew install eza dust bottom duf

# File listing (eza)
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first'
alias lt='eza --tree --level=2 --icons'

# System monitoring (btm)
alias top='btm'

# Disk usage (dust)
alias du='dust'

# Disk free (duf)
alias df='duf'

# Note: coreutils are available but not aliased to avoid conflicts
# Use g-prefix for GNU versions: gls, gcat, etc.

# fzf defaults (fuzzy finder)
export FZF_DEFAULT_OPTS='--height=40% --layout=reverse --border --info=inline'
export FZF_DEFAULT_COMMAND='fd --type f --strip-cwd-prefix --hidden --exclude .git'

# Copy current directory to clipboard (platform-aware)
cpwd() {
    local clip
    if [[ "$DOTFILES_OS" == macos ]]; then
        clip="pbcopy"
    elif command -v wl-copy &>/dev/null; then
        clip="wl-copy"
    elif command -v xclip &>/dev/null; then
        clip="xclip -selection clipboard"
    else
        echo "❌ Clipboard tool not found. Install wl-copy or xclip."
        return 1
    fi
    pwd | tr -d '\n' | eval "$clip"
    echo "📋 Path copied: $(pwd)"
}
