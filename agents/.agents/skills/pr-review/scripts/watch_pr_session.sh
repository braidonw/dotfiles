#!/usr/bin/env bash
# Waits for the agent in a herdr pane to exit or its pane to close, then cleans up what the PR session opened.
# Usage:
#   watch_pr_session.sh review <pane-id> <workspace-id> <worktree> <main-checkout> <head-sha>
#   watch_pr_session.sh branch <pane-id> <workspace-id> <worktree> <main-checkout>
#   watch_pr_session.sh tab <pane-id> <tab-id>
set -uo pipefail

mode=$1 pane=$2
poll_s=5

notify() {
  herdr notification show "$1" --body "$2" >/dev/null 2>&1
}

wait_for_agent_exit() {
  local misses=0 pane_json agent
  while [ "$misses" -lt 2 ]; do
    sleep "$poll_s"
    if pane_json=$(herdr pane get "$pane" 2>&1); then
      agent=$(jq -r '.result.pane.agent // empty' <<<"$pane_json")
    elif [ "$(jq -r '.error.code // empty' <<<"$pane_json" 2>/dev/null)" = pane_not_found ]; then
      agent=
    else
      misses=0
      continue
    fi

    if [ -z "$agent" ]; then
      misses=$((misses + 1))
    else
      misses=0
    fi
  done
}

# Volume names mirror preview.sh, which keeps them on stop.
stop_preview() {
  local preview=$main/scripts/preview.sh name
  [ -x "$preview" ] || return 0
  "$preview" stop "$worktree" >/dev/null 2>&1
  name=$(basename "$worktree" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')
  docker volume rm "$name-preview-pgdata" "$name-preview-deps" "$name-preview-build" >/dev/null 2>&1
  return 0
}

remove_worktree() {
  local label
  label=$(basename "$worktree")
  cd "$main" || exit 1

  if [ ! -d "$worktree" ]; then
    herdr workspace close "$workspace" >/dev/null 2>&1
    exit 0
  fi

  if [ -n "$(git -C "$worktree" status --porcelain)" ]; then
    notify "Kept $label" "Uncommitted changes in $worktree"
    exit 0
  fi

  case "$mode" in
    review)
      if [ "$(git -C "$worktree" rev-parse HEAD)" != "$head_sha" ]; then
        notify "Kept $label" "HEAD moved off the PR head in $worktree"
        exit 0
      fi
      ;;
    branch)
      if ! unpushed=$(git -C "$worktree" rev-list --count '@{u}..HEAD' 2>/dev/null) || [ "$unpushed" != 0 ]; then
        notify "Kept $label" "Unpushed commits in $worktree"
        exit 0
      fi
      ;;
  esac

  stop_preview

  if ! git worktree remove "$worktree"; then
    notify "Kept $label" "git worktree remove failed for $worktree"
    exit 1
  fi

  herdr workspace close "$workspace" >/dev/null 2>&1
  exit 0
}

case "$mode" in
  review)
    workspace=$3 worktree=$4 main=$5 head_sha=$6
    wait_for_agent_exit
    remove_worktree
    ;;
  branch)
    workspace=$3 worktree=$4 main=$5
    wait_for_agent_exit
    remove_worktree
    ;;
  tab)
    tab=$3
    wait_for_agent_exit
    herdr tab close "$tab" >/dev/null 2>&1
    ;;
  *)
    echo "unknown mode: $mode" >&2
    exit 2
    ;;
esac
