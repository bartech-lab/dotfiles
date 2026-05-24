# Git Functions
# git-cleanup and other git helpers

git-cleanup() {
  echo "→ Removing merged branches..."
  git branch --merged | grep -v "\*" | grep -v "master\|main" | xargs -r git branch -d
  
  echo "→ Cleaning old stashes..."
  git stash clear
  
  echo "→ Running git gc..."
  git gc
  
  echo "✅ Done!"
}

git-open() {
  local url host path

  url=$(git remote get-url origin 2>/dev/null) || {
    echo "No origin remote"
    return 1
  }

  # --- Azure DevOps SSH special case ---
  if [[ "$url" == git@ssh.dev.azure.com:* ]]; then
    # git@ssh.dev.azure.com:v3/org/project/repo
    path=${url#git@ssh.dev.azure.com:v3/}
    local azure_url="https://dev.azure.com/${path//\//\/_git\/}"
    echo "Opening Azure DevOps repo…"
    if [[ "$DOTFILES_OS" == macos ]]; then
      open "$azure_url"
    else
      xdg-open "$azure_url" &>/dev/null & disown
    fi
    return
  fi

  # --- Generic SSH remotes ---
  if [[ "$url" == git@*:* ]]; then
    host=${url%%:*}
    host=${host#git@}
    path=${url#*:}
    url="https://${host}/${path}"
  fi

  # --- Remove trailing .git ---
  url=${url%.git}

  echo "Opening $url"
  if [[ "$DOTFILES_OS" == macos ]]; then
    open "$url"
  else
    xdg-open "$url" &>/dev/null & disown
  fi
}
