#!/usr/bin/env bash
set -euo pipefail

# Runs a Codex review of an implementation plan via the Codex CLI, letting
# the model verify the plan's assumptions against the actual repository.
# Usage: codex_plan_review.sh --plan <file> [--model <model>] [--focus "<text>"]
# Prints the review to stdout and saves it next to the prompt in a temp dir.

PLAN_FILE=""
MODEL="gpt-5.6-sol"
FOCUS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) PLAN_FILE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --focus) FOCUS="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$PLAN_FILE" || ! -f "$PLAN_FILE" ]]; then
  echo "usage: codex_plan_review.sh --plan <file> (file must exist)" >&2
  exit 2
fi
PLAN_FILE="$(cd "$(dirname "$PLAN_FILE")" && pwd)/$(basename "$PLAN_FILE")"

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
BRANCH="$(git rev-parse --abbrev-ref HEAD)"

WORKDIR="$(mktemp -d -t codex-plan-review)"
PROMPT_FILE="$WORKDIR/prompt.md"
REVIEW_FILE="$WORKDIR/review.md"

{
  cat <<EOF
You are reviewing an implementation plan BEFORE any work starts on it. Your
job is to find the problems that would be expensive to discover mid-build.

Repository root: $ROOT
Current branch: $BRANCH

The plan follows:

---PLAN START---
EOF
  cat "$PLAN_FILE"
  cat <<'EOF'
---PLAN END---

## How to review

You have read and bash tools. The single most valuable thing you can do is
check the plan's claims against the actual codebase: open the files it names,
grep for the functions and modules it assumes exist, look at how similar
features are already built here, and read the repo's CLAUDE.md/AGENTS.md
conventions. A plan review that doesn't touch the repo is just proofreading.
Do not modify any files or run any command that writes, commits, or pushes.

Assess, in order of importance:
1. Wrong assumptions: files, functions, schemas, or behaviour the plan
   describes that don't match reality.
2. Gaps: steps the plan needs but doesn't mention - migrations and their
   safety, backfills, test coverage, feature flags/rollout, backwards
   compatibility, error handling, updating callers the plan forgot.
3. Risks: steps that could corrupt data, break existing behaviour, or be
   hard to roll back; ordering problems between steps.
4. Fit: places where the plan reinvents something the codebase already has,
   or fights an established convention instead of following it.
5. Simpler alternatives: only when clearly better, not as taste.

Do not review prose quality, and do not pad the report - if a step is fine,
say nothing about it.

## Output format

Return a markdown report with exactly this structure:

# Plan review

## Findings

For each finding:

### [BLOCKER|MAJOR|MINOR] <one-line title>
- Plan step: which part of the plan this concerns
- Issue: what is wrong or missing, concretely
- Evidence: what you checked in the repo to confirm it (paths, symbols)
- Suggestion: how the plan should change, briefly

Order findings by severity. If the plan is sound, write "No findings." under
## Findings and say what you verified to reach that conclusion.

## Verdict

One short paragraph: is this plan ready to implement as written, ready with
the amendments above, or in need of a rethink - and why.
EOF

  if [[ -n "$FOCUS" ]]; then
    printf '\n## Additional reviewer focus requested by the author\n\n%s\n' "$FOCUS"
  fi
} > "$PROMPT_FILE"

codex exec -m "$MODEL" \
  -c model_reasoning_effort=high \
  --sandbox read-only \
  --ephemeral \
  --color never \
  --output-last-message "$REVIEW_FILE" \
  - < "$PROMPT_FILE"

if [[ ! -s "$REVIEW_FILE" ]]; then
  echo "codex exec finished but produced no review output" >&2
  exit 1
fi

echo ""
echo "REVIEW_SAVED: $REVIEW_FILE"
