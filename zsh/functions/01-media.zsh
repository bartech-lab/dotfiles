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
  
  # Create temp file for progress tracking
  local progress_file=$(mktemp)
  echo "0" > "$progress_file"
  
  # Start progress display in background (suppress job notifications)
  (
    while true; do
      local current=$(cat "$progress_file" 2>/dev/null || echo 0)
      if [[ "$current" -ge "$total_count" ]]; then
        break
      fi
      printf "\rOptimizing %d/%d files..." "$current" "$total_count"
      sleep 0.1
    done
  ) 2>/dev/null &
  local display_pid=$!
  
  # Process JPEG files in parallel
  if [[ $jpeg_count -gt 0 ]]; then
    find . -maxdepth 1 \( -name "*.jpg" -o -name "*.jpeg" \) -print0 | \
      sed 's|^\./||' | \
      parallel -0 --will-cite '
        cjpeg -quality 92 -optimize -progressive {} > optimized/{} 2>/dev/null
        echo $(($(cat "'$progress_file'") + 1)) > "'$progress_file'"
      ' >/dev/null 2>&1
  fi
  
  # Process PNG files in parallel
  if [[ $png_count -gt 0 ]]; then
    if [[ $LOSSLESS -eq 1 ]]; then
      find . -maxdepth 1 -name "*.png" -print0 | \
        sed 's|^\./||' | \
        parallel -0 --will-cite '
          oxipng -q -o 4 --strip safe -i 0 --out optimized/{} {} 2>/dev/null
          echo $(($(cat "'$progress_file'") + 1)) > "'$progress_file'"
        ' >/dev/null 2>&1
    else
      find . -maxdepth 1 -name "*.png" -print0 | \
        sed 's|^\./||' | \
        parallel -0 --will-cite '
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
          echo $(($(cat "'$progress_file'") + 1)) > "'$progress_file'"
        ' >/dev/null 2>&1
    fi
  fi
  
  # Kill progress display
  kill $display_pid 2>/dev/null
  wait $display_pid 2>/dev/null
  
  # Final display
  printf "\rOptimizing %d/%d files..." "$total_count" "$total_count"
  echo ""
  echo ""
  
  # Cleanup
  rm -f "$progress_file"
  
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
  
  # Progress tracking
  local progress_file=$(mktemp)
  echo "0" > "$progress_file"
  
  # Start progress display in background (suppress job notifications)
  (
    while true; do
      local current=$(cat "$progress_file" 2>/dev/null || echo 0)
      if [[ "$current" -ge "$total_files" ]]; then
        break
      fi
      printf "\rProcessing %d/%d files..." "$current" "$total_files"
      sleep 0.2
    done
  ) 2>/dev/null &
  local display_pid=$!
  
  # Export variables for parallel
  export OUTDIR ERROR_LOG progress_file
  
  # Use GNU parallel for clean parallel processing
  printf '%s\0' "${files[@]}" | parallel -0 --will-cite '
    file="{}"
    base=$(basename "$file")
    name="${base%.*}"
    out="'$OUTDIR'/${name}.mp4"
    
    if [[ -f "$out" ]]; then
      echo $(($(cat "'$progress_file'") + 1)) > "'$progress_file'"
    elif ffmpeg -hide_banner -loglevel error -i "$file" -c:v copy -c:a copy -movflags +faststart "$out" 2>/dev/null; then
      touch -r "$file" "$out"
      echo $(($(cat "'$progress_file'") + 1)) > "'$progress_file'"
    else
      echo "FAILED: $base" >> "'$ERROR_LOG'"
      echo $(($(cat "'$progress_file'") + 1)) > "'$progress_file'"
    fi
  ' >/dev/null 2>&1
  
  # Kill progress display
  kill $display_pid 2>/dev/null
  wait $display_pid 2>/dev/null
  
  # Final display
  printf "\rProcessing %d/%d files..." "$total_files" "$total_files"
  echo ""
  echo ""
  
  # Check for errors
  if [[ -f "$ERROR_LOG" ]]; then
    local error_count=$(wc -l < "$ERROR_LOG")
    if (( error_count > 0 )); then
      echo "⚠️  $error_count file(s) had issues. Check: $ERROR_LOG"
      echo ""
    fi
  fi
  
  rm -f "$progress_file"
  
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
  
  # Progress tracking
  local progress_file=$(mktemp)
  echo "0" > "$progress_file"
  
  # Start progress display in background (suppress job notifications)
  (
    while true; do
      local current=$(cat "$progress_file" 2>/dev/null || echo 0)
      if [[ "$current" -ge "$total_files" ]]; then
        break
      fi
      printf "\rEncoding %d/%d files..." "$current" "$total_files"
      sleep 0.5
    done
  ) 2>/dev/null &
  local display_pid=$!
  
  # Export variables for parallel
  export OUTDIR ERROR_LOG progress_file
  
  # Use GNU parallel for clean parallel processing (2 jobs for CPU)
  printf '%s\0' "${files[@]}" | parallel -0 -j2 --will-cite '
    file="{}"
    base=$(basename "$file")
    name="${base%.*}"
    out="'$OUTDIR'/${name}.mp4"
    
    if [[ -f "$out" ]]; then
      echo $(($(cat "'$progress_file'") + 1)) > "'$progress_file'"
    elif ffmpeg -hide_banner -loglevel error -i "$file" -c:v libx265 -preset slow -crf 22 -pix_fmt yuv420p10le -c:a aac -b:a 320k -ac 2 -ar 48000 "$out" 2>/dev/null; then
      echo $(($(cat "'$progress_file'") + 1)) > "'$progress_file'"
    else
      echo "FAILED: $base" >> "'$ERROR_LOG'"
      echo $(($(cat "'$progress_file'") + 1)) > "'$progress_file'"
    fi
  ' >/dev/null 2>&1
  
  # Kill progress display
  kill $display_pid 2>/dev/null
  wait $display_pid 2>/dev/null
  
  # Final display
  printf "\rEncoding %d/%d files..." "$total_files" "$total_files"
  echo ""
  echo ""
  
  # Check for errors
  if [[ -f "$ERROR_LOG" ]]; then
    local error_count=$(wc -l < "$ERROR_LOG")
    if (( error_count > 0 )); then
      echo "⚠️  $error_count file(s) had issues. Check: $ERROR_LOG"
      echo ""
    fi
  fi
  
  rm -f "$progress_file"
  
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
  
  # Progress tracking
  local progress_file=$(mktemp)
  echo "0" > "$progress_file"
  
  # Start progress display in background (suppress job notifications)
  (
    while true; do
      local current=$(cat "$progress_file" 2>/dev/null || echo 0)
      if [[ "$current" -ge "$total_files" ]]; then
        break
      fi
      printf "\rEncoding %d/%d files..." "$current" "$total_files"
      sleep 0.5
    done
  ) 2>/dev/null &
  local display_pid=$!
  
  # Export variables for parallel
  export OUTDIR ERROR_LOG progress_file
  
  # Use GNU parallel for clean parallel processing (4 jobs for GPU)
  printf '%s\0' "${files[@]}" | parallel -0 -j4 --will-cite '
    file="{}"
    base=$(basename "$file")
    name="${base%.*}"
    out="'$OUTDIR'/${name}.mp4"
    
    if [[ -f "$out" ]]; then
      echo $(($(cat "'$progress_file'") + 1)) > "'$progress_file'"
    else
      q=52
      crop=$(ffmpeg -hide_banner -i "$file" -vf cropdetect=limit=0.1:round=2 -t 8 -f null - 2>&1 | awk -F'"'"'crop='"'"' '"'"'/crop=/{print $2}'"'"' | awk '"'"'{print $1}'"'"' | tail -1)
      vf=""
      [[ -n "$crop" ]] && vf="-vf crop=$crop"
      
      if ffmpeg -hide_banner -loglevel error -i "$file" $vf -c:v hevc_videotoolbox -q:v $q -c:a aac -b:a 320k -ac 2 -ar 48000 "$out" 2>/dev/null; then
        :
      else
        echo "FAILED: $base" >> "'$ERROR_LOG'"
      fi
      echo $(($(cat "'$progress_file'") + 1)) > "'$progress_file'"
    fi
  ' >/dev/null 2>&1
  
  # Kill progress display
  kill $display_pid 2>/dev/null
  wait $display_pid 2>/dev/null
  
  # Final display
  printf "\rEncoding %d/%d files..." "$total_files" "$total_files"
  echo ""
  echo ""
  
  # Check for errors
  if [[ -f "$ERROR_LOG" ]]; then
    local error_count=$(wc -l < "$ERROR_LOG")
    if (( error_count > 0 )); then
      echo "⚠️  $error_count file(s) had issues. Check: $ERROR_LOG"
      echo ""
    fi
  fi
  
  rm -f "$progress_file"
  
  echo "✅ Done! Encoded files in: $(pwd)/$OUTDIR/"
  
  if command -v osascript &>/dev/null; then
    osascript -e 'display notification "GPU encoding complete!" with title "video-encode-gpu"'
  fi
}
