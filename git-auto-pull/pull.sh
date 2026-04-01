#!/bin/bash

# Git Auto-Pull Script
# Runs in background every hour
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
    
    # Change to repo and update configured branch
    (
        cd "$repo_path" || exit

        current_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
        
        if ! fetch_output=$(git fetch --quiet origin "$branch_name" 2>&1); then
            echo "$(timestamp): Fetch failed for $repo_path ($branch_name): $fetch_output" >> "$ERROR_LOG"
            exit
        fi

        LOCAL=$(git rev-parse "refs/heads/$branch_name" 2>/dev/null || true)
        REMOTE=$(git rev-parse "refs/remotes/origin/$branch_name" 2>/dev/null || true)

        if [[ -z "$REMOTE" ]]; then
            echo "$(timestamp): Unable to resolve remote ref for $repo_path ($branch_name)" >> "$ERROR_LOG"
            exit
        fi

        # Create missing local branch from fetched remote ref.
        if [[ -z "$LOCAL" ]]; then
            if git update-ref "refs/heads/$branch_name" "$REMOTE" 2>/dev/null; then
                echo "$(timestamp): Created local branch $branch_name for $repo_path" >> "$LOG_FILE"
            else
                echo "$(timestamp): Failed to create local branch $branch_name for $repo_path" >> "$ERROR_LOG"
            fi
            exit
        fi
        
        if [[ "$LOCAL" != "$REMOTE" ]]; then
            if git merge-base --is-ancestor "$LOCAL" "$REMOTE"; then
                if [[ "$current_branch" == "$branch_name" ]]; then
                    if pull_output=$(git merge --ff-only --quiet "origin/$branch_name" 2>&1); then
                        echo "$(timestamp): Updated $repo_path ($branch_name)" >> "$LOG_FILE"
                    else
                        echo "$(timestamp): Fast-forward failed for checked out branch in $repo_path ($branch_name): $pull_output" >> "$ERROR_LOG"
                    fi
                elif git update-ref "refs/heads/$branch_name" "$REMOTE" "$LOCAL" 2>/dev/null; then
                    echo "$(timestamp): Updated $repo_path ($branch_name)" >> "$LOG_FILE"
                else
                    echo "$(timestamp): Failed to update branch ref for $repo_path ($branch_name)" >> "$ERROR_LOG"
                fi
            else
                echo "$(timestamp): Skipped diverged branch for $repo_path ($branch_name)" >> "$ERROR_LOG"
            fi
        fi
    ) &
    
done < "$CONFIG_FILE"

# Wait for all background jobs to complete
wait
