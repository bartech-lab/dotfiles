#!/bin/bash

# Git Auto-Pull Script
# Runs silently in background every 6 hours
# Reads repo configuration from repos.conf

CONFIG_FILE="$HOME/.config/git-auto-pull/repos.conf"
LOG_FILE="$HOME/.config/git-auto-pull/pull.log"

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "$(date): Config file not found at $CONFIG_FILE" >> "$LOG_FILE"
    exit 1
fi

# Process each repo
while IFS=':' read -r repo_path branch_name; do
    # Skip empty lines and comments
    [[ -z "$repo_path" ]] && continue
    [[ "$repo_path" =~ ^[[:space:]]*# ]] && continue
    
    # Trim whitespace
    repo_path=$(echo "$repo_path" | xargs)
    branch_name=$(echo "$branch_name" | xargs)
    
    # Validate inputs
    [[ -z "$branch_name" ]] && continue
    
    # Expand tilde to home directory
    repo_path="${repo_path/#\~/$HOME}"
    
    # Check if repo exists
    if [[ ! -d "$repo_path/.git" ]]; then
        echo "$(date): Not a git repo: $repo_path" >> "$LOG_FILE"
        continue
    fi
    
    # Change to repo and pull
    (
        cd "$repo_path" || exit
        
        # Fetch quietly
        git fetch --quiet origin "$branch_name" 2>/dev/null
        
        # Check if we're behind
        LOCAL=$(git rev-parse "$branch_name" 2>/dev/null)
        REMOTE=$(git rev-parse "origin/$branch_name" 2>/dev/null)
        
        if [[ "$LOCAL" != "$REMOTE" ]]; then
            # Pull changes
            git pull --quiet origin "$branch_name" 2>/dev/null
            echo "$(date): Updated $repo_path ($branch_name)" >> "$LOG_FILE"
        fi
    ) &
    
done < "$CONFIG_FILE"

# Wait for all background jobs to complete
wait
