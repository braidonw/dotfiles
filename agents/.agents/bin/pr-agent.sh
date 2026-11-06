#!/usr/bin/env bash
# Hands a GitHub PR to a fresh review or feedback agent in its own herdr or Rex workspace or tab.
# Usage: pr-agent.sh review|feedback <repo-dir> <pr-number> [--kind claude|codex|pi] [--note <text>]
#   review    fetches the PR head into a detached throwaway worktree and hands it to /pr-review
#   feedback  hands the PR branch's existing worktree, or a throwaway one on the branch, to /pr-feedback
# Prints "<workspace-or-tab>\t<agent-pane>", as terminal.sh hand-off does. Run outside the sandbox.
#
# Exit codes:
#   0  handed off
#   1  genuine failure
#   2  bad arguments
#   6  neither herdr nor Rex

set -uo pipefail

terminal=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/terminal.sh

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

die() {
  echo "pr-agent.sh: $*" >&2
  exit 1
}

[[ $# -ge 3 ]] || usage
mode=$1 repo=$2 number=$3
shift 3
[[ $mode == review || $mode == feedback ]] || usage
[[ $number =~ ^[0-9]+$ ]] || usage
kind=claude note=
while [[ $# -gt 0 ]]; do
  case $1 in
    --kind)
      [[ $# -ge 2 && $2 =~ ^(claude|codex|pi)$ ]] || usage
      kind=$2
      shift 2
      ;;
    --note)
      [[ $# -ge 2 ]] || usage
      note=$2
      shift 2
      ;;
    *) usage ;;
  esac
done

# gh-dash passes repoPaths values as written
repo=${repo/#\~/$HOME}

[[ $("$terminal" backend) != none ]] || {
  echo "pr-agent.sh: must run inside herdr or Rex" >&2
  exit 6
}

common=$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir) || die "$repo is not a git repository"
main=$(dirname "$common")
pr=$(cd "$repo" && gh pr view "$number" --json url,headRefName,headRefOid) || die "gh pr view $number failed"
url=$(jq -r .url <<<"$pr")
branch=$(jq -r .headRefName <<<"$pr")
head_sha=$(jq -r .headRefOid <<<"$pr")

prompt="/pr-$mode $url${note:+ $note}"
name=$mode-pr-$number
worktree=$(dirname "$main")/$(basename "$main")-$name

created=0 new_branch=
cleanup_created() {
  ((created)) || return 0
  git -C "$main" worktree remove --force "$worktree" >/dev/null 2>&1
  [[ -z $new_branch ]] || git -C "$main" branch -D "$new_branch" >/dev/null 2>&1
}

if [[ $mode == review ]]; then
  # An existing path may hold kept edits or a live review, so it is never reused
  [[ ! -e $worktree ]] || die "$worktree already exists. Finish or remove that review first"
  git -C "$repo" fetch --quiet origin "pull/$number/head" || die "fetch of pull/$number/head failed"
  created=1
  git -C "$repo" worktree add --quiet --detach "$worktree" "$head_sha" || {
    cleanup_created
    die "git worktree add failed"
  }
  "$terminal" hand-off review "$worktree" "$name" "$kind" "$prompt" "$head_sha" || {
    cleanup_created
    exit 1
  }
  exit 0
fi

checked_out=$(git -C "$repo" worktree list --porcelain |
  awk -v ref="branch refs/heads/$branch" '/^worktree /{p=substr($0,10)} $0==ref{print p; exit}')
[[ -z $checked_out ]] || exec "$terminal" hand-off tab "$checked_out" "$name" "$kind" "$prompt"

[[ ! -e $worktree ]] || die "$worktree already exists. Finish or remove that feedback session first"
git -C "$repo" fetch --quiet origin "$branch" || die "fetch of $branch failed"
created=1
if git -C "$repo" show-ref --verify --quiet "refs/heads/$branch"; then
  git -C "$repo" worktree add --quiet "$worktree" "$branch"
else
  new_branch=$branch
  git -C "$repo" worktree add --quiet --track -b "$branch" "$worktree" "origin/$branch"
fi || {
  cleanup_created
  die "git worktree add failed"
}
"$terminal" hand-off branch "$worktree" "$name" "$kind" "$prompt" || {
  cleanup_created
  exit 1
}
