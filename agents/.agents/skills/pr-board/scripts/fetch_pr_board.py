#!/usr/bin/env python3
"""Gather GitHub PR board data for the current user into one JSON document.

Emits the user's own open PRs (with review, check and unresolved-thread
state), the stacked-branch chain graph reconstructed from base/head branch
names, PRs awaiting the user's review (requested of them directly or of a
team they belong to), and local branches stacked on an open PR that have no
PR of their own.

Read-only. This script never merges, pushes, comments, retargets a base, or
otherwise mutates anything on GitHub or in git. Every `gh` and `git` call it
makes is a read.

Usage:
    fetch_pr_board.py                          # board for the current repo
    fetch_pr_board.py --repo owner/name
    fetch_pr_board.py --limit 200
    fetch_pr_board.py --bot some-ci-bot        # extends the default bot set
    fetch_pr_board.py --review-team developers # override team auto-discovery
    fetch_pr_board.py --no-team-review-queue
    fetch_pr_board.py --no-review-queue
    fetch_pr_board.py --no-local-branches
    fetch_pr_board.py --pretty
"""

import argparse
import json
import subprocess
import sys
import time
from datetime import datetime

DEFAULT_BOTS = {
    "cubic-dev-ai",
    "coderabbitai",
    "codecov",
    "codecov-commenter",
    "github-actions",
    "renovate",
    "dependabot",
    "sonarcloud",
    "vercel",
    "netlify",
}

FAILING_CONCLUSIONS = {
    "FAILURE",
    "TIMED_OUT",
    "CANCELLED",
    "ACTION_REQUIRED",
    "STARTUP_FAILURE",
}
FAILING_STATES = {"ERROR", "FAILURE"}
PENDING_STATUSES = {"IN_PROGRESS", "QUEUED"}

GH_TIMEOUT_SECONDS = 60
GIT_TIMEOUT_SECONDS = 15
THREAD_CHUNK_SIZE = 25
MAX_MERGEABILITY_RETRIES = 2
MERGEABILITY_RETRY_SLEEP_SECONDS = 2
MAX_LOCAL_BRANCHES = 300
MAX_CHAIN_DEPTH = 50
MAX_UNRESOLVED_THREADS_PER_PR = 10
THREAD_BODY_EXCERPT_CHARS = 400


class GhError(RuntimeError):
    """A `gh` call failed. Callers of non-essential steps catch this and warn."""


def gh(args, timeout=GH_TIMEOUT_SECONDS):
    try:
        result = subprocess.run(
            ["gh", *args], capture_output=True, text=True, timeout=timeout
        )
    except FileNotFoundError:
        raise SystemExit(
            "gh CLI not found. Install GitHub CLI and run `gh auth login`."
        )
    except subprocess.TimeoutExpired:
        raise GhError(f"`gh {' '.join(args)}` timed out after {timeout}s")
    if result.returncode != 0:
        raise GhError(
            f"`gh {' '.join(args)}` failed (exit {result.returncode}): "
            f"{result.stderr.strip()}"
        )
    return result.stdout


def git(args, timeout=GIT_TIMEOUT_SECONDS):
    """Run a git command. Returns stdout, or None on any failure."""
    try:
        result = subprocess.run(
            ["git", *args], capture_output=True, text=True, timeout=timeout
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return result.stdout


def current_repo():
    out = gh(["repo", "view", "--json", "nameWithOwner"])
    return json.loads(out)["nameWithOwner"]


def get_trunk(repo):
    out = gh(["repo", "view", repo, "--json", "defaultBranchRef"])
    ref = json.loads(out)["defaultBranchRef"]
    return ref["name"] if ref else None


def get_viewer():
    out = gh(["api", "graphql", "-f", "query=query { viewer { login } }"])
    return json.loads(out)["data"]["viewer"]["login"]


def get_viewer_teams(owner, warnings):
    """Slugs of the org's teams the viewer belongs to.

    `review-requested:@me` matches only direct user requests, so a PR that
    asks a team the viewer is on and nobody in particular is invisible
    without a separate `team-review-requested:` query per team.
    """
    try:
        out = gh(["api", "--paginate", "/user/teams"])
    except GhError as e:
        warnings.append(f"team lookup failed, team review queue skipped: {e}")
        return []
    teams = []
    for team in json.loads(out):
        org = ((team.get("organization") or {}).get("login") or "").lower()
        if org == owner.lower() and team.get("slug"):
            teams.append(team["slug"])
    return sorted(set(teams))


def get_trunk_rules(repo, trunk, warnings):
    """What the trunk branch actually requires before anything can merge into it.

    These settings decide whether an approved, green PR can really merge, so
    they change the reading of every row on the board. Note the legacy
    /branches/{b}/protection endpoint returns 404 on repos using rulesets, or
    for tokens without admin. The rules endpoint works for ordinary members.
    """
    if not trunk:
        return None
    try:
        raw = gh(["api", f"repos/{repo}/rules/branches/{trunk}"])
    except GhError:
        warnings.append(
            f"could not read branch rules for {trunk}; merge requirements unknown"
        )
        return None

    try:
        entries = json.loads(raw)
    except json.JSONDecodeError:
        warnings.append(f"branch rules for {trunk} were not valid JSON")
        return None

    rules = {
        "required_approving_review_count": None,
        "required_review_thread_resolution": None,
        "dismiss_stale_reviews_on_push": None,
        "require_last_push_approval": None,
        "require_code_owner_review": None,
        "required_status_checks": [],
        "strict_required_status_checks_policy": None,
        "has_merge_queue": False,
    }

    # Rulesets stack, so the same rule type can appear more than once. Take the
    # strictest value seen rather than letting the last one win.
    for entry in entries:
        params = entry.get("parameters") or {}
        kind = entry.get("type")
        if kind == "pull_request":
            count = params.get("required_approving_review_count")
            if count is not None:
                existing = rules["required_approving_review_count"]
                rules["required_approving_review_count"] = (
                    count if existing is None else max(existing, count)
                )
            for flag in (
                "required_review_thread_resolution",
                "require_last_push_approval",
                "require_code_owner_review",
            ):
                if params.get(flag):
                    rules[flag] = True
                elif rules[flag] is None:
                    rules[flag] = False
            if params.get("dismiss_stale_reviews_on_push"):
                rules["dismiss_stale_reviews_on_push"] = True
            elif rules["dismiss_stale_reviews_on_push"] is None:
                rules["dismiss_stale_reviews_on_push"] = False
        elif kind == "required_status_checks":
            for check in params.get("required_status_checks") or []:
                context = check.get("context")
                if context and context not in rules["required_status_checks"]:
                    rules["required_status_checks"].append(context)
            if params.get("strict_required_status_checks_policy"):
                rules["strict_required_status_checks_policy"] = True
        elif kind == "merge_queue":
            rules["has_merge_queue"] = True

    return rules


def is_bot(login, author=None, bots=DEFAULT_BOTS):
    if not login:
        return True  # ghost / deleted account, not a human to attribute review to
    if author and author.get("is_bot"):
        return True
    lower = login.lower()
    if lower in bots:
        return True
    return lower.endswith("[bot]") or lower.endswith("-bot")


PR_LIST_FIELDS = (
    "number,title,url,headRefName,baseRefName,headRefOid,isDraft,reviewDecision,"
    "mergeable,mergeStateStatus,additions,deletions,changedFiles,createdAt,"
    "updatedAt,reviews,statusCheckRollup"
)


def fetch_own_prs(repo, limit):
    out = gh(
        [
            "pr", "list", "--repo", repo, "--author", "@me", "--state", "open",
            "--limit", str(limit), "--json", PR_LIST_FIELDS,
        ]
    )
    return json.loads(out)


def resolve_unknown_mergeability(repo, prs, warnings):
    """Force GitHub's lazily-computed mergeability for PRs the bulk list left
    UNKNOWN. Retries up to MAX_MERGEABILITY_RETRIES times with a sleep between
    attempts; a PR still UNKNOWN after that is left as-is with a warning.
    """
    resolved_count = 0
    for pr in prs:
        if pr["mergeable"] != "UNKNOWN" and pr["mergeStateStatus"] != "UNKNOWN":
            continue
        for attempt in range(MAX_MERGEABILITY_RETRIES + 1):
            try:
                out = gh(
                    [
                        "pr", "view", str(pr["number"]), "--repo", repo,
                        "--json", "number,mergeable,mergeStateStatus",
                    ]
                )
            except GhError as e:
                warnings.append(
                    f"PR #{pr['number']}: mergeability re-poll failed: {e}"
                )
                break
            data = json.loads(out)
            pr["mergeable"] = data["mergeable"]
            pr["mergeStateStatus"] = data["mergeStateStatus"]
            if pr["mergeable"] != "UNKNOWN" and pr["mergeStateStatus"] != "UNKNOWN":
                resolved_count += 1
                break
            if attempt < MAX_MERGEABILITY_RETRIES:
                time.sleep(MERGEABILITY_RETRY_SLEEP_SECONDS)
        else:
            warnings.append(
                f"PR #{pr['number']}: mergeability still UNKNOWN after "
                f"{MAX_MERGEABILITY_RETRIES} retries"
            )
    return resolved_count


def chunked(items, size):
    for i in range(0, len(items), size):
        yield items[i:i + size]


def fetch_unresolved_threads(owner, name, numbers, bots, warnings):
    """One batched GraphQL call per chunk of THREAD_CHUNK_SIZE PRs, using field
    aliases (only GraphQL exposes thread resolution state; the REST-backed `gh
    pr list` json does not). `author` is not a field on
    PullRequestReviewThread; asking for it fails the whole query. The author
    lives on the thread's first comment, at comments.nodes[0].author.login.
    """
    thread_data = {}
    for chunk in chunked(numbers, THREAD_CHUNK_SIZE):
        aliases = " ".join(
            f'p{n}: pullRequest(number: {n}) {{ reviewThreads(first: 100) {{ '
            f'nodes {{ isResolved isOutdated path line comments(first: 1) {{ '
            f'nodes {{ author {{ login }} body }} }} }} }} }}'
            for n in chunk
        )
        query = (
            "query($owner: String!, $repo: String!) { "
            f"repository(owner: $owner, name: $repo) {{ {aliases} }} }}"
        )
        try:
            out = gh(
                [
                    "api", "graphql",
                    "-f", f"query={query}",
                    "-F", f"owner={owner}",
                    "-F", f"repo={name}",
                ]
            )
        except GhError as e:
            warnings.append(
                f"unresolved-thread lookup failed for PRs {chunk}: {e}"
            )
            continue
        repository = json.loads(out)["data"]["repository"]
        for n in chunk:
            thread_data[n] = repository[f"p{n}"]["reviewThreads"]["nodes"]

    stats = {}
    for n in numbers:
        threads = thread_data.get(n)
        if threads is None:
            stats[n] = {
                "unresolved_total": None,
                "unresolved_by_author": {},
                "unresolved_human": None,
                "resolved_total": None,
                "unresolved_threads": [],
            }
            continue

        unresolved = [t for t in threads if not t["isResolved"]]
        resolved_total = len(threads) - len(unresolved)

        by_author = {}
        human_count = 0
        samples = []
        for t in unresolved:
            comments = t["comments"]["nodes"]
            first = comments[0] if comments else {}
            login = (first.get("author") or {}).get("login")
            author_key = login or "ghost"
            by_author[author_key] = by_author.get(author_key, 0) + 1
            if not is_bot(login, bots=bots):
                human_count += 1
            if len(samples) < MAX_UNRESOLVED_THREADS_PER_PR:
                body = first.get("body", "")
                excerpt = body[:THREAD_BODY_EXCERPT_CHARS]
                if len(body) > THREAD_BODY_EXCERPT_CHARS:
                    excerpt += "..."
                samples.append(
                    {
                        "path": t["path"],
                        "line": t["line"],
                        "author": author_key,
                        "body_excerpt": excerpt,
                    }
                )

        stats[n] = {
            "unresolved_total": len(unresolved),
            "unresolved_by_author": by_author,
            "unresolved_human": human_count,
            "resolved_total": resolved_total,
            "unresolved_threads": samples,
        }
    return stats


REVIEW_QUEUE_FIELDS = (
    "number,title,url,author,isDraft,createdAt,updatedAt,additions,deletions,"
    "changedFiles,reviewDecision,reviews"
)


def search_review_queue(repo, query, limit):
    out = gh(
        [
            "pr", "list", "--repo", repo,
            "--search", query,
            "--limit", str(limit), "--json", REVIEW_QUEUE_FIELDS,
        ]
    )
    return json.loads(out)


def fetch_review_queue(repo, limit, bots, viewer, teams, warnings):
    """Open PRs awaiting the viewer's review, by direct or team request.

    Merged on PR number, since a PR can ask both the viewer and their team.
    """
    queries = [("direct", "is:open review-requested:@me")]
    owner = repo.split("/", 1)[0]
    for slug in teams:
        queries.append(
            (f"team:{slug}", f"is:open team-review-requested:{owner}/{slug}")
        )

    merged = {}
    for source, query in queries:
        try:
            prs = search_review_queue(repo, query, limit)
        except GhError as e:
            warnings.append(f"review queue query `{query}` failed: {e}")
            continue
        for pr in prs:
            if pr["isDraft"]:
                continue
            author = pr.get("author") or {}
            login = author.get("login")
            if is_bot(login, author, bots):
                continue
            if viewer and login == viewer:
                continue
            existing = merged.get(pr["number"])
            if existing:
                existing["requested_via"].append(source)
                continue
            pr["requested_via"] = [source]
            merged[pr["number"]] = pr

    kept = sorted(merged.values(), key=lambda p: p["updatedAt"])
    for pr in kept:
        pr["my_last_review"] = viewer_last_review(pr.pop("reviews", []), viewer)
    return kept


def viewer_last_review(reviews, viewer):
    """The viewer's most recent review on a PR, or None if they never reviewed.

    A team request stays pending after one member reviews, so without this an
    already-reviewed PR reads as untouched work.
    """
    if not viewer:
        return None
    mine = [
        r for r in reviews
        if (r.get("author") or {}).get("login") == viewer and r.get("submittedAt")
    ]
    if not mine:
        return None
    latest = max(mine, key=lambda r: r["submittedAt"])
    return {"state": latest["state"], "submitted_at": latest["submittedAt"]}


def latest_review_states(reviews, bots):
    """Return (human_reviews_chronological, latest_state_by_author)."""
    human = [
        {
            "login": (r.get("author") or {}).get("login"),
            "state": r["state"],
            "submitted_at": r.get("submittedAt"),
        }
        for r in reviews
        if not is_bot((r.get("author") or {}).get("login"), bots=bots)
        and r.get("submittedAt")
    ]
    human.sort(key=lambda r: r["submitted_at"])

    latest = {}
    for r in human:
        latest[r["login"]] = r["state"]
    return human, latest


def normalise_check(entry):
    """CheckRun and StatusContext entries use different field names."""
    name = entry.get("name") or entry.get("context") or entry.get("workflowName")
    conclusion = entry.get("conclusion") or entry.get("state")
    status = entry.get("status")
    details_url = entry.get("detailsUrl") or entry.get("targetUrl")
    return name, conclusion, status, details_url


def check_is_failing(entry):
    _, conclusion, _, _ = normalise_check(entry)
    return conclusion in FAILING_CONCLUSIONS or conclusion in FAILING_STATES


def check_is_pending(entry):
    _, conclusion, status, _ = normalise_check(entry)
    if status:
        return status in PENDING_STATUSES
    return conclusion == "PENDING"


def build_pr_record(pr, bots, thread_stats, trunk_rules=None):
    human_reviews, latest_by_author = latest_review_states(pr["reviews"], bots)
    approved_by = [login for login, state in latest_by_author.items() if state == "APPROVED"]
    changes_requested_by = [
        login for login, state in latest_by_author.items()
        if state == "CHANGES_REQUESTED"
    ]

    checks = pr["statusCheckRollup"] or []
    failing_checks = []
    for c in checks:
        if check_is_failing(c):
            name, conclusion, _, details_url = normalise_check(c)
            failing_checks.append(
                {
                    "name": name,
                    "conclusion": conclusion,
                    "details_url": details_url,
                    "workflow_name": c.get("workflowName"),
                }
            )
    pending_checks = sum(1 for c in checks if check_is_pending(c))

    reasons = []
    if pr["isDraft"]:
        reasons.append("draft")
    if pr["reviewDecision"] == "CHANGES_REQUESTED":
        who = ", ".join(sorted(changes_requested_by)) or "a reviewer"
        reasons.append(f"changes requested by {who}")
    elif pr["reviewDecision"] != "APPROVED":
        reasons.append("awaiting review")
    if pr["mergeable"] == "CONFLICTING":
        reasons.append("conflicts with base")
    if failing_checks:
        plural = "s" if len(failing_checks) != 1 else ""
        reasons.append(f"{len(failing_checks)} failing check{plural}")
    if pr["mergeStateStatus"] == "BEHIND":
        reasons.append("behind base branch")
    # Thread resolution is a separate gate from approval. When the trunk
    # requires it, an approved and green PR with an open thread still cannot
    # merge, which is the usual explanation for a PR that looks ready and is not.
    stats = thread_stats.get(pr["number"]) or {}
    open_threads = stats.get("unresolved_total")
    if (
        trunk_rules
        and trunk_rules.get("required_review_thread_resolution")
        and open_threads
    ):
        plural = "s" if open_threads != 1 else ""
        reasons.append(f"{open_threads} unresolved review thread{plural}")
    elif pr["mergeStateStatus"] in ("BLOCKED", "DIRTY"):
        reasons.append(f"merge state {pr['mergeStateStatus'].lower()}")

    stats = thread_stats.get(
        pr["number"],
        {
            "unresolved_total": None,
            "unresolved_by_author": {},
            "unresolved_human": None,
            "resolved_total": None,
            "unresolved_threads": [],
        },
    )

    return {
        "number": pr["number"],
        "title": pr["title"],
        "url": pr["url"],
        "head_ref": pr["headRefName"],
        "base_ref": pr["baseRefName"],
        "head_sha": pr["headRefOid"],
        "is_draft": pr["isDraft"],
        "review_decision": pr["reviewDecision"],
        "mergeable": pr["mergeable"],
        "merge_state_status": pr["mergeStateStatus"],
        "additions": pr["additions"],
        "deletions": pr["deletions"],
        "changed_files": pr["changedFiles"],
        "created_at": pr["createdAt"],
        "updated_at": pr["updatedAt"],
        "human_reviews": human_reviews,
        "latest_human_review_by_author": latest_by_author,
        "approved_by": approved_by,
        "changes_requested_by": changes_requested_by,
        "failing_checks": failing_checks,
        "pending_checks": pending_checks,
        "ready": not reasons,
        "blocked_reasons": reasons,
        **stats,
    }


def build_chains(pr_records, warnings):
    by_number = {p["number"]: p for p in pr_records}
    head_to_number = {p["head_ref"]: p["number"] for p in pr_records}

    parent_of = {}
    children_of = {n: [] for n in by_number}
    for p in pr_records:
        parent = head_to_number.get(p["base_ref"])
        parent_of[p["number"]] = parent
        if parent is not None:
            children_of[parent].append(p["number"])

    roots = [n for n, parent in parent_of.items() if parent is None]

    paths = []
    for root in roots:
        stack = [(root, [root], {root})]
        while stack:
            node, path, visited = stack.pop()
            if len(path) > MAX_CHAIN_DEPTH:
                warnings.append(
                    f"chain rooted at PR #{root} exceeded depth "
                    f"{MAX_CHAIN_DEPTH}; truncated"
                )
                paths.append(path)
                continue
            kids = children_of.get(node, [])
            new_kids = [k for k in kids if k not in visited]
            cyclic_kids = [k for k in kids if k in visited]
            for k in cyclic_kids:
                warnings.append(
                    f"cycle detected in stack graph at PR #{node} -> #{k}; "
                    "not followed"
                )
            if not new_kids:
                paths.append(path)
            else:
                for k in new_kids:
                    stack.append((k, path + [k], visited | {k}))

    chains = []
    for path in paths:
        entries = []
        bottleneck = None
        for i, number in enumerate(path):
            pr = by_number[number]
            entries.append(
                {
                    "position": i,
                    "number": number,
                    "title": pr["title"],
                    "url": pr["url"],
                    "head_ref": pr["head_ref"],
                    "base_ref": pr["base_ref"],
                    "ready": pr["ready"],
                    "review_decision": pr["review_decision"],
                }
            )
            if bottleneck is None and not pr["ready"]:
                bottleneck = number

        if bottleneck is None:
            mergeable_prefix = list(path)
            stranded_approved = []
        else:
            bottleneck_pos = next(
                e["position"] for e in entries if e["number"] == bottleneck
            )
            mergeable_prefix = path[:bottleneck_pos]
            stranded_approved = [
                number for number in path[bottleneck_pos + 1:]
                if by_number[number]["review_decision"] == "APPROVED"
            ]

        chains.append(
            {
                "is_stack": len(path) > 1,
                "prs": entries,
                "bottleneck": bottleneck,
                "stranded_approved": stranded_approved,
                "mergeable_prefix": mergeable_prefix,
            }
        )

    return chains


def local_stacked_branches(pr_records, warnings):
    if git(["rev-parse", "--is-inside-work-tree"]) is None:
        return []

    raw = git(["for-each-ref", "--format=%(refname:short)", "refs/heads"])
    if raw is None:
        warnings.append("git for-each-ref failed; skipping local branch scan")
        return []
    branches = [b for b in raw.splitlines() if b]
    if len(branches) > MAX_LOCAL_BRANCHES:
        warnings.append(
            f"{len(branches)} local branches exceeds the cap of "
            f"{MAX_LOCAL_BRANCHES}; skipping local branch scan"
        )
        return []

    pr_heads = {p["head_ref"] for p in pr_records}
    local_heads = [h for h in pr_heads if git(["rev-parse", "--verify", "--quiet", h]) is not None]

    # One "branch --contains" per PR head rather than an is-ancestor call per
    # (branch, head) pair. On a repo with 76 local branches and 10 open PRs that
    # is 10 git calls instead of 760, which dominated the runtime.
    containing = {}
    for head in local_heads:
        listed = git(["branch", "--contains", head, "--format=%(refname:short)"])
        if listed is None:
            warnings.append(f"git branch --contains failed for {head}; skipping it")
            continue
        for name in listed.splitlines():
            name = name.strip()
            if name and name not in pr_heads:
                containing.setdefault(name, []).append(head)

    results = []
    for branch in branches:
        if branch in pr_heads or branch not in containing:
            continue

        candidates = []
        for head in containing[branch]:
            count_out = git(["rev-list", "--count", f"{head}..{branch}"])
            if count_out is None:
                continue
            ahead = int(count_out.strip())
            if ahead >= 1:
                candidates.append((ahead, head))

        if not candidates:
            continue
        candidates.sort()
        commits_ahead, nearest_head = candidates[0]
        stacked_on_pr = next(
            p["number"] for p in pr_records if p["head_ref"] == nearest_head
        )

        has_upstream = git(["rev-parse", "--verify", "--quiet", f"{branch}@{{upstream}}"]) is not None
        ahead_of_upstream = behind_upstream = None
        if has_upstream:
            lr = git(
                ["rev-list", "--left-right", "--count", f"{branch}@{{upstream}}...{branch}"]
            )
            if lr:
                parts = lr.split()
                if len(parts) == 2:
                    behind_upstream, ahead_of_upstream = int(parts[0]), int(parts[1])

        last_commit = git(["log", "-1", "--format=%s|%cI", branch])
        subject, date = (None, None)
        if last_commit:
            line = last_commit.strip()
            if "|" in line:
                subject, date = line.split("|", 1)

        results.append(
            {
                "branch": branch,
                "stacked_on_pr": stacked_on_pr,
                "commits_ahead": commits_ahead,
                "has_upstream": has_upstream,
                "ahead_of_upstream": ahead_of_upstream,
                "behind_upstream": behind_upstream,
                "last_commit_subject": subject,
                "last_commit_date": date,
            }
        )

    return results


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", help="owner/name; defaults to the current directory's repo")
    parser.add_argument("--limit", type=int, default=100, help="max PRs per list call (default 100)")
    parser.add_argument(
        "--bot", action="append", default=[], dest="extra_bots",
        help="additional bot login to exclude from review signal (repeatable)",
    )
    parser.add_argument("--no-review-queue", action="store_true", help="skip the review-requested-of-me query")
    parser.add_argument(
        "--review-team", action="append", default=[], dest="review_teams",
        help="team slug whose review requests count as mine (repeatable); "
             "defaults to every team in this org the viewer belongs to",
    )
    parser.add_argument(
        "--no-team-review-queue", action="store_true",
        help="only count review requests addressed to the viewer directly",
    )
    parser.add_argument("--no-local-branches", action="store_true", help="skip the local git branch scan")
    parser.add_argument("--pretty", action="store_true", help="pretty-print the JSON output")
    return parser.parse_args()


def main():
    opts = parse_args()
    bots = DEFAULT_BOTS | {b.lower() for b in opts.extra_bots}
    warnings = []

    try:
        gh(["auth", "status"])
    except GhError as e:
        raise SystemExit(f"gh is not authenticated: {e}\nRun `gh auth login`.")

    try:
        repo = opts.repo or current_repo()
    except GhError as e:
        raise SystemExit(f"could not resolve a repository: {e}")
    owner, name = repo.split("/", 1)

    try:
        viewer = get_viewer()
    except GhError as e:
        warnings.append(f"could not resolve viewer login: {e}")
        viewer = None

    try:
        trunk = get_trunk(repo)
    except GhError as e:
        warnings.append(f"could not resolve default branch: {e}")
        trunk = None

    trunk_rules = get_trunk_rules(repo, trunk, warnings)

    try:
        raw_prs = fetch_own_prs(repo, opts.limit)
    except GhError as e:
        raise SystemExit(f"could not list open PRs: {e}")

    try:
        resolve_unknown_mergeability(repo, raw_prs, warnings)
    except GhError as e:
        warnings.append(f"mergeability re-poll failed: {e}")

    numbers = [pr["number"] for pr in raw_prs]
    try:
        thread_stats = fetch_unresolved_threads(owner, name, numbers, bots, warnings)
    except GhError as e:
        warnings.append(f"unresolved-thread lookup failed: {e}")
        thread_stats = {}

    pr_records = [
        build_pr_record(pr, bots, thread_stats, trunk_rules) for pr in raw_prs
    ]
    chains = build_chains(pr_records, warnings)

    review_queue = []
    review_teams = []
    if not opts.no_review_queue:
        if not opts.no_team_review_queue:
            review_teams = opts.review_teams or get_viewer_teams(owner, warnings)
        queue_raw = fetch_review_queue(
            repo, opts.limit, bots, viewer, review_teams, warnings
        )
        review_queue = [
            {
                "number": pr["number"],
                "title": pr["title"],
                "url": pr["url"],
                "author": (pr.get("author") or {}).get("login"),
                "created_at": pr["createdAt"],
                "updated_at": pr["updatedAt"],
                "additions": pr["additions"],
                "deletions": pr["deletions"],
                "changed_files": pr["changedFiles"],
                "review_decision": pr["reviewDecision"],
                "requested_via": pr["requested_via"],
                "my_last_review": pr["my_last_review"],
            }
            for pr in queue_raw
        ]

    local_branches = []
    if not opts.no_local_branches:
        local_branches = local_stacked_branches(pr_records, warnings)

    output = {
        "repo": repo,
        "viewer": viewer,
        "generated_at": datetime.now().astimezone().isoformat(),
        "trunk": trunk,
        "trunk_rules": trunk_rules,
        "prs": pr_records,
        "chains": chains,
        "review_teams": review_teams,
        "review_queue": review_queue,
        "local_stacked_branches": local_branches,
        "warnings": warnings,
    }
    print(json.dumps(output, indent=2 if opts.pretty else None))


if __name__ == "__main__":
    main()
