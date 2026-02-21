# Modern CLI Aliases
# Requires: brew install eza fd ripgrep dust bottom duf

# File listing (eza)
alias ls='eza --icons --group-directories-first'
alias ll='eza -la --icons --group-directories-first'
alias lt='eza --tree --level=2 --icons'

# File search (fd)
alias find='fd'

# Text search (ripgrep)
alias grep='rg'

# System monitoring (btm)
alias top='btm'

# Disk usage (dust)
alias du='dust'

# Disk free (duf)
alias df='duf'

# Note: coreutils are available but not aliased to avoid conflicts
# Use g-prefix for GNU versions: gls, gcat, etc.
