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
  local jpeg_count=$(find . -maxdepth 1 \( -iname "*.jpg" -o -iname "*.jpeg" \) | wc -l)
  local png_count=$(find . -maxdepth 1 -iname "*.png" | wc -l)
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
    find . -maxdepth 1 \( -iname "*.jpg" -o -iname "*.jpeg" \) -print0 | \
      sed 's|^\./||' | \
      xargs -0 -P 4 -I{} sh -c 'cjpeg -quality 92 -optimize -progressive "$1" > "optimized/$1" 2>/dev/null' _ {}
  fi
  
  # Process PNG files in parallel
  if [[ $png_count -gt 0 ]]; then
    if [[ $LOSSLESS -eq 1 ]]; then
      find . -maxdepth 1 -iname "*.png" -print0 | \
        sed 's|^\./||' | \
        xargs -0 -P 4 -I{} sh -c 'oxipng -q -o 4 --strip safe -i 0 --out "optimized/$1" "$1" 2>/dev/null' _ {}
    else
      find . -maxdepth 1 -iname "*.png" -print0 | \
        sed 's|^\./||' | \
        xargs -0 -P 4 -I{} sh -c '
          if file "$1" 2>/dev/null | grep -q "RGBA\|alpha"; then
            name=$(basename "$1" .png)
            ffmpeg -hide_banner -loglevel error -i "$1" -q:v 2 "optimized/${name}.jpg" 2>/dev/null
          else
            pngquant --quality=80-90 --speed 1 --output "tmp_$1" -- "$1" 2>/dev/null
            if [[ -f "tmp_$1" ]]; then
              oxipng -q -o 4 --strip safe -i 0 --out "optimized/$1" "tmp_$1" 2>/dev/null
              rm "tmp_$1" 2>/dev/null
            else
              oxipng -q -o 4 --strip safe -i 0 --out "optimized/$1" "$1" 2>/dev/null
            fi
          fi
        ' _ {}
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
  local SOURCE_PATH="${1:-.}"
  local INPUT_DIR=""
  local SINGLE_FILE=""
  local USE_SUBDIR=0

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --subdir)
        USE_SUBDIR=1
        shift
        ;;
      *)
        SOURCE_PATH="$1"
        shift
        ;;
    esac
  done

  if [[ -d "$SOURCE_PATH" ]]; then
    INPUT_DIR="$SOURCE_PATH"
  elif [[ -f "$SOURCE_PATH" ]]; then
    INPUT_DIR="${SOURCE_PATH:h}"
    SINGLE_FILE="${SOURCE_PATH:t}"
  else
    echo "❌ Error: Path '$SOURCE_PATH' not found"
    return 1
  fi

  cd "$INPUT_DIR" || return 1
  
  local OUTDIR="."
  local ERROR_LOG="./remux_errors.log"
  local SKIP_LOG="./remux_skipped.log"
  
  if [[ $USE_SUBDIR -eq 1 ]]; then
    mkdir -p mp4
    OUTDIR="mp4"
    ERROR_LOG="$OUTDIR/remux_errors.log"
    SKIP_LOG="$OUTDIR/remux_skipped.log"
  fi
  
  # Clear old error log if exists
  rm -f "$ERROR_LOG"
  rm -f "$SKIP_LOG"
  
  # Count files
  local files=()
  if [[ -n "$SINGLE_FILE" ]]; then
    local single_ext="${SINGLE_FILE##*.}"
    single_ext="${single_ext:l}"
    case "$single_ext" in
      mov|mkv|avi|flv|webm|webp)
        files+=("./$SINGLE_FILE")
        ;;
      *)
        echo "❌ Unsupported file type: $SINGLE_FILE"
        echo "Supported: .mov, .mkv, .avi, .flv, .webm, .webp"
        return 1
        ;;
    esac
  else
    while IFS= read -r -d '' file; do
      files+=("$file")
    done < <(find . -maxdepth 1 -type f \( -iname "*.mov" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.flv" -o -iname "*.webm" -o -iname "*.webp" \) -print0)
  fi
  
  local total_files=${#files[@]}
  
  if (( total_files == 0 )); then
    echo "No video files found to remux"
    return 0
  fi
  
  echo "Found $total_files files to remux"
  echo "Mode: LOSSLESS COPY for most video containers + animated WEBP conversion"
  echo ""
  
  # Process files in parallel using xargs
  printf '%s\0' "${files[@]}" | xargs -0 -P 4 -I{} sh -c '
    file="$1"
    base=$(basename "$file")
    name="${base%.*}"
    ext=$(printf "%s" "${base##*.}" | tr "[:upper:]" "[:lower:]")
    
    # Determine output filename
    if [[ "'$USE_SUBDIR'" == "1" ]]; then
      out="'${OUTDIR}'/${name}.mp4"
    elif [[ "$ext" == "mp4" ]]; then
      out="${name}_remuxed.mp4"
    else
      out="${name}.mp4"
    fi
    
    if [[ ! -f "$out" ]]; then
      if [[ "$ext" == "webp" ]]; then
        packets=$(ffprobe -v error -count_packets -select_streams v:0 -show_entries stream=nb_read_packets -of csv=p=0 "$file" 2>/dev/null | tr -d "\r")

        if [[ "$packets" == "N/A" || -z "$packets" ]]; then
          packets=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$file" 2>/dev/null | tr -d "\r")
        fi

        if [[ "$packets" =~ ^[0-9]+$ ]] && (( packets > 1 )); then
          if ffmpeg -hide_banner -loglevel error -i "$file" -an -c:v libx264 -pix_fmt yuv420p -movflags +faststart "$out" 2>/dev/null; then
            touch -r "$file" "$out"
          else
            echo "FAILED: $base" >> "'$ERROR_LOG'"
          fi
        else
          echo "SKIPPED (not animated): $base" >> "'$SKIP_LOG'"
        fi
      else
        if ffmpeg -hide_banner -loglevel error -i "$file" -c:v copy -c:a copy -movflags +faststart "$out" 2>/dev/null; then
          touch -r "$file" "$out"
        else
          if [[ "$ext" == "webm" ]]; then
            if ffmpeg -hide_banner -loglevel error -i "$file" -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart "$out" 2>/dev/null; then
              touch -r "$file" "$out"
            else
              echo "FAILED: $base" >> "'$ERROR_LOG'"
            fi
          else
            echo "FAILED: $base" >> "'$ERROR_LOG'"
          fi
        fi
      fi
    fi
  ' _ {}
  
  # Show errors if any
  if [[ -f "$ERROR_LOG" && -s "$ERROR_LOG" ]]; then
    local error_count=$(wc -l < "$ERROR_LOG")
    echo ""
    echo "⚠️  $error_count file(s) had issues:"
    cat "$ERROR_LOG"
  fi

  if [[ -f "$SKIP_LOG" && -s "$SKIP_LOG" ]]; then
    local skip_count=$(wc -l < "$SKIP_LOG")
    echo ""
    echo "ℹ️  $skip_count WEBP file(s) were skipped (not animated):"
    cat "$SKIP_LOG"
  fi
  
  if [[ $USE_SUBDIR -eq 1 ]]; then
    echo "✅ Done! Remuxed files in: $(pwd)/$OUTDIR/"
  else
    echo "✅ Done! Remuxed files in current directory"
  fi
  
  if command -v osascript &>/dev/null; then
    osascript -e 'display notification "Video remux complete!" with title "video-remux"'
  fi
}

video-encode-cpu() {
  local SOURCE_DIR="${1:-.}"
  local USE_SUBDIR=0
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --subdir)
        USE_SUBDIR=1
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
  
  local OUTDIR="."
  local ERROR_LOG="./encode_errors.log"
  
  if [[ $USE_SUBDIR -eq 1 ]]; then
    mkdir -p encoded
    OUTDIR="encoded"
    ERROR_LOG="$OUTDIR/encode_errors.log"
  fi
  
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
  
  # Process files in parallel using xargs (2 jobs for CPU)
  printf '%s\0' "${files[@]}" | xargs -0 -P 2 -I{} sh -c '
    file="$1"
    base=$(basename "$file")
    name="${base%.*}"
    ext=$(printf "%s" "${base##*.}" | tr "[:upper:]" "[:lower:]")
    
    # Determine output filename
    if [[ "'$USE_SUBDIR'" == "1" ]]; then
      out="'${OUTDIR}'/${name}.mp4"
    elif [[ "$ext" == "mp4" ]]; then
      out="${name}_h265.mp4"
    else
      out="${name}.mp4"
    fi
    
    if [[ ! -f "$out" ]]; then
      if ffmpeg -hide_banner -loglevel error -i "$file" -c:v libx265 -preset slow -crf 22 -pix_fmt yuv420p10le -c:a aac -b:a 320k -ac 2 -ar 48000 "$out" 2>/dev/null; then
        : # success
      else
        echo "FAILED: $base" >> "'$ERROR_LOG'"
      fi
    fi
  ' _ {}
  
  # Show errors if any
  if [[ -f "$ERROR_LOG" && -s "$ERROR_LOG" ]]; then
    local error_count=$(wc -l < "$ERROR_LOG")
    echo ""
    echo "⚠️  $error_count file(s) had issues:"
    cat "$ERROR_LOG"
  fi
  
  if [[ $USE_SUBDIR -eq 1 ]]; then
    echo "✅ Done! Encoded files in: $(pwd)/$OUTDIR/"
  else
    echo "✅ Done! Encoded files in current directory"
  fi
  
  if command -v osascript &>/dev/null; then
    osascript -e 'display notification "CPU encoding complete!" with title "video-encode-cpu"'
  fi
}

video-encode-gpu() {
  local SOURCE_DIR="${1:-.}"
  local USE_SUBDIR=0
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --subdir)
        USE_SUBDIR=1
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
  
  local OUTDIR="."
  local ERROR_LOG="./encode_errors.log"
  
  if [[ $USE_SUBDIR -eq 1 ]]; then
    mkdir -p encoded
    OUTDIR="encoded"
    ERROR_LOG="$OUTDIR/encode_errors.log"
  fi
  
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
  
  # Process files in parallel using xargs (4 jobs for GPU)
  printf '%s\0' "${files[@]}" | xargs -0 -P 4 -I{} sh -c '
    file="$1"
    base=$(basename "$file")
    name="${base%.*}"
    ext=$(printf "%s" "${base##*.}" | tr "[:upper:]" "[:lower:]")
    
    # Determine output filename
    if [[ "'"$USE_SUBDIR"'" == "1" ]]; then
      out="'"$OUTDIR"'/${name}.mp4"
    elif [[ "$ext" == "mp4" ]]; then
      out="${name}_h265.mp4"
    else
      out="${name}.mp4"
    fi
    
    if [[ ! -f "$out" ]]; then
      q=52
      crop=$(ffmpeg -hide_banner -i "$file" -vf cropdetect=limit=0.1:round=2 -t 8 -f null - 2>&1 | awk -F'"'"'crop='"'"' '"'"'/crop=/{print $2}'"'"' | awk '"'"'{print $1}'"'"' | tail -1)
      
      if [[ -n "$crop" ]]; then
        if ffmpeg -hide_banner -loglevel error -i "$file" -vf "crop=$crop" -c:v hevc_videotoolbox -q:v $q -c:a aac -b:a 320k -ac 2 -ar 48000 "$out" 2>/dev/null; then
          : # success
        else
          echo "FAILED: $base" >> "'"$ERROR_LOG"'"
        fi
      else
        if ffmpeg -hide_banner -loglevel error -i "$file" -c:v hevc_videotoolbox -q:v $q -c:a aac -b:a 320k -ac 2 -ar 48000 "$out" 2>/dev/null; then
          : # success
        else
          echo "FAILED: $base" >> "'"$ERROR_LOG"'"
        fi
      fi
    fi
  ' _ {}
  
  # Show errors if any
  if [[ -f "$ERROR_LOG" && -s "$ERROR_LOG" ]]; then
    local error_count=$(wc -l < "$ERROR_LOG")
    echo ""
    echo "⚠️  $error_count file(s) had issues:"
    cat "$ERROR_LOG"
  fi
  
  if [[ $USE_SUBDIR -eq 1 ]]; then
    echo "✅ Done! Encoded files in: $(pwd)/$OUTDIR/"
  else
    echo "✅ Done! Encoded files in current directory"
  fi
  
  if command -v osascript &>/dev/null; then
    osascript -e 'display notification "GPU encoding complete!" with title "video-encode-gpu"'
  fi
}

# Convert video to GIF (useful for documentation/issues)
video-to-gif() {
    emulate -L zsh
    
    local input="$1"
    local output="${2:-${input:r}.gif}"
    local fps="${3:-12}"
    local scale="${4:-420}"

    if [[ -z "$input" ]]; then
        echo "Usage: video-to-gif <input.mp4> [output.gif] [fps=12] [width=420]"
        return 1
    fi

    if [[ ! -f "$input" ]]; then
        echo "❌ File not found: $input"
        return 1
    fi

    if [[ -f "$output" ]]; then
        echo "❌ Output already exists: $output"
        return 1
    fi

    echo "🎞  Creating optimized GIF"
    echo "   fps:   $fps"
    echo "   width: $scale"
    echo "   input: $input"
    echo "   output:$output"
    echo

    local hwaccel_args=(-hwaccel videotoolbox)

    ffmpeg \
        -hide_banner -loglevel error -stats \
        "${hwaccel_args[@]}" \
        -i "$input" \
        -filter_complex "\
mpdecimate,\
setpts=N/FRAME_RATE/TB,\
fps=${fps},\
scale=${scale}:-1:flags=lanczos,\
split[s0][s1];\
[s0]palettegen=max_colors=96:stats_mode=diff[p];\
[s1][p]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
        -loop 0 "$output"

    local rc=$?

    if (( rc == 0 )); then
        echo
        echo "✅ GIF created:"
        ls -lh "$output"
    else
        echo
        echo "❌ Conversion failed"
        return $rc
    fi
}
