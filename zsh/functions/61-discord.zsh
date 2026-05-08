# Discord OpenAsar utilities

discord-openasar-apply() {
  "$HOME/dotfiles/discord/openasar/apply-openasar.sh" "$@"
}

discord-openasar-recover() {
  "$HOME/dotfiles/discord/openasar/recover-discord.sh" "$@"
}

discord-openasar-status() {
  local app="/Applications/Discord.app"
  local asar="$app/Contents/Resources/app.asar"
  local info="$app/Contents/Resources/build_info.json"
  local settings="$HOME/Library/Application Support/discord/settings.json"
  local backups="$HOME/Library/OpenAsarPersist/backups"
  local persist="$HOME/Library/OpenAsarPersist/openasar.app.asar"

  echo "===== Discord OpenAsar Status ====="
  echo ""

  if [ -d "$app" ]; then
    local ver
    ver=$(jq -r '.version // "?"' "$info" 2>/dev/null || echo "?")
    echo "  Discord:       $ver ($app)"
  else
    echo "  Discord:       not installed"
  fi

  if [ -f "$asar" ]; then
    local asar_size
    asar_size=$(stat -f%z "$asar" 2>/dev/null || echo 0)
    if [ "$asar_size" -lt 100000 ]; then
      echo "  app.asar:      ${asar_size} bytes  (likely OpenAsar)"
    else
      echo "  app.asar:      $(du -h "$asar" | cut -f1)  (likely stock Discord)"
    fi
  else
    echo "  app.asar:      missing"
  fi

  if [ -f "$settings" ]; then
    if python3 -c "import json; s=json.load(open('$settings')); exit(0 if 'openasar' in s else 1)" 2>/dev/null; then
      echo "  settings:      OpenAsar configured"
    else
      echo "  settings:      no OpenAsar config"
    fi
  else
    echo "  settings:      missing"
  fi

  echo ""

  if [ -d "$backups" ] && [ -n "$(ls -A "$backups" 2>/dev/null)" ]; then
    echo "  Backups:"
    ls -1tr "$backups" | while read -r f; do
      printf "    %s  %s\n" "$(du -h "$backups/$f" | cut -f1)" "$f"
    done
  else
    echo "  Backups:       none"
  fi

  if [ -f "$persist" ]; then
    echo "  OpenAsar src:  $(du -h "$persist" | cut -f1)"
  else
    echo "  OpenAsar src:  not downloaded"
  fi

  echo ""
}
