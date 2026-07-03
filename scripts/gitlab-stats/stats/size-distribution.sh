#!/usr/bin/env bash

stat_size_distribution() {
  local thresholds_csv="${BUCKETS:-0,50,200,500,999999}"
  local labels=("S" "M" "L" "XL")

  local jq_buckets=""
  local header_buckets="Name|Total"
  IFS=',' read -ra THRE <<< "$thresholds_csv"
  for ((i=0; i<${#THRE[@]}-1; i++)); do
    local lo="${THRE[$i]}"
    local hi="${THRE[$((i+1))]}"
    local label="${labels[$i]:-B$i}"
    lo="${lo// /}"
    hi="${hi// /}"
    if [[ "$i" -gt 0 ]]; then
      jq_buckets+=", "
    fi
    if [[ "$lo" == "0" ]]; then
      jq_buckets+="\"${label}\": map(select(.total_changes < ${hi})) | length"
      header_buckets+="|${label} (<${hi})"
    elif [[ "${hi}" -ge 999999 ]]; then
      jq_buckets+="\"${label}\": map(select(.total_changes >= ${lo})) | length"
      header_buckets+="|${label} (${lo}+)"
    else
      jq_buckets+="\"${label}\": map(select(.total_changes >= ${lo} and .total_changes < ${hi})) | length"
      header_buckets+="|${label} (${lo}-${hi})"
    fi
  done

  local exclude_bots_json
  [[ "${EXCLUDE_BOTS:-true}" == "true" ]] && exclude_bots_json="true" || exclude_bots_json="false"

  local result
  result=$(echo "$MR_DATA" | jq --argjson top "${TOP_N:-10}" --argjson exclude_bots "$exclude_bots_json" "
    map(select(.diffStatsSummary != null and .author != null)
      | select(\$exclude_bots == false or .author.bot == false)
      | {
        key: .author.username,
        name: .author.name,
        total_changes: ((.diffStatsSummary.additions // 0) + (.diffStatsSummary.deletions // 0))
      })
    | group_by(.key)
    | map({
      username: .[0].key,
      name: .[0].name,
      total: length,
      ${jq_buckets}
    }) | sort_by(-.total) | if \$top > 0 then .[:\$top] else . end
  ") || true

  # Build jq fields and format headers dynamically
  local jq_fields="[.name, (.total | tostring)"
  local field_labels="Name|Total"
  for ((i=0; i<${#THRE[@]}-1; i++)); do
    local label="${labels[$i]:-B$i}"
    jq_fields+=", (.${label} | tostring)"
    field_labels+="|${label}"
  done
  jq_fields+="]"

  print_heading "MR Size Distribution"
  format_results "$result" "$jq_fields" "$field_labels"
}
