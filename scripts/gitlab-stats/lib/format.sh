#!/usr/bin/env bash

print_heading() {
  local title="$1"
  echo ""
  echo "=== ${title} ==="
}

format_results() {
  local json="$1" jq_fields="$2" headers="$3"

  local count
  count=$(echo "$json" | jq 'length // 0')
  [[ "$count" -eq 0 ]] && return

  case "${FORMAT:-table}" in
    json)
      echo "$json" | jq '.'
      ;;
    csv)
      echo "$headers" | tr '|' ','
      echo "$json" | jq -r ".[] | $jq_fields | @csv"
      ;;
    table|*)
      {
        echo "$headers" | tr '|' '\t'
        echo "$json" | jq -r ".[] | $jq_fields | @tsv"
      } | column -t -s $'\t'
      ;;
  esac
}
