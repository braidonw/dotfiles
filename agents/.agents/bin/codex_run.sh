#!/usr/bin/env bash
set -euo pipefail

# Single front door for every Codex invocation across the agent roles and
# review skills. Owns plugin discovery, availability preflight, waiting, and
# the exit-code contract. Callers own prompt construction.
#
# Usage:
#   codex_run.sh task   [--model M] [--effort E] [--write] [--resume]
#                       [--timeout-ms N] (--prompt-file F | --prompt TEXT)
#   codex_run.sh review [--model M] [--effort E] --prompt-file F
#   codex_run.sh check
#
# Two engines, chosen by mode. `task` runs through the codex plugin's
# companion runtime, which drives the Codex app-server protocol and so gives
# tracked background jobs, persistent threads and resume. `review` runs
# `codex exec --ephemeral` instead, deliberately leaving no thread behind: a
# throwaway review must never become the newest resumable task and hijack a
# later `/codex:rescue --resume`.
#
# Model and effort are pass-through. Unset means inherit ~/.codex/config.toml,
# because the right model is a property of the calling role, not of this layer.
#
# Exit codes:
#   0  finished; the report is on stdout
#   1  Codex ran and failed; the tree may carry partial edits
#   3  nothing to do (reserved for callers, never emitted here)
#   4  Codex unavailable; stderr carries "CODEX_UNAVAILABLE: <reason>"
#   5  still running at the ceiling; stdout carries "CODEX_JOB: <id>"
#
# Exit 1 and exit 4 mean different things to a caller that can fall back. Only
# 4 guarantees nothing ran, so only 4 is safe to redo natively.

DEFAULT_TIMEOUT_MS=2700000
POLL_CHUNK_MS=60000

MODE="${1:-}"
[[ -n "$MODE" ]] || { echo "usage: codex_run.sh <task|review|check> [options]" >&2; exit 2; }
shift || true

MODEL=""
EFFORT=""
PROMPT_FILE=""
PROMPT_TEXT=""
WRITE=0
RESUME=0
TIMEOUT_MS="$DEFAULT_TIMEOUT_MS"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --prompt-file) PROMPT_FILE="$2"; shift 2 ;;
    --prompt) PROMPT_TEXT="$2"; shift 2 ;;
    --timeout-ms) TIMEOUT_MS="$2"; shift 2 ;;
    --write) WRITE=1; shift ;;
    --resume) RESUME=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

unavailable() { echo "CODEX_UNAVAILABLE: $1" >&2; exit 4; }

# The codex install is a symlink in ~/.local/bin, which a subagent shell may not have.
export PATH="$HOME/.local/bin:$PATH"

command -v codex >/dev/null 2>&1 || unavailable "the codex CLI is not on PATH"
codex login status >/dev/null 2>&1 || unavailable "not logged in to Codex (run: codex login)"

# Quota exhaustion and throttling both mean unavailable but read differently to
# a human, so they are classified apart rather than as one "usage limit".
classify_failure() {
  local stderr_file="$1" status="$2"
  if grep -qiE 'usage limit|insufficient_quota|out of (credits|quota)|quota exceeded' "$stderr_file"; then
    unavailable "usage limit reached"
  fi
  if grep -qiE 'rate.?limit|too many requests|\b429\b' "$stderr_file"; then
    unavailable "rate limited by the provider, retry shortly"
  fi
  echo "codex failed (status $status)" >&2
  exit 1
}

# The plugin lives in a version-pinned cache directory and ${CLAUDE_PLUGIN_ROOT}
# is only set inside plugin context, so the path is resolved at runtime. A
# missing plugin is an unavailable Codex, not a crash.
resolve_companion() {
  local manifest="$HOME/.claude/plugins/installed_plugins.json" path=""
  if [[ -f "$manifest" ]] && command -v node >/dev/null 2>&1; then
    path="$(node -e '
      const fs = require("fs");
      try {
        const m = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        const e = (m.plugins?.["codex@openai-codex"] ?? [])[0];
        process.stdout.write(e?.installPath ?? "");
      } catch { process.stdout.write(""); }
    ' "$manifest" 2>/dev/null || true)"
  fi
  if [[ -n "$path" && -f "$path/scripts/codex-companion.mjs" ]]; then
    echo "$path/scripts/codex-companion.mjs"
    return 0
  fi
  local newest
  newest="$(ls -d "$HOME"/.claude/plugins/cache/openai-codex/codex/*/ 2>/dev/null | sort -V | tail -1 || true)"
  if [[ -n "$newest" && -f "${newest}scripts/codex-companion.mjs" ]]; then
    echo "${newest}scripts/codex-companion.mjs"
    return 0
  fi
  return 1
}

json_field() { node -e '
  let raw = "";
  process.stdin.on("data", (c) => (raw += c));
  process.stdin.on("end", () => {
    try {
      const parsed = JSON.parse(raw);
      const value = process.argv[1].split(".").reduce((acc, key) => acc?.[key], parsed);
      process.stdout.write(value === undefined || value === null ? "" : String(value));
    } catch { process.stdout.write(""); }
  });
' "$1"; }

run_task() {
  local companion
  companion="$(resolve_companion)" || unavailable "the codex plugin is not installed"
  command -v node >/dev/null 2>&1 || unavailable "node is not on PATH"

  local -a launch=(node "$companion" task --background --json --cwd "$PWD")
  [[ -n "$MODEL" ]] && launch+=(--model "$MODEL")
  [[ -n "$EFFORT" ]] && launch+=(--effort "$EFFORT")
  [[ "$WRITE" -eq 1 ]] && launch+=(--write)
  [[ "$RESUME" -eq 1 ]] && launch+=(--resume-last)
  if [[ -n "$PROMPT_FILE" ]]; then
    launch+=(--prompt-file "$PROMPT_FILE")
  elif [[ -n "$PROMPT_TEXT" ]]; then
    launch+=("$PROMPT_TEXT")
  elif [[ "$RESUME" -eq 0 ]]; then
    echo "task needs --prompt-file, --prompt, or --resume" >&2
    exit 2
  fi

  local workdir launch_out launch_err
  workdir="$(mktemp -d -t codex-run)"
  launch_out="$workdir/launch.json"
  launch_err="$workdir/launch.stderr"

  set +e
  "${launch[@]}" >"$launch_out" 2>"$launch_err"
  local launch_status=$?
  set -e
  [[ "$launch_status" -eq 0 ]] || { cat "$launch_err" >&2; classify_failure "$launch_err" "$launch_status"; }

  local job_id
  job_id="$(json_field jobId < "$launch_out")"
  [[ -n "$job_id" ]] || { cat "$launch_out" "$launch_err" >&2; echo "codex task did not return a job id" >&2; exit 1; }

  local deadline now remaining chunk snapshot status
  deadline=$(( $(date +%s) * 1000 + TIMEOUT_MS ))
  while :; do
    now=$(( $(date +%s) * 1000 ))
    remaining=$(( deadline - now ))
    if [[ "$remaining" -le 0 ]]; then
      echo "CODEX_JOB: $job_id"
      echo "Codex job $job_id is still running after ${TIMEOUT_MS}ms. Check /codex:status $job_id." >&2
      exit 5
    fi
    chunk=$(( remaining < POLL_CHUNK_MS ? remaining : POLL_CHUNK_MS ))

    set +e
    snapshot="$(node "$companion" status "$job_id" --wait --json --cwd "$PWD" --timeout-ms "$chunk" 2>"$workdir/status.stderr")"
    local status_exit=$?
    set -e
    [[ "$status_exit" -eq 0 ]] || { cat "$workdir/status.stderr" >&2; echo "could not read status for $job_id" >&2; exit 1; }

    status="$(printf '%s' "$snapshot" | json_field job.status)"
    case "$status" in
      completed)
        node "$companion" result "$job_id" --cwd "$PWD"
        exit 0
        ;;
      failed|cancelled)
        node "$companion" result "$job_id" --cwd "$PWD" || true
        echo "codex job $job_id ended with status $status" >&2
        exit 1
        ;;
      queued|running) ;;
      *)
        echo "unexpected job status for $job_id: ${status:-<empty>}" >&2
        exit 1
        ;;
    esac
  done
}

run_review() {
  [[ -n "$PROMPT_FILE" && -f "$PROMPT_FILE" ]] || { echo "review needs --prompt-file <existing file>" >&2; exit 2; }

  local workdir review_file stderr_file
  workdir="$(mktemp -d -t codex-run)"
  review_file="$workdir/review.md"
  stderr_file="$workdir/codex.stderr"

  local -a cmd=(codex exec)
  [[ -n "$MODEL" ]] && cmd+=(-m "$MODEL")
  [[ -n "$EFFORT" ]] && cmd+=(-c "model_reasoning_effort=$EFFORT")
  cmd+=(--sandbox read-only --ephemeral --color never --output-last-message "$review_file" -)

  set +e
  "${cmd[@]}" < "$PROMPT_FILE" 2>"$stderr_file"
  local status=$?
  set -e
  cat "$stderr_file" >&2

  if [[ "$status" -ne 0 || ! -s "$review_file" ]]; then
    classify_failure "$stderr_file" "$status"
  fi

  echo ""
  echo "REVIEW_SAVED: $review_file"
}

case "$MODE" in
  task) run_task ;;
  review) run_review ;;
  check) resolve_companion >/dev/null || unavailable "the codex plugin is not installed"; echo "codex available" ;;
  *) echo "unknown mode: $MODE (expected task, review, or check)" >&2; exit 2 ;;
esac
