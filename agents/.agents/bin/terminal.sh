#!/usr/bin/env bash
# One front for the terminal multiplexer the agent skills run in, herdr or Rex.
# Usage: terminal.sh <subcommand> [args...]
#   backend                                            prints herdr, rex or none
#   hand-off review|branch|tab <dir> <name> <kind> <prompt> [watcher args...]
#                                                      starts an agent in a new workspace or tab and a detached
#                                                      cleanup watcher; prints "<workspace-or-tab>\t<agent-pane>"
#   split-beside <label> <dir> [--keep-open] -- <cmd...>   splits right of the caller; prints the pane id
#   tab-beside <label> <dir> -- <cmd...>               opens an unfocused tab in the caller's workspace that closes
#                                                      when the command exits; prints the pane id
#   labelled-panes <label>                             panes in the caller's tab with that label, minus the caller
#   pane-state <pane>                                  exit 0 running, 1 exited, 2 lookup failed
#   pane-tail <pane> <lines>
#   close-pane <pane>
#   wait-agent-exit <pane>                             watcher only
#   notify <title> <body>                              watcher only
#   close-workspace <id>                               watcher only
#   close-tab <id>                                     watcher only
# Run outside the sandbox. herdr takes precedence when both are set, since it runs inside the Rex terminal.
#
# Exit codes, unless a subcommand says otherwise below:
#   0  done
#   1  genuine failure
#   2  bad arguments
#   6  neither herdr nor Rex
# Per subcommand:
#   backend                                            always 0
#   pane-state                                         0 running, 1 exited, 2 lookup failed or bad arguments, 6 neither
#   pane-tail, close-pane                              the backend command's own status on failure (Rex gives 3 for a gone block)
#   wait-agent-exit                                    0 once the agent has exited, and never returns before then
#   notify, close-workspace, close-tab                 0 once the backend resolves, even when its call fails

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
watcher=$script_dir/../skills/pr-review/scripts/watch_pr_session.sh

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

detect_backend() {
  if [[ ${HERDR_ENV:-} == 1 ]]; then
    echo herdr
  elif [[ -n ${REX_SESSION:-} && $(rex --autostart=false whoami --json 2>/dev/null | jq -r '.session_id // empty') == "$REX_SESSION" ]]; then
    echo rex
  else
    echo none
  fi
}

# The watcher inherits the backend from hand-off, since its own session may be gone by the time it cleans up
backend=${TERMINAL_BACKEND:-}
resolve_backend() {
  [[ -n $backend ]] || backend=$(detect_backend)
  [[ $backend != none ]] || {
    echo "terminal.sh: not inside herdr or Rex" >&2
    exit 6
  }
}

# Block commands scope to $REX_SESSION unless it is unset, which lets them take a full id from any session
rx() {
  env -u REX_SESSION -u REX_BLOCK rex --autostart=false "$@"
}

# Session labels are renamed by every agent started in them, so a session is found by where its panes work
rex_session_in() {
  local dir found= count=0 s b cwd
  dir=$(cd "$1" && pwd -P) || return 0
  for s in $(rx ls --json | jq -r '.sessions[].session_id'); do
    for b in $(rx block ls -s "$s" --json | jq -r '.blocks[] | select(.creator_name == "com.superlogical.terminal") | .block_id'); do
      cwd=$(rx block call -b "$b" process 2>/dev/null | jq -r '.foreground.cwd // empty')
      if [[ $cwd == "$dir" || $cwd == "$dir"/* ]]; then
        found=$s
        count=$((count + 1))
        break
      fi
    done
  done
  ((count == 1)) && echo "$found"
  return 0
}

hand_off() {
  [[ $# -ge 5 ]] || usage
  local mode=$1 dir=$2 name=$3 kind=$4 prompt=$5 common main out ws pane session
  shift 5
  [[ $mode == review || $mode == branch || $mode == tab ]] || usage
  [[ $mode != review || $# -ge 1 ]] || usage
  common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir) || exit 1
  main=$(dirname "$common")
  resolve_backend

  case $backend in
    herdr)
      if [[ $mode == tab ]]; then
        ws=$(herdr workspace list | jq -r --arg path "$dir" \
          '[.result.workspaces[] | select(.worktree.checkout_path == $path) | .workspace_id][0] // empty')
        if [[ -z $ws ]]; then
          out=$(herdr worktree open --cwd "$main" --path "$dir" --no-focus) || exit 1
          ws=$(jq -r '.result.workspace.workspace_id' <<<"$out")
        fi
        out=$(herdr tab create --workspace "$ws" --cwd "$dir" --label "$name" --no-focus) || exit 1
        ws=$(jq -r '.result.tab.tab_id' <<<"$out")
      else
        out=$(herdr worktree open --cwd "$main" --path "$dir" --label "$name" --no-focus) || exit 1
        ws=$(jq -r '.result.workspace.workspace_id' <<<"$out")
      fi
      pane=$(jq -r '.result.root_pane.pane_id' <<<"$out")
      herdr agent start "$name" --kind "$kind" --pane "$pane" >/dev/null || exit 1
      herdr agent prompt "$name" "$prompt" >/dev/null || exit 1
      ;;
    rex)
      if [[ $mode == tab ]]; then
        session=$(rex_session_in "$dir")
        [[ -n $session ]] || session=$REX_SESSION
        out=$(rx window new -s "$session" "$name" -c "$dir" --focus=false --json -- "$kind" "$prompt") || exit 1
        ws=$(jq -r '.window_id // empty' <<<"$out")
      else
        out=$(rx new "$name" -c "$dir" --window Terminal --json) || exit 1
        session=$(jq -r '.session_id // empty' <<<"$out")
        [[ -n $session && $session != null ]] || exit 1
        out=$(rx window new -s "$session" "$name" -c "$dir" --focus=false --json -- "$kind" "$prompt") || {
          rx kill "$session" >/dev/null 2>&1
          exit 1
        }
        ws=$session
      fi
      pane=$(jq -r '.block_ids[0] // empty' <<<"$out")
      if [[ -z $ws || $ws == null || -z $pane || $pane == null ]]; then
        [[ $mode == tab ]] || rx kill "$session" >/dev/null 2>&1
        exit 1
      fi
      ;;
  esac

  case $mode in
    review) set -- "$mode" "$pane" "$ws" "$dir" "$main" "$@" ;;
    branch) set -- "$mode" "$pane" "$ws" "$dir" "$main" ;;
    tab) set -- "$mode" "$pane" "$ws" ;;
  esac
  TERMINAL_BACKEND=$backend nohup "$watcher" "$@" </dev/null >/dev/null 2>&1 &
  disown
  printf '%s\t%s\n' "$ws" "$pane"
}

split_beside() {
  [[ $# -ge 4 ]] || usage
  local label=$1 dir=$2 keep_open=() pane cmd
  shift 2
  if [[ $1 == --keep-open ]]; then
    keep_open=(--keep-open)
    shift
  fi
  [[ $1 == -- && $# -ge 2 ]] || usage
  shift
  resolve_backend

  case $backend in
    herdr)
      pane=$(herdr pane split --current --direction right --cwd "$dir" --no-focus | jq -r '.result.pane.pane_id') || exit 1
      cmd=$(printf '%q ' "$@")
      herdr pane rename "$pane" "$label" >/dev/null && herdr pane run "$pane" "${cmd% }" >/dev/null || {
        herdr pane close "$pane" >/dev/null 2>&1
        exit 1
      }
      echo "$pane"
      ;;
    rex)
      rx split -s "$REX_SESSION" -b "$REX_BLOCK" --split=right --label "$label" --focus=false -c "$dir" \
        ${keep_open[@]+"${keep_open[@]}"} --json -- "$@" | jq -r '.block_ids[0]'
      ;;
  esac
}

tab_beside() {
  [[ $# -ge 4 && $3 == -- ]] || usage
  local label=$1 dir=$2 ws out pane cmd
  shift 3
  resolve_backend

  case $backend in
    herdr)
      ws=$(herdr pane current | jq -r '.result.pane.workspace_id') || exit 1
      out=$(herdr tab create --workspace "$ws" --cwd "$dir" --label "$label") || exit 1
      pane=$(jq -r '.result.root_pane.pane_id' <<<"$out")
      cmd=$(printf '%q ' "$@")
      # exit closes the tab once the command ends, rather than leaving a shell behind
      herdr pane run "$pane" "${cmd% }; exit" >/dev/null || {
        herdr tab close "$(jq -r '.result.tab.tab_id' <<<"$out")" >/dev/null 2>&1
        exit 1
      }
      echo "$pane"
      ;;
    rex)
      rx window new -s "$REX_SESSION" "$label" -c "$dir" --focus=false --json -- "$@" | jq -er '.block_ids[0]'
      ;;
  esac
}

labelled_panes() {
  [[ $# -eq 1 ]] || usage
  local self tab
  resolve_backend

  case $backend in
    herdr)
      read -r self tab < <(herdr pane current | jq -r '.result.pane | "\(.pane_id) \(.tab_id)"')
      herdr pane list | jq -r --arg tab "$tab" --arg self "$self" --arg label "$1" \
        '.result.panes[] | select(.tab_id == $tab and .pane_id != $self and .label == $label) | .pane_id'
      ;;
    rex)
      rx block ls -s "$REX_SESSION" --json | jq -r --arg self "$REX_BLOCK" --arg label "$1" \
        '(.blocks[] | select(.block_id == $self) | .window_id) as $win
        | .blocks[] | select(.window_id == $win and .block_id != $self and .label == $label) | .block_id'
      ;;
  esac
}

pane_state() {
  [[ $# -eq 1 ]] || usage
  local info state ec
  resolve_backend

  case $backend in
    herdr)
      # 0 a command holds the foreground, 1 only the shell's own group (prompt hooks included), else a failed lookup
      info=$(herdr pane process-info --pane "$1") || return 2
      state=$(jq -r '.result.process_info | if .foreground_process_group_id == null or .shell_pid == null then "unknown"
        elif .foreground_process_group_id != .shell_pid then "running" else "exited" end' <<<"$info") || return 2
      ;;
    rex)
      ec=0
      info=$(rx block call -b "$1" process 2>/dev/null) || ec=$?
      # A closed block is gone, which means its command exited
      ((ec == 3)) && return 1
      ((ec == 0)) || return 2
      state=$(jq -r 'if .last_exit == null then "running" else "exited" end' <<<"$info") || return 2
      ;;
  esac

  case $state in
    running) return 0 ;;
    exited) return 1 ;;
    *) return 2 ;;
  esac
}

pane_tail() {
  [[ $# -eq 2 ]] || usage
  resolve_backend

  case $backend in
    herdr) herdr pane read "$1" --lines "$2" ;;
    rex) rx capture -b "$1" --trim | tail -n "$2" ;;
  esac
}

close_pane() {
  [[ $# -eq 1 ]] || usage
  resolve_backend

  case $backend in
    herdr) herdr pane close "$1" >/dev/null ;;
    rex) rx block close "$1" >/dev/null ;;
  esac
}

wait_agent_exit() {
  [[ $# -eq 1 ]] || usage
  local pane=$1 poll_s=5 misses=0 pane_json agent ec
  resolve_backend

  case $backend in
    herdr)
      while [[ $misses -lt 2 ]]; do
        sleep "$poll_s"
        if pane_json=$(herdr pane get "$pane" 2>&1); then
          agent=$(jq -r '.result.pane.agent // empty' <<<"$pane_json")
        elif [[ $(jq -r '.error.code // empty' <<<"$pane_json" 2>/dev/null) == pane_not_found ]]; then
          agent=
        else
          misses=0
          continue
        fi

        if [[ -z $agent ]]; then
          misses=$((misses + 1))
        else
          misses=0
        fi
      done
      ;;
    rex)
      while :; do
        rx wait "$pane" >/dev/null 2>&1
        ec=0
        pane_state "$pane" || ec=$?
        # A failed lookup is retried, never taken as an exit
        ((ec == 1)) && return 0
        sleep "$poll_s"
      done
      ;;
  esac
}

notify() {
  [[ $# -eq 2 ]] || usage
  resolve_backend

  case $backend in
    herdr) herdr notification show "$1" --body "$2" >/dev/null 2>&1 ;;
    rex) osascript -e 'on run argv' -e 'display notification (item 2 of argv) with title (item 1 of argv)' -e 'end run' -- "$1" "$2" >/dev/null 2>&1 ;;
  esac
  return 0
}

close_workspace() {
  [[ $# -eq 1 ]] || usage
  resolve_backend

  case $backend in
    herdr) herdr workspace close "$1" >/dev/null 2>&1 ;;
    rex) rx kill "$1" >/dev/null 2>&1 ;;
  esac
  return 0
}

close_tab() {
  [[ $# -eq 1 ]] || usage
  resolve_backend

  case $backend in
    herdr) herdr tab close "$1" >/dev/null 2>&1 ;;
    rex) rx window close "$1" >/dev/null 2>&1 ;;
  esac
  return 0
}

[[ $# -ge 1 ]] || usage
sub=$1
shift

case $sub in
  backend) detect_backend ;;
  hand-off) hand_off "$@" ;;
  split-beside) split_beside "$@" ;;
  tab-beside) tab_beside "$@" ;;
  labelled-panes) labelled_panes "$@" ;;
  pane-state) pane_state "$@" ;;
  pane-tail) pane_tail "$@" ;;
  close-pane) close_pane "$@" ;;
  wait-agent-exit) wait_agent_exit "$@" ;;
  notify) notify "$@" ;;
  close-workspace) close_workspace "$@" ;;
  close-tab) close_tab "$@" ;;
  *) usage ;;
esac
