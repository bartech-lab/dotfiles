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
    echo "Opening Azure DevOps repo…"
    open "https://dev.azure.com/${path//\//\/_git\/}"
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
  open "$url"
}
