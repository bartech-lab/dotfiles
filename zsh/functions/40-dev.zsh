# Dev Functions
# Development helpers and utilities

# Universal archive extractor
extract() {
    if [[ -z "$1" ]]; then
        echo "Usage: extract <archive_file>"
        return 1
    fi
    
    if [[ ! -f "$1" ]]; then
        echo "❌ File not found: $1"
        return 1
    fi

    local file="$1"

    # Extract base name (remove all known extensions)
    local base_name="$file"
    # Strip extensions in order from most specific to least
    base_name="${base_name%.tar.zst}"
    base_name="${base_name%.tar.gz}"
    base_name="${base_name%.tar.bz2}"
    base_name="${base_name%.tar.xz}"
    base_name="${base_name%.tgz}"
    base_name="${base_name%.tbz2}"
    base_name="${base_name%.tar}"
    base_name="${base_name%.zip}"
    base_name="${base_name%.rar}"
    base_name="${base_name%.7z}"
    base_name="${base_name%.gz}"
    base_name="${base_name%.bz2}"
    base_name="${base_name%.xz}"
    base_name="${base_name%.Z}"

    # Create extraction directory
    local extract_dir="$base_name"
    local counter=2
    while [[ -d "$extract_dir" ]]; do
        extract_dir="${base_name}-${counter}"
        ((counter++))
    done

    mkdir -p "$extract_dir"
    echo "📁 Extracting to: $extract_dir/"

    case "$file" in
        *.tar.zst)
            if ! command -v zstd >/dev/null; then
                echo "❌ zstd not found. Install with: brew install zstd"
                return 1
            fi
            zstd -cd "$file" | tar xf - -C "$extract_dir" ;;
        *.tar.gz|*.tgz)  gzip -cd "$file" | tar xf - -C "$extract_dir" ;;
        *.tar.bz2|*.tbz2)  bzip2 -cd "$file" | tar xf - -C "$extract_dir" ;;
        *.tar.xz)  xz -cd "$file" | tar xf - -C "$extract_dir" ;;
        *.tar)     tar xf "$file" -C "$extract_dir" ;;
        *.zip|*.rar|*.7z)
            if ! command -v unar >/dev/null; then
                echo "❌ unar not found. Install with: brew install unar"
                return 1
            fi
            unar -q -D -o "$extract_dir" "$file" ;;
        *.gz)      gunzip -c "$file" > "$extract_dir/$(basename "${file%.gz}")" ;;
        *.bz2)     bunzip2 -c "$file" > "$extract_dir/$(basename "${file%.bz2}")" ;;
        *.xz)      unxz -c "$file" > "$extract_dir/$(basename "${file%.xz}")" ;;
        *.Z)       uncompress -c "$file" > "$extract_dir/$(basename "${file%.Z}")" ;;
        *) echo "❌ Unknown archive format: $file" ;;
    esac
}

# Create reproducible archive with exclusions
archive() {
    emulate -L zsh
    setopt LOCAL_OPTIONS NO_NOMATCH

    # Check for compressor
    if [[ "$use_gzip" == true ]]; then
        if ! command -v gzip &>/dev/null; then
            echo "❌ gzip not found"
            return 1
        fi
    else
        if ! command -v zstd &>/dev/null; then
            echo "❌ zstd not found. Install with: brew install zstd"
            return 1
        fi
    fi

    # Detect which tar to use (GNU tar preferred for reproducibility)
    local tar_cmd="tar"
    local use_gnu_tar=false
    if command -v gtar &>/dev/null; then
        tar_cmd="gtar"
        use_gnu_tar=true
    fi

    local dry_run=false
    local use_gzip=false
    local name=""

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --dry-run|-n)
                dry_run=true
                ;;
            -gzip)
                use_gzip=true
                ;;
            -*)
                echo "❌ Unknown option: $arg"
                echo "Usage: archive [name] [--dry-run] [-gzip]"
                return 1
                ;;
            *)
                if [[ -z "$name" ]]; then
                    name="$arg"
                fi
                ;;
        esac
    done

    # Default name from current directory
    name="${name:-$(basename "$PWD")}"
    
    # Check if directory has content
    if [[ -z "$(ls -A 2>/dev/null)" ]]; then
        echo "❌ Directory is empty, nothing to archive"
        return 1
    fi

    local ts="$(date +%Y%m%d-%H%M)"
    local outfile
    if [[ "$use_gzip" == true ]]; then
        outfile="${name}-${ts}.tar.gz"
    else
        outfile="${name}-${ts}.tar.zst"
    fi

    # Build exclude patterns
    local excludes=(
        .git .idea .vscode
        .DS_Store Thumbs.db
        node_modules .npm .pnpm-store .yarn
        .bun .eslintcache .parcel-cache .turbo .vercel
        .venv venv env
        __pycache__ '*.pyc'
        .tox .nox .pytest_cache
        target bin obj
        dist build .next .nuxt
        coverage .mypy_cache
        playwright-report test-results
        allure-results allure-report
        'cmake-build-*' CMakeFiles CMakeCache.txt .gradle
        tmp temp '*.log' .cache
        '*.sqlite' '*.db' '*.pid'
        .env '.env.*' '*.local'
        '*.tar' '*.tar.gz' '*.tar.zst' '*.zip' '*.7z'
        .sisyphus
    )

    # Build base tar options (common to both)
    local tar_opts=()
    
    # Add GNU tar specific options for reproducibility
    if [[ "$use_gnu_tar" == true ]]; then
        tar_opts+=(
            --sort=name
            --mtime='UTC 2020-01-01'
            --owner=0 --group=0 --numeric-owner
        )
    fi

    if [[ "$dry_run" == true ]]; then
        echo "📋 Dry run mode - Files that would be archived:"
        echo ""
        local exclude_args=()
        for pattern in "${excludes[@]}"; do
            exclude_args+=(--exclude="$pattern")
        done
        
        # Show what would be archived
        $tar_cmd \
            "${tar_opts[@]}" \
            "${exclude_args[@]}" \
            -cf - . 2>/dev/null | $tar_cmd -tf - 2>/dev/null | head -20
        
        local total_count=$(\
            $tar_cmd \
                "${tar_opts[@]}" \
                "${exclude_args[@]}" \
                -cf - . 2>/dev/null | $tar_cmd -tf - 2>/dev/null | wc -l\
        )
        
        echo ""
        echo "... and $((total_count - 20)) more files"
        echo ""
        echo "Would create: $outfile"
        if [[ "$use_gnu_tar" == false ]]; then
            echo "⚠️  Note: Install gnu-tar for reproducible archives: brew install gnu-tar"
        fi
        echo "Run without --dry-run to create the archive"
        return 0
    fi

    # Build tar command with exclusions
    local exclude_args=()
    for pattern in "${excludes[@]}"; do
        exclude_args+=(--exclude="$pattern")
    done

    # Create archive
    echo "📦 Creating archive..."
    
    if [[ "$use_gzip" == true ]]; then
        $tar_cmd \
            "${tar_opts[@]}" \
            "${exclude_args[@]}" \
            -cf - . 2>/dev/null | \
            gzip -6 -c > "$outfile"
    else
        $tar_cmd \
            "${tar_opts[@]}" \
            "${exclude_args[@]}" \
            -cf - . 2>/dev/null | \
            zstd -19 -T0 -q -o "$outfile"
    fi

    if [[ -f "$outfile" ]]; then
        local size=$(stat -f%z "$outfile" | awk '{split("B KB MB GB TB PB", unit); u=1; while($1>=1024 && u<6) {$1/=1024; u++} printf "%.1f %s", $1, unit[u]}')
        echo "✅ Created: $outfile ($size)"
        if [[ "$use_gnu_tar" == false ]]; then
            echo "💡 For reproducible archives, install: brew install gnu-tar"
        fi
    else
        echo "❌ Failed to create archive"
        return 1
    fi
}

# Pre-archive sanity checker for repositories
repo-check() {
    emulate -L zsh
    setopt LOCAL_OPTIONS NO_NOMATCH

    local strict_mode=false
    local has_errors=0
    local has_warnings=0

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --strict)
                strict_mode=true
                ;;
            --help|-h)
                echo "Usage: repo-check [--strict]"
                echo ""
                echo "Pre-archive sanity checker for repositories"
                echo ""
                echo "Options:"
                echo "  --strict    Treat warnings as errors"
                return 0
                ;;
            -*)
                echo "❌ Unknown option: $arg"
                echo "Usage: repo-check [--strict]"
                return 1
                ;;
        esac
    done

    echo "🔍 Repository Health Check"
    echo "=========================="
    echo ""

    # Check if we're in a git repo
    local in_git_repo=false
    if git rev-parse --git-dir > /dev/null 2>&1; then
        in_git_repo=true
    fi

    # Security Checks
    echo "Security:"

    # Check for .env files tracked in git
    local env_files=()
    if [[ "$in_git_repo" == true ]]; then
        while IFS= read -r file; do
            [[ -n "$file" ]] && env_files+=("$file")
        done < <(git ls-files 2>/dev/null | grep -E '^\.env' | head -5)
    fi

    # Also check for .env files not in .gitignore
    local untracked_env=()
    if [[ -f ".env" ]]; then
        if [[ "$in_git_repo" == true ]]; then
            if git check-ignore -q ".env" 2>/dev/null; then
                : # .env is properly ignored
            else
                untracked_env+=(".env")
            fi
        else
            untracked_env+=(".env")
        fi
    fi

    if [[ ${#env_files[@]} -gt 0 ]]; then
        echo "  ❌ .env files tracked in git:"
        for f in "${env_files[@]}"; do
            echo "     - $f"
        done
        ((has_errors++))
    elif [[ ${#untracked_env[@]} -gt 0 ]]; then
        echo "  ⚠️  .env file present (not in .gitignore):"
        for f in "${untracked_env[@]}"; do
            echo "     - $f"
        done
        ((has_warnings++))
    else
        echo "  ✅ No .env files exposed"
    fi

    # Check for secret files
    local secret_files=()
    if [[ "$in_git_repo" == true ]]; then
        while IFS= read -r file; do
            [[ -n "$file" ]] && secret_files+=("$file")
        done < <(git ls-files 2>/dev/null | grep -E '\.(pem|key|p12|pfx|jks|keystore)$' | head -5)
    fi

    # Also check filesystem
    local fs_secrets=()
    for pattern in '*.pem' '*.key' '*.p12' '*.pfx' 'id_rsa' 'id_dsa' 'id_ecdsa' 'id_ed25519'; do
        for file in $pattern(N); do
            if [[ -f "$file" ]]; then
                if [[ "$in_git_repo" == true ]]; then
                    if ! git check-ignore -q "$file" 2>/dev/null; then
                        fs_secrets+=("$file")
                    fi
                else
                    fs_secrets+=("$file")
                fi
            fi
        done
    done

    if [[ ${#secret_files[@]} -gt 0 ]]; then
        echo "  ❌ Secret files tracked in git:"
        for f in "${secret_files[@]}"; do
            echo "     - $f"
        done
        ((has_errors++))
    elif [[ ${#fs_secrets[@]} -gt 0 ]]; then
        echo "  ⚠️  Secret files present (not in .gitignore):"
        for f in "${fs_secrets[@]:0:5}"; do
            echo "     - $f"
        done
        ((has_warnings++))
    else
        echo "  ✅ No secret files exposed"
    fi

    # Check for large files (>100MB)
    local large_files=()
    if [[ "$in_git_repo" == true ]]; then
        while IFS= read -r line; do
            [[ -n "$line" ]] && large_files+=("$line")
        done < <(git ls-files 2>/dev/null | while read -r f; do
            if [[ -f "$f" ]]; then
                local size=$(stat -f%z "$f" 2>/dev/null)
                if [[ "$size" -gt 104857600 ]]; then
                    local mb=$((size / 1048576))
                    echo "$f (${mb}MB)"
                fi
            fi
        done | head -5)
    else
        # Check filesystem for large files
        while IFS= read -r line; do
            [[ -n "$line" ]] && large_files+=("$line")
        done < <(find . -type f -size +100M 2>/dev/null | sed 's|^\./||' | grep -v '^\.git/' | head -5)
    fi

    if [[ ${#large_files[@]} -gt 0 ]]; then
        echo "  ❌ Large files (>100MB):"
        for f in "${large_files[@]}"; do
            echo "     - $f"
        done
        echo "     💡 Consider using Git LFS or excluding from archive"
        ((has_errors++))
    else
        echo "  ✅ No large files"
    fi

    echo ""
    echo "Repository:"

    # Check for uncommitted changes
    if [[ "$in_git_repo" == true ]]; then
        if ! git diff-index --quiet HEAD -- 2>/dev/null || [[ -n $(git ls-files --others --exclude-standard 2>/dev/null) ]]; then
            local modified=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
            local untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
            echo "  ⚠️  Uncommitted changes:"
            [[ "$modified" -gt 0 ]] && echo "     - $modified modified files"
            [[ "$untracked" -gt 0 ]] && echo "     - $untracked untracked files"
            ((has_warnings++))
        else
            echo "  ✅ Working tree clean"
        fi
    else
        echo "  ℹ️  Not a git repository"
    fi

    # Check for README
    if [[ -f "README.md" ]] || [[ -f "README" ]] || [[ -f "readme.md" ]]; then
        echo "  ✅ README present"
    else
        echo "  ⚠️  No README.md found"
        ((has_warnings++))
    fi

    # Check for LICENSE
    if [[ -f "LICENSE" ]] || [[ -f "LICENSE.md" ]] || [[ -f "COPYING" ]]; then
        echo "  ✅ LICENSE present"
    else
        echo "  ⚠️  No LICENSE file found"
        ((has_warnings++))
    fi

    echo ""
    echo "Accidental Inclusions:"

    # Check for node_modules in git
    local tracked_deps=()
    if [[ "$in_git_repo" == true ]]; then
        while IFS= read -r file; do
            [[ -n "$file" ]] && tracked_deps+=("$file")
        done < <(git ls-files 2>/dev/null | grep -E '^(node_modules/|vendor/|.venv/|venv/|__pycache__/|.sisyphus/)' | head -5)
    fi

    # Check filesystem
    local dep_dirs=("node_modules" "vendor" ".venv" "venv" "__pycache__" ".sisyphus")
    local fs_deps=()
    for dir in "${dep_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            if [[ "$in_git_repo" == true ]]; then
                if ! git check-ignore -q "$dir" 2>/dev/null; then
                    fs_deps+=("$dir/")
                fi
            else
                fs_deps+=("$dir/")
            fi
        fi
    done

    if [[ ${#tracked_deps[@]} -gt 0 ]]; then
        echo "  ❌ Dependency directories tracked in git:"
        for d in "${tracked_deps[@]}"; do
            echo "     - $d"
        done
        echo "     💡 Add to .gitignore and remove from tracking"
        ((has_errors++))
    elif [[ ${#fs_deps[@]} -gt 0 ]]; then
        echo "  ⚠️  Dependency directories present (not in .gitignore):"
        for d in "${fs_deps[@]}"; do
            echo "     - $d"
        done
        ((has_warnings++))
    else
        echo "  ✅ No dependency directories"
    fi

    # Check for .DS_Store files
    local ds_store_count=$(find . -name ".DS_Store" -type f 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$ds_store_count" -gt 0 ]]; then
        if [[ "$in_git_repo" == true ]]; then
            local tracked_ds=$(git ls-files 2>/dev/null | grep -c '\.DS_Store$')
            if [[ "$tracked_ds" -gt 0 ]]; then
                echo "  ❌ .DS_Store files tracked in git ($tracked_ds files)"
                ((has_errors++))
            else
                echo "  ⚠️  $ds_store_count .DS_Store files (ignored by git)"
                ((has_warnings++))
            fi
        else
            echo "  ⚠️  $ds_store_count .DS_Store files present"
            ((has_warnings++))
        fi
    else
        echo "  ✅ No .DS_Store files"
    fi

    # Summary
    echo ""
    echo "Summary: $has_errors error(s), $has_warnings warning(s)"
    echo ""

    if [[ "$has_errors" -gt 0 ]]; then
        echo "❌ Issues found that should be fixed before archiving"
        return 1
    elif [[ "$strict_mode" == true && "$has_warnings" -gt 0 ]]; then
        echo "⚠️  Warnings found (strict mode enabled)"
        return 1
    elif [[ "$has_warnings" -gt 0 ]]; then
        echo "⚠️  Warnings present, but safe to proceed"
        return 0
    else
        echo "✅ Repository looks good!"
        return 0
    fi
}

# Comprehensive dotfiles environment health checker
dotfiles-doctor() {
    emulate -L zsh
    setopt LOCAL_OPTIONS NO_NOMATCH

    local auto_fix=false
    local has_errors=0
    local has_warnings=0

    # Parse arguments
    for arg in "$@"; do
        case "$arg" in
            --fix)
                auto_fix=true
                ;;
            --help|-h)
                echo "Usage: dotfiles-doctor [--fix]"
                echo ""
                echo "Comprehensive health check for dotfiles environment"
                echo ""
                echo "Options:"
                echo "  --fix    Attempt to auto-fix common issues"
                return 0
                ;;
            -*)
                echo "❌ Unknown option: $arg"
                echo "Usage: dotfiles-doctor [--fix]"
                return 1
                ;;
        esac
    done

    echo "🔧 Dotfiles Doctor"
    echo "=================="
    echo ""

    # System Checks
    echo "System:"

    # macOS version
    local macos_version=$(sw_vers -productVersion 2>/dev/null)
    if [[ -n "$macos_version" ]]; then
        local major_version=$(echo "$macos_version" | cut -d. -f1)
        if [[ "$major_version" -ge 14 ]]; then
            echo "  ✅ macOS $macos_version"
        else
            echo "  ⚠️  macOS $macos_version (tested on 14+)"
            ((has_warnings++))
        fi
    else
        echo "  ❌ Cannot detect macOS version"
        ((has_errors++))
    fi

    # Command Line Tools
    if xcode-select -p &>/dev/null; then
        echo "  ✅ Command Line Tools"
    else
        echo "  ❌ Command Line Tools not installed"
        echo "     Run: xcode-select --install"
        ((has_errors++))
    fi

    # Homebrew
    if command -v brew &>/dev/null; then
        local brew_version=$(brew --version | head -1 | awk '{print $2}')
        echo "  ✅ Homebrew $brew_version"
    else
        echo "  ❌ Homebrew not installed"
        echo "     Run: ./install.sh"
        ((has_errors++))
    fi

    echo ""
    echo "Critical Tools:"

    # Check critical tools with versions
    declare -A tool_packages=(
        [zstd]="zstd"
        [gtar]="gnu-tar"
        [ffmpeg]="ffmpeg"
        [cjpeg]="mozjpeg"
        [parallel]="parallel"
        [eza]="eza"
        [rg]="ripgrep"
        [dust]="dust"
        [btm]="bottom"
        [duf]="duf"
    )

    local missing_tools=()
    for tool in zstd gtar ffmpeg cjpeg parallel eza rg dust btm duf; do
        if command -v "$tool" &>/dev/null; then
            local version=""
            case "$tool" in
                zstd) version=$(zstd --version 2>&1 | head -1 | awk '{print $3}') ;;
                gtar) version=$(gtar --version 2>&1 | head -1 | awk '{print $4}') ;;
                ffmpeg) version=$(ffmpeg -version 2>&1 | head -1 | awk '{print $3}') ;;
                cjpeg) version=$(cjpeg -version 2>&1 | head -1 | awk '{print $3}') ;;
                parallel) version=$(parallel --version 2>&1 | head -1 | awk '{print $3}') ;;
                eza) version=$(eza --version 2>&1 | head -1) ;;
                rg) version=$(rg --version 2>&1 | head -1 | awk '{print $2}') ;;
                dust) version=$(dust --version 2>&1 | awk '{print $2}') ;;
                btm) version=$(btm --version 2>&1 | awk '{print $2}') ;;
                duf) version=$(duf --version 2>&1 | awk '{print $2}') ;;
            esac
            [[ -n "$version" ]] && echo "  ✅ $tool $version" || echo "  ✅ $tool"
        else
            echo "  ❌ $tool (install: brew install ${tool_packages[$tool]})"
            missing_tools+=("$tool")
            ((has_errors++))
        fi
    done

    # Auto-fix missing tools
    if [[ "$auto_fix" == true && ${#missing_tools[@]} -gt 0 && -x "$(command -v brew)" ]]; then
        echo ""
        echo "🔧 Auto-fixing missing tools..."
        for tool in "${missing_tools[@]}"; do
            local package="${tool_packages[$tool]}"
            echo "  → Installing $package..."
            brew install "$package" 2>/dev/null || echo "  ⚠️ Failed to install $package"
        done
    fi

    echo ""
    echo "Dotfiles Setup:"

    # Check loader symlink
    local dotfiles_dir="${DOTFILES_DIR:-$HOME/dotfiles}"
    local loader_path="$HOME/.config/zsh-dotfiles-loader.zsh"

    if [[ -L "$loader_path" ]]; then
        local link_target=$(readlink "$loader_path")
        if [[ "$link_target" == "$dotfiles_dir/zsh/functions.zsh" ]]; then
            echo "  ✅ Loader symlinked correctly"
        else
            echo "  ⚠️  Loader symlink points elsewhere"
            echo "     Expected: $dotfiles_dir/zsh/functions.zsh"
            echo "     Actual: $link_target"
            ((has_warnings++))
            
            if [[ "$auto_fix" == true ]]; then
                echo "  🔧 Fixing symlink..."
                ln -sf "$dotfiles_dir/zsh/functions.zsh" "$loader_path"
                echo "  ✅ Fixed"
            fi
        fi
    elif [[ -f "$loader_path" ]]; then
        echo "  ⚠️  Loader exists but is not a symlink"
        ((has_warnings++))
    else
        echo "  ❌ Loader not found at $loader_path"
        echo "     Run: ./install.sh"
        ((has_errors++))
    fi

    # Check if sourced in .zshrc
    if [[ -f "$HOME/.zshrc" ]]; then
        if grep -q "zsh-dotfiles-loader.zsh" "$HOME/.zshrc" 2>/dev/null; then
            echo "  ✅ Sourced in ~/.zshrc"
        else
            echo "  ❌ Not sourced in ~/.zshrc"
            echo "     Add: source ~/.config/zsh-dotfiles-loader.zsh"
            ((has_errors++))
            
            if [[ "$auto_fix" == true ]]; then
                echo "" >> "$HOME/.zshrc"
                echo "# Load dotfiles functions" >> "$HOME/.zshrc"
                echo 'source ~/.config/zsh-dotfiles-loader.zsh' >> "$HOME/.zshrc"
                echo "  🔧 Added to ~/.zshrc"
            fi
        fi
    else
        echo "  ⚠️  ~/.zshrc not found"
        ((has_warnings++))
    fi

    # Count loaded functions
    local function_count=$(functions | grep -cE '^[a-zA-Z_-]+\s*\(\)' 2>/dev/null || echo "0")
    if [[ "$function_count" -gt 30 ]]; then
        echo "  ✅ Functions loaded ($function_count functions)"
    elif [[ "$function_count" -gt 0 ]]; then
        echo "  ⚠️  Functions loaded ($function_count - expected >30)"
        ((has_warnings++))
    else
        echo "  ❌ No functions loaded"
        ((has_errors++))
    fi

    echo ""
    echo "PATH Configuration:"

    # Check mozjpeg priority
    if which -a cjpeg 2>/dev/null | head -1 | grep -q "mozjpeg"; then
        echo "  ✅ mozjpeg priority correct"
    else
        local cjpeg_path=$(which cjpeg 2>/dev/null)
        if [[ -n "$cjpeg_path" ]]; then
            echo "  ⚠️  mozjpeg not first in PATH"
            echo "     Current: $cjpeg_path"
            echo "     Add to ~/.zshrc (before /opt/homebrew/bin):"
            echo '       path=("/opt/homebrew/opt/mozjpeg/bin" $path)'
            ((has_warnings++))
        else
            echo "  ❌ cjpeg not found (install mozjpeg)"
            ((has_errors++))
        fi
    fi

    # Check for duplicates in PATH
    local path_dups=$(echo "$PATH" | tr ':' '\n' | sort | uniq -d | wc -l | tr -d ' ')
    if [[ "$path_dups" -eq 0 ]]; then
        echo "  ✅ No duplicates"
    else
        echo "  ⚠️  $path_dups duplicate(s) in PATH"
        ((has_warnings++))
    fi

    echo ""
    echo "Shell:"

    # Check zinit
    if [[ -d "$HOME/.local/share/zinit/zinit.git" ]] || [[ -d "/opt/homebrew/opt/zinit" ]]; then
        local zinit_version=$(zinit --version 2>/dev/null | head -1 | awk '{print $2}')
        [[ -n "$zinit_version" ]] && echo "  ✅ zinit $zinit_version" || echo "  ✅ zinit installed"
    else
        echo "  ⚠️  zinit not found (install: brew install zinit)"
        ((has_warnings++))
    fi

    # Check powerlevel10k
    if [[ -n "$P9K_SSH" ]] || [[ -n "$POWERLEVEL9K_DISABLE_GITSTATUS" ]] || typeset -p POWERLEVEL9K_* &>/dev/null; then
        echo "  ✅ powerlevel10k active"
    else
        echo "  ⚠️  powerlevel10k not detected"
        ((has_warnings++))
    fi

    # Check syntax highlighting
    if typeset -p ZSH_HIGHLIGHT_VERSION &>/dev/null || [[ -n "${ZSH_HIGHLIGHT_STYLES+x}" ]]; then
        echo "  ✅ Syntax highlighting"
    else
        echo "  ⚠️  Syntax highlighting not loaded"
        ((has_warnings++))
    fi

    # Check autosuggestions
    if typeset -p ZSH_AUTOSUGGEST_STRATEGY &>/dev/null || [[ -n "${ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE+x}" ]]; then
        echo "  ✅ Auto-suggestions"
    else
        echo "  ⚠️  Auto-suggestions not loaded"
        ((has_warnings++))
    fi

    echo ""
    echo "Fonts:"

    # Check for Nerd Fonts
    local font_check=false
    if fc-list : family 2>/dev/null | grep -qi "nerd\|powerline\|meslo\|hack\|fira"; then
        font_check=true
    elif [[ -d "$HOME/Library/Fonts" ]]; then
        if ls "$HOME/Library/Fonts" | grep -qiE "(Nerd|Powerline|Meslo|Hack|Fira)"; then
            font_check=true
        fi
    fi

    if [[ "$font_check" == true ]]; then
        echo "  ✅ Nerd Fonts installed"
    else
        echo "  ⚠️  Nerd Fonts not detected"
        echo "     Install: brew tap homebrew/cask-fonts && brew install --cask font-meslo-lg-nerd-font"
        ((has_warnings++))
    fi

    echo ""
    echo "Git:"

    if command -v git &>/dev/null; then
        local git_version=$(git --version | awk '{print $3}')
        echo "  ✅ Git $git_version"

        # Check git config
        local git_name=$(git config user.name 2>/dev/null)
        local git_email=$(git config user.email 2>/dev/null)

        if [[ -n "$git_name" ]]; then
            echo "  ✅ User name: $git_name"
        else
            echo "  ⚠️  Git user.name not set"
            echo "     Run: git config --global user.name 'Your Name'"
            ((has_warnings++))
        fi

        if [[ -n "$git_email" ]]; then
            echo "  ✅ User email: $git_email"
        else
            echo "  ⚠️  Git user.email not set"
            echo "     Run: git config --global user.email 'you@example.com'"
            ((has_warnings++))
        fi
    else
        echo "  ❌ Git not installed"
        ((has_errors++))
    fi

    # Summary
    echo ""
    echo "=================="

    if [[ "$has_errors" -eq 0 && "$has_warnings" -eq 0 ]]; then
        echo "✅ All systems operational!"
        return 0
    elif [[ "$has_errors" -eq 0 ]]; then
        echo "⚠️  $has_warnings warning(s) - safe to proceed"
        echo ""
        echo "Run 'dotfiles-doctor --fix' to auto-fix common issues"
        return 0
    else
        echo "❌ $has_errors error(s), $has_warnings warning(s)"
        echo ""
        echo "Fix errors above, then run again."
        if [[ "$auto_fix" == false && "$has_errors" -gt 0 ]]; then
            echo "Run 'dotfiles-doctor --fix' to attempt auto-fixes."
        fi
        return 1
    fi
}

# Manually repair macOS Calendar ghost invite state
calfix() {
    "$HOME/dotfiles/calendar-ghost-fix/run-now.sh"
}
