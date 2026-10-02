#!/usr/bin/env bash
set -euo pipefail

# Points a Hunk session at the working tree diffed against its merge-base with a fixed point.
# Usage: hunk_session.sh <fixed-point>, run from inside the repo.
# Reloads the one session open on this repo, or opens one in a herdr split beside the caller.
#
# Exit codes:
#   0  session ready; last line is "HUNK_SESSION: <session-id>"
#   1  genuine failure
#   2  bad arguments
#   5  several sessions on this repo; stderr lists them
#   6  no session and not inside herdr; stderr carries "HUNK_OPEN_MANUALLY: <command>"

if [[ $# -ne 1 ]]; then
  echo "usage: hunk_session.sh <fixed-point>" >&2
  exit 2
fi

root=$(git rev-parse --show-toplevel)
base=$(git merge-base "$1" HEAD)

sessions_on_repo() {
  hunk session list --json | jq -r --arg root "$root" '(.sessions // [])[] | select(.repoRoot == $root) | "\(.sessionId)\t\(.title)"'
}

matches=$(sessions_on_repo)
count=$(grep -c . <<<"$matches" || true)

if [[ $count -gt 1 ]]; then
  echo "Several Hunk sessions are open on $root:" >&2
  echo "$matches" >&2
  exit 5
fi

if [[ $count -eq 1 ]]; then
  id=$(cut -f1 <<<"$matches")
  hunk session reload "$id" -- diff "$base" --watch >/dev/null
  echo "HUNK_SESSION: $id"
  exit 0
fi

command="hunk diff $base --watch"

if [[ ${HERDR_ENV:-} != 1 ]]; then
  echo "HUNK_OPEN_MANUALLY: cd $PWD && $command" >&2
  exit 6
fi

pane=$(herdr pane split --current --direction right --cwd "$PWD" --no-focus | jq -r '.result.pane.pane_id')
herdr pane run "$pane" "$command" >/dev/null

for _ in $(seq 1 30); do
  matches=$(sessions_on_repo)
  if [[ -n $matches ]]; then
    echo "HUNK_SESSION: $(head -1 <<<"$matches" | cut -f1)"
    exit 0
  fi
  sleep 0.5
done

echo "Started Hunk in herdr pane $pane, but no session registered within 15s" >&2
exit 1
