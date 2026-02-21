# Dotfiles

Personal shell functions and scripts for macOS.

## Prerequisites

The following tools must be installed for the functions to work:

### Required for all functions:
- **zsh** - Default shell on macOS (pre-installed)
- **parallel** - GNU parallel for parallel processing
  ```bash
  brew install parallel
  ```

### Required for image optimization (`optimize-images`):
- **cjpeg** (mozjpeg) - JPEG optimization
  ```bash
  brew install mozjpeg
  ```
- **oxipng** - PNG optimization
  ```bash
  brew install oxipng
  ```
- **pngquant** - PNG quantization (for default mode)
  ```bash
  brew install pngquant
  ```
- **ffmpeg** - For converting transparent PNGs to JPEG
  ```bash
  brew install ffmpeg
  ```

### Required for video operations (`video-remux`, `video-encode-cpu`, `video-encode-gpu`):
- **ffmpeg** - Video processing
  ```bash
  brew install ffmpeg
  ```

### Quick install (all dependencies at once):
```bash
brew install parallel mozjpeg oxipng pngquant ffmpeg
```

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
