#!/bin/bash

# Git Auto-Pull Script
# Runs in background every 4 hours
# Reads repo configuration from repos.conf

CONFIG_FILE="$HOME/.config/git-auto-pull/repos.conf"
LOG_FILE="$HOME/.config/git-auto-pull/pull.log"
ERROR_LOG="$HOME/.config/git-auto-pull/error.log"

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Check if config exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "$(timestamp): Config file not found at $CONFIG_FILE" >> "$ERROR_LOG"
    exit 1
fi

echo "$(timestamp): Run started" >> "$LOG_FILE"

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
        
        if ! fetch_output=$(git fetch --quiet origin "$branch_name" 2>&1); then
            echo "$(timestamp): Fetch failed for $repo_path ($branch_name): $fetch_output" >> "$ERROR_LOG"
            exit
        fi
        
        # Check if we're behind
        LOCAL=$(git rev-parse "$branch_name" 2>/dev/null)
        REMOTE=$(git rev-parse "origin/$branch_name" 2>/dev/null)

        if [[ -z "$LOCAL" || -z "$REMOTE" ]]; then
            echo "$(timestamp): Unable to resolve refs for $repo_path ($branch_name)" >> "$ERROR_LOG"
            exit
        fi
        
        if [[ "$LOCAL" != "$REMOTE" ]]; then
            if pull_output=$(git pull --ff-only --quiet origin "$branch_name" 2>&1); then
                echo "$(timestamp): Updated $repo_path ($branch_name)" >> "$LOG_FILE"
            else
                echo "$(timestamp): Pull failed for $repo_path ($branch_name): $pull_output" >> "$ERROR_LOG"
            fi
        fi
    ) &
    
done < "$CONFIG_FILE"

# Wait for all background jobs to complete
wait

echo "$(timestamp): Run finished" >> "$LOG_FILE"
