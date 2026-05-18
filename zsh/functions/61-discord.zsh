# Discord OpenAsar utilities

# Platform helpers (callable from sub-function scope)
_discord_app_dir() {
    if [[ "$DOTFILES_OS" == macos ]]; then
        echo "/Applications/Discord.app"
    else
        for d in "/opt/discord" "/usr/lib/discord" "$HOME/.local/share/discord"; do
            [[ -d "$d" ]] && { echo "$d"; return 0; }
        done
        echo ""
    fi
}

_discord_config_dir() {
    if [[ "$DOTFILES_OS" == macos ]]; then
        echo "$HOME/Library/Application Support/discord"
    else
        echo "${XDG_CONFIG_HOME:-$HOME/.config}/discord"
    fi
}

_discord_asar_path() {
    local app_dir=$(_discord_app_dir)
    if [[ "$DOTFILES_OS" == macos ]]; then
        echo "$app_dir/Contents/Resources/app.asar"
    else
        echo "$app_dir/resources/app.asar"
    fi
}

_discord_backup_dir() {
    if [[ "$DOTFILES_OS" == macos ]]; then
        echo "$HOME/Library/OpenAsarPersist"
    else
        echo "${XDG_DATA_HOME:-$HOME/.local/share}/OpenAsarPersist"
    fi
}

_stat_bytes() {
    if [[ "$(uname -s)" == Darwin ]]; then
        stat -f%z "$1" 2>/dev/null
    else
        stat -c%s "$1" 2>/dev/null
    fi
}

discord-openasar-apply() {
  "$HOME/dotfiles/discord/openasar/apply-openasar.sh" "$@"
}

discord-openasar-recover() {
  "$HOME/dotfiles/discord/openasar/recover-discord.sh" "$@"
}

discord-openasar-status() {
  local app=$(_discord_app_dir)
  local asar=$(_discord_asar_path)

  echo "===== Discord OpenAsar Status ====="
  echo ""

  if [[ -n "$app" && -d "$app" ]]; then
    if [[ "$DOTFILES_OS" == macos ]]; then
      local info="$app/Contents/Resources/build_info.json"
      local ver
      ver=$(jq -r '.version // "?"' "$info" 2>/dev/null || echo "?")
      echo "  Discord:       $ver ($app)"
    else
      echo "  Discord:       found at $app"
    fi
  else
    echo "  Discord:       not installed"
  fi

  if [[ -f "$asar" ]]; then
    local asar_size=$(_stat_bytes "$asar")
    if [[ "$asar_size" -lt 100000 ]]; then
      echo "  app.asar:      ${asar_size} bytes  (likely OpenAsar)"
    else
      echo "  app.asar:      $(du -h "$asar" | cut -f1)  (likely stock Discord)"
    fi
  else
    echo "  app.asar:      missing"
  fi

  local settings=$(_discord_config_dir)/settings.json
  if [[ -f "$settings" ]]; then
    if python3 -c "import json; s=json.load(open('$settings')); exit(0 if 'openasar' in s else 1)" 2>/dev/null; then
      echo "  settings:      OpenAsar configured"
    else
      echo "  settings:      no OpenAsar config"
    fi
  else
    echo "  settings:      missing"
  fi

  echo ""

  local persist_dir=$(_discord_backup_dir)
  local backups="$persist_dir/backups"
  if [[ -d "$backups" ]] && [[ -n "$(ls -A "$backups" 2>/dev/null)" ]]; then
    echo "  Backups:"
    ls -1tr "$backups" | while read -r f; do
      printf "    %s  %s\n" "$(du -h "$backups/$f" | cut -f1)" "$f"
    done
  else
    echo "  Backups:       none"
  fi

  local persist="$persist_dir/openasar.app.asar"
  if [[ -f "$persist" ]]; then
    echo "  OpenAsar src:  $(du -h "$persist" | cut -f1)"
  else
    echo "  OpenAsar src:  not downloaded"
  fi

  echo ""
}
