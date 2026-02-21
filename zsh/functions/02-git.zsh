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
