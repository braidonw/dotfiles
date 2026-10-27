#!/usr/bin/env bash
# Waits for the review agent in <pane-id> to exit or its pane to close, then removes the review worktree and closes its workspace.
# Usage: watch_review_worktree.sh <pane-id> <workspace-id> <worktree-path> <main-checkout> <head-sha>
set -uo pipefail

pane=$1 workspace=$2 worktree=$3 main=$4 head_sha=$5
poll_s=5
misses=0

notify() {
  herdr notification show "$1" --body "$2" >/dev/null 2>&1
}

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

cd "$main" || exit 1
label=$(basename "$worktree")

if [ ! -d "$worktree" ]; then
  herdr workspace close "$workspace" >/dev/null 2>&1
  exit 0
fi

if [ -n "$(git -C "$worktree" status --porcelain)" ]; then
  notify "Kept $label" "Uncommitted changes in $worktree"
  exit 0
fi

if [ "$(git -C "$worktree" rev-parse HEAD)" != "$head_sha" ]; then
  notify "Kept $label" "HEAD moved off the PR head in $worktree"
  exit 0
fi

if ! git worktree remove "$worktree"; then
  notify "Kept $label" "git worktree remove failed for $worktree"
  exit 1
fi

herdr workspace close "$workspace" >/dev/null 2>&1
exit 0
