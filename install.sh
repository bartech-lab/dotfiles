#!/bin/bash
set -e

DOTFILES_DIR="$HOME/dotfiles"
echo "🚀 Installing dotfiles..."

# Create necessary directories
mkdir -p ~/.config
echo "✓ Created ~/.config"

# Symlink the functions loader
if [[ ! -L ~/.config/zsh-dotfiles-loader.zsh ]]; then
    ln -sf "$DOTFILES_DIR/zsh/functions.zsh" ~/.config/zsh-dotfiles-loader.zsh
    echo "✓ Linked functions loader to ~/.config/zsh-dotfiles-loader.zsh"
else
    echo "✓ Functions loader already linked"
fi

# Add to .zshrc if not present
if ! grep -q "zsh-dotfiles-loader.zsh" ~/.zshrc 2>/dev/null; then
    echo "" >> ~/.zshrc
    echo "# Load dotfiles functions" >> ~/.zshrc
    echo 'source ~/.config/zsh-dotfiles-loader.zsh' >> ~/.zshrc
    echo "✓ Added dotfiles loader to ~/.zshrc"
else
    echo "✓ Dotfiles loader already in ~/.zshrc"
fi

echo ""
echo "📋 Available functions:"
echo ""
echo "Media:"
echo "  optimize-images [path] [--lossless]  - Optimize JPEG/PNG images (default: aggressive mode)"
echo "    --lossless              Use lossless oxipng only (no pngquant)"
echo "  video-remux [path]                   - Lossless copy videos to MP4 (optional path)"
echo "  video-encode-cpu [path]              - High-quality CPU encoding (optional path)"
echo "  video-encode-gpu [path]              - Fast GPU encoding (optional path)"
echo ""
echo "Git:"
echo "  git-cleanup                          - Clean merged git branches"
echo ""
echo "Homebrew:"
echo "  brewup                               - Update, upgrade, and cleanup Homebrew"
echo ""
echo "OpenCode:"
echo "  opencode                             - Launch OpenCode with default profile"
echo "  omo                                  - Launch Oh-My-OpenCode profile (with auto-update)"
echo "  oac                                  - Launch OpenAgentsControl profile (with auto-update)"
echo "  ocp                                  - List all available OpenCode profiles"
echo "  ocx-profile <name>                   - Launch OpenCode with specific profile"
echo ""
echo "Usage examples:"
echo "  optimize-images                      # Process current directory (aggressive mode)"
echo "  optimize-images ~/Downloads/pics     # Process specific directory"
echo "  optimize-images --lossless           # Use lossless mode only"
echo "  optimize-images ~/pics --lossless    # Path + lossless mode"
echo "  video-encode-gpu ~/Movies/videos     # Encode videos in specific folder"
echo "  brewup                               # Update Homebrew packages"
echo "  omo                                  # Launch Oh-My-OpenCode"
echo ""
