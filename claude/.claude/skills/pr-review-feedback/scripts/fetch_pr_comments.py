#!/usr/bin/env python3
"""Fetch review feedback for a GitHub PR, with thread-resolution state.

Why this exists: the plain `gh pr` commands don't expose whether a review
thread is *resolved* or *outdated* — that lives only behind GitHub's GraphQL
API. Since the common ask is "what review feedback still needs addressing?",
the resolved/outdated filtering is the whole point, so we do it here once and
correctly rather than re-deriving the GraphQL on every run.

Output: JSON on stdout with the PR meta, the unresolved review threads (each
with its file/line, diff hunk, and full comment chain), review summaries
(approvals / change requests and their bodies), and counts of what was skipped
so the caller can mention it. Pass --all to include resolved/outdated threads.

Usage:
    fetch_pr_comments.py                 # PR for the current branch
    fetch_pr_comments.py 1234            # PR number
    fetch_pr_comments.py https://github.com/owner/repo/pull/1234
    fetch_pr_comments.py --all           # include resolved + outdated threads
"""

import json
import re
import subprocess
import sys


def gh(args, **kwargs):
    """Run a gh command, returning stdout. Raises on non-zero exit."""
    result = subprocess.run(
        ["gh", *args], capture_output=True, text=True, **kwargs
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise SystemExit(
            f"`gh {' '.join(args)}` failed (exit {result.returncode}). "
            "Is `gh` installed and authenticated (`gh auth status`)?"
        )
    return result.stdout


def resolve_target(arg):
    """Resolve (owner, repo, number) from an arg or the current branch."""
    if arg:
        m = re.search(r"github\.com/([^/]+)/([^/]+)/pull/(\d+)", arg)
        if m:
            return m.group(1), m.group(2), int(m.group(3))
        if arg.isdigit():
            owner, repo = current_repo()
            return owner, repo, int(arg)
        raise SystemExit(f"Could not parse a PR from {arg!r}.")

    # No arg: infer the PR open on the current branch.
    owner, repo = current_repo()
    out = gh(["pr", "view", "--json", "number"])
    number = json.loads(out)["number"]
    return owner, repo, number


def current_repo():
    out = gh(["repo", "view", "--json", "nameWithOwner"])
    owner, repo = json.loads(out)["nameWithOwner"].split("/", 1)
    return owner, repo


QUERY = """
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      number
      title
      url
      state
      headRefName
      baseRefName
      reviewThreads(first: 100) {
        nodes {
          isResolved
          isOutdated
          path
          line
          originalLine
          comments(first: 50) {
            nodes {
              author { login }
              authorAssociation
              body
              diffHunk
              createdAt
              url
            }
          }
        }
      }
      reviews(first: 50) {
        nodes {
          author { login }
          authorAssociation
          state
          body
          submittedAt
          url
        }
      }
    }
  }
}
"""


def fetch(owner, repo, number):
    out = gh(
        [
            "api", "graphql",
            "-f", f"query={QUERY}",
            "-F", f"owner={owner}",
            "-F", f"repo={repo}",
            "-F", f"number={number}",
        ]
    )
    return json.loads(out)["data"]["repository"]["pullRequest"]


def normalise_thread(thread):
    comments = [
        {
            "author": (c["author"] or {}).get("login", "ghost"),
            "association": c.get("authorAssociation"),
            "body": c["body"],
            "created_at": c["createdAt"],
            "url": c["url"],
        }
        for c in thread["comments"]["nodes"]
    ]
    # The diff hunk is the same across a thread; keep it once for context.
    first = thread["comments"]["nodes"][0] if thread["comments"]["nodes"] else {}
    return {
        "path": thread["path"],
        "line": thread["line"] or thread["originalLine"],
        "is_outdated": thread["isOutdated"],
        "diff_hunk": first.get("diffHunk", ""),
        "comments": comments,
    }


def main():
    args = [a for a in sys.argv[1:] if a != "--all"]
    include_all = "--all" in sys.argv[1:]
    target_arg = args[0] if args else None

    owner, repo, number = resolve_target(target_arg)
    pr = fetch(owner, repo, number)

    threads = pr["reviewThreads"]["nodes"]
    unresolved, resolved_count, outdated_count = [], 0, 0
    for t in threads:
        if t["isResolved"]:
            resolved_count += 1
            if not include_all:
                continue
        if t["isOutdated"] and not t["isResolved"]:
            outdated_count += 1
            if not include_all:
                continue
        unresolved.append(normalise_thread(t))

    # Review summaries worth surfacing: an explicit verdict or a written body.
    summaries = [
        {
            "author": (r["author"] or {}).get("login", "ghost"),
            "association": r.get("authorAssociation"),
            "state": r["state"],
            "body": r["body"],
            "submitted_at": r["submittedAt"],
            "url": r["url"],
        }
        for r in pr["reviews"]["nodes"]
        if r["body"].strip() or r["state"] in ("CHANGES_REQUESTED", "APPROVED")
    ]

    output = {
        "pr": {
            "number": pr["number"],
            "title": pr["title"],
            "url": pr["url"],
            "state": pr["state"],
            "head": pr["headRefName"],
            "base": pr["baseRefName"],
        },
        "unresolved_threads": unresolved,
        "review_summaries": summaries,
        "skipped": {"resolved": resolved_count, "outdated": outdated_count},
        "included_all": include_all,
    }
    print(json.dumps(output, indent=2))


if __name__ == "__main__":
    main()
