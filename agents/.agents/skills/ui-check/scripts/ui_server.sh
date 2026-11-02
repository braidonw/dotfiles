#!/usr/bin/env bash
set -euo pipefail

# Finds or starts the local app server a UI check browses.
# Usage: ui_server.sh <url>                       check the server only
#        ui_server.sh <url> -- <start command...>  start it when it is down
# Run from the directory the start command must run in. The command runs in a herdr or Rex split beside the
# caller labelled ui-server. A ui-server pane in the caller's tab whose command still runs is a server
# starting, so it is polled rather than split again. One whose command has exited is reported and closed.
# A URL answers when it returns any status below 500. Every check times out after 5s.
#
# Exit codes:
#   0  server up; last line is "UI_SERVER: <url>"
#   1  genuine failure
#   2  bad arguments
#   6  server down and not inside herdr or Rex; stderr carries "UI_OPEN_MANUALLY: cd <dir> && <command>"
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

terminal=$(cd "$(dirname "$0")/../../../bin" && pwd)/terminal.sh

report_exit_and_close() {
  "$terminal" pane-tail "$1" 40 >&2 || true
  "$terminal" close-pane "$1" || true
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

if [[ $("$terminal" backend) == none ]]; then
  echo "UI_OPEN_MANUALLY: cd $(printf %q "$PWD") && $command" >&2
  exit 6
fi

pane=
while read -r other; do
  [[ -n $other ]] || continue
  state=0
  "$terminal" pane-state "$other" || state=$?
  # Act only when inspection succeeds, never on a failed lookup
  case $state in
    0) pane=$other ;;
    1) report_exit_and_close "$other" ;;
  esac
done <<<"$("$terminal" labelled-panes ui-server)"

if [[ -z $pane ]]; then
  pane=$("$terminal" split-beside ui-server "$PWD" --keep-open -- bash -c "$command")
fi

deadline=$((SECONDS + wait_s))
while ((SECONDS < deadline)); do
  sleep "$poll_s"
  if up; then
    echo "UI_SERVER: $url"
    exit 0
  fi
  state=0
  "$terminal" pane-state "$pane" || state=$?
  if ((state == 1)); then
    report_exit_and_close "$pane"
  fi
done

echo "UI_SERVER_STARTING: $pane" >&2
exit 10
