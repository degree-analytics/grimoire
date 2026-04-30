#!/usr/bin/env bash
# triage.sh — determine if a PR is ready for review.
# Reads a single PR JSON object from stdin (inbox.sh schema).
# Usage:
#   triage.sh --viewer <gh-login>
#     → live: fetches comments via gh pr view
#   triage.sh --viewer <gh-login> --comments-file <path>
#     → test: reads comments from file
#
# Output: JSON object with verdict and metadata.
#
# Verdicts:
#   ready          — PR is not draft, CI is green (or empty). Review it.
#   not_ready      — PR is draft and/or CI failing. No prior comment, or author replied.
#   already_flagged — We already commented about readiness and author hasn't replied.
#
# Schema:
#   { "verdict", "reasons": [], "commented": bool, "author_replied": bool }
set -euo pipefail

VIEWER=""
COMMENTS_FILE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --viewer)        VIEWER="$2"; shift 2 ;;
    --comments-file) COMMENTS_FILE="$2"; shift 2 ;;
    *) echo "unknown arg $1" >&2; exit 2 ;;
  esac
done
[ -n "$VIEWER" ] || { echo "missing --viewer" >&2; exit 2; }

PR=$(cat)
IS_DRAFT=$(echo "$PR" | jq -r '.isDraft')
CHECKS=$(echo "$PR" | jq -r '.checks')
NUMBER=$(echo "$PR" | jq -r '.number')
NWO=$(echo "$PR" | jq -r '.nameWithOwner')
PR_AUTHOR=$(echo "$PR" | jq -r '.author')

# --- Step 1: Check readiness ---
REASONS='[]'
if [ "$IS_DRAFT" = "true" ]; then
  REASONS=$(echo "$REASONS" | jq '. + ["PR is still in draft"]')
fi

# checks is a comma-joined string of unique states from statusCheckRollup.
# "SUCCESS" or "" (no checks) = green. Anything else = not green.
if [ -n "$CHECKS" ] && [ "$CHECKS" != "SUCCESS" ]; then
  REASONS=$(echo "$REASONS" | jq '. + ["CI is not green ('"$CHECKS"')"]')
fi

REASON_COUNT=$(echo "$REASONS" | jq 'length')
if [ "$REASON_COUNT" = "0" ]; then
  jq -nc '{verdict: "ready", reasons: [], commented: false, author_replied: false}'
  exit 0
fi

# --- Step 2: Check comment history ---
if [ -n "$COMMENTS_FILE" ]; then
  COMMENTS=$(cat "$COMMENTS_FILE")
else
  COMMENTS=$(gh pr view "$NUMBER" --repo "$NWO" --json comments --jq '.comments' 2>/dev/null || echo '[]')
fi

# Find the most recent comment from us (the reviewer/viewer)
LAST_VIEWER_IDX=$(echo "$COMMENTS" | jq --arg v "$VIEWER" '
  [to_entries[] | select(.value.author.login == $v)] | last | .key // -1
')

if [ "$LAST_VIEWER_IDX" = "-1" ] || [ "$LAST_VIEWER_IDX" = "null" ]; then
  # Never commented
  echo "$REASONS" | jq -c '{verdict: "not_ready", reasons: ., commented: false, author_replied: false}'
  exit 0
fi

# Check if the PR author replied after our last comment
AUTHOR_REPLIED=$(echo "$COMMENTS" | jq --arg v "$VIEWER" --arg a "$PR_AUTHOR" --argjson idx "$LAST_VIEWER_IDX" '
  [to_entries[] | select(.key > $idx and .value.author.login == $a)] | length > 0
')

if [ "$AUTHOR_REPLIED" = "true" ]; then
  echo "$REASONS" | jq -c '{verdict: "not_ready", reasons: ., commented: true, author_replied: true}'
else
  echo "$REASONS" | jq -c '{verdict: "already_flagged", reasons: ., commented: true, author_replied: false}'
fi
