# Dotfiles

Personal shell functions and scripts for macOS.

## Setup

```bash
# 1. Clone (or use existing folder)
cd ~/dotfiles

# 2. Run installer
./install.sh

# 3. Add to your ~/.zshrc:
echo 'source ~/.config/zsh-dotfiles-loader.zsh' >> ~/.zshrc

# 4. Reload
source ~/.zshrc
```

## Available Functions

### Media
- `optimize-images` - Optimize JPEG/PNG images using parallel processing
- `video-remux` - Lossless copy videos to MP4 format (no re-encoding)
- `video-encode-cpu` - High-quality H.265 CPU encoding
- `video-encode-gpu` - Fast H.265 GPU encoding (VideoToolbox)

### Git
- `git-cleanup` - Remove merged branches and clean repository

## Adding New Functions

1. Create a new file in `zsh/functions/` (e.g., `03-docker.zsh`)
2. Add your functions
3. Reload shell: `source ~/.zshrc`

Functions are automatically loaded from all `.zsh` files in that directory.

## Archive

Old/obsolete scripts from previous setups are kept in `archive/`:
- `archive/IEH/` - IEH game scripts
- `archive/Manjaro/` - Manjaro Linux scripts

These are not loaded automatically but kept for reference.
