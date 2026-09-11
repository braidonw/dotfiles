#!/usr/bin/env python3
"""List open PRs worth reviewing, with review/activity state.

Why this exists: "which PRs should I review?" is not a plain `gh pr list`.
The useful set is open PRs authored by *other humans* (not me, not bots) that I
either have not reviewed yet, or have reviewed but which have new activity since
(the author pushed changes, or someone left a reply/comment). That last bit --
"already reviewed unless there's something new" -- needs each PR's review and
comment timeline, which only GraphQL exposes. So we compute it here once, and
correctly, rather than re-deriving it on every run.

Output: JSON on stdout with the viewer login, the candidate PRs (each with its
status and a short note on what is new), and counts of what was filtered out so
the caller can mention it.

Status values:
    unreviewed    -- I have never submitted a review on this PR.
    new_activity  -- I reviewed it, but there are new commits/comments since.
    reviewed_quiet-- I reviewed it and nothing has changed (hidden unless --all).

Usage:
    list_review_candidates.py                 # actionable PRs by others
    list_review_candidates.py --all           # include reviewed-and-quiet PRs
    list_review_candidates.py --include-drafts # include draft PRs
    list_review_candidates.py --author alice   # only PRs by a given login
    list_review_candidates.py --limit 100      # cap PRs scanned (default 60)
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone

# Logins that are bots but not always flagged as such by GitHub's typename.
BOT_LOGIN_MARKERS = ("dependabot", "renovate", "[bot]", "github-actions")


def gh(args):
    """Run a gh command, returning stdout. Raises on non-zero exit."""
    result = subprocess.run(["gh", *args], capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(result.stderr)
        raise SystemExit(
            f"`gh {' '.join(args)}` failed (exit {result.returncode}). "
            "Is `gh` installed and authenticated (`gh auth status`)?"
        )
    return result.stdout


def current_repo():
    out = gh(["repo", "view", "--json", "nameWithOwner"])
    owner, repo = json.loads(out)["nameWithOwner"].split("/", 1)
    return owner, repo


QUERY = """
query($owner: String!, $repo: String!, $first: Int!, $cursor: String) {
  viewer { login }
  repository(owner: $owner, name: $repo) {
    pullRequests(states: OPEN, first: $first, after: $cursor,
                 orderBy: {field: UPDATED_AT, direction: DESC}) {
      pageInfo { hasNextPage endCursor }
      nodes {
        number
        title
        url
        isDraft
        updatedAt
        author { login __typename }
        commits(last: 1) { nodes { commit { committedDate } } }
        reviews(first: 100) {
          nodes { author { login } submittedAt }
        }
        comments(last: 30) {
          nodes { author { login __typename } createdAt }
        }
        reviewThreads(first: 60) {
          nodes {
            comments(last: 10) {
              nodes { author { login __typename } createdAt }
            }
          }
        }
      }
    }
  }
}
"""


def fetch_page(owner, repo, first, cursor):
    args = [
        "api", "graphql",
        "-f", f"query={QUERY}",
        "-F", f"owner={owner}",
        "-F", f"repo={repo}",
        "-F", f"first={first}",
    ]
    if cursor:
        args += ["-F", f"cursor={cursor}"]
    return json.loads(gh(args))["data"]


def parse_ts(value):
    """Parse a GitHub ISO8601 timestamp to an aware datetime, or None."""
    if not value:
        return None
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def is_bot(author):
    if not author:
        return True  # ghost / deleted account -- not a person to review for
    if author.get("__typename") == "Bot":
        return True
    login = (author.get("login") or "").lower()
    return any(marker in login for marker in BOT_LOGIN_MARKERS)


def classify(pr, me):
    """Return (status, note, my_last_review_at, latest_activity_at)."""
    my_reviews = [
        parse_ts(r["submittedAt"])
        for r in pr["reviews"]["nodes"]
        if (r["author"] or {}).get("login") == me and r["submittedAt"]
    ]
    my_last_review = max(my_reviews) if my_reviews else None

    # New commits pushed by the author (code changed since my review).
    commit_nodes = pr["commits"]["nodes"]
    last_commit = parse_ts(
        commit_nodes[0]["commit"]["committedDate"]
    ) if commit_nodes else None

    # Comments and thread replies left by anyone other than me.
    other_comment_times = []
    for c in pr["comments"]["nodes"]:
        author = c["author"] or {}
        if author.get("login") != me:
            other_comment_times.append((parse_ts(c["createdAt"]), author.get("login")))
    for thread in pr["reviewThreads"]["nodes"]:
        for c in thread["comments"]["nodes"]:
            author = c["author"] or {}
            if author.get("login") != me:
                other_comment_times.append((parse_ts(c["createdAt"]), author.get("login")))

    activity_times = [t for t, _ in other_comment_times if t]
    if last_commit:
        activity_times.append(last_commit)
    latest_activity = max(activity_times) if activity_times else None

    if my_last_review is None:
        return "unreviewed", "not reviewed by you yet", None, latest_activity

    new_commit = bool(last_commit and last_commit > my_last_review)
    new_commenters = sorted({
        login for t, login in other_comment_times
        if t and t > my_last_review and login
    })

    if new_commit or new_commenters:
        parts = []
        if new_commit:
            parts.append("new commits pushed")
        if new_commenters:
            who = ", ".join("@" + c for c in new_commenters)
            parts.append(f"new comments from {who}")
        note = "since your review: " + "; ".join(parts)
        return "new_activity", note, my_last_review, latest_activity

    return "reviewed_quiet", "reviewed by you, no new activity", my_last_review, latest_activity


def iso(dt):
    return dt.astimezone(timezone.utc).isoformat() if dt else None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--all", action="store_true",
                        help="include PRs you reviewed that have no new activity")
    parser.add_argument("--include-drafts", action="store_true")
    parser.add_argument("--author", help="only PRs by this login")
    parser.add_argument("--limit", type=int, default=60,
                        help="max open PRs to scan (default 60)")
    opts = parser.parse_args()

    owner, repo = current_repo()

    me = None
    prs = []
    cursor = None
    truncated = False
    while len(prs) < opts.limit:
        page_size = min(50, opts.limit - len(prs))
        data = fetch_page(owner, repo, page_size, cursor)
        me = data["viewer"]["login"]
        conn = data["repository"]["pullRequests"]
        prs.extend(conn["nodes"])
        if conn["pageInfo"]["hasNextPage"]:
            cursor = conn["pageInfo"]["endCursor"]
        else:
            break
    else:
        truncated = True

    skipped = {"mine": 0, "bots": 0, "drafts": 0, "reviewed_quiet": 0}
    candidates = []
    for pr in prs:
        author = pr["author"] or {}
        login = author.get("login")

        if login == me:
            skipped["mine"] += 1
            continue
        if is_bot(author):
            skipped["bots"] += 1
            continue
        if opts.author and login != opts.author:
            continue
        if pr["isDraft"] and not opts.include_drafts:
            skipped["drafts"] += 1
            continue

        status, note, my_review_at, activity_at = classify(pr, me)
        if status == "reviewed_quiet":
            skipped["reviewed_quiet"] += 1
            if not opts.all:
                continue

        candidates.append({
            "number": pr["number"],
            "title": pr["title"],
            "url": pr["url"],
            "author": login,
            "is_draft": pr["isDraft"],
            "status": status,
            "note": note,
            "my_last_review_at": iso(my_review_at),
            "latest_activity_at": iso(activity_at),
            "updated_at": pr["updatedAt"],
        })

    # Stable sort twice: newest-first within each status group, groups ordered
    # so the actionable ones (new activity, then unreviewed) come first.
    order = {"new_activity": 0, "unreviewed": 1, "reviewed_quiet": 2}
    candidates.sort(key=lambda c: c["updated_at"], reverse=True)
    candidates.sort(key=lambda c: order.get(c["status"], 9))

    print(json.dumps({
        "viewer": me,
        "repo": f"{owner}/{repo}",
        "scanned": len(prs),
        "truncated": truncated,
        "candidates": candidates,
        "skipped": skipped,
        "included_all": opts.all,
    }, indent=2))


if __name__ == "__main__":
    main()
