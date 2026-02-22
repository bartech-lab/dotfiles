# Media Functions
# optimize-images, video-remux, video-encode-cpu, video-encode-gpu

optimize-images() {
  local SOURCE_DIR="."
  local LOSSLESS=0
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --lossless)
        LOSSLESS=1
        shift
        ;;
      *)
        SOURCE_DIR="$1"
        shift
        ;;
    esac
  done
  
  if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "❌ Error: Directory '$SOURCE_DIR' not found"
    return 1
  fi
  
  cd "$SOURCE_DIR" || return 1
  mkdir -p optimized
  
  # Count files to process
  local jpeg_count=$(find . -maxdepth 1 \( -name "*.jpg" -o -name "*.jpeg" \) | wc -l)
  local png_count=$(find . -maxdepth 1 -name "*.png" | wc -l)
  local total_count=$((jpeg_count + png_count))
  
  if [[ $total_count -eq 0 ]]; then
    echo "No JPEG or PNG files found to process"
    return 0
  fi
  
  echo "Mode: $([[ $LOSSLESS -eq 1 ]] && echo 'Lossless' || echo 'Default')"
  echo "Found $total_count files ($jpeg_count JPEG, $png_count PNG)"
  echo ""
  
  # Process JPEG files in parallel
  if [[ $jpeg_count -gt 0 ]]; then
    find . -maxdepth 1 \( -name "*.jpg" -o -name "*.jpeg" \) -print0 | \
      sed 's|^\./||' | \
      parallel -0 --shell zsh --bar --will-cite '
        cjpeg -quality 92 -optimize -progressive {} > optimized/{} 2>/dev/null
      ' >/dev/null 2>&1
  fi
  
  # Process PNG files in parallel
  if [[ $png_count -gt 0 ]]; then
    if [[ $LOSSLESS -eq 1 ]]; then
      find . -maxdepth 1 -name "*.png" -print0 | \
        sed 's|^\./||' | \
        parallel -0 --shell zsh --bar --will-cite '
          oxipng -q -o 4 --strip safe -i 0 --out optimized/{} {} 2>/dev/null
        ' >/dev/null 2>&1
    else
      find . -maxdepth 1 -name "*.png" -print0 | \
        sed 's|^\./||' | \
        parallel -0 --shell zsh --bar --will-cite '
          if file {} 2>/dev/null | grep -q "RGBA\|alpha"; then
            name=$(basename {} .png)
            ffmpeg -hide_banner -loglevel error -i {} -q:v 2 optimized/${name}.jpg 2>/dev/null
          else
            pngquant --quality=80-90 --speed 1 --output tmp_{} -- {} 2>/dev/null
            if [[ -f tmp_{} ]]; then
              oxipng -q -o 4 --strip safe -i 0 --out optimized/{} tmp_{} 2>/dev/null
              rm tmp_{} 2>/dev/null
            else
              oxipng -q -o 4 --strip safe -i 0 --out optimized/{} {} 2>/dev/null
            fi
          fi
        ' >/dev/null 2>&1
    fi
  fi
  
  echo ""
  
  # Check for DNG files and warn user
  local dng_files=()
  while IFS= read -r -d '' f; do
    dng_files+=("${f#\./}")
  done < <(find . -maxdepth 1 -name "*.dng" -print0)
  
  if (( ${#dng_files[@]} > 0 )); then
    echo "⚠️  Found ${#dng_files[@]} DNG raw file(s) - NOT processed:"
    for f in "${dng_files[@]}"; do
      echo "  - $f"
    done
    echo ""
    echo "💡 Handle DNG files manually via: Finder → Right-click → Quick Actions → Convert Image"
    echo ""
  fi
  
  echo "✅ Done! Optimized $total_count files in: $(pwd)/optimized/"
}

video-remux() {
  local SOURCE_DIR="${1:-.}"
  
  if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "❌ Error: Directory '$SOURCE_DIR' not found"
    return 1
  fi
  
  cd "$SOURCE_DIR" || return 1
  mkdir -p mp4
  
  local OUTDIR="mp4"
  local ERROR_LOG="$OUTDIR/remux_errors.log"
  
  # Clear old error log if exists
  rm -f "$ERROR_LOG"
  
  # Count files
  local files=()
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find . -maxdepth 1 -type f \( -iname "*.mov" -o -iname "*.mkv" -o -iname "*.avi" \) -print0)
  
  local total_files=${#files[@]}
  
  if (( total_files == 0 )); then
    echo "No video files found to remux"
    return 0
  fi
  
  echo "Found $total_files files to remux"
  echo "Mode: LOSSLESS COPY (no re-encoding)"
  echo ""
  
  # Use GNU parallel for clean parallel processing
  printf '%s\0' "${files[@]}" | parallel -0 --shell zsh --bar --will-cite '
    file="{}"
    base=$(basename "$file")
    name="${base%.*}"
    out="mp4/${name}.mp4"
    
    if [[ ! -f "$out" ]]; then
      ffmpeg -hide_banner -loglevel error -i "$file" -c:v copy -c:a copy -movflags +faststart "$out" 2>/dev/null && touch -r "$file" "$out" || echo "FAILED: $base" >> "'$ERROR_LOG'"
    fi
  '
  
  # Show errors if any
  if [[ -f "$ERROR_LOG" && -s "$ERROR_LOG" ]]; then
    local error_count=$(wc -l < "$ERROR_LOG")
    echo ""
    echo "⚠️  $error_count file(s) had issues:"
    cat "$ERROR_LOG"
  fi
  
  echo "✅ Done! Remuxed files in: $(pwd)/$OUTDIR/"
  
  if command -v osascript &>/dev/null; then
    osascript -e 'display notification "Video remux complete!" with title "video-remux"'
  fi
}

video-encode-cpu() {
  local SOURCE_DIR="${1:-.}"
  
  if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "❌ Error: Directory '$SOURCE_DIR' not found"
    return 1
  fi
  
  cd "$SOURCE_DIR" || return 1
  mkdir -p encoded
  
  local OUTDIR="encoded"
  local ERROR_LOG="$OUTDIR/encode_errors.log"
  
  # Clear old error log if exists
  rm -f "$ERROR_LOG"
  
  # Count files
  local files=()
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find . -maxdepth 1 -type f \( -iname "*.mov" -o -iname "*.mp4" \) -print0)
  
  local total_files=${#files[@]}
  
  if (( total_files == 0 )); then
    echo "No video files found to encode"
    return 0
  fi
  
  echo "Found $total_files files to encode"
  echo "Mode: CPU H.265 (high quality, slow)"
  echo ""
  
  # Use GNU parallel for clean parallel processing (2 jobs for CPU)
  printf '%s\0' "${files[@]}" | parallel -0 -j2 --shell zsh --bar --will-cite '
    file="{}"
    base=$(basename "$file")
    name="${base%.*}"
    out="encoded/${name}.mp4"
    
    if [[ ! -f "$out" ]]; then
      ffmpeg -hide_banner -loglevel error -i "$file" -c:v libx265 -preset slow -crf 22 -pix_fmt yuv420p10le -c:a aac -b:a 320k -ac 2 -ar 48000 "$out" 2>/dev/null || echo "FAILED: $base" >> "'$ERROR_LOG'"
    fi
  '
  
  # Show errors if any
  if [[ -f "$ERROR_LOG" && -s "$ERROR_LOG" ]]; then
    local error_count=$(wc -l < "$ERROR_LOG")
    echo ""
    echo "⚠️  $error_count file(s) had issues:"
    cat "$ERROR_LOG"
  fi
  
  echo "✅ Done! Encoded files in: $(pwd)/$OUTDIR/"
  
  if command -v osascript &>/dev/null; then
    osascript -e 'display notification "CPU encoding complete!" with title "video-encode-cpu"'
  fi
}

video-encode-gpu() {
  local SOURCE_DIR="${1:-.}"
  
  if [[ ! -d "$SOURCE_DIR" ]]; then
    echo "❌ Error: Directory '$SOURCE_DIR' not found"
    return 1
  fi
  
  cd "$SOURCE_DIR" || return 1
  mkdir -p encoded
  
  local OUTDIR="encoded"
  local ERROR_LOG="$OUTDIR/encode_errors.log"
  
  # Clear old error log if exists
  rm -f "$ERROR_LOG"
  
  # Count files
  local files=()
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find . -maxdepth 1 -type f \( -iname "*.mov" -o -iname "*.mp4" \) -print0)
  
  local total_files=${#files[@]}
  
  if (( total_files == 0 )); then
    echo "No video files found to encode"
    return 0
  fi
  
  echo "Found $total_files files to encode"
  echo "Mode: GPU H.265 (fast encoding)"
  echo ""
  
  # Use GNU parallel for clean parallel processing (4 jobs for GPU)
  printf '%s\0' "${files[@]}" | parallel -0 -j4 --shell zsh --bar --will-cite '
    file="{}"
    base=$(basename "$file")
    name="${base%.*}"
    out="encoded/${name}.mp4"
    
    if [[ ! -f "$out" ]]; then
      q=52
      crop=$(ffmpeg -hide_banner -i "$file" -vf cropdetect=limit=0.1:round=2 -t 8 -f null - 2>&1 | awk -F'"'"'crop='"'"' '"'"'/crop=/{print $2}'"'"' | awk '"'"'{print $1}'"'"' | tail -1)
      
      if [[ -n "$crop" ]]; then
        ffmpeg -hide_banner -loglevel error -i "$file" -vf "crop=$crop" -c:v hevc_videotoolbox -q:v $q -c:a aac -b:a 320k -ac 2 -ar 48000 "$out" 2>/dev/null || echo "FAILED: $base" >> "'$ERROR_LOG'"
      else
        ffmpeg -hide_banner -loglevel error -i "$file" -c:v hevc_videotoolbox -q:v $q -c:a aac -b:a 320k -ac 2 -ar 48000 "$out" 2>/dev/null || echo "FAILED: $base" >> "'$ERROR_LOG'"
      fi
    fi
  '
  
  # Show errors if any
  if [[ -f "$ERROR_LOG" && -s "$ERROR_LOG" ]]; then
    local error_count=$(wc -l < "$ERROR_LOG")
    echo ""
    echo "⚠️  $error_count file(s) had issues:"
    cat "$ERROR_LOG"
  fi
  
  echo "✅ Done! Encoded files in: $(pwd)/$OUTDIR/"
  
  if command -v osascript &>/dev/null; then
    osascript -e 'display notification "GPU encoding complete!" with title "video-encode-gpu"'
  fi
}

# Convert video to GIF (useful for documentation/issues)
video-to-gif() {
    local input="$1"
    local output="${2:-output.gif}"
    local fps="${3:-15}"
    local scale="${4:-480}"
    
    if [[ -z "$input" ]]; then
        echo "Usage: video-to-gif <input.mp4> [output.gif] [fps] [scale]"
        return 1
    fi
    
    if [[ ! -f "$input" ]]; then
        echo "❌ File not found: $input"
        return 1
    fi
    
    echo "Converting to GIF (${fps}fps, ${scale}px wide)..."
    
    ffmpeg -i "$input" \
        -vf "fps=$fps,scale=$scale:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse" \
        -loop 0 "$output"
    
    if [[ $? -eq 0 ]]; then
        echo "✅ Created: $output"
        ls -lh "$output"
    else
        echo "❌ Conversion failed"
        return 1
    fi
}
