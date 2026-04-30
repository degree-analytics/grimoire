#!/usr/bin/env bash
# detect-pr.sh - resolve repo and PR number from args or git context.
# Usage:
#   detect-pr.sh [repo] [pr-number]
#   detect-pr.sh --test-repo-file F --test-pr-file F [repo] [pr-number]
#
# Args are unordered: numeric = PR number, non-numeric = repo name.
# Owner is always degree-analytics.
#
# Output: JSON object {"repo": "degree-analytics/bifrost", "pr": 1234}
set -euo pipefail

REPO_FILE=""
PR_FILE=""
REPO_ARG=""
PR_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --test-repo-file)
      REPO_FILE="$2"
      shift 2
      ;;
    --test-pr-file)
      PR_FILE="$2"
      shift 2
      ;;
    *)
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        PR_ARG="$1"
      else
        REPO_ARG="$1"
      fi
      shift
      ;;
  esac
done

if [ -n "$REPO_ARG" ]; then
  REPO="${REPO_ARG#degree-analytics/}"
  REPO="degree-analytics/$REPO"
elif [ -n "$REPO_FILE" ]; then
  [ -f "$REPO_FILE" ] || {
    echo "Run from inside a git repo, or pass a repo name" >&2
    exit 1
  }
  REPO=$(jq -r .nameWithOwner "$REPO_FILE")
else
  command -v gh >/dev/null || {
    echo "gh CLI not installed" >&2
    exit 2
  }
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null) || {
    echo "No GitHub remote found. Pass a repo name" >&2
    exit 1
  }
fi

if [ -n "$PR_ARG" ]; then
  PR="$PR_ARG"
elif [ -n "$PR_FILE" ]; then
  [ -f "$PR_FILE" ] || {
    echo "No PR for current branch. Pass a PR number" >&2
    exit 1
  }
  PR=$(jq -r .number "$PR_FILE")
else
  command -v gh >/dev/null || {
    echo "gh CLI not installed" >&2
    exit 2
  }
  PR=$(gh pr view --json number -q .number 2>/dev/null) || {
    echo "No PR for current branch. Pass a PR number" >&2
    exit 1
  }
fi

printf '{"repo": "%s", "pr": %s}\n' "$REPO" "$PR"
