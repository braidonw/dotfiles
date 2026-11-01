#!/bin/bash
input=$(cat)

limit() {
  local label=$1 key=$2 fmt=$3
  local pct reset
  pct=$(jq -r ".rate_limits.$key.used_percentage // empty" <<<"$input")
  [ -z "$pct" ] && return
  reset=$(jq -r ".rate_limits.$key.resets_at" <<<"$input")
  printf ' · %s %s%% (%s)' "$label" "$pct" "$(date -r "$reset" +"$fmt")"
}

model=$(jq -r '.model.display_name' <<<"$input")
ctx=$(jq -r '.context_window.used_percentage // 0' <<<"$input")

printf '%s · ctx %s%%' "$model" "$ctx"
limit 5h five_hour '%H:%M'
limit 7d seven_day '%a %H:%M'
