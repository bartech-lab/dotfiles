#!/bin/bash

# Git Auto-Pull Script
# Auto-discovers git repos in ~/Projects and ~/dotfiles
# Optional repos.conf for additional repositories

CONFIG_DIR="$HOME/.config/git-auto-pull"
CONFIG_FILE="$CONFIG_DIR/repos.conf"
LOG_FILE="$CONFIG_DIR/pull.log"
ERROR_LOG="$CONFIG_DIR/error.log"

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log_info() {
    echo "$(timestamp): $1" >> "$LOG_FILE"
}

log_error() {
    echo "$(timestamp): $1" >> "$ERROR_LOG"
}

process_repo() {
    local repo_path="$1" branch_name="$2"

    cd "$repo_path" || return

    local remote
    remote=$(git remote get-url origin 2>/dev/null || true)
    [[ -z "$remote" ]] && return

    local fetch_output
    if ! fetch_output=$(git fetch --quiet origin "$branch_name" 2>&1); then
        log_error "Fetch failed for $repo_path ($branch_name): $fetch_output"
        return
    fi

    local LOCAL REMOTE
    LOCAL=$(git rev-parse "refs/heads/$branch_name" 2>/dev/null || true)
    REMOTE=$(git rev-parse "refs/remotes/origin/$branch_name" 2>/dev/null || true)

    if [[ -z "$REMOTE" ]]; then
        log_error "Unable to resolve remote ref for $repo_path ($branch_name)"
        return
    fi

    if [[ -z "$LOCAL" ]]; then
        if git update-ref "refs/heads/$branch_name" "$REMOTE" 2>/dev/null; then
            log_info "Created local branch $branch_name for $repo_path"
        else
            log_error "Failed to create local branch $branch_name for $repo_path"
        fi
        return
    fi

    if [[ "$LOCAL" != "$REMOTE" ]]; then
        if git merge-base --is-ancestor "$LOCAL" "$REMOTE"; then
            local current_branch
            current_branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)
            if [[ "$current_branch" == "$branch_name" ]]; then
                local merge_output
                if merge_output=$(git merge --ff-only --quiet "origin/$branch_name" 2>&1); then
                    log_info "Updated $repo_path ($branch_name)"
                else
                    log_error "Fast-forward failed for $repo_path ($branch_name): $merge_output"
                fi
            elif git update-ref "refs/heads/$branch_name" "$REMOTE" "$LOCAL" 2>/dev/null; then
                log_info "Updated $repo_path ($branch_name)"
            else
                log_error "Failed to update branch ref for $repo_path ($branch_name)"
            fi
        else
            log_error "Skipped diverged branch for $repo_path ($branch_name)"
        fi
    fi
}

# Auto-discover repos in ~/Projects
for d in "$HOME/Projects"/*/; do
    [[ -d "${d}.git" ]] || continue
    repo="${d%/}"
    branch=$(git -C "$repo" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    [[ "$branch" == "HEAD" ]] && branch="main"
    process_repo "$repo" "$branch" &
done

# Include ~/dotfiles
if [[ -d "$HOME/dotfiles/.git" ]]; then
    branch=$(git -C "$HOME/dotfiles" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
    [[ "$branch" == "HEAD" ]] && branch="main"
    process_repo "$HOME/dotfiles" "$branch" &
fi

# repos.conf: additional repos outside ~/Projects and ~/dotfiles
if [[ -f "$CONFIG_FILE" ]]; then
    while IFS=':' read -r repo_path branch_name; do
        [[ -z "$repo_path" ]] && continue
        [[ "$repo_path" =~ ^[[:space:]]*# ]] && continue

        repo_path=$(echo "$repo_path" | xargs)
        repo_path="${repo_path/#\~/$HOME}"
        branch_name=$(echo "$branch_name" | xargs)
        [[ -z "$branch_name" ]] && branch_name="main"

        [[ ! -d "$repo_path/.git" ]] && continue

        process_repo "$repo_path" "$branch_name" &
    done < "$CONFIG_FILE"
fi

wait
