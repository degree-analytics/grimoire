#!/usr/bin/env bash
# inbox.sh — fetch PRs where I am a requested reviewer.
# Usage:
#   inbox.sh                      → live: gh search prs --review-requested=@me --state=open
#   inbox.sh --from-file PATH     → read PR JSON from file (for tests)
#
# Output: JSON array of normalized PR objects. One line of JSON per run.
#
# Normalized PR schema:
#   { "number", "title", "author", "repo", "nameWithOwner",
#     "updatedAt", "additions", "deletions", "isDraft", "checks" }
set -euo pipefail

SOURCE_JSON=""
if [ "${1:-}" = "--from-file" ]; then
  [ -n "${2:-}" ] || { echo "missing path after --from-file" >&2; exit 2; }
  SOURCE_JSON=$(cat "$2")
else
  command -v gh >/dev/null || { echo "gh CLI not installed" >&2; exit 2; }
  SOURCE_JSON=$(gh search prs \
    --review-requested=@me \
    --state=open \
    --json number,title,author,updatedAt,repository \
    --limit 25)
  # gh search prs doesn't expose additions/deletions/isDraft/statusCheckRollup in one call.
  # Enrich per-PR via `gh pr view`. Keep it simple: sequential loop.
  SOURCE_JSON=$(echo "$SOURCE_JSON" | jq -c '.[]' | while read -r row; do
    n=$(echo "$row" | jq -r '.number')
    nwo=$(echo "$row" | jq -r '.repository.nameWithOwner')
    extra=$(gh pr view "$n" --repo "$nwo" \
      --json additions,deletions,isDraft,statusCheckRollup 2>/dev/null || echo '{}')
    echo "$row" | jq --argjson extra "$extra" '. + $extra'
  done | jq -s '.')
fi

# Normalize to our schema
echo "$SOURCE_JSON" | jq '[.[] | {
  number,
  title,
  author: (.author.login // "unknown"),
  repo: .repository.name,
  nameWithOwner: .repository.nameWithOwner,
  updatedAt,
  additions: (.additions // 0),
  deletions: (.deletions // 0),
  isDraft: (.isDraft // false),
  checks: ((.statusCheckRollup // []) | [.[].state] | unique | join(","))
}]'
