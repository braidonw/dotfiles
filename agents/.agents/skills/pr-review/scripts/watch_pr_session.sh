#!/usr/bin/env bash
# Waits for the agent in a herdr or Rex pane to exit or its pane to close, then cleans up what the PR session opened.
# Usage:
#   watch_pr_session.sh review <pane-id> <workspace-id> <worktree> <main-checkout> <head-sha>
#   watch_pr_session.sh branch <pane-id> <workspace-id> <worktree> <main-checkout>
#   watch_pr_session.sh tab <pane-id> <tab-id>
set -uo pipefail

mode=$1 pane=$2

terminal=$(cd "$(dirname "$0")/../../../bin" && pwd)/terminal.sh

notify() {
  "$terminal" notify "$1" "$2"
}

wait_for_agent_exit() {
  "$terminal" wait-agent-exit "$pane"
}

# Names mirror preview.sh. Torn down here because the main checkout's branch may not carry preview.sh.
stop_preview() {
  local network container
  network=$(basename "$worktree" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9_-]/-/g')-preview
  for container in $(docker ps -aq --filter "name=^$network-"); do
    docker rm -fv "$container" >/dev/null 2>&1
  done
  for container in $(docker network inspect "$network" --format '{{range .Containers}}{{.Name}} {{end}}' 2>/dev/null); do
    docker network disconnect "$network" "$container" >/dev/null 2>&1
  done
  docker network rm "$network" >/dev/null 2>&1
  docker volume rm "$network-pgdata" "$network-deps" "$network-build" >/dev/null 2>&1
  return 0
}

remove_worktree() {
  local label
  label=$(basename "$worktree")
  cd "$main" || exit 1

  if [ ! -d "$worktree" ]; then
    "$terminal" close-workspace "$workspace"
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

  "$terminal" close-workspace "$workspace"
  exit 0
}

case "$mode" in
  review)
    workspace=$3 worktree=$4 main=$5 head_sha=$6
    wait_for_agent_exit || exit 1
    remove_worktree
    ;;
  branch)
    workspace=$3 worktree=$4 main=$5
    wait_for_agent_exit || exit 1
    remove_worktree
    ;;
  tab)
    tab=$3
    wait_for_agent_exit || exit 1
    "$terminal" close-tab "$tab"
    ;;
  *)
    echo "unknown mode: $mode" >&2
    exit 2
    ;;
esac
