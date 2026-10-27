#!/usr/bin/env bash
set -euo pipefail

# Finds or opens the tuicr session that review comments go into.
# Usage: tuicr_session.sh <fixed-point>  the working tree diffed against its merge-base with a fixed point
#        tuicr_session.sh --pr <number>  the PR session for that pull request
# Run from inside the repo. Reuses the matching active session, or opens tuicr in a herdr split
# beside the caller, first closing any pane in the caller's tab labelled tuicr whose tuicr has exited.
#
# Exit codes:
#   0  session ready; last line is "TUICR_SESSION: <slug>"
#   1  genuine failure
#   2  bad arguments
#   5  several local sessions active on this repo; stderr lists them
#   6  no session and not inside herdr; stderr carries "TUICR_OPEN_MANUALLY: <command>"
#   7  the active local session shows a different diff; stderr carries "TUICR_MISMATCH: <slug>"

usage() {
  echo "usage: tuicr_session.sh <fixed-point> | --pr <number>" >&2
  exit 2
}

pr=
if [[ $# -eq 2 && $1 == --pr && $2 =~ ^[0-9]+$ ]]; then
  pr=$2
elif [[ $# -ne 1 || $1 == -* ]]; then
  usage
fi

root=$(git rev-parse --show-toplevel)
head=$(git rev-parse HEAD)

commit_of() {
  git rev-parse --verify --quiet "$1^{commit}" || true
}

if [[ -n $pr ]]; then
  repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
  slug="gh:$repo/pr/$pr"
  command="tuicr pr $pr"
  poll_s=60

  find_session() {
    tuicr review list --repo "$repo" | jq -r --arg slug "$slug" 'map(select(.slug == $slug and .active))[0].slug // empty'
  }
else
  base=$(git merge-base "$1" HEAD)
  first=
  command="tuicr -w"
  if [[ $base != "$head" ]]; then
    first=$(git rev-list --topo-order "$base..HEAD" | tail -1)
    command="tuicr -w -r $base..HEAD"
  fi
  poll_s=15

  active_local() {
    tuicr review list --repo "$root" | jq -r '.[] | select(.kind == "local" and .active) | .slug'
  }

  # Slugs end in <kind>/<head> for -w alone and staged-and-unstaged-and-commits/<head>..<first> for a range
  shows_expected_diff() {
    local kind=${1%/*} range=${1##*/} a b
    kind=${kind##*/}
    if [[ -z $first ]]; then
      [[ ($kind == worktree || $kind == staged-and-unstaged) && $(commit_of "$range") == "$head" ]]
      return
    fi
    [[ $kind == staged-and-unstaged-and-commits && $range == *..* ]] || return 1
    a=$(commit_of "${range%%..*}")
    b=$(commit_of "${range#*..}")
    [[ $a == "$head" && $b == "$first" ]]
  }

  find_session() {
    local slug
    while read -r slug; do
      if [[ -n $slug ]] && shows_expected_diff "$slug"; then
        echo "$slug"
        return
      fi
    done <<<"$(active_local)"
  }

  active=$(active_local)
  count=$(grep -c . <<<"$active" || true)

  if [[ $count -gt 1 ]]; then
    echo "Several tuicr sessions are active on $root:" >&2
    echo "$active" >&2
    exit 5
  fi

  if [[ $count -eq 1 ]] && ! shows_expected_diff "$active"; then
    echo "TUICR_MISMATCH: $active" >&2
    exit 7
  fi
fi

found=$(find_session)
if [[ -n $found ]]; then
  echo "TUICR_SESSION: $found"
  exit 0
fi

if [[ ${HERDR_ENV:-} != 1 ]]; then
  echo "TUICR_OPEN_MANUALLY: cd $root && $command" >&2
  exit 6
fi

read -r self tab < <(herdr pane current | jq -r '.result.pane | "\(.pane_id) \(.tab_id)"')

# A pane labelled tuicr falls back to a shell once tuicr exits
herdr pane list | jq -r --arg tab "$tab" --arg self "$self" \
  '.result.panes[] | select(.tab_id == $tab and .pane_id != $self and .label == "tuicr") | .pane_id' |
  while read -r other; do
    # Close only when inspection succeeds and finds no tuicr, never on a failed lookup
    info=$(herdr pane process-info --pane "$other") || continue
    if jq -e 'any(.result.process_info.foreground_processes[]; .name == "tuicr") | not' >/dev/null <<<"$info"; then
      herdr pane close "$other" >/dev/null
    fi
  done

pane=$(herdr pane split --current --direction right --cwd "$root" --no-focus | jq -r '.result.pane.pane_id')
herdr pane rename "$pane" tuicr >/dev/null
herdr pane run "$pane" "bash -c '$command'" >/dev/null

for _ in $(seq 1 $((poll_s * 2))); do
  found=$(find_session)
  if [[ -n $found ]]; then
    echo "TUICR_SESSION: $found"
    exit 0
  fi
  sleep 0.5
done

echo "Started tuicr in herdr pane $pane, but no session registered within ${poll_s}s" >&2
exit 1
