#!/usr/bin/env bash
set -euo pipefail

# Finds or starts the local app server a UI check browses.
# Usage: ui_server.sh <url>                       check the server only
#        ui_server.sh <url> -- <start command...>  start it when it is down
# Run from the directory the start command must run in. The command runs in a herdr split beside the
# caller labelled ui-server. A ui-server pane in the caller's tab whose command still runs is a server
# starting, so it is polled rather than split again. One whose command has exited is reported and closed.
# A URL answers when it returns any status below 500. Every check times out after 5s.
#
# Exit codes:
#   0  server up; last line is "UI_SERVER: <url>"
#   1  genuine failure
#   2  bad arguments
#   6  server down and not inside herdr; stderr carries "UI_OPEN_MANUALLY: cd <dir> && <command>"
#   8  server down and no start command; stderr carries "UI_SERVER_DOWN: <url>"
#   9  the start command exited; stderr carries its last 40 lines, then "UI_SERVER_FAILED: <url>"
#  10  still starting after 8 minutes; stderr carries "UI_SERVER_STARTING: <pane-id>". Call again to keep waiting.

usage() {
  echo "usage: ui_server.sh <url> [-- <start command...>]" >&2
  exit 2
}

[[ $# -ge 1 && $1 != -* ]] || usage
url=$1
shift
command=
if [[ $# -gt 0 ]]; then
  [[ $1 == -- && $# -ge 2 ]] || usage
  shift
  command=$*
fi

wait_s=480
poll_s=3

up() {
  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$url" || true)
  [[ $code != 000 && $code -lt 500 ]]
}

# 0 a command holds the foreground, 1 only the shell's own group (prompt hooks included), else a failed lookup
pane_state() {
  local info state
  info=$(herdr pane process-info --pane "$1") || return 2
  state=$(jq -r '.result.process_info | if .foreground_process_group_id == null or .shell_pid == null then "unknown"
    elif .foreground_process_group_id != .shell_pid then "running" else "exited" end' <<<"$info") || return 2
  case $state in
    running) return 0 ;;
    exited) return 1 ;;
    *) return 2 ;;
  esac
}

report_exit_and_close() {
  herdr pane read "$1" --lines 40 >&2
  herdr pane close "$1" >/dev/null
  echo "UI_SERVER_FAILED: $url" >&2
  exit 9
}

if up; then
  echo "UI_SERVER: $url"
  exit 0
fi

if [[ -z $command ]]; then
  echo "UI_SERVER_DOWN: $url" >&2
  exit 8
fi

if [[ ${HERDR_ENV:-} != 1 ]]; then
  echo "UI_OPEN_MANUALLY: cd $(printf %q "$PWD") && $command" >&2
  exit 6
fi

read -r self tab < <(herdr pane current | jq -r '.result.pane | "\(.pane_id) \(.tab_id)"')

pane=
while read -r other; do
  [[ -n $other ]] || continue
  state=0
  pane_state "$other" || state=$?
  # Act only when inspection succeeds, never on a failed lookup
  case $state in
    0) pane=$other ;;
    1) report_exit_and_close "$other" ;;
  esac
done <<<"$(herdr pane list | jq -r --arg tab "$tab" --arg self "$self" \
  '.result.panes[] | select(.tab_id == $tab and .pane_id != $self and .label == "ui-server") | .pane_id')"

if [[ -z $pane ]]; then
  pane=$(herdr pane split --current --direction right --cwd "$PWD" --no-focus | jq -r '.result.pane.pane_id')
  herdr pane rename "$pane" ui-server >/dev/null
  herdr pane run "$pane" "bash -c $(printf %q "$command")" >/dev/null
fi

deadline=$((SECONDS + wait_s))
while ((SECONDS < deadline)); do
  sleep "$poll_s"
  if up; then
    echo "UI_SERVER: $url"
    exit 0
  fi
  state=0
  pane_state "$pane" || state=$?
  if ((state == 1)); then
    report_exit_and_close "$pane"
  fi
done

echo "UI_SERVER_STARTING: $pane" >&2
exit 10
