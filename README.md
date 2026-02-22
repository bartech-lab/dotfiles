# Dotfiles

Personal shell functions, aliases, and scripts for macOS. Clean, minimal, and automated setup for new machines.

## Quick Start

```bash
git clone <your-repo-url> ~/dotfiles
cd ~/dotfiles
./install.sh
source ~/.zshrc
```

## What's Included

### Modern CLI Replacements

| Command | Replacement | Why |
|---------|-------------|-----|
| `ls`, `ll`, `lt` | `eza` | Icons, git status, tree view |
| `grep` | `rg` (ripgrep) | Fast search, smart defaults |
| `top` | `btm` (bottom) | Visual system monitor |
| `du` | `dust` | Visual disk usage |
| `df` | `duf` | Colorful disk free |

### Media Processing

- `optimize-images [path]` - Batch optimize JPEG/PNG
- `video-to-gif <input>` - Convert videos to GIF
- `video-remux [path]` - Lossless container conversion
- `video-encode-cpu/gpu [path]` - H.265 encoding

### Development Utilities

- `extract <archive>` - Universal archive extractor
- `archive [name] [--dry-run] [-gzip]` - Create reproducible archives
- `repo-check` - Pre-archive sanity checker
- `dotfiles-doctor` - Environment health check

### Git & macOS Helpers

- `git-cleanup` - Clean merged branches
- `git-open` - Open repo in browser
- `macos-defaults` - Apply system preferences
- `cpwd` - Copy current path to clipboard

## Documentation

- [📥 Installation Guide](docs/install.md) - Setup, prerequisites, troubleshooting
- [🏗️ Architecture](docs/architecture.md) - How it works, file structure, extending
- [📚 Functions Reference](docs/functions.md) - Complete command reference
- [🎬 Media Processing](docs/media.md) - Video/image optimization
- [🛠️ Development Utilities](docs/dev.md) - Archives, diagnostics, helpers

## Safety First

```bash
# Preview changes before installing
./install.sh --dry-run

# Check repository health before archiving
repo-check && archive

# Diagnose your environment
dotfiles-doctor
```

## Requirements

- **macOS** 14+ (Sonoma and later)
- **zsh** (pre-installed)
- **Homebrew** (auto-installed by `./install.sh`)

## License

Personal dotfiles - feel free to use as inspiration for your own setup.
