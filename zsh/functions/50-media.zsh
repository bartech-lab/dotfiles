# Media Functions
# optimize-images, dng-to-jpg, video-remux, video-encode-cpu, video-encode-gpu, video-encode-av1

_notify() {
    local title="$1" msg="$2"
    if [[ "$DOTFILES_OS" == macos ]]; then
        osascript -e "display notification \"$msg\" with title \"$title\"" 2>/dev/null
    elif command -v notify-send &>/dev/null; then
        notify-send "$title" "$msg" 2>/dev/null
    fi
}

optimize-images() (
  local SOURCE_PATH="."
  local INPUT_DIR=""
  local SINGLE_FILE=""
  local LOSSLESS=0
  
  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case $1 in
      --lossless)
        LOSSLESS=1
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

  local ERROR_LOG="./optimize_images_errors.log"
  rm -f "$ERROR_LOG"

  local jpeg_files=()
  local png_files=()

  if [[ -n "$SINGLE_FILE" ]]; then
    local single_ext="${SINGLE_FILE##*.}"
    single_ext="${single_ext:l}"

    case "$single_ext" in
      jpg|jpeg)
        jpeg_files+=("./$SINGLE_FILE")
        ;;
      png)
        png_files+=("./$SINGLE_FILE")
        ;;
      *)
        echo "❌ Unsupported file type: $SINGLE_FILE"
        echo "Supported: .jpg, .jpeg, .png"
        return 1
        ;;
    esac
  else
    while IFS= read -r -d '' file; do
      jpeg_files+=("$file")
    done < <(find . -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" \) ! -iname "*-opt.*" ! -iname "*-opt[0-9]*.*" -print0)

    while IFS= read -r -d '' file; do
      png_files+=("$file")
    done < <(find . -maxdepth 1 -type f -iname "*.png" ! -iname "*-opt.*" ! -iname "*-opt[0-9]*.*" -print0)
  fi
  
  # Count files to process
  local jpeg_count=${#jpeg_files[@]}
  local png_count=${#png_files[@]}
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
    printf '%s\0' "${jpeg_files[@]}" | xargs -0 -P 4 -I{} sh -c '
      file="$1"
      base=$(basename "$file")
      name="${base%.*}"
      ext=$(printf "%s" "${base##*.}" | tr "[:upper:]" "[:lower:]")
      prefix="${name}-opt"
      out="${prefix}.${ext}"
      n=2

      while [[ -e "$out" ]]; do
        out="${prefix}${n}.${ext}"
        n=$((n + 1))
      done

      tmp=".optimize_tmp_${$}_${RANDOM}_${name}.jpg"

      # Prefer cjpegli (jpeg-xl): ~30% smaller than mozjpeg at q85+, standard JPEG output.
      # Fall back to djpeg | cjpeg where jpeg-xl is not installed (e.g. Linux): libjpeg-turbo cjpeg cannot read JPEG input.
      if command -v cjpegli >/dev/null 2>&1; then
        ok=0; cjpegli "$file" "$tmp" -q 85 2>/dev/null && ok=1
      else
        ok=0; djpeg "$file" 2>/dev/null | cjpeg -quality 85 -optimize -progressive > "$tmp" 2>/dev/null && ok=1
      fi

      if [[ $ok -eq 1 ]]; then
        mv "$tmp" "$out"
        touch -r "$file" "$out"
      else
        rm -f "$tmp" 2>/dev/null
        echo "FAILED: $base" >> "'$ERROR_LOG'"
      fi
    ' _ {}
  fi
  
  # Process PNG files in parallel
  if [[ $png_count -gt 0 ]]; then
    if [[ $LOSSLESS -eq 1 ]]; then
      printf '%s\0' "${png_files[@]}" | xargs -0 -P 4 -I{} sh -c '
        file="$1"
        base=$(basename "$file")
        name="${base%.*}"
        prefix="${name}-opt"
        out="${prefix}.png"
        n=2

        while [[ -e "$out" ]]; do
          out="${prefix}${n}.png"
          n=$((n + 1))
        done

        tmp=".optimize_tmp_${$}_${RANDOM}_${name}.png"

        if oxipng -q -o 4 --strip safe -a -i 0 --out "$tmp" "$file" 2>/dev/null; then
          mv "$tmp" "$out"
          touch -r "$file" "$out"
        else
          rm -f "$tmp" 2>/dev/null
          echo "FAILED: $base" >> "'$ERROR_LOG'"
        fi
      ' _ {}
    else
      printf '%s\0' "${png_files[@]}" | xargs -0 -P 4 -I{} sh -c '
          file="$1"
          base=$(basename "$file")
          name="${base%.*}"
          tmp_png=".optimize_tmp_${$}_${RANDOM}_${name}.png"

          prefix="${name}-opt"
          out="${prefix}.png"
          n=2

          while [[ -e "$out" ]]; do
            out="${prefix}${n}.png"
            n=$((n + 1))
          done

          tmp_quant=".optimize_quant_tmp_${$}_${RANDOM}_${base}"
          pngquant --quality=80-90 --speed 1 --output "$tmp_quant" -- "$file" 2>/dev/null

          if [[ -f "$tmp_quant" ]]; then
            if oxipng -q -o 4 --strip safe -a -i 0 --out "$tmp_png" "$tmp_quant" 2>/dev/null; then
              mv "$tmp_png" "$out"
              touch -r "$file" "$out"
            else
              echo "FAILED: $base" >> "'$ERROR_LOG'"
            fi
            rm -f "$tmp_quant" "$tmp_png" 2>/dev/null
          else
            if oxipng -q -o 4 --strip safe -a -i 0 --out "$tmp_png" "$file" 2>/dev/null; then
              mv "$tmp_png" "$out"
              touch -r "$file" "$out"
            else
              rm -f "$tmp_png" 2>/dev/null
              echo "FAILED: $base" >> "'$ERROR_LOG'"
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
    echo "💡 Convert them first with: dng-to-jpg [path] [quality]"
  fi
  
  if [[ -f "$ERROR_LOG" && -s "$ERROR_LOG" ]]; then
    local error_count=$(wc -l < "$ERROR_LOG")
    echo "⚠️  $error_count file(s) had issues:"
    cat "$ERROR_LOG"
    echo ""
  fi

  echo "✅ Done! Optimized $total_count files in current directory"
)

video-remux() (
  local SOURCE_PATH="."
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
    else
      out="${name}.mp4"
    fi
    
    tmp="$out.part"
    if [[ ! -f "$out" ]]; then
      if [[ "$ext" == "webp" ]]; then
        packets=$(ffprobe -v error -count_packets -select_streams v:0 -show_entries stream=nb_read_packets -of csv=p=0 "$file" 2>/dev/null | tr -d "\r")

        if [[ "$packets" == "N/A" || -z "$packets" ]]; then
          packets=$(ffprobe -v error -count_frames -select_streams v:0 -show_entries stream=nb_read_frames -of csv=p=0 "$file" 2>/dev/null | tr -d "\r")
        fi

        if [[ "$packets" =~ ^[0-9]+$ ]] && (( packets > 1 )); then
          if ffmpeg -hide_banner -loglevel error -i "$file" -an -c:v libx264 -pix_fmt yuv420p -movflags +faststart -y -f mp4 "$tmp" 2>/dev/null && mv "$tmp" "$out"; then
            touch -r "$file" "$out"
          else
            rm -f "$tmp"
            echo "FAILED: $base" >> "'$ERROR_LOG'"
          fi
        else
          echo "SKIPPED (not animated): $base" >> "'$SKIP_LOG'"
        fi
      else
        if ffmpeg -hide_banner -loglevel error -i "$file" -c:v copy -c:a copy -movflags +faststart -y -f mp4 "$tmp" 2>/dev/null && mv "$tmp" "$out"; then
          touch -r "$file" "$out"
        else
          if [[ "$ext" == "webm" ]]; then
            if ffmpeg -hide_banner -loglevel error -i "$file" -c:v libx264 -pix_fmt yuv420p -c:a aac -b:a 192k -movflags +faststart -y -f mp4 "$tmp" 2>/dev/null && mv "$tmp" "$out"; then
              touch -r "$file" "$out"
            else
              rm -f "$tmp"
              echo "FAILED: $base" >> "'$ERROR_LOG'"
            fi
          else
            rm -f "$tmp"
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
  
  _notify "video-remux" "Video remux complete!"
)

# Shared by video-encode-cpu and video-encode-gpu: pick .mov/.mp4/.mkv/.avi
# sources, skip an .mp4 that a same-name source already produced, and report
# two sources that would write the same output instead of dropping one.
_video_encode_plan() {
  local outdir=$1 subdir=$2 file base name ext out
  local -A sources taken
  local -a found
  _venc_files=() _venc_outs=()
  found=("${(@0)$(find . -maxdepth 1 -type f \( -iname "*.mov" -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" \) ! -iname "*-h265.mp4" -print0 | sort -z)}")
  found=("${(@)found:#}")
  for file in "${found[@]}"; do
    base=${file:t}; ext=${${base##*.}:l}
    [[ $ext != mp4 ]] && sources[${${base%.*}:l}]=$base
  done
  for file in "${found[@]}"; do
    base=${file:t}; name=${base%.*}; ext=${${base##*.}:l}
    if [[ $ext == mp4 && -n ${sources[${name:l}]} ]]; then
      echo "⏭️  Skipping $base: output of ${sources[${name:l}]}"
      continue
    fi
    if (( subdir )); then
      out="$outdir/$name.mp4"
    elif [[ $ext == mp4 ]]; then
      out="$name-h265.mp4"
    else
      out="$name.mp4"
    fi
    if [[ -n ${taken[$out]} ]]; then
      echo "⚠️  Skipping $base: $out is already the output of ${taken[$out]}"
      continue
    fi
    taken[$out]=$base
    _venc_files+=("$file")
    _venc_outs+=("$out")
  done
}

_video_encode_pairs() {
  local i
  for (( i = 1; i <= ${#_venc_files}; i++ )); do
    printf '%s\0%s\0' "${_venc_files[i]}" "${_venc_outs[i]}"
  done
}

video-encode-cpu() (
  local SOURCE_DIR="."
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
  
  local files=() outs=()
  _video_encode_plan "$OUTDIR" "$USE_SUBDIR"
  files=("${_venc_files[@]}")
  outs=("${_venc_outs[@]}")
  
  local total_files=${#files[@]}
  
  if (( total_files == 0 )); then
    echo "No video files found to encode"
    return 0
  fi
  
  echo "Found $total_files files to encode"
  echo "Mode: CPU H.265 (high quality, slow)"
  echo ""

  # Platform-aware parallel: M4 Pro handles 4 concurrent x265 encodes;
  # 9800X3D (8c/16t) caps at 3 to avoid thread contention
  local enc_parallel=2
  if [[ "$DOTFILES_OS" == macos ]]; then
    enc_parallel=4
  elif [[ "$DOTFILES_OS" == linux ]]; then
    enc_parallel=3
  fi

  # Process files in parallel using xargs
  _video_encode_pairs | xargs -0 -n 2 -P "$enc_parallel" sh -c '
    file="$1"
    out="$2"
    base=$(basename "$file")
    
    tmp="$out.part"
    if [[ ! -f "$out" ]]; then
      if ffmpeg -hide_banner -loglevel error -i "$file" -c:v libx265 -preset slow -crf 22 -pix_fmt yuv420p10le -c:a aac -b:a 320k -ac 2 -ar 48000 -y -f mp4 "$tmp" 2>/dev/null && mv "$tmp" "$out"; then
        : # success
      else
        rm -f "$tmp"
        echo "FAILED: $base" >> "'$ERROR_LOG'"
      fi
    fi
  ' _
  
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
  
  _notify "video-encode-cpu" "CPU encoding complete!"
)

video-encode-gpu() (
  local SOURCE_DIR="."
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
  
  local files=() outs=()
  _video_encode_plan "$OUTDIR" "$USE_SUBDIR"
  files=("${_venc_files[@]}")
  outs=("${_venc_outs[@]}")
  
  local total_files=${#files[@]}
  
  if (( total_files == 0 )); then
    echo "No video files found to encode"
    return 0
  fi
  
  echo "Found $total_files files to encode"
  echo "Mode: GPU H.265 (fast encoding)"
  echo ""

  # Platform-aware encoder with optimized flags
  local encoder
  local enc_flags
  if [[ "$DOTFILES_OS" == macos ]]; then
    encoder="hevc_videotoolbox"
    enc_flags="-q:v 40 -pix_fmt p010le -allow_sw 0"
  elif command -v nvidia-smi &>/dev/null; then
    encoder="hevc_nvenc"
    enc_flags="-preset p7 -tune hq -cq 26 -pix_fmt p010le -multipass qres -bf 5 -b_ref_mode each -spatial-aq 1 -temporal-aq 1"
  else
    encoder="hevc_vaapi"
    enc_flags="-qp 26"
  fi
  export DOTFILES_ENCODER="$encoder"
  export DOTFILES_ENCODER_FLAGS="$enc_flags"
  
  # Process files in parallel using xargs (4 jobs for GPU)
  _video_encode_pairs | xargs -0 -n 2 -P 4 sh -c '
    file="$1"
    out="$2"
    base=$(basename "$file")
    
    tmp="$out.part"
    if [[ ! -f "$out" ]]; then
      crop=""; best=0
      dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$file" 2>/dev/null)
      dur=${dur%.*}
      case "$dur" in ""|*[!0-9]*) dur=0 ;; esac
      for pct in 20 50 80; do
        c=$(ffmpeg -hide_banner -ss $((dur * pct / 100)) -i "$file" -vf cropdetect=limit=0.1:round=2 -t 4 -f null - 2>&1 | grep -o "crop=[0-9]*:[0-9]*:[0-9]*:[0-9]*" | tail -1)
        c=${c#crop=}
        w=${c%%:*}; rest=${c#*:}; h=${rest%%:*}
        if [ -n "$c" ] && [ $((w * h)) -gt "$best" ]; then best=$((w * h)); crop=$c; fi
      done
      
      if [[ -n "$crop" ]]; then
        if ffmpeg -hide_banner -loglevel error -i "$file" -vf "crop=$crop" -c:v "$DOTFILES_ENCODER" $DOTFILES_ENCODER_FLAGS -c:a aac -b:a 320k -ac 2 -ar 48000 -y -f mp4 "$tmp" 2>/dev/null && mv "$tmp" "$out"; then
          : # success
        else
          rm -f "$tmp"
          echo "FAILED: $base" >> "'"$ERROR_LOG"'"
        fi
      else
        if ffmpeg -hide_banner -loglevel error -i "$file" -c:v "$DOTFILES_ENCODER" $DOTFILES_ENCODER_FLAGS -c:a aac -b:a 320k -ac 2 -ar 48000 -y -f mp4 "$tmp" 2>/dev/null && mv "$tmp" "$out"; then
          : # success
        else
          rm -f "$tmp"
          echo "FAILED: $base" >> "'"$ERROR_LOG"'"
        fi
      fi
    fi
  ' _
  
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
  
  _notify "video-encode-gpu" "GPU encoding complete!"
)

video-encode-av1() (
  local SOURCE_DIR="."
  local USE_SUBDIR=0

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

  # AV1 NVENC requires RTX 40xx/50xx
  if ! command -v nvidia-smi &>/dev/null; then
    echo "❌ NVIDIA GPU not detected (av1_nvenc requires RTX 40xx/50xx)"
    return 1
  fi

  cd "$SOURCE_DIR" || return 1

  local OUTDIR="."
  local ERROR_LOG="./encode_errors.log"

  if [[ $USE_SUBDIR -eq 1 ]]; then
    mkdir -p av1
    OUTDIR="av1"
    ERROR_LOG="$OUTDIR/encode_errors.log"
  fi

  rm -f "$ERROR_LOG"

  local files=()
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find . -maxdepth 1 -type f \( -iname "*.mov" -o -iname "*.mp4" -o -iname "*.mkv" \) ! -iname "*-av1.mp4" -print0)

  local total_files=${#files[@]}

  if (( total_files == 0 )); then
    echo "No video files found to encode"
    return 0
  fi

  echo "Found $total_files files to encode"
  echo "Mode: GPU AV1 (NVENC, 10-bit)"
  echo ""

  printf '%s\0' "${files[@]}" | xargs -0 -P 2 -I{} sh -c '
    file="$1"
    base=$(basename "$file")
    name="${base%.*}"
    ext=$(printf "%s" "${base##*.}" | tr "[:upper:]" "[:lower:]")

    if [[ "'"$USE_SUBDIR"'" == "1" ]]; then
      out="'"$OUTDIR"'/${name}.mp4"
    elif [[ "$ext" == "mp4" ]]; then
      out="${name}-av1.mp4"
    else
      out="${name}.mp4"
    fi

    tmp="$out.part"
    if [[ ! -f "$out" ]]; then
      if ffmpeg -hide_banner -loglevel error -i "$file" \
          -c:v av1_nvenc -preset p7 -tune hq -cq 28 -pix_fmt p010le \
          -multipass qres -b_ref_mode each -spatial-aq 1 -temporal-aq 1 \
          -c:a aac -b:a 192k -ac 2 -ar 48000 \
          -movflags +faststart -y -f mp4 "$tmp" 2>/dev/null && mv "$tmp" "$out"; then
        touch -r "$file" "$out"
      else
        rm -f "$tmp"
        echo "FAILED: $base" >> "'"$ERROR_LOG"'"
      fi
    fi
  ' _ {}

  if [[ -f "$ERROR_LOG" && -s "$ERROR_LOG" ]]; then
    local error_count=$(wc -l < "$ERROR_LOG")
    echo ""
    echo "⚠️  $error_count file(s) had issues:"
    cat "$ERROR_LOG"
  fi

  if [[ $USE_SUBDIR -eq 1 ]]; then
    echo "✅ Done! AV1-encoded files in: $(pwd)/$OUTDIR/"
  else
    echo "✅ Done! AV1-encoded files in current directory"
  fi

  _notify "video-encode-av1" "AV1 encoding complete!"
)

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

    local hwaccel_args=()
    if [[ "$DOTFILES_OS" == macos ]]; then
        hwaccel_args=(-hwaccel videotoolbox)
    elif command -v nvidia-smi &>/dev/null; then
        hwaccel_args=(-hwaccel cuda)
    fi

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

# Convert DNG raw files to JPEG via ImageMagick (libraw decode)
dng-to-jpg() (
    emulate -L zsh

    local SOURCE_PATH="${1:-.}"
    local QUALITY="${2:-92}"

    if [[ ! -d "$SOURCE_PATH" && ! -f "$SOURCE_PATH" ]]; then
        echo "❌ Error: Path '$SOURCE_PATH' not found"
        return 1
    fi

    if ! command -v magick >/dev/null 2>&1; then
        echo "❌ Error: ImageMagick 7 ('magick') is required but not installed"
        return 1
    fi

    local INPUT_DIR SINGLE_FILE=""
    if [[ -d "$SOURCE_PATH" ]]; then
        INPUT_DIR="$SOURCE_PATH"
    else
        INPUT_DIR="${SOURCE_PATH:h}"
        SINGLE_FILE="${SOURCE_PATH:t}"
    fi

    cd "$INPUT_DIR" || return 1

    local ERROR_LOG="./dng_to_jpg_errors.log"
    rm -f "$ERROR_LOG"

    local dng_files=()
    if [[ -n "$SINGLE_FILE" ]]; then
        local single_ext="${SINGLE_FILE##*.}"
        if [[ "${single_ext:l}" != "dng" ]]; then
            echo "❌ Unsupported file type: $SINGLE_FILE"
            echo "Supported: .dng"
            return 1
        fi
        dng_files+=("./$SINGLE_FILE")
    else
        while IFS= read -r -d '' file; do
            dng_files+=("$file")
        done < <(find . -maxdepth 1 -type f -iname "*.dng" -print0)
    fi

    local total_count=${#dng_files[@]}
    if [[ $total_count -eq 0 ]]; then
        echo "No DNG files found to process"
        return 0
    fi

    echo "Mode: DNG → JPEG"
    echo "Found $total_count file(s), quality: $QUALITY"
    echo ""

    printf '%s\0' "${dng_files[@]}" | xargs -0 -P 4 -I{} sh -c '
        file="$1"
        quality="$2"
        error_log="$3"
        base=$(basename "$file")
        name="${base%.*}"
        out="$name.jpg"

        if [[ -e "$out" ]]; then
            echo "SKIP: $out already exists"
            exit 0
        fi

        tmp=".dng_to_jpg_tmp_${$}_${RANDOM}_$name.jpg"

        if magick "$file" -auto-orient -quality "$quality" "$tmp"; then
            mv "$tmp" "$out"
            touch -r "$file" "$out"
            echo "OK: $base → $out"
        else
            rm -f "$tmp" 2>/dev/null
            echo "FAILED: $base" >> "$error_log"
        fi
    ' _ {} "$QUALITY" "$ERROR_LOG"

    echo ""

    if [[ -f "$ERROR_LOG" && -s "$ERROR_LOG" ]]; then
        local error_count=$(wc -l < "$ERROR_LOG")
        echo "⚠️  $error_count file(s) failed:"
        cat "$ERROR_LOG"
        echo ""
        rm -f "$ERROR_LOG"
        return 1
    fi

    echo "✅ Done! Converted $total_count file(s) in $INPUT_DIR"
)
