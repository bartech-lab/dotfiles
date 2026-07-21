#!/bin/bash

# Git Auto-Pull Script
# Auto-discovers git repos in ~/Projects and ~/dotfiles
# Optional repos.conf for explicit branch overrides and additional repositories

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

resolve_default_branch() {
    local repo_path="$1"
    local remote
    local head_output
    local branch_name

    remote=$(git -C "$repo_path" remote get-url origin 2>/dev/null || true)
    [[ -z "$remote" ]] && return 1

    if ! head_output=$(git -C "$repo_path" ls-remote --symref origin HEAD 2>&1); then
        log_error "Default branch lookup failed for $repo_path: $head_output"
        return 1
    fi

    branch_name=$(printf '%s\n' "$head_output" | sed -n 's/^ref: refs\/heads\/\([^[:space:]]*\)[[:space:]]HEAD$/\1/p' | head -n 1)
    if [[ -z "$branch_name" ]]; then
        log_error "Remote did not advertise a default branch for $repo_path"
        return 1
    fi

    printf '%s\n' "$branch_name"
}

repo_is_scheduled() {
    local repo_path="$1"
    local scheduled_path

    for scheduled_path in "${REPO_PATHS[@]}"; do
        [[ "$scheduled_path" == "$repo_path" ]] && return 0
    done

    return 1
}

schedule_repo() {
    local repo_path="$1" branch_name="$2"

    REPO_PATHS[${#REPO_PATHS[@]}]="$repo_path"
    REPO_BRANCHES[${#REPO_BRANCHES[@]}]="$branch_name"
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
    LOCAL=$(git rev-parse --verify --quiet "refs/heads/$branch_name" 2>/dev/null || true)
    REMOTE=$(git rev-parse --verify --quiet "refs/remotes/origin/$branch_name" 2>/dev/null || true)

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

# Load explicit configuration first so it overrides auto-discovery and prevents
# the same repository from being processed twice.
REPO_PATHS=()
REPO_BRANCHES=()

if [[ -f "$CONFIG_FILE" ]]; then
    while IFS=':' read -r repo_path branch_name; do
        [[ -z "$repo_path" ]] && continue
        [[ "$repo_path" =~ ^[[:space:]]*# ]] && continue

        repo_path=$(echo "$repo_path" | xargs)
        repo_path="${repo_path/#\~/$HOME}"
        repo_path="${repo_path%/}"
        branch_name=$(echo "$branch_name" | xargs)
        [[ -z "$branch_name" ]] && {
            log_error "Missing configured branch for $repo_path"
            continue
        }

        [[ ! -d "$repo_path/.git" ]] && continue

        if repo_is_scheduled "$repo_path"; then
            log_error "Duplicate repository configuration ignored for $repo_path"
            continue
        fi

        schedule_repo "$repo_path" "$branch_name"
    done < "$CONFIG_FILE"
fi

# Auto-discover repos in ~/Projects and ~/dotfiles. Auto-discovered repositories
# follow the remote's advertised default branch, never the checked-out branch.
for d in "$HOME/Projects"/*/; do
    [[ -d "${d}.git" ]] || continue
    repo="${d%/}"
    repo_is_scheduled "$repo" && continue

    if branch=$(resolve_default_branch "$repo"); then
        schedule_repo "$repo" "$branch"
    fi
done

if [[ -d "$HOME/dotfiles/.git" ]]; then
    repo="$HOME/dotfiles"
    if ! repo_is_scheduled "$repo"; then
        if branch=$(resolve_default_branch "$repo"); then
            schedule_repo "$repo" "$branch"
        fi
    fi
fi

for i in "${!REPO_PATHS[@]}"; do
    process_repo "${REPO_PATHS[$i]}" "${REPO_BRANCHES[$i]}" &
done

wait
