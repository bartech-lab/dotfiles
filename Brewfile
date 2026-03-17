# Minimal Dotfiles Brewfile
# Essential tools for a clean macOS setup
# 
# To install: brew bundle --file=~/dotfiles/Brewfile
# To check:   brew bundle check --file=~/dotfiles/Brewfile

# Taps - Additional package repositories
# autoupdate: Keeps Homebrew updated automatically
tap "homebrew/autoupdate"

# ============================================================================
# Core System Tools
# ============================================================================

# Essential utilities
brew "git"              # Version control (probably already installed, but ensures latest)
brew "gh"               # GitHub CLI for PRs, issues, repos
brew "curl"             # HTTP client (macOS built-in is outdated)
brew "coreutils"        # GNU core utilities (gcp, gmv, gdate, etc.)

# ============================================================================
# Modern CLI Replacements
# ============================================================================
# These replace default macOS commands with better alternatives
# See functions.md for usage details

brew "eza"              # Modern ls replacement (icons, git status, tree)
brew "ripgrep"          # Modern grep replacement (rg command, fast search)
brew "dust"             # Modern du replacement (visual disk usage)
brew "bottom"           # Modern top replacement (btm command, graphs)
brew "duf"              # Modern df replacement (colorful disk free)

# Optional but recommended
brew "fzf"              # Fuzzy finder (interactive file/command selection)
brew "zoxide"           # Smart cd replacement (z command, learns your habits)
brew "fd"               # Fast find replacement (simple, fast, user-friendly)

# ============================================================================
# Zsh Shell Enhancements
# ============================================================================

brew "zinit"            # Zsh plugin manager (fast, parallel loading)
brew "powerlevel10k"    # Fast Zsh theme with git status, instant prompt
brew "zsh-syntax-highlighting"   # Command highlighting as you type
brew "zsh-autosuggestions"       # Fish-like suggestions from history

# ============================================================================
# Media Processing Pipeline
# ============================================================================
# Used by: optimize-images, video-* functions
# See docs/media.md for details

brew "ffmpeg"           # Universal media converter (required for video/gif)
brew "parallel"         # GNU parallel for batch processing images
brew "zstd"             # Fast compression for archive() function
brew "gnu-tar"          # Reproducible archives (--sort=name, --mtime)
brew "unar"             # Universal archive extractor (zip, rar, 7z)
brew "mozjpeg"          # Provides cjpeg binary for image optimization
brew "yt-dlp"           # YouTube video downloader (ffmpeg companion)

# Image optimization tools (used by optimize-images)
brew "oxipng"           # PNG optimizer (lossless)
brew "pngquant"         # PNG quantizer (lossy, smaller files)
# Note: mozjpeg provides cjpeg for JPEG optimization

# ============================================================================
# Development Tools
# ============================================================================

brew "fnm"              # Fast Node Manager (faster nvm alternative)
brew "pipx"             # Python app installer (isolated packages)

# ============================================================================
# GUI Applications (Casks)
# ============================================================================

cask "brave-browser"            # Privacy-focused browser
cask "android-platform-tools"   # ADB, fastboot for Android development
cask "ghostty"                  # Modern terminal emulator (GPU-accelerated)
cask "handbrake-app"            # Video transcoder (GUI for ffmpeg tasks)
cask "iina"                     # Modern macOS video player
cask "keka"                     # Archive extractor (7z, rar support)
cask "kekaexternalhelper"       # Keka Finder integration
cask "pinta"                    # Image editor (Paint.NET alternative)
cask "stats"                    # System monitor in menu bar
# cask "tg-pro"                 # Temperature monitoring for Mac -> commenting this one out, causing checksum issue
cask "visual-studio-code"       # Code editor
cask "localsend"                # Cross-platform file sharing

# ============================================================================
# VS Code Extensions
# ============================================================================
# Installed automatically with VS Code

vscode "davidanson.vscode-markdownlint"   # Markdown linting
vscode "mikestead.dotenv"                 # .env file support
vscode "tamasfe.even-better-toml"         # TOML file support
vscode "ms-playwright.playwright"         # Playwright test support
