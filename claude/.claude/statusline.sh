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

dir=$(jq -r '.workspace.current_dir // .cwd // empty' <<<"$input")
[ -z "$dir" ] && exit 0
printf '\n\033[2m%s\033[0m' "${dir/#$HOME/\~}"

git=(git -C "$dir" --no-optional-locks)
branch=$("${git[@]}" branch --show-current 2>/dev/null) || exit 0
[ -z "$branch" ] && branch="detached $("${git[@]}" rev-parse --short HEAD 2>/dev/null)"
# A linked worktree's git dir sits under the main checkout's .git/worktrees
if [ "$("${git[@]}" rev-parse --path-format=absolute --git-dir)" != "$("${git[@]}" rev-parse --path-format=absolute --git-common-dir)" ]; then
  printf ' · \033[33mworktree %s\033[0m' "$(basename "$("${git[@]}" rev-parse --show-toplevel)")"
fi
printf ' · \033[36m%s\033[0m' "$branch"
