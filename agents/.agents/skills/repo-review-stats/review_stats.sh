#!/bin/bash
# Review/PR activity stats for a GitHub repo over a time window.
# Usage: review_stats.sh [owner/repo] [since-date YYYY-MM-DD]
# Defaults: supersimplesuper/code, one month ago. Requires gh (authed) and jq.
set -euo pipefail

REPO="${1:-supersimplesuper/code}"
SINCE="${2:-$(date -v-1m +%Y-%m-%d 2>/dev/null || date -d '1 month ago' +%Y-%m-%d)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "# repo=$REPO since=$SINCE (bot-authored PRs = author login ending in [bot] or known bot logins)"

is_bot='(a ~ /\[bot\]$/ || a == "superapi-renovate" || a == "dependabot" || a == "renovate")'

# --- Inline review comments (diff-anchored), with their PR number ---
gh api --paginate "repos/$REPO/pulls/comments?since=${SINCE}T00:00:00Z&per_page=100" \
  --jq ".[] | select(.created_at >= \"$SINCE\") | \"\(.pull_request_url | split(\"/\") | last)\t\(.user.login)\"" \
  > "$WORK/comments.tsv"

# --- PRs with any activity in the window, and their authors ---
gh api --paginate "search/issues?q=repo:$REPO+is:pr+updated:%3E=$SINCE&per_page=100" \
  --jq '.items[] | "\(.number)\t\(.user.login)"' > "$WORK/pr_authors.tsv"

# --- Formal reviews on each of those PRs ---
cat > "$WORK/fetch_reviews.sh" <<EOF
#!/bin/bash
gh api --paginate "repos/$REPO/pulls/\$1/reviews?per_page=100" \
  --jq ".[] | select(.submitted_at != null and .submitted_at >= \"$SINCE\") | \"\$1\t\(.user.login)\t\(.state)\""
EOF
chmod +x "$WORK/fetch_reviews.sh"
cut -f1 "$WORK/pr_authors.tsv" | xargs -n1 -P8 "$WORK/fetch_reviews.sh" > "$WORK/reviews.tsv"

# --- PRs created in the window: author, state, size (GraphQL) ---
gh api graphql --paginate -f query="
query(\$endCursor: String) {
  search(query: \"repo:$REPO is:pr created:>=$SINCE\", type: ISSUE, first: 100, after: \$endCursor) {
    pageInfo { hasNextPage endCursor }
    nodes {
      ... on PullRequest {
        number additions deletions changedFiles
        merged state
        author { login }
      }
    }
  }
}" --jq '.data.search.nodes[] | "\(.author.login)\t\(if .merged then "merged" elif .state == "OPEN" then "open" else "closed_unmerged" end)\t\(.additions)\t\(.deletions)\t\(.changedFiles)"' \
  > "$WORK/created.tsv"

section() { printf '\n== %s ==\n' "$1"; }

section "inline review comments per author (all PRs)"
cut -f2 "$WORK/comments.tsv" | sort | uniq -c | sort -rn

section "inline review comments per author (bot-authored PRs excluded)"
awk -F'\t' -v OFS='\t' '
  NR==FNR {author[$1] = $2; next}
  {a = author[$1]; if (a != "" && !'"$is_bot"') print $2}
' "$WORK/pr_authors.tsv" "$WORK/comments.tsv" | sort | uniq -c | sort -rn

section "distinct PRs reviewed / approvals per reviewer (all PRs; self-reviews excluded)"
awk -F'\t' -v OFS='\t' '
  NR==FNR {author[$1] = $2; next}
  author[$1] != $2 {
    if (!(($2 SUBSEP $1) in seen)) {seen[$2, $1]; prs[$2]++}
    if ($3 == "APPROVED") appr[$2]++
  }
  END {for (u in prs) print prs[u], appr[u] + 0, u}
' "$WORK/pr_authors.tsv" "$WORK/reviews.tsv" | sort -rn |
  awk 'BEGIN {print "prs_reviewed\tapprovals\treviewer"} {print}'

section "distinct PRs reviewed / approvals per reviewer (bot-authored PRs excluded)"
awk -F'\t' -v OFS='\t' '
  NR==FNR {author[$1] = $2; next}
  {a = author[$1]}
  a != "" && !'"$is_bot"' && a != $2 {
    if (!(($2 SUBSEP $1) in seen)) {seen[$2, $1]; prs[$2]++}
    if ($3 == "APPROVED") appr[$2]++
  }
  END {for (u in prs) print prs[u], appr[u] + 0, u}
' "$WORK/pr_authors.tsv" "$WORK/reviews.tsv" | sort -rn |
  awk 'BEGIN {print "prs_reviewed\tapprovals\treviewer"} {print}'

section "reviewer -> PR author matrix (distinct PRs; bot-authored and self excluded)"
awk -F'\t' -v OFS='\t' '
  NR==FNR {author[$1] = $2; next}
  {a = author[$1]}
  a != "" && !'"$is_bot"' && a != $2 {
    if (!(($2 SUBSEP a SUBSEP $1) in seen)) {seen[$2, a, $1]; n[$2 "\t" a]++}
  }
  END {for (k in n) print n[k], k}
' "$WORK/pr_authors.tsv" "$WORK/reviews.tsv" | sort -t$'\t' -k2,2 -k1,1rn |
  awk 'BEGIN {print "prs\treviewer\tpr_author"} {print}'

section "PRs created per author: count / merged / open / closed_unmerged / +lines / -lines / files / median lines changed"
sort -t$'\t' -k1,1 "$WORK/created.tsv" | awk -F'\t' -v OFS='\t' '
  {
    n[$1]++; s[$1, $2]++; add[$1] += $3; del[$1] += $4; files[$1] += $5
    size[$1, n[$1]] = $3 + $4
  }
  END {
    print "author", "prs", "merged", "open", "closed_unmerged", "added", "deleted", "files", "median_lines"
    for (u in n) {
      c = n[u]
      for (i = 1; i <= c; i++) v[i] = size[u, i]
      for (i = 2; i <= c; i++) {x = v[i]; for (j = i - 1; j >= 1 && v[j] > x; j--) v[j + 1] = v[j]; v[j + 1] = x}
      m = (c % 2) ? v[(c + 1) / 2] : (v[c / 2] + v[c / 2 + 1]) / 2
      print u, c, s[u, "merged"] + 0, s[u, "open"] + 0, s[u, "closed_unmerged"] + 0, add[u], del[u], files[u], m
    }
  }' | (read -r header; echo "$header"; sort -t$'\t' -k2,2rn)
