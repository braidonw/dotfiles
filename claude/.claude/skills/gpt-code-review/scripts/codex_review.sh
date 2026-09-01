#!/usr/bin/env bash
set -euo pipefail

# Runs a Codex code review of the current branch via the Codex CLI.
# Usage: codex_review.sh [--base <branch>] [--model <model>] [--focus "<text>"]
# Prints the review to stdout and saves it next to the prompt in a temp dir.

BASE="main"
MODEL="gpt-5.6-sol"
FOCUS=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --focus) FOCUS="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if git rev-parse --verify -q "origin/$BASE" >/dev/null; then
  BASE_REF="origin/$BASE"
else
  BASE_REF="$BASE"
fi
MERGE_BASE="$(git merge-base "$BASE_REF" HEAD)"

WORKDIR="$(mktemp -d -t codex-review)"
DIFF_FILE="$WORKDIR/branch.diff"
PROMPT_FILE="$WORKDIR/prompt.md"
REVIEW_FILE="$WORKDIR/review.md"

git diff "$MERGE_BASE" > "$DIFF_FILE"
DIFF_BYTES="$(wc -c < "$DIFF_FILE" | tr -d ' ')"
if [[ "$DIFF_BYTES" -eq 0 ]]; then
  echo "No changes between $BASE_REF (merge-base $MERGE_BASE) and the working tree." >&2
  exit 3
fi

COMMITS="$(git log --oneline "$MERGE_BASE..HEAD")"
DIFF_STAT="$(git diff --stat "$MERGE_BASE")"
UNTRACKED="$(git ls-files --others --exclude-standard)"

{
  cat <<EOF
You are performing a thorough code review of a git branch. Work from the
repository root: $ROOT

Branch under review: $BRANCH
Base: $BASE_REF (merge-base $MERGE_BASE)

Commits on the branch:
$COMMITS

Diff stat:
$DIFF_STAT
EOF

  if [[ -n "$UNTRACKED" ]]; then
    printf '\nUntracked files (not in the diff below; read them directly if relevant):\n%s\n' "$UNTRACKED"
  fi

  # Inline the diff when it comfortably fits; otherwise have Codex page
  # through it with git so a huge diff never blows the context window.
  if [[ "$DIFF_BYTES" -lt 300000 ]]; then
    printf '\nThe full diff follows:\n\n```diff\n'
    cat "$DIFF_FILE"
    printf '```\n'
  else
    cat <<EOF

The diff is too large to inline ($DIFF_BYTES bytes). Read it yourself in
chunks with your bash tool, e.g.:
  git diff $MERGE_BASE -- <path>
Review every file listed in the diff stat above; do not skip any.
EOF
  fi

  cat <<'EOF'

## How to review

You have read and bash tools. Before flagging an issue, verify it: open the
surrounding file, grep for callers and existing conventions, check whether a
concern is already handled elsewhere. Do not modify any files or run any
command that writes, commits, or pushes.

Prioritise, in order:
1. Correctness bugs: logic errors, wrong branch conditions, off-by-ones,
   broken error handling, race conditions, crashes on nil/empty input.
2. Security and data integrity: injection, authz gaps, leaking secrets or
   PII, unsafe migrations, missing constraints.
3. Silent failures: swallowed errors, fallbacks that hide problems.
4. Missing or inadequate tests for new behaviour and error branches.
5. Deviations from the project's documented conventions (CLAUDE.md /
   AGENTS.md files in this repo).
6. Performance problems with real impact (N+1 queries, unbounded loads).

Skip style nitpicks a formatter or linter would catch, and do not praise the
parts that are fine.

## Output format

Return a markdown report with exactly this structure:

# Codex review: <branch>

## Findings

For each finding:

### [CRITICAL|MAJOR|MINOR] <one-line title>
- File: <path>:<line>
- Issue: what is wrong, concretely
- Evidence: what you checked to confirm it (callers read, tests run, etc.)
- Suggestion: the fix, briefly

Order findings by severity. If you found nothing worth raising, write
"No findings." under ## Findings and say why you are confident.

## Verdict

One short paragraph: overall assessment and whether you would merge this.
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
