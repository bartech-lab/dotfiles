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