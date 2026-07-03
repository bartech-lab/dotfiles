#!/usr/bin/env bash

stat_approvals() {
  local exclude_bots_json
  [[ "${EXCLUDE_BOTS:-true}" == "true" ]] && exclude_bots_json="true" || exclude_bots_json="false"

  local result
  result=$(echo "$MR_DATA" | jq --argjson top "${TOP_N:-10}" --argjson exclude_bots "$exclude_bots_json" '
    map(.approvedBy.nodes // [] | .[]
      | select(. != null)
      | select($exclude_bots == false or .bot == false)
      | {key: .username, name: .name})
    | group_by(.key) | map({
      username: .[0].key,
      name: .[0].name,
      count: length
    }) | sort_by(-.count) | if $top > 0 then .[:$top] else . end
  ') || true

  print_heading "Approvals"
  format_results "$result" "[.name, (.count | tostring)]" "Name|Count"
}
