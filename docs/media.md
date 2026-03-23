# Media Functions

Image and video processing utilities.

## optimize-images

Batch optimize JPEG and PNG images for web.

```bash
optimize-images [path] [--lossless]
```

**Arguments:**
- `path` - Directory or file to optimize (defaults to current directory)
- `--lossless` - Use lossless PNG optimization only

**Default behavior:**
- Aggressive optimization
- Parallel processing for speed
- Transparent PNGs → JPEG (better compression)
- Non-transparent PNGs → optimized PNG
- JPEGs → mozjpeg optimized

**Lossless mode:**
- PNGs → oxipng optimized (preserves transparency)
- JPEGs → mozjpeg optimized

**Examples:**
```bash
optimize-images                    # Optimize all images in current dir
optimize-images ./assets          # Optimize specific directory
optimize-images photo.jpg         # Optimize single file
optimize-images ./assets --lossless  # Lossless PNG optimization
```

**Requirements:**
- `parallel` - Parallel processing
- `mozjpeg` (provides `cjpeg`) - JPEG optimization
- `oxipng` - PNG optimization
- `pngquant` - PNG quantization
- `ffmpeg` - Image conversion

**Performance:**
- Uses all CPU cores via GNU parallel
- Processes multiple images simultaneously
- Shows progress bar

**File naming:**
- Original files are overwritten
- Creates backups in `optimized/` directory
- Final files keep original names

## video-remux

Losslessly remux videos to MP4 container.

```bash
video-remux [path] [--subdir]
```

**Arguments:**
- `path` - Directory or file to remux (defaults to current directory)
- `--subdir` - Create `mp4/` subdirectory (legacy behavior)

**Supported formats:**
- MOV → MP4 (lossless remux)
- MKV → MP4 (lossless remux)
- AVI → MP4 (lossless remux)
- FLV → MP4 (lossless remux)
- WEBM → MP4 (remux when possible, otherwise H.264/AAC conversion)
- Animated WEBP → MP4 (H.264 conversion)

**What it does:**
- MOV/MKV/AVI: no re-encoding (preserves quality)
- MOV/MKV/AVI: copies video/audio streams
- MOV/MKV/AVI: changes container only
- MOV/MKV/AVI: much faster than re-encoding
- WEBM: tries lossless stream copy first, falls back to H.264/AAC if needed
- Animated WEBP: converts frames to MP4 (cannot be losslessly remuxed)

**File naming:**
- Source files with non-MP4 extension → same basename with `.mp4`
- Source files with `.mp4` extension → basename with `_remuxed.mp4` suffix

**Examples:**
```bash
video-remux                   # Remux all videos in current dir
video-remux ./recordings      # Remux specific directory
video-remux video.mov         # Remux single file (outputs video.mp4)
video-remux clip.mp4          # Remux MP4 (outputs clip_remuxed.mp4)
video-remux --subdir          # Use mp4/ subdirectory
```

**Output:**
- By default: same directory, smart naming
- With `--subdir`: creates `mp4/` directory
- Original files preserved

## video-encode-cpu

High-quality H.265 CPU encoding.

```bash
video-encode-cpu [path] [--subdir]
```

**Arguments:**
- `path` - Directory or file to encode (defaults to current directory)
- `--subdir` - Create `encoded/` subdirectory (legacy behavior)

**Codec:** libx265 (H.265/HEVC)

**Quality:** Best possible, slower processing

**Use case:**
- Archival storage
- When quality matters more than speed
- Scenes with lots of detail/motion

**File naming:**
- Source files with non-MP4 extension → same basename with `.mp4`
- Source files with `.mp4` extension → basename with `_h265.mp4` suffix

**Examples:**
```bash
video-encode-cpu              # Encode all videos in current dir
video-encode-cpu ./videos     # Encode specific directory
video-encode-cpu input.mov    # Encode single file (outputs input.mp4)
video-encode-cpu clip.mp4     # Encode MP4 (outputs clip_h265.mp4)
video-encode-cpu --subdir     # Use encoded/ subdirectory
```

**Output:**
- By default: same directory, smart naming
- With `--subdir`: creates `encoded/` directory
- H.265 codec for better compression

## video-encode-gpu

Fast H.265 GPU encoding using Apple VideoToolbox.

```bash
video-encode-gpu [path] [--subdir]
```

**Arguments:**
- `path` - Directory or file to encode (defaults to current directory)
- `--subdir` - Create `encoded/` subdirectory (legacy behavior)

**Codec:** hevc_videotoolbox (hardware accelerated)

**Quality:** Good, very fast processing

**Use case:**
- Quick encoding
- Screen recordings
- When speed matters more than max quality

**File naming:**
- Source files with non-MP4 extension → same basename with `.mp4`
- Source files with `.mp4` extension → basename with `_h265.mp4` suffix

**Examples:**
```bash
video-encode-gpu              # Encode all videos in current dir
video-encode-gpu ./recordings # Encode specific directory
video-encode-gpu screencast.mov  # Encode single file (outputs screencast.mp4)
video-encode-gpu clip.mp4     # Encode MP4 (outputs clip_h265.mp4)
video-encode-gpu --subdir     # Use encoded/ subdirectory
```

**Output:**
- By default: same directory, smart naming
- With `--subdir`: creates `encoded/` directory
- H.265 codec, hardware accelerated

## video-to-gif

Convert videos to optimized animated GIF with hardware acceleration and duplicate frame removal.

```bash
video-to-gif <input.mp4> [output.gif] [fps] [width]
```

**Arguments:**
- `input.mp4` - Input video file (required)
- `output.gif` - Output filename (optional, defaults to `<input>.gif`)
- `fps` - Frames per second (optional, defaults to 12)
- `width` - Width in pixels (optional, defaults to 420)

**Features:**
- Hardware acceleration (VideoToolbox on macOS)
- Duplicate frame removal (mpdecimate)
- Optimized palette with diff mode
- Prevents overwriting existing files

**Examples:**
```bash
video-to-gif demo.mp4                    # demo.gif, 12fps, 420px
video-to-gif demo.mp4 animation.gif      # Custom name
video-to-gif demo.mp4 output.gif 30      # 30fps
video-to-gif demo.mp4 output.gif 15 720  # 15fps, 720px width
```

**Use case:**
- Documentation
- GitHub issues/comments
- Quick demos

**Tips:**
- Lower FPS = smaller file
- Lower width = smaller file
- For short clips only (GIFs get huge)

## Performance Comparison

| Function | Speed | Quality | Use Case |
|----------|-------|---------|----------|
| `video-remux` | Instant | 100% (no change) | Container swap only |
| `video-encode-gpu` | Fast | Good | Screen recordings |
| `video-encode-cpu` | Slow | Best | Archival storage |

## Batch Processing

All media functions support batch processing:

```bash
# Process entire directory
optimize-images ./assets

# Process with find
find . -name "*.mov" -exec video-remux {} \;

# Process specific files
video-encode-cpu video1.mov video2.mov video3.mov
```

## Output Directories

| Function | Default Output | With `--subdir` flag |
|----------|----------------|---------------------|
| `optimize-images` | `optimized/` | N/A |
| `video-remux` | Same directory* | `mp4/` |
| `video-encode-*` | Same directory* | `encoded/` |

\* Smart naming: files with non-MP4 source extensions use same basename; MP4 sources get suffix (`_remuxed` or `_h265`)

## Troubleshooting

### optimize-images produces empty files

**Cause:** PATH order - mozjpeg's cjpeg must come before jpeg-turbo's

**Fix:**
```bash
# Check which cjpeg is first
which -a cjpeg
# Should show: /opt/homebrew/opt/mozjpeg/bin/cjpeg

# Add to ~/.zshrc BEFORE /opt/homebrew/bin
path=(
  "/opt/homebrew/opt/mozjpeg/bin"
  "/opt/homebrew/bin"
  ...
)
```

### "command not found" errors

```bash
# Install missing dependencies
brew bundle --file=~/dotfiles/Brewfile

# Or manually:
brew install ffmpeg parallel mozjpeg oxipng pngquant
```

### Slow performance

- `optimize-images` uses all CPU cores by default
- For very large batches, consider splitting into chunks
- GPU encoding is much faster for video

## Requirements

All tools are installed via Brewfile:

```ruby
# Media processing
brew "ffmpeg"       # Video/image processing
brew "parallel"     # Parallel processing
brew "mozjpeg"      # JPEG optimization

# Image optimization tools
brew "oxipng"       # PNG optimizer
brew "pngquant"     # PNG quantizer
```

## Alternatives

### Handbrake

Installed via cask for GUI encoding:
```bash
open -a Handbrake
```

### FFmpeg directly

For custom encoding:
```bash
# Example: custom bitrate
ffmpeg -i input.mov -c:v libx264 -b:v 5M output.mp4
```

## Future Enhancements

Possible additions:
- `video-concat` - Concatenate videos
- `video-trim` - Trim video segments
- `optimize-video` - Two-pass encoding for max compression
- `image-resize` - Batch resize images
- `image-convert` - Format conversion (WebP, AVIF)
