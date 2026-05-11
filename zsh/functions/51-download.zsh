# Download Functions
# ytdl - yt-dlp with 16 concurrent fragments, infinite retries

ytdl() {
  yt-dlp -N 16 --fragment-retries infinite \
    --http-chunk-size 10M \
    -4 \
    "$@"
}
