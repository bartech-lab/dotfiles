#!/usr/bin/env bash

stat_throughput() {
  local exclude_bots_json
  [[ "${EXCLUDE_BOTS:-true}" == "true" ]] && exclude_bots_json="true" || exclude_bots_json="false"

  local months
  months=$(get_months_between "$SINCE" "$UNTIL")

  local months_json="["
  local first=true
  while IFS= read -r m; do
    [[ "$first" == true ]] && first=false || months_json+=", "
    months_json+="\"$m\""
  done <<< "$months"
  months_json+="]"

  if [[ "${BY_AUTHOR:-true}" == "true" ]]; then
    # Per-author throughput
    local result
    result=$(echo "$MR_DATA" | jq --argjson top "${TOP_N:-10}" --argjson months "$months_json" --argjson exclude_bots "$exclude_bots_json" '
      map(select(.mergedAt != null and .author != null)
        | select($exclude_bots == false or .author.bot == false)
        | {
          key: .author.username,
          name: .author.name,
          month: (.mergedAt | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y-%m"))
        })
      | group_by(.key)
      | map({
        username: .[0].key,
        name: .[0].name,
        months: group_by(.month) | map({month: .[0].month, count: length})
      })
      | map(
        (.months | map(.count) | add) as $total
        | {
          username,
          name,
          months: ([$months[] | {month: ., count: 0}] + .months
            | group_by(.month)
            | map({month: .[0].month, count: map(.count) | add})
            | sort_by(.month)),
          total: $total
        }
      )
      | sort_by(-.total) | if $top > 0 then .[:$top] else . end
    ') || true

    # Build dynamic table columns
    local header="Author"
    local jq_month_exprs=""
    while IFS= read -r m; do
      header+="|${m}"
    done <<< "$months"
    header+="|Total"

    format_throughput_table "$result" "$months_json" "$header"

  else
    # Overall throughput (no author breakdown)
    local result
    result=$(echo "$MR_DATA" | jq --argjson months "$months_json" --argjson exclude_bots "$exclude_bots_json" '
      map(select(.mergedAt != null)
        | select($exclude_bots == false or .author.bot == false)
        | {month: (.mergedAt | strptime("%Y-%m-%dT%H:%M:%SZ") | strftime("%Y-%m"))})
      | group_by(.month)
      | map({month: .[0].month, count: length})
      | ([$months[] | {month: ., count: 0}] + .)
      | group_by(.month)
      | map({month: .[0].month, count: map(.count) | add})
      | sort_by(.month)
    ') || true

    local header="Month|Count"

    case "${FORMAT:-table}" in
      json)
        print_heading "Throughput"
        echo "$result" | jq '.'
        ;;
      csv)
        print_heading "Throughput"
        echo "$result" | jq -r '["Month", "Count"], (.[] | [.month, (.count | tostring)]) | @csv'
        ;;
      table|*)
        print_heading "Throughput"
        {
          echo "Month"'	'"Count"
          echo "$result" | jq -r '.[] | [.month, (.count | tostring)] | @tsv'
        } | column -t -s $'\t'
        ;;
    esac
  fi
}

format_throughput_table() {
  local result="$1" months_json="$2" header="$3"

  case "${FORMAT:-table}" in
    json)
      print_heading "Throughput"
      echo "$result" | jq '.'
      ;;
    csv)
      print_heading "Throughput"
      # Build CSV header from months
      local csv_header
      csv_header=$(echo "$header" | tr '|' ',')
      echo "$csv_header"
      echo "$result" | jq -r --argjson m "$months_json" '
        .[] | . as $mr | [.name] + ($m | map(. as $mval | [first($mr.months[] | select(.month == $mval) | .count)] // [0] | .[0] | tostring)) + [.total | tostring] | @csv
      '
      ;;
    table|*)
      print_heading "Throughput"
      {
        echo "$header" | tr '|' '\t'
        echo "$result" | jq -r --argjson m "$months_json" '
          .[] | . as $mr | [.name] + ($m | map(. as $mval | [first($mr.months[] | select(.month == $mval) | .count)] // [0] | .[0] | tostring)) + [.total | tostring] | @tsv
        '
      } | column -t -s $'\t'
      ;;
  esac
}
