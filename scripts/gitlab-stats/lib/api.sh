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

    case "$remote" in
      git@gitlab.com:*|ssh://git@gitlab.com/*|https://gitlab.com/*|http://gitlab.com/*)
        ;;
      git@*:*|ssh://*|https://*|http://*)
        echo "Error: Current repository is not hosted on gitlab.com ('$remote'). Run from a GitLab checkout or pass --project PROJECT." >&2
        return 1
        ;;
    esac

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
    if ! response=$(glab api graphql -f query="$current_query" 2>&1); then
      echo "Error: GitLab GraphQL request failed for project '$project'." >&2
      echo "Query was: ${current_query:0:200}..." >&2
      echo "Response: ${response:0:200}" >&2
      return 1
    fi

    local graphql_errors
    graphql_errors=$(echo "$response" | jq -r '(.errors // [])[]?.message' 2>/dev/null || true)
    if [[ -n "$graphql_errors" ]]; then
      local err_msg
      err_msg=$(echo "$graphql_errors" | head -1)
      echo "GraphQL error for project '$project': $err_msg" >&2
      return 1
    fi

    local data_valid
    data_valid=$(echo "$response" | jq -e '.data.project.mergeRequests' &>/dev/null && echo 1 || echo 0)
    if [[ "$data_valid" -eq 0 ]]; then
      if echo "$response" | jq -e '.data.project == null' &>/dev/null; then
        echo "Error: GitLab project '$project' was not found or is not accessible. Run from its checkout or pass the full path with --project." >&2
      else
        echo "Error: GitLab merge requests are not accessible for project '$project'." >&2
      fi
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

urlencode_project() {
  local project="$1"
  printf '%s' "${project//\//%2F}"
}

api_get_with_retries() {
  local endpoint="$1" page="${2:-}"
  local attempt=1 max_attempts=4 response="" last_response=""
  local retry_delay="${GITLAB_STATS_RETRY_DELAY:-1}"

  while (( attempt <= max_attempts )); do
    if [[ -n "$page" ]]; then
      if response=$(glab api "$endpoint" --method GET -F "per_page=100" -F "page=$page" 2>&1); then
        printf '%s' "$response"
        return 0
      fi
    elif response=$(glab api "$endpoint" --method GET 2>&1); then
      printf '%s' "$response"
      return 0
    fi

    last_response="$response"
    if (( attempt < max_attempts && retry_delay > 0 )); then
      sleep "$((retry_delay * attempt))"
    fi
    attempt=$((attempt + 1))
  done

  printf '%s' "$last_response" >&2
  return 1
}

fetch_mr_discussions() {
  local project="$1" iid="$2" output_file="$3"
  local encoded_project endpoint page=1 response count discussions='[]'
  encoded_project=$(urlencode_project "$project")
  endpoint="projects/${encoded_project}/merge_requests/${iid}/discussions"

  while :; do
    if ! response=$(api_get_with_retries "$endpoint" "$page"); then
      echo "Error: discussion lookup failed for MR !${iid} at GET /${endpoint} (page ${page}) after 3 retries." >&2
      return 1
    fi
    if ! jq -e 'type == "array"' >/dev/null 2>&1 <<< "$response"; then
      echo "Error: invalid discussion response for MR !${iid} at GET /${endpoint} (page ${page})." >&2
      return 1
    fi

    discussions=$(jq -cn --argjson all "$discussions" --argjson page "$response" '$all + $page')
    count=$(jq 'length' <<< "$response")
    if (( count < 100 )); then
      break
    fi
    page=$((page + 1))
  done

  jq -cn --arg iid "$iid" --argjson discussions "$discussions" \
    '{iid: $iid, discussions: $discussions}' > "$output_file"
}

fetch_discussion_data() {
  local project="$1" mr_data="$2"
  local tmp_dir iid output_file failed=0
  local pids=() output_files=()

  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/gitlab-stats-discussions.XXXXXX") || {
    echo "Error: could not create a temporary directory for discussion data." >&2
    return 1
  }

  while IFS= read -r iid; do
    [[ -z "$iid" ]] && continue
    output_file="$tmp_dir/${#output_files[@]}.json"
    output_files+=("$output_file")
    (fetch_mr_discussions "$project" "$iid" "$output_file") &
    pids+=("$!")

    if (( ${#pids[@]} == 4 )); then
      for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
          failed=1
        fi
      done
      pids=()
    fi
  done < <(jq -r '.[].iid // empty' <<< "$mr_data")

  if (( ${#pids[@]} > 0 )); then
    for pid in "${pids[@]}"; do
      if ! wait "$pid"; then
        failed=1
      fi
    done
  fi

  if (( failed )); then
    rm -rf "$tmp_dir"
    return 1
  fi

  local raw_discussions
  raw_discussions=$(for output_file in "${output_files[@]}"; do cat "$output_file"; done | jq -s '.') || {
    echo "Error: could not combine REST discussion responses." >&2
    rm -rf "$tmp_dir"
    return 1
  }
  rm -rf "$tmp_dir"

  normalize_discussion_data "$raw_discussions"
}

normalize_discussion_data() {
  local raw_discussions="$1"
  local author_ids id user affected_mrs
  local tmp_dir raw_file author_records authors_file normalized

  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/gitlab-stats-normalize.XXXXXX") || {
    echo "Error: could not create a temporary directory for author data." >&2
    return 1
  }
  raw_file="$tmp_dir/discussions.json"
  author_records="$tmp_dir/authors.ndjson"
  authors_file="$tmp_dir/authors.json"
  printf '%s\n' "$raw_discussions" > "$raw_file"
  : > "$author_records"

  local missing_author_mrs
  if ! missing_author_mrs=$(jq -r '
    [.[] as $mr
     | $mr.discussions[]?
     | .notes[0]? as $note
     | select($note != null and ($note.system // false) != true and $note.author.id? == null)
     | $mr.iid] | unique | join(", ")
  ' <<< "$raw_discussions"); then
    echo "Error: invalid REST discussion data; refusing partial statistics." >&2
    rm -rf "$tmp_dir"
    return 1
  fi
  if [[ -n "$missing_author_mrs" ]]; then
    echo "Error: missing note author for MR IIDs ${missing_author_mrs} at GET /users/:id; refusing partial statistics." >&2
    rm -rf "$tmp_dir"
    return 1
  fi

  author_ids=$(jq -r '
    .[] as $mr
    | $mr.discussions[]?
    | .notes[0]?
    | select((.system // false) != true)
    | .author.id? // empty
    | tostring
  ' <<< "$raw_discussions" | sort -u)

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! user=$(api_get_with_retries "/users/${id}"); then
      affected_mrs=$(jq -r --arg id "$id" '
        [.[]
         | select(any(.discussions[]?;
             (.notes[0]? | select((.system // false) != true and .author.id? != null)
             | (.author.id | tostring) == $id)))
         | .iid] | join(", ")
      ' <<< "$raw_discussions")
      echo "Error: author lookup failed for MR IIDs ${affected_mrs:-unknown} at GET /users/${id} after 3 retries." >&2
      rm -rf "$tmp_dir"
      return 1
    fi
    if ! jq -e 'type == "object" and .id != null and .username != null and .name != null and .bot != null' >/dev/null 2>&1 <<< "$user"; then
      affected_mrs=$(jq -r --arg id "$id" '
        [.[]
         | select(any(.discussions[]?;
             (.notes[0]? | select((.system // false) != true and .author.id? != null)
             | (.author.id | tostring) == $id)))
         | .iid] | join(", ")
      ' <<< "$raw_discussions")
      echo "Error: invalid author response for MR IIDs ${affected_mrs:-unknown} at GET /users/${id}." >&2
      rm -rf "$tmp_dir"
      return 1
    fi
    jq -c '{id: (.id | tostring), user: {name, username, bot}}' <<< "$user" >> "$author_records"
  done <<< "$author_ids"

  if ! jq -s '.' "$author_records" > "$authors_file"; then
    echo "Error: could not prepare REST author data." >&2
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! normalized=$(jq -n --slurpfile discussions "$raw_file" --slurpfile authors "$authors_file" '
    (reduce $authors[0][] as $author ({}; .[$author.id] = $author.user)) as $author_by_id
    | $discussions[0] | map(
        . as $mr
        | {
            iid: $mr.iid,
            discussions: [
              $mr.discussions[]?
              | .notes[0]? as $note
              | select($note != null)
              | select(($note.system // false) != true)
              | ($author_by_id[($note.author.id | tostring)]) as $user
              | {
                  notes: {nodes: [{
                    author: {
                      name: ($user.name // $note.author.name),
                      username: ($user.username // $note.author.username),
                      bot: $user.bot
                    },
                    system: false,
                    resolved: ($note.resolved // false)
                  }]}
                }
            ]
          }
      )
  '); then
    echo "Error: could not normalize REST discussion data." >&2
    rm -rf "$tmp_dir"
    return 1
  fi
  rm -rf "$tmp_dir"
  printf '%s\n' "$normalized"
}

merge_discussion_data() {
  local mr_data="$1" discussion_data="$2"
  local tmp_dir mrs_file discussions_file merged

  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/gitlab-stats-merge.XXXXXX") || {
    echo "Error: could not create a temporary directory for discussion merge." >&2
    return 1
  }
  mrs_file="$tmp_dir/mrs.json"
  discussions_file="$tmp_dir/discussions.json"
  printf '%s\n' "$mr_data" > "$mrs_file"
  printf '%s\n' "$discussion_data" > "$discussions_file"

  if ! jq -e --slurpfile mrs "$mrs_file" --slurpfile discussions "$discussions_file" -n '
    ($mrs[0] | map(.iid | tostring) | unique) as $mr_iids
    | ([$discussions[0][].iid | tostring] | unique) as $discussion_iids
    | (($mr_iids - $discussion_iids) | length == 0)
  ' >/dev/null 2>&1; then
    echo "Error: REST discussion data does not cover every fetched merge request; refusing partial statistics." >&2
    rm -rf "$tmp_dir"
    return 1
  fi

  if ! merged=$(jq -n --slurpfile mrs "$mrs_file" --slurpfile discussions "$discussions_file" '
    ($discussions[0] | reduce .[] as $discussion ({}; .[$discussion.iid | tostring] = $discussion.discussions)) as $by_iid
    | $mrs[0] | map(. + {discussions: {nodes: ($by_iid[.iid | tostring] // [])}})
  '); then
    echo "Error: could not merge REST discussion data." >&2
    rm -rf "$tmp_dir"
    return 1
  fi
  rm -rf "$tmp_dir"
  printf '%s\n' "$merged"
}
