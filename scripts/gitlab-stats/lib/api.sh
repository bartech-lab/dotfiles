#!/usr/bin/env bash

build_query() {
  local project="$1" since="$2" until="$3" target_branch="$4"
  cat <<GRAPHQL
query {
  project(fullPath: "${project}") {
    mergeRequests(
      state: merged
      targetBranches: ["${target_branch}"]
      mergedAfter: "${since}T00:00:00Z"
      mergedBefore: "${until}T23:59:59Z"
      first: 100
      after: __CURSOR__
    ) {
      nodes {
        iid
        title
        webUrl
        mergedAt
        createdAt
        author { name username bot }
        mergeUser { name username bot }
        approvedBy(first: 50) { nodes { name username bot } }
        diffStatsSummary { additions deletions }
        discussions(first: 20) {
          nodes {
            notes(first: 1) { nodes { author { name username bot } system } }
          }
        }
      }
      pageInfo { hasNextPage endCursor }
    }
  }
}
GRAPHQL
}

detect_project() {
  # Try glab's built-in project detection first
  local result
  result=$(glab api projects/:id 2>/dev/null | jq -r '.path_with_namespace // empty')
  if [[ -n "$result" ]]; then
    echo "$result"
    return 0
  fi

  # Fallback: extract from git remote URL
  if has_command git; then
    local remote
    remote=$(git remote get-url origin 2>/dev/null) || remote=""
    # Handle git@gitlab.com:org/repo.git and https://gitlab.com/org/repo.git
    result=$(echo "$remote" | sed -E 's/\.git$//' | awk -F: '{print $NF}' | sed 's|^//[^/]*/||')
    if [[ -n "$result" ]]; then
      echo "$result"
      return 0
    fi
  fi

  echo "Error: Could not detect project. Run from a GitLab repo or use --project." >&2
  return 1
}

fetch_all_mrs() {
  local project="$1" since="$2" until="$3" target_branch="$4"

  local query
  query=$(build_query "$project" "$since" "$until" "$target_branch")

  local cursor="null"
  local has_next="true"
  local result="[]"
  local page=1

  while [[ "$has_next" == "true" ]]; do
    local current_query="${query/__CURSOR__/$cursor}"

    local response
    response=$(glab api graphql -f query="$current_query" 2>&1)
    local glab_exit=$?
    if [[ "$glab_exit" -ne 0 ]]; then
      echo "Error: glab API call failed (exit $glab_exit)" >&2
      echo "Query was: ${current_query:0:200}..." >&2
      echo "Response: ${response:0:200}" >&2
      return 1
    fi

    if echo "$response" | jq -e '.errors' &>/dev/null; then
      local err_msg
      err_msg=$(echo "$response" | jq -r '.errors[].message' | head -1)
      echo "GraphQL error: $err_msg" >&2
      return 1
    fi

    local data_valid
    data_valid=$(echo "$response" | jq -e '.data.project.mergeRequests' &>/dev/null && echo 1 || echo 0)
    if [[ "$data_valid" -eq 0 ]]; then
      echo "Error: mergeRequests not accessible. Check project permissions." >&2
      return 1
    fi

    local page_nodes
    page_nodes=$(echo "$response" | jq '.data.project.mergeRequests.nodes // []')
    local page_info
    page_info=$(echo "$response" | jq '.data.project.mergeRequests.pageInfo // {}')

    has_next=$(echo "$page_info" | jq -r '.hasNextPage // false')
    local end_cursor
    end_cursor=$(echo "$page_info" | jq -r '.endCursor // ""')

    result=$(printf '%s\n%s\n' "$result" "$page_nodes" | jq -s 'add')

    if [[ "$has_next" == "true" && -n "$end_cursor" ]]; then
      cursor="\"${end_cursor}\""
    fi

    page=$((page + 1))
  done

  echo "$result"
}
